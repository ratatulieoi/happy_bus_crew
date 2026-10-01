import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bus_crew/db/database.dart';
import 'package:happy_bus_crew/models/bus.dart';
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
    temporary = await Directory.systemTemp.createTemp('lpj-buses-');
    await databaseFactory.setDatabasesPath(temporary.path);
  });

  tearDown(() async {
    await store.close();
    await temporary.delete(recursive: true);
  });

  test('bus name lookup matches a plate loosely and never guesses', () {
    const buses = [
      Bus(id: 1, name: 'Happy Bus 01', plate: 'B 1001 XX'),
      Bus(id: 2, name: 'Happy Bus 02', plate: 'B 1002 XX'),
    ];
    expect(busNameForPlate(buses, 'B 1001 XX'), 'Happy Bus 01');
    expect(busNameForPlate(buses, '  b 1002 xx '), 'Happy Bus 02');
    expect(busNameForPlate(buses, 'L 9 ZZ'), isEmpty);
    expect(busNameForPlate(const [], 'B 1001 XX'), isEmpty);
  });

  Future<void> createLegacyDatabase(Map<String, String> settings) async {
    final db = await databaseFactory.openDatabase(
      p.join(temporary.path, 'happy_bus.db'),
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (db, _) async {
          await db.execute(
              'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
          await db.execute(
              'CREATE TABLE reports (id INTEGER PRIMARY KEY, no_polisi TEXT,'
              ' km_awal INTEGER, km_akhir INTEGER)');
          await db.execute(
              'CREATE TABLE report_attachments (id INTEGER PRIMARY KEY,'
              ' report_id INTEGER, file_path TEXT)');
          for (final entry in settings.entries) {
            await db
                .insert('settings', {'key': entry.key, 'value': entry.value});
          }
          await db.insert('reports', {
            'id': 7,
            'no_polisi': 'B 1001 XX',
            'km_awal': 123,
            'km_akhir': 456
          });
          await db.insert('report_attachments',
              {'id': 1, 'report_id': 7, 'file_path': '/saved/receipt.jpg'});
        },
      ),
    );
    await db.close();
  }

  test('fresh install has no template buses and can add more than six',
      () async {
    expect(await store.getBuses(), isEmpty);
    expect(await store.getSelectedBus(), isNull);
    for (var i = 0; i < 8; i++) {
      await store.saveBus(name: ' Bus $i ', plate: ' b ${1000 + i} xx ');
    }
    final buses = await store.getBuses();
    expect(buses, hasLength(8));
    expect(buses.first.name, 'Bus 0');
    expect(buses.first.plate, 'B 1000 XX');
    expect((await store.getSelectedBus())!.id, buses.last.id);
    await store.selectBus(buses.first.id);
    await store.close();
    expect((await store.getSelectedBus())!.id, buses.first.id);
    expect(await store.getBuses(), hasLength(8));
  });

  test('duplicate or blank identity does not change buses or selection',
      () async {
    final first = await store.saveBus(name: 'First', plate: 'B 1001 XX');
    final second = await store.saveBus(name: 'Second', plate: 'B 1002 XX');
    await expectLater(store.saveBus(name: 'Duplicate', plate: ' b 1001 xx '),
        throwsA(isA<DatabaseException>()));
    await expectLater(
        store.saveBus(id: second, name: 'Duplicate edit', plate: 'B 1001 XX'),
        throwsA(isA<DatabaseException>()));
    await expectLater(
        store.saveBus(name: ' ', plate: 'B 1003 XX'), throwsArgumentError);
    await expectLater(
        store.saveBus(name: 'Bus', plate: ' '), throwsArgumentError);
    await expectLater(store.selectBus(999), throwsStateError);
    expect((await store.getSelectedBus())!.id, second);
    expect((await store.getBuses()).map((bus) => bus.id), [first, second]);
    expect((await store.getBuses()).last.name, 'Second');
  });

  test('deleting an unused bus clears its selection and keeps the rest',
      () async {
    final first = await store.saveBus(name: 'First', plate: 'B 1001 XX');
    final second = await store.saveBus(name: 'Second', plate: 'B 1002 XX');
    expect((await store.getSelectedBus())!.id, second);
    await store.deleteBus(second);
    expect(await store.getSetting('selected_bus_id'), isNull);
    expect((await store.getBuses()).map((bus) => bus.id), [first]);
    expect((await store.getSelectedBus())!.id, first);
    await store.close();
    expect((await store.getBuses()).map((bus) => bus.id), [first]);
    await expectLater(store.selectBus(second), throwsStateError);
  });

  test('deleting an inactive or missing bus preserves selection and history',
      () async {
    final first = await store.saveBus(name: 'Unused', plate: 'B 1001 XX');
    final second = await store.saveBus(name: 'Active', plate: 'B 1002 XX');
    final db = await store.db;
    await db.insert('reports', {
      'id': 7,
      'tanggal_buat': '2026-09-15T08:00:00',
      'no_polisi': 'B 1002 XX'
    });
    await db.insert('report_attachments',
        {'report_id': 7, 'file_path': '/saved/receipt.jpg'});
    final reportsBefore = await db.query('reports');
    final receiptsBefore = await db.query('report_attachments');
    await store.deleteBus(first);
    await expectLater(store.deleteBus(first), throwsStateError);
    expect((await store.getBuses()).map((bus) => bus.id), [second]);
    expect(await store.getSetting('selected_bus_id'), '$second');
    expect(await db.query('reports'), reportsBefore);
    expect(await db.query('report_attachments'), receiptsBefore);
  });

  test('deleting the last bus clears selection and permits a new bus',
      () async {
    final id = await store.saveBus(name: 'Only bus', plate: 'B 1001 XX');
    await store.deleteBus(id);
    await store.close();
    expect(await store.getBuses(), isEmpty);
    expect(await store.getSelectedBus(), isNull);
    expect(await store.getSetting('selected_bus_id'), isNull);
    final replacement =
        await store.saveBus(name: 'Replacement', plate: 'B 1001 XX');
    expect((await store.getSelectedBus())!.id, replacement);
  });

  test('failed selection cleanup rolls back the bus deletion', () async {
    final id = await store.saveBus(name: 'Active', plate: 'B 1001 XX');
    final db = await store.db;
    await db.execute('''
      CREATE TRIGGER fail_selection_delete BEFORE DELETE ON settings
      BEGIN SELECT RAISE(ABORT, 'test failure'); END
    ''');
    await expectLater(store.deleteBus(id), throwsA(isA<DatabaseException>()));
    expect((await store.getBuses()).single.id, id);
    expect(await store.getSetting('selected_bus_id'), '$id');
    await db.execute('DROP TRIGGER fail_selection_delete');
    await store.deleteBus(id);
    expect(await store.getBuses(), isEmpty);
  });

  test('a bus with saved reports cannot be deleted and keeps its selection',
      () async {
    final db = await store.db;
    final first = await store.saveBus(name: 'First', plate: 'B 1001 XX');
    await db.insert('reports', {
      'id': 7,
      'tanggal_buat': '2026-09-15T08:00:00',
      'no_polisi': ' b 1001 xx ',
      'km_awal': 123,
      'km_akhir': 456
    });
    expect(await store.isBusUsed((await store.getBuses()).first), isTrue);
    await expectLater(store.deleteBus(first), throwsStateError);
    expect((await store.getBuses()).map((bus) => bus.id), [first]);
    expect((await store.getSelectedBus())!.id, first);
    expect((await db.query('reports')).single['no_polisi'], ' b 1001 xx ');
  });

  test('editing bus identity keeps saved report plate, manual KM and receipts',
      () async {
    final id = await store.saveBus(name: 'First', plate: 'B 1001 XX');
    final db = await store.db;
    await db.insert('reports', {
      'id': 7,
      'tanggal_buat': '2026-09-15T08:00:00',
      'no_polisi': 'B 1001 XX',
      'km_awal': 123,
      'km_akhir': 456
    });
    await db.insert('report_attachments',
        {'report_id': 7, 'file_path': '/saved/receipt.jpg'});
    final reportsBefore = await db.query('reports');
    final receiptsBefore = await db.query('report_attachments');
    await store.saveBus(id: id, name: 'Renamed', plate: 'L 9999 YY');
    expect((await store.getSelectedBus())!.plate, 'L 9999 YY');
    expect(await db.query('reports'), reportsBefore);
    expect(await db.query('report_attachments'), receiptsBefore);
  });

  test('v5 migration preserves saved identities and selection without trackers',
      () async {
    await createLegacyDatabase({
      'selected_bus_index': '4',
      'bus_0_name': 'First',
      'bus_0_plate': 'B 1001 XX',
      'bus_2_name': 'Incomplete',
      'bus_4_name': 'Selected',
      'bus_4_plate': ' l 4004 ab ',
      'bus_5_name': 'Duplicate plate',
      'bus_5_plate': 'B 1001 XX',
      'bus_4_oil_change_km': '120000',
      'bus_4_oil_interval': '10000',
    });
    final buses = await store.getBuses();
    expect(buses, hasLength(2));
    expect((await store.getSelectedBus())!.name, 'Selected');
    expect((await store.getSelectedBus())!.plate, 'L 4004 AB');
    final db = await store.db;
    expect(await db.getVersion(), 12);
    expect(await db.query('reports'), [
      {
        'id': 7,
        'no_polisi': 'B 1001 XX',
        'km_awal': 123,
        'km_akhir': 456,
        'extra_details': '[]',
        'trip_type': '',
        'luar_kota_count': null,
        'dalam_kota_count': null,
        'trip_periods': null,
        'pembayaran_tagihan': 0,
        'nama_tamu': '',
      }
    ]);
    expect(await db.query('report_attachments'), [
      {'id': 1, 'report_id': 7, 'file_path': '/saved/receipt.jpg'}
    ]);
    expect(await store.getSetting('bus_4_oil_change_km'), '120000');
    await store.close();
    expect(await store.getBuses(), hasLength(2));
  });

  test('migration does not invent buses when old setup was empty', () async {
    await createLegacyDatabase({'selected_bus_index': '0'});
    expect(await store.getBuses(), isEmpty);
    expect(await store.getSelectedBus(), isNull);
    expect(await (await store.db).query('reports'), hasLength(1));
  });
}
