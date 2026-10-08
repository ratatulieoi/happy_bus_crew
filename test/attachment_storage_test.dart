import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bus_crew/db/database.dart';
import 'package:happy_bus_crew/models/report.dart';
import 'package:happy_bus_crew/models/report_attachment.dart';
import 'package:happy_bus_crew/services/report_storage.dart';
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
    temporary = await Directory.systemTemp.createTemp('lpj-photos-');
    await databaseFactory.setDatabasesPath(temporary.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => temporary.path);
  });
  tearDown(() async {
    await store.close();
    await temporary.delete(recursive: true);
  });

  test('extra IDs survive rename and serialization, not duplicate names', () {
    final first = ExtraExpense(name: 'Tol', amount: 1000);
    final second = ExtraExpense(name: 'Tol', amount: 1000);
    expect(first.id, isNot(second.id));
    final renamed = first.copyWith(name: 'Parkir', amount: 2000);
    expect(renamed.id, first.id);
    expect(ExtraExpense.fromMap(renamed.toMap()).toMap(), renamed.toMap());
    final legacy = ExtraExpense.fromMap({'name': 'Tol', 'amount': 1000});
    expect(legacy.id, isNotEmpty);
    expect(ExtraExpense.fromMap(legacy.toMap()).id, legacy.id);
    expect(() => ExtraExpense.fromMap({'id': '', 'name': 'Tol', 'amount': 1}),
        throwsFormatException);
  });

  test('typed owners round-trip independently, including matching extra IDs',
      () {
    final owners = [
      for (final type in ExpenseType.values)
        ExpenseOwner(type, extraId: type.isExtra ? 'same-id' : null),
    ];
    expect(owners.toSet(), hasLength(7));
    for (final owner in owners) {
      final photo = ReportAttachment(filePath: '/photo.jpg', owner: owner);
      expect(ReportAttachment.fromMap(photo.toMap()), photo);
      expect(photo.withPath('/copy.jpg').owner, owner);
    }
    expect(ReportAttachment.fromMap({'file_path': '/old.jpg'}).owner, isNull);
    expect(
        () => ReportAttachment.fromMap({
              'file_path': '/photo.jpg',
              'expense_type': 'office_extra',
              'extra_id': null,
            }),
        throwsFormatException);
  });

  test(
      'save and reopen keep photos isolated through rename, removal and toggle',
      () async {
    final extras = [
      ExtraExpense(name: 'Tol', amount: 1000),
      ExtraExpense(name: 'Tol', amount: 2000),
    ];
    final guest = ExtraExpense(name: 'Tol', amount: 3000);
    final report = Report.fromMap({'no_polisi': 'AB 7317 BK'}).copyWith(
      extras: extras,
      hasGuestAllowance: true,
      guestTol: 4000,
      guestExtras: [guest],
    );
    final owners = [
      const ExpenseOwner(ExpenseType.officeBbm),
      const ExpenseOwner(ExpenseType.officeMeal),
      ExpenseOwner(ExpenseType.officeExtra, extraId: extras[0].id),
      ExpenseOwner(ExpenseType.officeExtra, extraId: extras[0].id),
      ExpenseOwner(ExpenseType.officeExtra, extraId: extras[1].id),
      const ExpenseOwner(ExpenseType.discovaTol),
      const ExpenseOwner(ExpenseType.discovaCrossing),
      const ExpenseOwner(ExpenseType.discovaParking),
      ExpenseOwner(ExpenseType.discovaExtra, extraId: guest.id),
    ];
    final photos = <ReportAttachment>[];
    for (var i = 0; i < owners.length; i++) {
      final file =
          await File('${temporary.path}/$i.jpg').writeAsString('photo $i');
      photos.add(ReportAttachment(filePath: file.path, owner: owners[i]));
    }
    final id = await ReportStorage.save(report, photos);
    await store.close();
    final reopened = (await store.getReport(id))!;
    final saved = await store.getAttachments(id);
    expect(reopened.extras.map((extra) => extra.id),
        extras.map((extra) => extra.id));
    expect(saved.map((photo) => photo.owner), owners);
    for (var i = 0; i < saved.length; i++) {
      expect(saved[i].filePath, isNot(photos[i].filePath));
      expect(await File(saved[i].filePath).readAsString(), 'photo $i');
    }

    // Rename the first duplicate, remove the second, remove one individual photo.
    final remaining = List<ReportAttachment>.of(saved)
      ..removeAt(3)
      ..removeWhere((photo) => photo.owner == owners[4]);
    await ReportStorage.save(
        reopened.copyWith(
          extras: [reopened.extras.first.copyWith(name: 'Parkir')],
          hasGuestAllowance: false,
        ),
        remaining);
    await store.close();
    final edited = (await store.getReport(id))!;
    final editedPhotos = await store.getAttachments(id);
    expect(edited.extras.single.id, extras[0].id);
    expect(edited.extras.single.name, 'Parkir');
    expect(edited.hasGuestAllowance, isFalse);
    expect(edited.guestTol, 4000);
    expect(edited.guestExtras.single.id, guest.id);
    expect(editedPhotos.map((photo) => photo.owner),
        remaining.map((photo) => photo.owner));
    for (final photo in [...photos, ...saved]) {
      expect(await File(photo.filePath).exists(), isTrue);
    }
  });

  test(
      'failed transaction preserves report, ownership and files; cleans staging',
      () async {
    final source =
        await File('${temporary.path}/source.jpg').writeAsString('keep');
    final report =
        Report.fromMap({'no_polisi': 'AB 7317 BK', 'catatan': 'saved'});
    final id = await ReportStorage.save(report, [
      ReportAttachment(
          filePath: source.path,
          owner: const ExpenseOwner(ExpenseType.officeBbm)),
    ]);
    final before = (await store.getReport(id))!;
    final links = await store.getAttachments(id);
    final root = Directory('${temporary.path}/attachments');
    final directories =
        (await root.list().toList()).map((file) => file.path).toList();
    await (await store.db).execute('''
      CREATE TRIGGER reject_photo BEFORE INSERT ON report_attachments
      BEGIN SELECT RAISE(ABORT, 'test failure'); END
    ''');
    await expectLater(
      ReportStorage.save(before.copyWith(catatan: 'unsaved'), [
        ReportAttachment(
            filePath: source.path,
            owner: const ExpenseOwner(ExpenseType.discovaTol)),
      ]),
      throwsA(anything),
    );
    expect((await store.getReport(id))!.toMap(), before.toMap());
    expect(await store.getAttachments(id), links);
    expect((await root.list().toList()).map((file) => file.path), directories);
    expect(await File(links.single.filePath).readAsString(), 'keep');
    expect(await source.readAsString(), 'keep');
  });

  test('v14 migration retains original links without assigning an owner',
      () async {
    final id = await store.saveReportWithAttachments(
      Report.fromMap({'no_polisi': 'AB 7317 BK'}),
      [const ReportAttachment(filePath: '/old/photo.jpg')],
    );
    final database = await store.db;
    await database
        .execute('ALTER TABLE report_attachments DROP COLUMN expense_type');
    await database
        .execute('ALTER TABLE report_attachments DROP COLUMN extra_id');
    await database.setVersion(14);
    final reports = await database.query('reports');
    final links = await database.query('report_attachments');
    await store.close();
    final upgraded = await store.db;
    expect(await upgraded.getVersion(), 15);
    expect(await upgraded.query('reports'), reports);
    expect(await upgraded.query('report_attachments'), [
      for (final link in links)
        {...link, 'expense_type': null, 'extra_id': null},
    ]);
    final photos = await store.getAttachments(id);
    expect(photos.single.owner, isNull);
    await store.saveReportWithAttachments((await store.getReport(id))!, photos);
    expect(await store.getAttachments(id), photos);
  });
}
