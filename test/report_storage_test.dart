import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bus_crew/models/report.dart';
import 'package:happy_bus_crew/services/report_storage.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  final statements = <String>[];
  final savedPaths = <String>[];
  var failAttachmentInsert = false;
  var reportInserts = 0;

  Report report({int? id}) => Report(
        id: id,
        hariTglBerangkat: '',
        jamBerangkat: '',
        hariTglKembali: '',
        noPolisi: 'B 1001 XX',
        namaTamu: 'Bpk. Hartono',
        pengemudi: 'Budi',
        kernet: '',
        kmAwal: 10,
        kmAkhir: 20,
        uangSaku: 100,
        bbm: 20,
        uangMakan: 0,
        pembayaranTagihan: 0,
        namaCrew: 'Budi',
      );

  setUpAll(() {
    databaseFactory = databaseFactorySqflitePlugin;
  });
  setUp(() async {
    temporary =
        await Directory.systemTemp.createTemp('happy_bus_storage_test_');
    statements.clear();
    savedPaths.clear();
    failAttachmentInsert = false;
    reportInserts = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => temporary.path);
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.tekartik.sqflite'), (call) async {
      final args =
          call.arguments is Map ? call.arguments as Map : <String, dynamic>{};
      final sql = args['sql'] as String? ?? '';
      if (sql.isNotEmpty) statements.add(sql);
      switch (call.method) {
        case 'getDatabasesPath':
          return temporary.path;
        case 'openDatabase':
          return {'id': 1};
        case 'query':
          return [
            {'user_version': 10}
          ];
        case 'execute':
          return null;
        case 'update':
          return 1;
        case 'insert':
          if (sql.contains('report_attachments')) {
            if (failAttachmentInsert) {
              throw PlatformException(code: 'disk_full');
            }
            final values = args['arguments'] as List;
            savedPaths.add(values[1] as String);
          } else if (sql.contains('reports')) {
            reportInserts++;
          }
          return 7;
        default:
          return null;
      }
    });
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test(
      'edited and reordered receipts use new copies without overwriting sources',
      () async {
    final first = await File('${temporary.path}/struk_1.jpg')
        .writeAsString('first receipt');
    final second = await File('${temporary.path}/struk_2.jpg')
        .writeAsString('second receipt');
    final id = await ReportStorage.save(report(id: 7), [second, first]);
    expect(id, 7);
    expect(await first.readAsString(), 'first receipt');
    expect(await second.readAsString(), 'second receipt');
    expect(savedPaths, hasLength(2));
    expect(await File(savedPaths[0]).readAsString(), 'second receipt');
    expect(await File(savedPaths[1]).readAsString(), 'first receipt');
    expect(savedPaths, isNot(contains(first.path)));
    expect(statements.any((sql) => sql.startsWith('BEGIN')), isTrue);
    expect(statements.last, 'COMMIT');
    expect(reportInserts, 0);
  });

  test('copy failure never changes the report or old receipt links', () async {
    final original =
        await File('${temporary.path}/original.jpg').writeAsString('keep me');
    await expectLater(
        ReportStorage.save(
            report(id: 7), [original, File('${temporary.path}/missing.jpg')]),
        throwsA(isA<FileSystemException>()));
    expect(statements, isEmpty);
    expect(await original.readAsString(), 'keep me');
    expect(await Directory('${temporary.path}/attachments').list().toList(),
        isEmpty);
  });

  test('database failure rolls back and removes only newly staged copies',
      () async {
    final original =
        await File('${temporary.path}/original.jpg').writeAsString('keep me');
    failAttachmentInsert = true;
    await expectLater(
        ReportStorage.save(report(id: 7), [original]), throwsA(anything));
    expect(statements.last, 'ROLLBACK');
    expect(statements, isNot(contains('COMMIT')));
    expect(await original.readAsString(), 'keep me');
    expect(await Directory('${temporary.path}/attachments').list().toList(),
        isEmpty);
    failAttachmentInsert = false;
    expect(await ReportStorage.save(report(id: 7), [original]), 7);
    expect(statements.last, 'COMMIT');
  });

  test('empty receipt list can be saved without filesystem access', () async {
    expect(await ReportStorage.save(report(), []), 7);
    expect(reportInserts, 1);
    expect(savedPaths, isEmpty);
    expect(statements.last, 'COMMIT');
    expect(await Directory('${temporary.path}/attachments').exists(), isFalse);
  });
}
