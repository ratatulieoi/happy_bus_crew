import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bus_crew/db/database.dart';
import 'package:happy_bus_crew/models/report.dart';
import 'package:happy_bus_crew/models/report_attachment.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = DatabaseHelper.instance;
  late Directory temporary;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    await store.close();
    temporary = await Directory.systemTemp.createTemp('lpj-periods-');
    await databaseFactory.setDatabasesPath(temporary.path);
  });
  tearDown(() async {
    await store.close();
    await temporary.delete(recursive: true);
  });

  Report report() => Report.fromMap({
        'tanggal_buat': '2026-09-01T08:00:00',
        'hari_tgl_berangkat': 'Selasa, 01/09/2026',
        'hari_tgl_kembali': 'Sabtu, 05/09/2026',
        'no_polisi': 'B 1001 XX',
        'trip_type': 'luar_kota',
        'luar_kota_count': 3,
        'dalam_kota_count': 2,
        'uang_saku': 1000000,
        'bbm': 300000,
        'uang_makan': 100000,
        'pembayaran_tagihan': 500000,
        'extra': 50000,
      });

  List<TripPeriod> periods() => [
        TripPeriod(
          start: DateTime(2026, 9, 1),
          end: DateTime(2026, 9, 2),
          type: TripType.luarKota,
        ),
        TripPeriod(
          start: DateTime(2026, 9, 3),
          end: DateTime(2026, 9, 5),
          type: TripType.dalamKota,
        ),
      ];

  test('periods survive reopening, replacement and clearing with attachments',
      () async {
    const paths = [ReportAttachment(filePath: '/saved/attachment.jpg')];
    final original = report().copyWith(tripPeriods: periods());
    final id = await store.saveReportWithAttachments(original, paths);
    await store.close();
    var restored = (await store.getReport(id))!;
    expect(restored.toMap(), {...original.toMap(), 'id': id});
    expect(restored.luarKotaCount, 2);
    expect(restored.dalamKotaCount, 3);
    expect(await store.getAttachments(id), paths);

    final replacement = restored.copyWith(tripPeriods: [
      TripPeriod(
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 5),
        type: TripType.dalamKota,
      ),
    ]);
    await store.saveReportWithAttachments(replacement, paths);
    await store.close();
    restored = (await store.getReport(id))!;
    expect(restored.toMap(), replacement.toMap());
    expect(restored.luarKotaCount, 0);
    expect(restored.dalamKotaCount, 5);

    await store.saveReportWithAttachments(
        restored.copyWith(tripPeriods: []), paths);
    await store.close();
    restored = (await store.getReport(id))!;
    expect(restored.tripPeriods, isEmpty);
    expect(restored.luarKotaCount, isNull);
    expect(restored.dalamKotaCount, isNull);
    await store.saveReportWithAttachments(
        restored.copyWith(catatan: 'Edit'), paths);
    await store.close();
    restored = (await store.getReport(id))!;
    expect(restored.tripPeriods, isEmpty);
    expect(restored.luarKotaCount, isNull);
    expect(restored.dalamKotaCount, isNull);
    expect(restored.uangMakan, 0);
    expect(restored.totalPengeluaran, 350000);
    expect(restored.pembayaranTagihan, original.pembayaranTagihan);
    expect(await store.getAttachments(id), paths);
  });

  test('route JSON saves and reopens without changing destination-only data',
      () async {
    final database = await store.db;
    final schema = await database.query('sqlite_master', orderBy: 'name');
    final version = await database.getVersion();
    final id = await database.insert('reports', {
      ...report().toMap(),
      'trip_periods': jsonEncode([
        {
          'start': '2026-09-01',
          'end': '2026-09-02',
          'type': 'luar_kota',
          'destination': 'Malang',
        },
        {
          'start': '2026-09-03',
          'end': '2026-09-05',
          'type': 'dalam_kota',
          'origin': 'Sidoarjo',
          'destination': 'Surabaya',
        },
        {
          'start': '2026-09-07',
          'end': '2026-09-07',
          'type': 'dalam_kota',
          'origin': 'Batu',
        },
        {
          'start': '2026-09-08',
          'end': '2026-09-08',
          'type': 'dalam_kota',
          'origin': '',
          'destination': '',
        },
      ]),
    });
    await store.close();
    var restored = (await store.getReport(id))!;
    expect(restored.tripPeriods!.map((period) => period.origin),
        ['', 'Sidoarjo', 'Batu', '']);
    expect(restored.tripPeriods!.map((period) => period.destination),
        ['Malang', 'Surabaya', '', '']);
    const attachments = [ReportAttachment(filePath: '/saved/receipt.jpg')];
    await store.saveReportWithAttachments(restored, attachments);
    await store.close();
    final unchanged = (await store.getReport(id))!;
    expect(unchanged.toMap(), restored.toMap());

    final first = unchanged.tripPeriods!.first;
    final edited = unchanged.copyWith(tripPeriods: [
      TripPeriod(
        start: first.start,
        end: first.end,
        type: first.type,
        origin: 'Surabaya',
        destination: first.destination,
      ),
      ...unchanged.tripPeriods!.skip(1),
    ]);
    await store.saveReportWithAttachments(edited, attachments);
    await store.close();
    restored = (await store.getReport(id))!;
    expect(restored.toMap(), edited.toMap());
    expect(restored.tripPeriods!.map((period) => period.origin),
        ['Surabaya', 'Sidoarjo', 'Batu', '']);
    expect(restored.tripPeriods!.map((period) => period.destination),
        ['Malang', 'Surabaya', '', '']);
    expect(restored.luarKotaCount, 2);
    expect(restored.dalamKotaCount, 5);
    expect(restored.uangMakan, 350000);
    expect(await store.getAttachments(id), attachments);
    final reopenedDatabase = await store.db;
    expect(await reopenedDatabase.getVersion(), version);
    expect(await reopenedDatabase.query('sqlite_master', orderBy: 'name'),
        schema);
  });

  test('automatic meals persist and recalculate after range edits and clearing',
      () async {
    final original = report().copyWith(tripPeriods: [
      TripPeriod(
          start: DateTime(2026, 9, 1),
          end: DateTime(2026, 9, 2),
          type: TripType.luarKota),
      TripPeriod(
          start: DateTime(2026, 9, 8),
          end: DateTime(2026, 9, 8),
          type: TripType.dalamKota),
    ]);
    final id = await store.saveReportWithAttachments(original, []);
    await store.close();
    var reopened = (await store.getReport(id))!;
    expect(reopened.uangMakan, 150000);
    expect(reopened.totalPengeluaran, 500000);
    expect(
        (await (await store.db).query('reports')).single['uang_makan'], 150000);
    await store.saveReportWithAttachments(
        reopened.copyWith(tripPeriods: [
          TripPeriod(
              start: DateTime(2026, 9, 8),
              end: DateTime(2026, 9, 11),
              type: TripType.dalamKota),
        ]),
        []);
    await store.close();
    reopened = (await store.getReport(id))!;
    expect(reopened.uangMakan, 200000);
    expect(reopened.sisa, 450000);
    await store
        .saveReportWithAttachments(reopened.copyWith(tripPeriods: []), []);
    await store.close();
    expect((await store.getReport(id))!.uangMakan, 0);
    expect((await (await store.db).query('reports')).single['uang_makan'], 0);
  });

  test(
      'manual meals including zero and auto-equal amounts survive SQLite reopening',
      () async {
    for (final amount in [0, 250000, 123456]) {
      final original = report().copyWith(
          tripPeriods: periods(), uangMakan: amount, uangMakanIsManual: true);
      final id = await store.saveReportWithAttachments(
          original, [const ReportAttachment(filePath: '/saved/receipt.jpg')]);
      await store.close();
      var reopened = (await store.getReport(id))!;
      expect(reopened.uangMakanIsManual, isTrue);
      expect(reopened.uangMakan, amount);
      expect(reopened.toMap(), {...original.toMap(), 'id': id});
      await store.saveReportWithAttachments(reopened.copyWith(tripPeriods: []),
          [const ReportAttachment(filePath: '/saved/receipt.jpg')]);
      await store.close();
      reopened = (await store.getReport(id))!;
      expect(reopened.mealDays, 0);
      expect(reopened.uangMakan, amount);
      expect(reopened.totalPengeluaran, 350000 + amount);
      expect(reopened.sisa, 650000 - amount);
      expect(reopened.pembayaranTagihan, 500000);
      expect(await store.getAttachments(id),
          [const ReportAttachment(filePath: '/saved/receipt.jpg')]);
    }
  });

  test(
      'v13 upgrade only adds the meal mode and preserves report and attachments',
      () async {
    final original = report().copyWith(tripPeriods: periods());
    final id = await store.saveReportWithAttachments(
        original, [const ReportAttachment(filePath: '/saved/receipt.jpg')]);
    final database = await store.db;
    await database.execute('ALTER TABLE reports DROP COLUMN uang_makan_manual');
    await database
        .execute('ALTER TABLE report_attachments DROP COLUMN expense_type');
    await database
        .execute('ALTER TABLE report_attachments DROP COLUMN extra_id');
    await database.setVersion(13);
    final before = (await database.query('reports')).single;
    final attachments = await database.query('report_attachments');
    await store.close();
    final upgraded = await store.db;
    expect(await upgraded.getVersion(), 15);
    expect((await upgraded.query('reports')).single,
        {...before, 'uang_makan_manual': 0});
    expect(await upgraded.query('report_attachments'), [
      for (final row in attachments)
        {...row, 'expense_type': null, 'extra_id': null},
    ]);
    expect((await store.getReport(id))!.uangMakan, 250000);
    expect((await store.getReport(id))!.uangMakanIsManual, isFalse);
  });

  test('v10 migration leaves historical counts intact until replaced',
      () async {
    final legacy = await databaseFactory.openDatabase(
      p.join(temporary.path, 'happy_bus.db'),
      options: OpenDatabaseOptions(
        version: 10,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE reports (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              tanggal_buat TEXT NOT NULL,
              hari_tgl_berangkat TEXT NOT NULL DEFAULT '',
              jam_berangkat TEXT NOT NULL DEFAULT '',
              hari_tgl_kembali TEXT NOT NULL DEFAULT '',
              no_polisi TEXT NOT NULL DEFAULT '',
              pengemudi TEXT NOT NULL DEFAULT '',
              kernet TEXT NOT NULL DEFAULT '',
              trip_type TEXT NOT NULL DEFAULT '',
              luar_kota_count INTEGER,
              dalam_kota_count INTEGER,
              km_awal INTEGER NOT NULL DEFAULT 0,
              km_akhir INTEGER NOT NULL DEFAULT 0,
              uang_saku INTEGER NOT NULL DEFAULT 0,
              bbm INTEGER NOT NULL DEFAULT 0,
              uang_makan INTEGER NOT NULL DEFAULT 0,
              pembayaran_tagihan INTEGER NOT NULL DEFAULT 0,
              extra INTEGER NOT NULL DEFAULT 0,
              extra_details TEXT NOT NULL DEFAULT '[]',
              nama_crew TEXT NOT NULL DEFAULT '',
              catatan TEXT NOT NULL DEFAULT ''
            )
          ''');
          await db.execute('''
            CREATE TABLE report_attachments (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              report_id INTEGER NOT NULL,
              file_path TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    // The v10 table predates both the period list and the guest name column.
    final oldData = report().toMap()
      ..remove('trip_periods')
      ..remove('nama_tamu')
      ..remove('has_guest_allowance')
      ..remove('guest_uang_saku')
      ..remove('guest_tol')
      ..remove('guest_penyeberangan')
      ..remove('guest_parkir')
      ..remove('guest_extra_details')
      ..remove('guest_catatan')
      ..remove('uang_makan_manual');
    final id = await legacy.insert('reports', oldData);
    await legacy.insert('report_attachments', {
      'report_id': id,
      'file_path': '/saved/attachment.jpg',
    });
    final oldRow = (await legacy.query('reports')).single;
    await legacy.close();

    final upgraded = await store.db;
    expect(await upgraded.getVersion(), 15);
    expect((await upgraded.query('reports')).single, {
      ...oldRow,
      'trip_periods': null,
      'nama_tamu': '',
      'has_guest_allowance': 0,
      'guest_uang_saku': 0,
      'guest_tol': 0,
      'guest_penyeberangan': 0,
      'guest_parkir': 0,
      'guest_extra_details': '[]',
      'guest_catatan': '',
      'uang_makan_manual': 0,
    });
    final restored = (await store.getReport(id))!;
    expect(restored.namaTamu, isEmpty);
    expect(restored.tripPeriods, isNull);
    expect(restored.luarKotaCount, 3);
    expect(restored.dalamKotaCount, 2);
    expect(restored.tripType, TripType.luarKota);
    final paths = await store.getAttachments(id);
    await store.saveReportWithAttachments(
        restored.copyWith(catatan: 'Edit'), paths);
    await store.close();
    final edited = (await store.getReport(id))!;
    expect(edited.tripPeriods, isNull);
    expect(edited.luarKotaCount, 3);
    expect(edited.dalamKotaCount, 2);

    await store.saveReportWithAttachments(
        edited.copyWith(tripPeriods: periods()), paths);
    await store.close();
    final replaced = (await store.getReport(id))!;
    expect(replaced.tripPeriods, hasLength(2));
    expect(replaced.luarKotaCount, 2);
    expect(replaced.dalamKotaCount, 3);
    expect(replaced.uangMakan, 250000);
    expect(replaced.totalPengeluaran, 600000);
    expect(replaced.pembayaranTagihan, restored.pembayaranTagihan);
    expect(await store.getAttachments(id), paths);
  });
}
