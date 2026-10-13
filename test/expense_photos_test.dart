import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bus_crew/db/database.dart';
import 'package:happy_bus_crew/models/report.dart';
import 'package:happy_bus_crew/models/report_attachment.dart';
import 'package:happy_bus_crew/screens/form_screen.dart';
import 'package:happy_bus_crew/screens/home_screen.dart';
import 'package:happy_bus_crew/screens/preview_screen.dart';
import 'package:happy_bus_crew/pdf/report_pdf.dart';
import 'package:happy_bus_crew/ui/app_theme.dart';
import 'package:happy_bus_crew/ui/expense_photo_manager.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite/sqflite.dart';

import 'support/pdf_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = DatabaseHelper.instance;
  late Directory temporary;
  late Report saved;
  late List<ReportAttachment> links;
  late List<String> picked;
  late List<File> sources;
  var pickCalls = 0;
  var failPicking = false;
  var failSaving = false;

  setUpAll(() async {
    databaseFactory = databaseFactorySqflitePlugin;
    await initializeDateFormatting('id_ID');
  });
  setUp(() async {
    await store.close();
    temporary = await Directory.systemTemp.createTemp('lpj-photo-widgets-');
    final bytes =
        (await rootBundle.load('assets/logo.png')).buffer.asUint8List();
    sources = [
      for (var i = 0; i < 4; i++)
        await File('${temporary.path}/$i.png').writeAsBytes(bytes),
    ];
    saved = Report.fromMap({'id': 1, 'no_polisi': 'AB 7317 BK'}).copyWith(
      extras: [
        ExtraExpense(id: 'office-a', name: 'Tol', amount: 1000),
        ExtraExpense(id: 'office-b', name: 'Tol', amount: 2000),
      ],
      hasGuestAllowance: true,
      guestTol: 3000,
      guestExtras: [ExtraExpense(id: 'discova-a', name: 'Tol', amount: 4000)],
    );
    links = [];
    picked = [];
    pickCalls = 0;
    failPicking = false;
    failSaving = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => temporary.path);
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/image_picker'), (call) async {
      expect(call.method, 'pickMultiImage');
      expect((call.arguments as Map)['limit'], isNull);
      pickCalls++;
      if (failPicking) throw PlatformException(code: 'denied');
      return picked;
    });
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.tekartik.sqflite'), (call) async {
      final args =
          call.arguments is Map ? call.arguments as Map : <String, dynamic>{};
      final sql = args['sql'] as String? ?? '';
      final values = args['arguments'] as List? ?? [];
      switch (call.method) {
        case 'getDatabasesPath':
          return temporary.path;
        case 'openDatabase':
          return {'id': 1};
        case 'query':
          if (sql.contains('PRAGMA user_version')) {
            return [
              {'user_version': 15}
            ];
          }
          if (sql.contains('FROM report_attachments')) {
            return [for (final photo in links) photo.toMap()];
          }
          if (sql.contains('FROM reports')) return [saved.toMap()];
          return <Map<String, Object?>>[];
        case 'update':
          if (failSaving) throw PlatformException(code: 'disk_full');
          if (sql.startsWith('UPDATE reports')) {
            final assignments = sql
                .substring(sql.indexOf(' SET ') + 5, sql.indexOf(' WHERE '))
                .split(',');
            var index = 0;
            saved = Report.fromMap({
              for (final assignment in assignments)
                assignment.split('=').first.trim():
                    assignment.split('=').last.trim() == 'NULL'
                        ? null
                        : values[index++],
            });
          }
          if (sql.startsWith('DELETE FROM report_attachments')) links.clear();
          return 1;
        case 'insert':
          if (sql.contains('INTO report_attachments')) {
            final columns = sql
                .substring(sql.indexOf('(') + 1, sql.indexOf(')'))
                .split(',');
            final placeholders = sql
                .substring(sql.indexOf('VALUES (') + 8, sql.lastIndexOf(')'))
                .split(',');
            var index = 0;
            links.add(ReportAttachment.fromMap({
              for (var i = 0; i < columns.length; i++)
                columns[i].trim():
                    placeholders[i].trim() == 'NULL' ? null : values[index++],
            }));
          }
          return 1;
        default:
          return null;
      }
    });
  });
  tearDown(() async {
    await store.close();
    await temporary.delete(recursive: true);
  });

  Future<void> ioPump(WidgetTester tester) async {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: screen));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder button(ExpenseOwner owner) => find.byKey(ValueKey(owner));
  const bbm = ExpenseOwner(ExpenseType.officeBbm);
  const meal = ExpenseOwner(ExpenseType.officeMeal);
  const first = ExpenseOwner(ExpenseType.officeExtra, extraId: 'office-a');
  const second = ExpenseOwner(ExpenseType.officeExtra, extraId: 'office-b');
  const guest = ExpenseOwner(ExpenseType.discovaExtra, extraId: 'discova-a');
  const tol = ExpenseOwner(ExpenseType.discovaTol);

  Future<void> add(
      WidgetTester tester, ExpenseOwner owner, List<File> files) async {
    await tap(tester, button(owner));
    picked = files.map((file) => file.path).toList();
    await tap(tester, find.text('Galeri'));
    await ioPump(tester);
    await tap(tester, find.text('Selesai'));
  }

  int count(WidgetTester tester, ExpenseOwner owner) {
    final text = tester
        .widget<Text>(
            find.descendant(of: button(owner), matching: find.byType(Text)))
        .data!;
    return text == '+' ? 0 : int.parse(text);
  }

  Future<PreviewScreen> preview(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Pratinjau PDF tanpa menyimpan'));
    for (var i = 0;
        i < 30 && find.byType(PreviewScreen).evaluate().isEmpty;
        i++) {
      await ioPump(tester);
    }
    expect(find.byType(PreviewScreen), findsOneWidget);
    return tester.widget<PreviewScreen>(find.byType(PreviewScreen));
  }

  testWidgets(
      'repeated gallery adds, viewing and removal stay with each expense',
      (tester) async {
    await pump(tester, FormScreen(report: saved));
    await tap(tester, find.text('2. Keuangan Kantor'));
    for (final owner in [bbm, meal, first, second]) {
      expect(count(tester, owner), 0);
    }
    await add(tester, first, sources.take(2).toList());
    await add(tester, first, [sources[2], sources[0]]);
    expect(count(tester, first), 4);
    expect(count(tester, second), 0);
    await add(tester, second, [sources[3]]);
    await add(tester, bbm, [sources[0]]);
    await add(tester, meal, [sources[1]]);
    expect(pickCalls, 5);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama extra 1'), 'Parkir');
    await tester.pumpAndSettle();
    expect(count(tester, first), 4);
    expect(count(tester, second), 1);
    await tap(tester, button(first));
    expect(find.text('Foto Parkir'), findsOneWidget);
    await tap(tester, find.bySemanticsLabel('Lihat foto 1'));
    expect(find.byType(InteractiveViewer), findsOneWidget);
    Navigator.of(tester.element(find.byType(InteractiveViewer))).pop();
    await tester.pumpAndSettle();
    await tap(tester, find.byTooltip('Hapus foto 2'));
    expect(find.text('3 foto'), findsOneWidget);
    await tap(tester, find.text('Selesai'));
    expect(count(tester, first), 3);
    expect(count(tester, second), 1);
    await tap(tester, button(first));
    expect(
        tester
            .widget<ExpensePhotoManager>(find.byType(ExpensePhotoManager))
            .photos
            .map((photo) => photo.filePath),
        [sources[0].path, sources[2].path, sources[0].path]);
    await tap(tester, find.text('Selesai'));
    final draft = await preview(tester);
    expect(
        draft.report.extras.map((extra) => extra.id), ['office-a', 'office-b']);
    expect(draft.report.extras.first.name, 'Parkir');
    expect(draft.attachmentImages, hasLength(6));
    expect(draft.attachmentImages.map((image) => image.owner),
        [first, first, first, second, bbm, meal]);
    final draftPdf = await ReportPdfBuilder.build(draft.report,
        attachmentImages: draft.attachmentImages);
    final text = normalizePdfText((await pdfPageText(draftPdf)).join(' '));
    expect(text, contains('c. Parkir'));
    expect(text, contains('d. Tol'));
    expect(text, contains('a. BBM'));
    expect(links, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final owner in [first, guest]) {
    testWidgets(
        '${owner.type.name} deletion confirms, cancels and discards without deleting saved files',
        (tester) async {
      links = [
        ReportAttachment(filePath: sources[0].path, owner: owner),
        ReportAttachment(filePath: sources[1].path, owner: second),
      ];
      await pump(tester, const HomeScreen());
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tap(tester, find.text('Ubah laporan'));
      await tap(
          tester,
          find.text(
              owner == guest ? '3. Keuangan Discova' : '2. Keuangan Kantor'));
      expect(count(tester, owner), 1);
      await tap(tester, find.text('Hapus').first);
      expect(find.text('Hapus extra beserta fotonya?'), findsOneWidget);
      await tap(tester, find.text('Batal'));
      expect(count(tester, owner), 1);
      await tap(tester, find.text('Hapus').first);
      await tap(tester, find.text('Hapus extra'));
      expect(button(owner), findsNothing);
      if (owner == first) expect(count(tester, second), 1);
      await tap(tester, find.byTooltip('Kembali'));
      expect(find.text('Keluar tanpa menyimpan?'), findsOneWidget);
      await tap(tester, find.text('Keluar'));
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(links, hasLength(2));
      expect(saved.extras, hasLength(2));
      expect(saved.guestExtras, hasLength(1));
      expect(await tester.runAsync(() => sources[0].exists()), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'individual removal alone marks draft dirty but cancellation preserves saved links',
      (tester) async {
    links = [ReportAttachment(filePath: sources[0].path, owner: bbm)];
    await pump(tester, FormScreen(report: saved));
    await tap(tester, find.text('2. Keuangan Kantor'));
    await tap(tester, button(bbm));
    await tap(tester, find.byTooltip('Hapus foto 1'));
    await tap(tester, find.text('Selesai'));
    expect(count(tester, bbm), 0);
    await tap(tester, find.byTooltip('Kembali'));
    expect(find.text('Keluar tanpa menyimpan?'), findsOneWidget);
    await tap(tester, find.text('Lanjut mengisi'));
    expect(links, hasLength(1));
    expect(await tester.runAsync(() => sources[0].exists()), isTrue);
  });

  testWidgets(
      'save, reopen and both previews retain photos when Discova is disabled',
      (tester) async {
    await pump(tester, const HomeScreen());
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tap(tester, find.text('Ubah laporan'));
    await tap(tester, find.text('2. Keuangan Kantor'));
    await add(tester, first, [sources[0]]);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama extra 1'), 'Parkir');
    await tap(tester, find.text('3. Keuangan Discova'));
    for (final owner in [
      tol,
      const ExpenseOwner(ExpenseType.discovaCrossing),
      const ExpenseOwner(ExpenseType.discovaParking),
      guest
    ]) {
      await add(tester, owner, [sources[1]]);
    }
    await tap(tester, find.text('1. Periode'));
    await tap(tester, find.text('Tamu Discova'));
    expect(find.text('3. Keuangan Discova'), findsNothing);
    await tap(tester, find.text('3. Penyelesaian'));
    expect(find.text('Penyelesaian'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Nama crew'), findsOneWidget);
    expect(
        find.widgetWithText(TextFormField, 'Catatan tambahan'), findsOneWidget);
    expect(find.text('Defisit kantor'), findsOneWidget);
    expect(find.text('Periksa pratinjau PDF'), findsOneWidget);
    expect(find.text('Galeri'), findsNothing);
    expect(find.text('Kamera'), findsNothing);
    final draft = await preview(tester);
    expect(draft.attachmentImages, hasLength(5));
    expect(draft.report.hasGuestAllowance, isFalse);
    Navigator.of(tester.element(find.byType(PreviewScreen))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan laporan'));
    for (var i = 0;
        i < 40 && find.byType(FormScreen).evaluate().isNotEmpty;
        i++) {
      await ioPump(tester);
    }
    await tester.pumpAndSettle();
    expect(find.byType(FormScreen), findsNothing);
    expect(saved.hasGuestAllowance, isFalse);
    expect(saved.guestTol, 3000);
    expect(saved.extras.first.id, 'office-a');
    expect(saved.extras.first.name, 'Parkir');
    expect(links.map((photo) => photo.owner), [
      first,
      tol,
      const ExpenseOwner(ExpenseType.discovaCrossing),
      const ExpenseOwner(ExpenseType.discovaParking),
      guest
    ]);
    expect(
        links.every(
            (photo) => !sources.any((source) => source.path == photo.filePath)),
        isTrue);

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lihat PDF'));
    for (var i = 0;
        i < 30 && find.byType(PreviewScreen).evaluate().isEmpty;
        i++) {
      await ioPump(tester);
    }
    final savedPreview =
        tester.widget<PreviewScreen>(find.byType(PreviewScreen));
    expect(savedPreview.attachmentImages.map((image) => image.owner),
        draft.attachmentImages.map((image) => image.owner));
    expect(savedPreview.attachmentImages.map((image) => image.bytes),
        draft.attachmentImages.map((image) => image.bytes));
    for (final preview in [draft, savedPreview]) {
      final pdf = await ReportPdfBuilder.build(preview.report,
          attachmentImages: preview.attachmentImages);
      final text = normalizePdfText((await pdfPageText(pdf)).join(' '));
      expect(text, contains('LPJ Kantor'));
      expect(text, contains('a. Parkir'));
      expect(text, contains('LPJ Discova'));
      expect(text, contains('a. Tol'));
      expect(text, contains('b. Penyeberangan'));
      expect(text, contains('c. Parkir'));
      expect(text, isNot(contains('Uang Saku Discova')));
    }
    Navigator.of(tester.element(find.byType(PreviewScreen))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tap(tester, find.text('Ubah laporan'));
    await tap(tester, find.text('2. Keuangan Kantor'));
    expect(count(tester, first), 1);
    expect(count(tester, second), 0);
    await tap(tester, find.text('3. Keuangan Discova'));
    expect(count(tester, guest), 1);
    expect(count(tester, tol), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new extra IDs stay stable and are never reused after deletion',
      (tester) async {
    saved = saved.copyWith(extras: []);
    await pump(tester, FormScreen(report: saved));
    await tap(tester, find.text('2. Keuangan Kantor'));
    await tap(tester, find.text('Tambah Extra'));
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama extra 1'), 'Tol');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Harga extra 1'), '1000');
    await tester.pumpAndSettle();
    ExpenseOwner addedOwner() => tester
        .widgetList<OutlinedButton>(
            find.byWidgetPredicate((widget) => widget is OutlinedButton))
        .map((widget) => widget.key)
        .whereType<ValueKey<ExpenseOwner>>()
        .map((key) => key.value)
        .singleWhere((owner) => owner.type == ExpenseType.officeExtra);
    final original = addedOwner();
    await add(tester, original, [sources[0]]);
    await tap(tester, find.text('4. Penyelesaian'));
    await tap(tester, find.text('2. Keuangan Kantor'));
    expect(addedOwner(), original);
    expect(count(tester, original), 1);
    await tap(tester, find.text('Hapus'));
    await tap(tester, find.text('Hapus extra'));
    await tap(tester, find.text('Tambah Extra'));
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama extra 1'), 'Tol');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Harga extra 1'), '1000');
    await tester.pumpAndSettle();
    final replacement = addedOwner();
    expect(replacement, isNot(original));
    expect(count(tester, replacement), 0);
    final draft = await preview(tester);
    expect(draft.attachmentImages, isEmpty);
    expect(draft.report.extras.single.id, replacement.extraId);
  });

  testWidgets('save failure retains the photo draft for retry', (tester) async {
    await pump(tester, FormScreen(report: saved));
    await tap(tester, find.text('2. Keuangan Kantor'));
    await add(tester, bbm, [sources[0]]);
    await tap(tester, find.text('4. Penyelesaian'));
    failSaving = true;
    await tester.tap(find.text('Simpan laporan'));
    for (var i = 0;
        i < 30 &&
            find
                .text('Gagal menyimpan. Isian tetap ada. Coba lagi.')
                .evaluate()
                .isEmpty;
        i++) {
      await ioPump(tester);
    }
    expect(find.text('Gagal menyimpan. Isian tetap ada. Coba lagi.'),
        findsOneWidget);
    expect(links, isEmpty);
    await tap(tester, find.text('2. Keuangan Kantor'));
    expect(count(tester, bbm), 1);
    expect(await tester.runAsync(() => sources[0].exists()), isTrue);
    expect(
        await tester.runAsync(
            () => Directory('${temporary.path}/attachments').list().toList()),
        isEmpty);
  });

  testWidgets('picker cancellation and failure leave existing photos unchanged',
      (tester) async {
    links = [ReportAttachment(filePath: sources[0].path, owner: bbm)];
    await pump(tester, FormScreen(report: saved));
    await tap(tester, find.text('2. Keuangan Kantor'));
    await tap(tester, button(bbm));
    await tap(tester, find.text('Galeri'));
    expect(find.text('1 foto'), findsOneWidget);
    failPicking = true;
    await tap(tester, find.text('Galeri'));
    expect(
        find.text('Foto belum dapat diambil. Periksa izin kamera atau galeri.'),
        findsOneWidget);
    expect(find.text('1 foto'), findsOneWidget);
    await tap(tester, find.text('Selesai'));
    expect(count(tester, bbm), 1);
    expect(find.byType(ExpensePhotoManager), findsNothing);
  });
}
