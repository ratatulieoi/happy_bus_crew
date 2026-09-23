import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bus_crew/db/database.dart';
import 'package:happy_bus_crew/models/report.dart';
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
    temporary = await Directory.systemTemp.createTemp('lpj-extras-');
    await databaseFactory.setDatabasesPath(temporary.path);
  });
  tearDown(() async {
    await store.close();
    await temporary.delete(recursive: true);
  });

  test('named extras survive save, reopen, editing and removal with receipts',
      () async {
    final report = Report.fromMap({
      'tanggal_buat': '2026-09-15T08:00:00',
      'no_polisi': 'B 1001 XX',
      'km_awal': 123,
      'km_akhir': 456,
      'uang_saku': 1000000,
      'bbm': 600000,
      'uang_makan': 100000,
      'pembayaran_tagihan': 50000,
      'luar_kota_count': 3,
      'dalam_kota_count': 5,
    }).copyWith(extras: const [
      ExtraExpense(name: 'Parkir', amount: 20000),
      ExtraExpense(name: 'Tol', amount: 30000),
    ]);
    const receipts = ['/saved/receipt.jpg'];
    final id = await store.saveReportWithAttachments(report, receipts);
    await store.close();
    final restored = (await store.getReport(id))!;
    expect(restored.extras.map((item) => item.name), ['Parkir', 'Tol']);
    expect(restored.extras.map((item) => item.amount), [20000, 30000]);
    expect(restored.luarKotaCount, 3);
    expect(restored.dalamKotaCount, 5);
    expect(restored.extra, 50000);
    expect(restored.pembayaranTagihan, 50000);
    expect(restored.totalPengeluaran, 750000);
    expect(restored.kmAwal, 123);
    expect(restored.kmAkhir, 456);
    expect(await store.getAttachments(id), receipts);

    final edited = restored.copyWith(
        luarKotaCount: 0,
        dalamKotaCount: 8,
        extras: const [ExtraExpense(name: 'Tol kota', amount: 150000)]);
    await store.saveReportWithAttachments(edited, receipts);
    await store.close();
    expect((await store.getReport(id))!.extras.single.name, 'Tol kota');
    expect((await store.getReport(id))!.extra, 150000);
    expect((await store.getReport(id))!.luarKotaCount, 0);
    expect((await store.getReport(id))!.dalamKotaCount, 8);
    await store.saveReportWithAttachments(edited.copyWith(extras: []), receipts);
    await store.close();
    expect((await store.getReport(id))!.extras, isEmpty);
    expect((await store.getReport(id))!.extra, 0);
    expect((await store.getReport(id))!.totalPengeluaran, 700000);
    expect(await store.getAttachments(id), receipts);
  });

  for (final version in [6, 7, 8, 9, 10]) {
  test('v$version upgrade preserves totals, buses, KM, extras and receipt links',
      () async {
    final legacy = await databaseFactory.openDatabase(
      p.join(temporary.path, 'happy_bus.db'),
      options: OpenDatabaseOptions(
        version: version,
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
              km_awal INTEGER NOT NULL DEFAULT 0,
              km_akhir INTEGER NOT NULL DEFAULT 0,
              uang_saku INTEGER NOT NULL DEFAULT 0,
              bbm INTEGER NOT NULL DEFAULT 0,
              uang_makan INTEGER NOT NULL DEFAULT 0,
              extra INTEGER NOT NULL DEFAULT 0,
              tagihan INTEGER NOT NULL DEFAULT 0,
              ${version >= 10 ? 'pembayaran_tagihan INTEGER NOT NULL DEFAULT 0,' : ''}
              nama_crew TEXT NOT NULL DEFAULT '',
              catatan TEXT NOT NULL DEFAULT ''
            )
          ''');
          if (version >= 7) {
            await db.execute(
                "ALTER TABLE reports ADD COLUMN extra_details TEXT NOT NULL DEFAULT '[]'");
          }
          if (version >= 8) {
            await db.execute(
                "ALTER TABLE reports ADD COLUMN trip_type TEXT NOT NULL DEFAULT ''");
          }
          if (version >= 9) {
            await db.execute(
                'ALTER TABLE reports ADD COLUMN luar_kota_count INTEGER CHECK (luar_kota_count >= 0)');
            await db.execute(
                'ALTER TABLE reports ADD COLUMN dalam_kota_count INTEGER CHECK (dalam_kota_count >= 0)');
          }
          await db.execute('''
            CREATE TABLE buses (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              plate TEXT NOT NULL COLLATE NOCASE UNIQUE
            )
          ''');
          await db.execute(
              'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
          await db.execute('''
            CREATE TABLE report_attachments (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              report_id INTEGER NOT NULL,
              file_path TEXT NOT NULL
            )
          ''');
          await db.insert('buses',
              {'id': 1, 'name': 'Happy Bus', 'plate': 'B 1001 XX'});
          await db.insert('settings', {'key': 'selected_bus_id', 'value': '1'});
          for (var i = 1; i <= 3; i++) {
            await db.insert('reports', {
              'id': i,
              'tanggal_buat': '2026-09-15T08:00:00',
              'no_polisi': 'B 1001 XX',
              'km_awal': 123,
              'km_akhir': 456,
              'extra': i == 1 ? 75000 : 0,
              'bbm': 100000,
              'tagihan': 20000 * i,
              if (version >= 10) 'pembayaran_tagihan': 20000 * i,
              if (version >= 7 && i == 1)
                'extra_details': '[{"name":"Parkir","amount":75000}]',
              if (version == 8)
                'trip_type': ['', 'luar_kota', 'dalam_kota'][i - 1],
            });
          }
          await db.insert('report_attachments',
              {'report_id': 1, 'file_path': '/saved/receipt.jpg'});
        },
      ),
    );
    final originalRows = await legacy.query('reports', orderBy: 'id');
    final originalReceipts = await legacy.query('report_attachments');
    final originalBuses = await legacy.query('buses');
    final originalSettings = await legacy.query('settings');
    await legacy.close();

    final upgraded = await store.db;
    expect(await upgraded.getVersion(), 10);
    final rows = await upgraded.query('reports', orderBy: 'id');
    for (var i = 0; i < rows.length; i++) {
      expect(rows[i], {
        ...originalRows[i],
        if (version == 6) 'extra_details': '[]',
        if (version < 8) 'trip_type': '',
        if (version < 9) 'luar_kota_count': null,
        if (version < 9) 'dalam_kota_count': null,
        'pembayaran_tagihan': 0,
        'tagihan': 0,
      });
    }
    expect(await upgraded.query('report_attachments'), originalReceipts);
    expect(await upgraded.query('buses'), originalBuses);
    expect(await upgraded.query('settings'), originalSettings);
    for (final row in originalRows) {
      final id = row['id'] as int;
      final restored = (await store.getReport(id))!;
      expect(restored.luarKotaCount, isNull);
      expect(restored.dalamKotaCount, isNull);
      expect(restored.tripType, TripType.fromValue(row['trip_type']));
      final paths = await store.getAttachments(id);
      await store.saveReportWithAttachments(restored.copyWith(catatan: 'Edit'), paths);
      await store.close();
      final reopened = (await store.getReport(id))!;
      expect(reopened.hasTripCounts, isFalse);
      expect(reopened.tripType, restored.tripType);
      expect(await store.getAttachments(id), paths);
    }
    final report = (await store.getReport(1))!;
    expect(report.tripType, TripType.unspecified);
    expect(report.extras.single.name, version == 6 ? 'Extra lama' : 'Parkir');
    expect(report.extras.single.amount, 75000);
    expect(report.totalPengeluaran, version == 6 ? 175000 : 100000);
    expect((await store.getReport(2))!.extras, isEmpty);
    await store.saveReportWithAttachments(report, ['/saved/receipt.jpg']);
    await store.close();
    expect((await store.getReport(1))!.tripType, TripType.unspecified);
    expect((await store.getReport(1))!.extras.single.name,
        version == 6 ? 'Extra lama' : 'Parkir');
    expect((await store.getReport(1))!.extra, 75000);
    expect(await store.getAttachments(1), ['/saved/receipt.jpg']);
  });
  }
}
