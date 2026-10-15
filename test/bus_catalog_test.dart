import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bus_crew/db/database.dart';
import 'package:happy_bus_crew/models/bus.dart';
import 'package:happy_bus_crew/models/report.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalog contains exactly HG2 through HG6 and HC1 through HC3 with fixed plates', () {
    expect(busCatalog.map((bus) => (bus.name, bus.plate)), [
      ('HG2', 'AB 7317 BK'),
      ('HG3', 'AB 7402 BK'),
      ('HG4', 'AB 7403 BK'),
      ('HG5', 'AB 7454 BK'),
      ('HG6', 'AB 7497 BK'),
      ('HC1', 'AB 1669 SV'),
      ('HC2', 'AB 1779 KP'),
      ('HC3', 'AB 1097 DF'),
    ]);
    expect(() => busCatalog.clear(), throwsUnsupportedError);
    expect(() => busCatalog.add(const Bus(name: 'HG1', plate: 'custom')),
        throwsUnsupportedError);
    for (final bus in busCatalog) {
      expect(busNameForPlate(bus.plate), bus.name);
    }
  });

  test('reports persist catalog plates without mutable bus storage', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final store = DatabaseHelper.instance;
    await store.close();
    final directory = await Directory.systemTemp.createTemp('lpj-catalog-');
    await databaseFactory.setDatabasesPath(directory.path);
    addTearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });

    final database = await store.db;
    final tables = await database
        .rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'");
    expect(tables.map((row) => row['name']), isNot(contains('buses')));
    final saved = <int, String>{};
    for (final bus in busCatalog) {
      final report = Report.fromMap({
        'tanggal_buat': '2026-09-15T08:00:00',
        'no_polisi': bus.plate,
      });
      final id = await store.saveReportWithAttachments(report, []);
      saved[id] = bus.plate;
    }
    await store.close();
    for (final entry in saved.entries) {
      final report = (await store.getReport(entry.key))!;
      expect(report.noPolisi, entry.value);
      expect(report.toMap()['no_polisi'], entry.value);
      expect(report.toMap().containsKey('bus_name'), isFalse);
    }
    expect(await store.getAllReports(), hasLength(8));
  });
}
