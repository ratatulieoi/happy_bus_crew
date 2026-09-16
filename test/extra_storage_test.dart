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
      'tagihan': 50000,
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
    expect(restored.extra, 50000);
    expect(restored.totalPengeluaran, 800000);
    expect(restored.kmAwal, 123);
    expect(restored.kmAkhir, 456);
    expect(await store.getAttachments(id), receipts);

    final edited = restored.copyWith(extras: const [
      ExtraExpense(name: 'Tol kota', amount: 150000),
    ]);
    await store.saveReportWithAttachments(edited, receipts);
    await store.close();
    expect((await store.getReport(id))!.extras.single.name, 'Tol kota');
    expect((await store.getReport(id))!.extra, 150000);
    await store.saveReportWithAttachments(edited.copyWith(extras: []), receipts);
    await store.close();
    expect((await store.getReport(id))!.extras, isEmpty);
    expect((await store.getReport(id))!.extra, 0);
    expect((await store.getReport(id))!.totalPengeluaran, 750000);
    expect(await store.getAttachments(id), receipts);
  });

  test('v6 upgrade preserves legacy totals, buses, KM and receipt links',
      () async {
    final legacy = await databaseFactory.openDatabase(
      p.join(temporary.path, 'happy_bus.db'),
      options: OpenDatabaseOptions(
        version: 6,
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
              nama_crew TEXT NOT NULL DEFAULT '',
              catatan TEXT NOT NULL DEFAULT ''
            )
          ''');
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
          for (var i = 1; i <= 2; i++) {
            await db.insert('reports', {
              'id': i,
              'tanggal_buat': '2026-09-15T08:00:00',
              'no_polisi': 'B 1001 XX',
              'km_awal': 123,
              'km_akhir': 456,
              'extra': i == 1 ? 75000 : 0,
              'bbm': 100000,
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
    expect(await upgraded.getVersion(), 7);
    final rows = await upgraded.query('reports', orderBy: 'id');
    for (var i = 0; i < rows.length; i++) {
      expect(rows[i], {...originalRows[i], 'extra_details': '[]'});
    }
    expect(await upgraded.query('report_attachments'), originalReceipts);
    expect(await upgraded.query('buses'), originalBuses);
    expect(await upgraded.query('settings'), originalSettings);
    final report = (await store.getReport(1))!;
    expect(report.extras.single.name, 'Extra lama');
    expect(report.extras.single.amount, 75000);
    expect(report.totalPengeluaran, 175000);
    expect((await store.getReport(2))!.extras, isEmpty);
    await store.saveReportWithAttachments(report, ['/saved/receipt.jpg']);
    await store.close();
    expect((await store.getReport(1))!.extras.single.name, 'Extra lama');
    expect((await store.getReport(1))!.extra, 75000);
    expect(await store.getAttachments(1), ['/saved/receipt.jpg']);
  });
}
