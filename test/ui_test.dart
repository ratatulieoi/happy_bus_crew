import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bus_crew/main.dart';
import 'package:happy_bus_crew/models/report.dart';
import 'package:happy_bus_crew/screens/form_screen.dart';
import 'package:happy_bus_crew/screens/home_screen.dart';
import 'package:happy_bus_crew/screens/preview_screen.dart';
import 'package:happy_bus_crew/ui/app_theme.dart';
import 'package:happy_bus_crew/ui/components.dart';
import 'package:happy_bus_crew/ui/period_range_picker.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite/sqflite.dart';

Report fixture(
        {int id = 1,
        DateTime? tanggalBuat,
        String plate = 'AB 7317 BK',
        String driver = 'Budi Santoso',
        int allowance = 2000000}) =>
    Report(
      id: id,
      tanggalBuat: tanggalBuat ?? DateTime(2026, 6, 12),
      hariTglBerangkat: 'Jumat, 12/06/2026',
      jamBerangkat: '08:00',
      hariTglKembali: 'Sabtu, 13/06/2026',
      noPolisi: plate,
      namaTamu: 'Bpk. Hartono',
      pengemudi: driver,
      kernet: 'Agus',
      kmAwal: 124000,
      kmAkhir: 124850,
      uangSaku: allowance,
      bbm: 900000,
      extras: [
        ExtraExpense(name: 'Parkir', amount: 20000),
        ExtraExpense(name: 'Tol', amount: 30000),
      ],
      pembayaranTagihan: 100000,
      namaCrew: 'Budi Santoso',
      catatan: 'Perjalanan lancar.',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var reports = <Report>[];
  Map<String, Object?>? savedReport;
  var failQueries = false;
  final captureKey = GlobalKey();

  setUpAll(() async {
    databaseFactory = databaseFactorySqflitePlugin;
    await initializeDateFormatting('id_ID');
    final fontRoot = Platform.environment['UI_TEST_FONT_DIR'];
    if (fontRoot != null) {
      final fonts = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(
            await File('$fontRoot/Roboto-Regular.ttf').readAsBytes())))
        ..addFont(Future.value(ByteData.sublistView(
            await File('$fontRoot/Roboto-Bold.ttf').readAsBytes())));
      await fonts.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(
            await File('$fontRoot/MaterialIcons-Regular.otf').readAsBytes())));
      await icons.load();
    }
  });

  setUp(() {
    reports = [
      fixture(),
      fixture(
          id: 2,
          tanggalBuat: DateTime(2026, 6, 11),
          plate: 'AB 7402 BK',
          driver: 'Dedi',
          allowance: 500000)
    ];
    savedReport = null;
    failQueries = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.tekartik.sqflite'),
            (call) async {
      final args =
          call.arguments is Map ? call.arguments as Map : <String, dynamic>{};
      switch (call.method) {
        case 'getDatabasesPath':
          return '/tmp/happy-bus-test-db';
        case 'openDatabase':
          return {'id': 1};
        case 'query':
          if (failQueries) throw PlatformException(code: 'db_error');
          final sql = args['sql'] as String;
          if (sql.contains('PRAGMA user_version')) {
            return [
              {'user_version': 14}
            ];
          }
          if (sql.contains('FROM settings') || sql.contains('FROM buses')) {
            fail('The fixed catalog must not query bus storage.');
          }
          if (sql.contains('MAX(km_akhir)')) {
            fail('Mileage tracking queries must not run.');
          }
          if (sql.contains('FROM reports')) {
            final rows = reports.map((r) => r.toMap()).toList();
            if (sql.contains('ORDER BY')) {
              rows.sort((a, b) {
                final date = (b['tanggal_buat'] as String)
                    .compareTo(a['tanggal_buat'] as String);
                if (date != 0) return date;
                return (b['id'] as int).compareTo(a['id'] as int);
              });
            }
            return rows;
          }
          return <Map<String, Object?>>[];
        case 'insert':
          final sql = args['sql'] as String;
          final values = args['arguments'] as List;
          if (sql.contains('settings') || sql.contains('buses')) {
            fail('The fixed catalog must not write bus storage.');
          }
          if (sql.contains('INTO reports')) {
            final columns = sql
                .substring(sql.indexOf('(') + 1, sql.indexOf(')'))
                .split(',')
                .map((column) => column.trim())
                .toList();
            final placeholders = sql
                .substring(sql.indexOf('VALUES (') + 8, sql.lastIndexOf(')'))
                .split(',');
            var index = 0;
            savedReport = {
              for (var i = 0; i < columns.length; i++)
                columns[i]:
                    placeholders[i].trim() == 'NULL' ? null : values[index++],
            };
          }
          return 3;
        // Sqflite sends both UPDATE and DELETE through this method.
        case 'update':
          final sql = args['sql'] as String;
          final values = args['arguments'] as List;
          if (sql.contains('settings') || sql.contains('buses')) {
            fail('The fixed catalog must not change bus storage.');
          }
          if (sql.startsWith('UPDATE reports')) {
            final assignments = sql
                .substring(sql.indexOf(' SET ') + 5, sql.indexOf(' WHERE '))
                .split(',');
            var index = 0;
            savedReport = {
              for (final assignment in assignments)
                assignment.split('=').first.trim():
                    assignment.split('=').last.trim() == 'NULL'
                        ? null
                        : values[index++],
            };
          }
          return 1;
        case 'execute':
          return null;
        default:
          return null;
      }
    });
  });

  Future<void> pumpScreen(WidgetTester tester, Widget screen,
      {Size size = const Size(390, 844), double scale = 1}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('id', 'ID'),
      supportedLocales: const [Locale('id', 'ID')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      theme: Platform.environment['UI_TEST_FONT_DIR'] == null
          ? buildAppTheme()
          : buildAppTheme().copyWith(
              textTheme: buildAppTheme().textTheme.apply(fontFamily: 'Roboto'),
              primaryTextTheme:
                  buildAppTheme().primaryTextTheme.apply(fontFamily: 'Roboto'),
              appBarTheme: buildAppTheme().appBarTheme.copyWith(
                  titleTextStyle: buildAppTheme()
                      .appBarTheme
                      .titleTextStyle!
                      .copyWith(fontFamily: 'Roboto')),
              chipTheme: buildAppTheme().chipTheme.copyWith(
                  labelStyle: buildAppTheme()
                      .chipTheme
                      .labelStyle!
                      .copyWith(fontFamily: 'Roboto')),
            ),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: captureKey, child: child!)),
      home: screen,
    ));
    await tester.pumpAndSettle();
  }

  /// A .first or .last finder throws when it matches nothing, so an empty
  /// result has to be read without evaluating the finder directly.
  bool isBuilt(Finder target) {
    try {
      return target.evaluate().isNotEmpty;
    } on StateError {
      return false;
    }
  }

  Future<void> dragPage(WidgetTester tester, Rect rect, Offset move) async {
    await tester.dragFrom(Offset(rect.left + 4, rect.center.dy), move);
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Bring [target] into the built range of the page and into the viewport.
  ///
  /// A list only builds the children near its viewport, so a target that was
  /// scrolled out of range has no element to act on. Rewind the page first,
  /// then walk down until the target is built. Drags start in the list
  /// padding, because a drag that begins on a text field is kept by the field
  /// for its own selection gesture and never scrolls the page.
  Future<void> reveal(WidgetTester tester, Finder target) async {
    final pages = <({Finder finder, Rect rect})>[];
    for (final element in find.byType(Scrollable).evaluate()) {
      final finder = find.byElementPredicate((e) => e == element);
      final rect = tester.getRect(finder);
      if (rect.width > 200 && rect.height > 200) {
        pages.add((finder: finder, rect: rect));
      }
    }
    pages.sort((a, b) =>
        (b.rect.width * b.rect.height).compareTo(a.rect.width * a.rect.height));

    for (final page in pages) {
      for (var i = 0; i < 3; i++) {
        await dragPage(tester, page.rect, const Offset(0, 3000));
      }
      for (var i = 0; i < 40 && !isBuilt(target); i++) {
        await dragPage(tester, page.rect, const Offset(0, -400));
      }
      if (isBuilt(target)) {
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        return;
      }
    }
    throw StateError('Target not reachable: ${target.toString()}');
  }

  String dayInput(DateTime day) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(day.day)}/${two(day.month)}/${day.year}';
  }

  Future<PeriodRangePickerDialog> openRange(
      WidgetTester tester, int index) async {
    final trigger = find.byKey(ValueKey('period-range-$index'));
    await reveal(tester, trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(find.byType(PeriodRangePickerDialog), findsOneWidget);
    return tester
        .widget<PeriodRangePickerDialog>(find.byType(PeriodRangePickerDialog));
  }

  Finder calendarDay(WidgetTester tester, DateTime date) {
    final localizations = MaterialLocalizations.of(
        tester.element(find.byType(PeriodRangePickerDialog)));
    return find.descendant(
        of: find.byType(PeriodRangePickerDialog),
        matching: find.byWidgetPredicate((widget) =>
            widget is Semantics &&
            widget.properties.label == localizations.formatFullDate(date)));
  }

  Future<void> returnRange(
      WidgetTester tester, DateTime start, DateTime end) async {
    Navigator.of(tester.element(find.byType(PeriodRangePickerDialog)))
        .pop(DateTimeRange(start: start, end: end));
    await tester.pumpAndSettle();
  }

  Future<void> addPeriod(
      WidgetTester tester, DateTime start, DateTime end, TripType type) async {
    await reveal(tester, find.text('Tambah periode'));
    await tester.tap(find.text('Tambah periode'));
    await tester.pumpAndSettle();
    final trigger = find
        .byWidgetPredicate((widget) =>
            widget is InkWell &&
            widget.key is ValueKey<String> &&
            (widget.key as ValueKey<String>).value.startsWith('period-range-'))
        .last;
    await reveal(tester, trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await returnRange(tester, start, end);
    final label = type == TripType.luarKota ? 'LK' : 'DK';
    final choice = find.widgetWithText(ChoiceChip, label).last;
    await reveal(tester, choice);
    await tester.tap(choice);
    await tester.pumpAndSettle();
  }

  Future<void> fillExtra(
      WidgetTester tester, int row, String name, String amount) async {
    final nameField = find.widgetWithText(TextFormField, 'Nama extra $row');
    final priceField = find.widgetWithText(TextFormField, 'Harga extra $row');
    await reveal(tester, nameField);
    await tester.enterText(nameField, name);
    await reveal(tester, priceField);
    await tester.enterText(priceField, amount);
    await tester.pumpAndSettle();
  }

  Future<void> fillGuestExtra(
      WidgetTester tester, String name, String amount) async {
    final nameField =
        find.widgetWithText(TextFormField, 'Nama extra Discova 1');
    final priceField =
        find.widgetWithText(TextFormField, 'Harga extra Discova 1');
    await reveal(tester, nameField);
    await tester.enterText(nameField, name);
    await reveal(tester, priceField);
    await tester.enterText(priceField, amount);
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final directory = Platform.environment['UI_TEST_SCREENSHOT_DIR'];
    if (directory == null) return;
    await tester.pumpAndSettle();
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> selectBus(WidgetTester tester,
      {String label = 'HG 2 • AB 7317 BK'}) async {
    final dropdown = find.byType(DropdownButtonFormField<String>);
    await reveal(tester, dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  void expectNoBusManagement() {
    for (final label in [
      'Daftar bus',
      'Tambah bus',
      'Ubah bus',
      'Hapus bus',
      'Simpan bus',
      'Tambahkan bus pertama',
      'BUS AKTIF'
    ]) {
      expect(find.text(label), findsNothing);
      expect(find.byTooltip(label), findsNothing);
    }
    expect(find.widgetWithText(TextFormField, 'Nomor polisi'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Nama bus'), findsNothing);
  }

  testWidgets('first launch opens reports without bus setup or CRUD controls',
      (tester) async {
    reports.clear();
    await tester.pumpWidget(const HappyBusApp());
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Buat laporan baru'), findsOneWidget);
    expectNoBusManagement();
    await tester.tap(find.text('Buat laporan baru'));
    await tester.pumpAndSettle();
    expect(find.byType(FormScreen), findsOneWidget);
    expectNoBusManagement();
    expect(find.text('Pilih bus'), findsOneWidget);
    expect(
        tester
            .widget<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>))
            .initialValue,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'bus dropdown has only the fixed catalog and uses the input theme',
      (tester) async {
    await pumpScreen(tester, const FormScreen());
    final field = find.byType(DropdownButtonFormField<String>);
    final dropdown = tester.widget<DropdownButton<String>>(find.descendant(
        of: field, matching: find.byType(DropdownButton<String>)));
    expect(dropdown.value, isNull);
    expect(dropdown.items!.map((item) => item.value), [
      'AB 7317 BK',
      'AB 7402 BK',
      'AB 7403 BK',
      'AB 7454 BK',
      'AB 7497 BK',
    ]);
    expect(dropdown.items!.map((item) => (item.child as Text).data), [
      'HG 2 • AB 7317 BK',
      'HG 3 • AB 7402 BK',
      'HG 4 • AB 7403 BK',
      'HG 5 • AB 7454 BK',
      'HG 6 • AB 7497 BK',
    ]);
    final decoration = tester
        .widget<InputDecorator>(
            find.descendant(of: field, matching: find.byType(InputDecorator)))
        .decoration;
    expect(
        decoration.fillColor, buildAppTheme().inputDecorationTheme.fillColor);
    expect(decoration.contentPadding, const EdgeInsets.all(12));
    expect(decoration.constraints?.minHeight, 48);
    expectNoBusManagement();
    await selectBus(tester, label: 'HG 6 • AB 7497 BK');
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Keuangan Kantor'), findsOneWidget);
    await tester.tap(find.text('Kembali'));
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButtonFormField<String>>(field).initialValue,
        'AB 7497 BK');
    await tester.tap(find.byTooltip('Kembali'));
    await tester.pumpAndSettle();
    expect(find.text('Keluar tanpa menyimpan?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing bus blocks next, every direct step and preview',
      (tester) async {
    await pumpScreen(tester, const FormScreen());
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Pilih bus terlebih dahulu.'), findsOneWidget);
    expect(find.text('Periode'), findsNWidgets(2));
    await tester.tap(find.text('Tamu Discova'));
    await tester.pumpAndSettle();
    for (final label in [
      '2. Keuangan Kantor',
      '3. Keuangan Discova',
      '4. Penyelesaian'
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.text('LANGKAH 1 DARI 4'), findsOneWidget);
      expect(find.text('Pilih bus terlebih dahulu.'), findsOneWidget);
      expect(find.text('Simpan laporan'), findsNothing);
    }
    await tester.tap(find.byTooltip('Pratinjau PDF tanpa menyimpan'));
    await tester.pumpAndSettle();
    expect(find.byType(PreviewScreen), findsNothing);
    expect(savedReport, isNull);
    await selectBus(tester, label: 'HG 4 • AB 7403 BK');
    expect(find.text('Pilih bus terlebih dahulu.'), findsNothing);
    await reveal(tester, find.text('4. Penyelesaian'));
    await tester.tap(find.text('4. Penyelesaian'));
    await tester.pumpAndSettle();
    expect(find.text('Simpan laporan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save validates bus independently of step navigation',
      (tester) async {
    await pumpScreen(tester, const FormScreen());
    await selectBus(tester);
    await reveal(tester, find.text('3. Penyelesaian'));
    await tester.tap(find.text('3. Penyelesaian'));
    await tester.pumpAndSettle();
    final save = tester
        .widget<FilledButton>(find.ancestor(
            of: find.text('Simpan laporan'),
            matching:
                find.byWidgetPredicate((widget) => widget is FilledButton)))
        .onPressed!;
    await tester.tap(find.text('1. Periode'));
    await tester.pumpAndSettle();
    // Invoke the saved action after clearing selection to test its own guard.
    tester
        .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>))
        .onChanged!(null);
    await tester.pumpAndSettle();
    save();
    await tester.pumpAndSettle();
    expect(savedReport, isNull);
    expect(find.text('Periode'), findsNWidgets(2));
    expect(find.text('Pilih bus terlebih dahulu.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected bus reaches preview without saving', (tester) async {
    await pumpScreen(tester, const FormScreen());
    await selectBus(tester, label: 'HG 3 • AB 7402 BK');
    await tester.tap(find.byTooltip('Pratinjau PDF tanpa menyimpan'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final preview = tester.widget<PreviewScreen>(find.byType(PreviewScreen));
    expect(preview.report.noPolisi, 'AB 7402 BK');
    expect(savedReport, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard loads, searches, filters and opens edit',
      (tester) async {
    await pumpScreen(tester, const HomeScreen());
    expect(find.text('HG 2'), findsWidgets);
    expectNoBusManagement();
    expect(find.text('Kilometer terakhir'), findsNothing);
    expect(find.text('Jarak tempuh'), findsNothing);
    expect(find.text('Tersimpan di perangkat'), findsNothing);
    await capture(tester, 'home');
    final search = find.byType(TextField);
    await tester.ensureVisible(search);
    await tester.enterText(search, 'Dedi');
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('HG 3 • Dedi'), findsOneWidget);
    expect(find.text('HG 2 • Budi Santoso'), findsNothing);
    await tester.tap(find.byTooltip('Hapus pencarian'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'HG 2'));
    await tester.pumpAndSettle();
    expect(find.text('HG 3 • Dedi'), findsNothing);
    expect(find.text('HG 2 • Budi Santoso'), findsOneWidget);
    await tester.tap(find.byTooltip('Tindakan laporan').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ubah laporan'));
    await tester.pumpAndSettle();
    expect(find.byType(FormScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty and recoverable loading error states', (tester) async {
    reports = [];
    await pumpScreen(tester, const HomeScreen());
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Perjalanan pertama dimulai di sini'), findsOneWidget);
    failQueries = true;
    await tester.tap(find.byTooltip('Muat ulang'));
    await tester.pumpAndSettle();
    expect(find.text('Belum bisa memuat data'), findsOneWidget);
    failQueries = false;
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();
    expect(find.text('Laporan crew'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all input steps use compact styling without changing Home',
      (tester) async {
    await pumpScreen(
        tester,
        FormScreen(
            report: fixture().copyWith(
          hasGuestAllowance: true,
          guestUangSaku: 100000,
        )));
    final headings = [
      'Periode',
      'Keuangan Kantor',
      'Keuangan Discova',
      'Penyelesaian'
    ];
    final fields = [
      'Nama tamu',
      'Uang saku',
      'Uang saku diterima',
      'Nama crew'
    ];
    for (var step = 0; step < headings.length; step++) {
      final pageHeading = find.text(headings[step]).first;
      await reveal(tester, pageHeading);
      expect(tester.widget<Text>(pageHeading).style?.fontSize, 20);
      final field = find.widgetWithText(TextFormField, fields[step]);
      await reveal(tester, field);
      final theme = Theme.of(tester.element(field));
      expect(theme.textTheme.bodyLarge?.fontSize, 14);
      expect(theme.textTheme.titleMedium?.fontSize, 14);
      expect(
          theme.inputDecorationTheme.contentPadding, const EdgeInsets.all(12));
      expect(theme.inputDecorationTheme.constraints?.minHeight, 48);
      expect(theme.inputDecorationTheme.fillColor,
          buildAppTheme().inputDecorationTheme.fillColor);
      expect(theme.filledButtonTheme.style!.minimumSize!.resolve({}),
          const Size(48, 48));
      expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
      for (final card
          in tester.widgetList<SectionCard>(find.byType(SectionCard))) {
        expect(card.padding, const EdgeInsets.all(16));
      }
      for (final heading
          in tester.widgetList<SectionHeading>(find.byType(SectionHeading))) {
        expect(heading.compact, isTrue);
      }
      for (final label in [
        'Jam berangkat',
        'KM awal',
        'KM akhir',
        'Kilometer',
        'Uang saku diterima dari kantor.',
        'Kosongkan jika tidak ada.',
        'Nama untuk tanda tangan PDF.',
        'Uang saku tamu diterima, terpisah dari kas utama.'
      ]) {
        expect(find.text(label), findsNothing);
      }
      if (step < headings.length - 1) {
        await tester.tap(find.text('Lanjut'));
        await tester.pumpAndSettle();
      }
    }
    await pumpScreen(tester, const HomeScreen());
    final homeTheme = Theme.of(tester.element(find.byType(TextField)));
    expect(homeTheme.textTheme.bodyLarge?.fontSize, 16);
    expect(homeTheme.inputDecorationTheme.contentPadding,
        buildAppTheme().inputDecorationTheme.contentPadding);
    expect(tester.widget<BottomActionBar>(find.byType(BottomActionBar)).padding,
        const EdgeInsets.fromLTRB(20, 12, 20, 12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('report steps retain all values and update balance',
      (tester) async {
    await pumpScreen(tester, FormScreen(report: fixture()));
    expect(find.text('Jam berangkat'), findsNothing);
    expect(find.text('KM awal'), findsNothing);
    expect(find.text('KM akhir'), findsNothing);
    expect(find.text('Periode'), findsNWidgets(2));
    await capture(tester, 'report-trip');
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await capture(tester, 'report-finance');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Uang saku'), '1000000');
    await reveal(tester, find.text('Sisa uang kantor'));
    expect(find.text('Rp 950.000'), findsOneWidget);
    expect(find.text('Rp 50.000'), findsOneWidget);
    final paymentField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Pembayaran tagihan'));
    expect(paymentField.controller!.text, '100.000');
    expect(find.text('Sisa uang kantor'), findsOneWidget);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Budi Santoso'), findsOneWidget);
    expect(find.text('Perjalanan lancar.'), findsOneWidget);
    await capture(tester, 'report-attachments');
    await tester.tap(find.text('Kembali').last);
    await tester.pumpAndSettle();
    expect(find.text('1.000.000'), findsOneWidget);
    await tester.tap(find.byTooltip('Kembali'));
    await tester.pumpAndSettle();
    expect(find.text('Keluar tanpa menyimpan?'), findsOneWidget);
    await tester.tap(find.text('Lanjut mengisi'));
    await tester.pumpAndSettle();
    expect(find.byType(FormScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Discova toggle is the first Periode input and saves guest columns',
      (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.tap(find.text('Buat laporan baru'));
    await tester.pumpAndSettle();

    final toggle = find
        .ancestor(
            of: find.text('Tamu Discova'),
            matching: find.byType(GestureDetector))
        .first;
    final toggleWidget = tester.widget<GestureDetector>(toggle);
    final controls = tester
        .widgetList<Widget>(find.descendant(
          of: find.byType(ListView),
          matching: find.byWidgetPredicate((widget) =>
              identical(widget, toggleWidget) ||
              widget is ChoiceChip ||
              widget is DropdownButtonFormField<String> ||
              widget is TextFormField),
        ))
        .toList();
    final toggleIndex = controls.indexOf(toggleWidget);
    expect(toggleIndex, greaterThan(0));
    expect(controls.take(toggleIndex), everyElement(isA<ChoiceChip>()));
    expect(controls[toggleIndex + 1], isA<DropdownButtonFormField<String>>());
    expect(
        controls[toggleIndex + 2],
        same(tester.widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Nama tamu'))));
    expect(find.ancestor(of: toggle, matching: find.byType(SectionCard)),
        findsNothing);

    final track = find
        .descendant(of: toggle, matching: find.byType(AnimatedContainer))
        .first;
    final trackWidget = tester.widget<AnimatedContainer>(track);
    expect(trackWidget.decoration, isA<BoxDecoration>());
    expect((trackWidget.decoration! as BoxDecoration).color,
        buildAppTheme().inputDecorationTheme.fillColor);
    expect((trackWidget.decoration! as BoxDecoration).border, isA<Border>());
    expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
    await tester.tap(find.text('Tamu Discova'));
    await tester.pumpAndSettle();
    await selectBus(tester);
    await reveal(
        tester, find.widgetWithText(ChoiceChip, '3. Keuangan Discova'));
    expect(find.text('3. Keuangan Discova'), findsOneWidget);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    for (final label in [
      'Uang saku diterima',
      'Tol',
      'Penyeberangan',
      'Parkir',
      'Catatan Discova',
    ]) {
      await reveal(tester, find.widgetWithText(TextFormField, label));
    }

    for (final entry in {
      'Uang saku diterima': '100000',
      'Tol': '10000',
      'Penyeberangan': '20000',
      'Parkir': '5000',
    }.entries) {
      final field = find.widgetWithText(TextFormField, entry.key);
      await reveal(tester, field);
      await tester.enterText(field, entry.value);
    }
    final note = find.widgetWithText(TextFormField, 'Catatan Discova');
    await reveal(tester, note);
    await tester.enterText(note, 'Titipan tamu');
    await reveal(tester, find.text('Tambah Extra Discova'));
    await tester.tap(find.text('Tambah Extra Discova'));
    await tester.pumpAndSettle();
    await fillGuestExtra(tester, 'Bagasi', '3000');

    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan laporan'));
    await tester.pumpAndSettle();

    expect(savedReport, isNotNull);
    expect(savedReport!['has_guest_allowance'], 1);
    expect(savedReport!['guest_uang_saku'], 100000);
    expect(savedReport!['guest_tol'], 10000);
    expect(savedReport!['guest_penyeberangan'], 20000);
    expect(savedReport!['guest_parkir'], 5000);
    final savedExtra = Report.fromMap(savedReport!).guestExtras.single;
    expect(savedExtra.name, 'Bagasi');
    expect(savedExtra.amount, 3000);
    expect(savedExtra.id, isNotEmpty);
    expect(savedReport!['guest_catatan'], 'Titipan tamu');
  });

  testWidgets('Discova extra validation blocks incomplete rows',
      (tester) async {
    await pumpScreen(tester, const FormScreen());
    await selectBus(tester);
    await reveal(tester, find.text('Tamu Discova'));
    await tester.tap(find.text('Tamu Discova'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('LANGKAH 1 DARI 4'));
    expect(find.text('LANGKAH 1 DARI 4'), findsOneWidget);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('3. Keuangan Discova'), findsOneWidget);

    await reveal(tester, find.text('Tambah Extra Discova'));
    await tester.tap(find.text('Tambah Extra Discova'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();

    expect(find.text('Extra Discova 1 belum diisi. Isi atau hapus.'),
        findsWidgets);
    await reveal(tester, find.text('LANGKAH 3 DARI 4'));
    expect(find.text('LANGKAH 3 DARI 4'), findsOneWidget);
    expect(find.text('Simpan laporan'), findsNothing);
    expect(find.text('Penyelesaian'), findsNothing);

    final price = find.widgetWithText(TextFormField, 'Harga extra Discova 1');
    await reveal(tester, price);
    await tester.enterText(price, '1000');
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Isi nama untuk extra Discova 1.'), findsWidgets);

    await fillGuestExtra(tester, 'Bagasi', '0');
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(
        find.text('Isi harga untuk "Bagasi" lebih dari Rp 0.'), findsWidgets);
    await reveal(tester, find.text('Hapus'));
    await tester.tap(find.text('Hapus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Penyelesaian'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Discova finance titles stay fixed when Nama tamu changes',
      (tester) async {
    await pumpScreen(
        tester,
        FormScreen(
            report: fixture().copyWith(
          hasGuestAllowance: true,
          guestUangSaku: 100000,
          guestTol: 10000,
          guestExtras: [ExtraExpense(name: 'Bagasi', amount: 3000)],
        )));
    for (final name in ['Bpk. Hartono', 'Ibu Ratna', '']) {
      final identity = find.widgetWithText(TextFormField, 'Nama tamu');
      await reveal(tester, identity);
      await tester.enterText(identity, name);
      await reveal(tester, find.text('3. Keuangan Discova'));
      await tester.tap(find.text('3. Keuangan Discova'));
      await tester.pumpAndSettle();
      expect(find.text('Keuangan Discova'), findsOneWidget);

      for (final title in ['Uang saku Discova', 'Pengeluaran Discova']) {
        final heading = find.widgetWithText(SectionHeading, title);
        await reveal(tester, heading);
        expect(tester.widget<SectionHeading>(heading).title, title);
      }
      for (final label in [
        'Nama extra Discova 1',
        'Harga extra Discova 1',
        'Catatan Discova',
      ]) {
        await reveal(tester, find.widgetWithText(TextFormField, label));
        expect(find.widgetWithText(TextFormField, label), findsOneWidget);
      }
      await reveal(tester, find.text('Tambah Extra Discova'));
      expect(find.text('Tambah Extra Discova'), findsOneWidget);
      await reveal(tester, find.text('Sisa uang Discova'));
      expect(find.text('Sisa uang Discova'), findsOneWidget);
      expect(find.text('Total pengeluaran Discova'), findsOneWidget);
      expect(find.text('Rp 87.000'), findsOneWidget);
      for (final title in [
        'Uang saku Discova',
        'Pengeluaran Discova',
        'Sisa uang Discova',
      ]) {
        if (name.isNotEmpty) {
          expect(find.text('$title $name'), findsNothing);
        }
      }
      if (name.isEmpty) {
        final allowance =
            find.widgetWithText(TextFormField, 'Uang saku diterima');
        await reveal(tester, allowance);
        await tester.enterText(allowance, '1000');
        await reveal(tester, find.text('Defisit uang Discova'));
        expect(find.text('Defisit uang Discova'), findsOneWidget);
        expect(find.text('-Rp 12.000'), findsOneWidget);
      }
      await reveal(tester, find.text('1. Periode'));
      await tester.tap(find.text('1. Periode'));
      await tester.pumpAndSettle();
      await reveal(tester, identity);
      expect(tester.widget<TextFormField>(identity).controller!.text, name);
    }
    await tester.tap(find.byTooltip('Pratinjau PDF tanpa menyimpan'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final preview = tester.widget<PreviewScreen>(find.byType(PreviewScreen));
    expect(preview.report.namaTamu, isEmpty);
    expect(preview.report.hasGuestAllowance, isTrue);
    expect(preview.report.guestUangSaku, 1000);
    expect(preview.report.guestTol, 10000);
    expect(savedReport, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('turning guest allowance off retains values but hides preview',
      (tester) async {
    final saved = fixture().copyWith(
      hasGuestAllowance: true,
      guestUangSaku: 100000,
      guestTol: 10000,
      guestCatatan: 'Titipan tamu',
    );
    await pumpScreen(tester, FormScreen(report: saved));
    await reveal(tester, find.text('Tamu Discova'));
    await tester.tap(find.text('Tamu Discova'));
    await tester.pumpAndSettle();
    expect(
        find.widgetWithText(ChoiceChip, '3. Keuangan Discova'), findsNothing);
    await reveal(tester, find.text('3. Penyelesaian'));
    expect(find.text('3. Penyelesaian'), findsOneWidget);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Uang saku diterima'), findsNothing);
    expect(find.text('Pengeluaran Discova'), findsNothing);

    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Periksa pratinjau PDF'));
    await tester.tap(find.text('Periksa pratinjau PDF'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final preview = tester.widget<PreviewScreen>(find.byType(PreviewScreen));
    expect(preview.report.hasGuestAllowance, isFalse);
    expect(preview.report.guestUangSaku, 100000);
    expect(preview.report.guestTol, 10000);
    expect(preview.report.guestCatatan, 'Titipan tamu');
    expect(tester.takeException(), isNull);
  });

  testWidgets('extra rows can be added, edited and removed in expense order',
      (tester) async {
    await pumpScreen(tester, FormScreen(report: fixture()));
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Tambah Extra'));
    final labels = ['BBM', 'Uang makan (0 hari)'];
    final positions = [
      for (final label in labels)
        tester.getTopLeft(find.widgetWithText(TextFormField, label)).dy,
      tester.getTopLeft(find.text('Extra')).dy,
    ];
    for (var i = 1; i < positions.length; i++) {
      expect(positions[i], greaterThan(positions[i - 1]));
    }
    await tester.tap(find.text('Tambah Extra'));
    await tester.pumpAndSettle();
    await fillExtra(tester, 3, 'Cuci bus', '50000');
    await fillExtra(tester, 2, 'Tol kota', '150000');
    await reveal(tester, find.text('Hapus').first);
    await tester.tap(find.text('Hapus').first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Nama extra 3'), findsNothing);
    expect(
        tester
            .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Nama extra 1'))
            .controller!
            .text,
        'Tol kota');
    expect(
        tester
            .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Harga extra 1'))
            .controller!
            .text,
        '150.000');
    await reveal(tester, find.text('Total pengeluaran'));
    expect(find.text('Rp 1.100.000'), findsOneWidget);
    for (var i = 0; i < 2; i++) {
      await reveal(tester, find.text('Hapus').first);
      await tester.tap(find.text('Hapus').first);
      await tester.pumpAndSettle();
    }
    expect(find.widgetWithText(TextFormField, 'Nama extra 1'), findsNothing);
    await reveal(tester, find.text('Total pengeluaran'));
    expect(find.text('Rp 900.000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'extra validation blocks incomplete rows on next, save and preview',
      (tester) async {
    await pumpScreen(
        tester, FormScreen(report: fixture().copyWith(extras: [])));
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Tambah Extra'));
    await tester.tap(find.text('Tambah Extra'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Extra 1 belum diisi'), findsWidgets);
    await fillExtra(tester, 1, '', '20000');
    await tester.tap(find.byTooltip('Pratinjau PDF tanpa menyimpan'));
    await tester.pumpAndSettle();
    expect(find.byType(PreviewScreen), findsNothing);
    expect(find.textContaining('Isi nama untuk extra 1'), findsWidgets);
    await fillExtra(tester, 1, 'Parkir', '0');
    // Step chips can bypass Next, but Save must still validate every extra.
    await tester.scrollUntilVisible(find.text('3. Penyelesaian'), -250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('3. Penyelesaian'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan laporan'));
    await tester.pumpAndSettle();
    expect(savedReport, isNull);
    expect(find.textContaining('Isi harga untuk "Parkir"'), findsWidgets);
    await fillExtra(tester, 1, 'Parkir', '20000');
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Penyelesaian'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving multiple extras retains names and prices when reopened',
      (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.tap(find.text('Buat laporan baru'));
    await tester.pumpAndSettle();
    await selectBus(tester);
    // The guest name is optional, and it has to reach the saved report.
    final guest = find.widgetWithText(TextFormField, 'Nama tamu');
    await reveal(tester, guest);
    await tester.enterText(guest, 'Bpk. Hartono');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    for (var i = 1; i <= 2; i++) {
      await reveal(tester, find.text('Tambah Extra'));
      await tester.tap(find.text('Tambah Extra'));
      await tester.pumpAndSettle();
      await fillExtra(
          tester, i, i == 1 ? 'Parkir' : 'Tol', i == 1 ? '20000' : '150000');
    }
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan laporan'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    final restored = Report.fromMap(savedReport!);
    expect(restored.namaTamu, 'Bpk. Hartono');
    expect(restored.extras.map((item) => item.name), ['Parkir', 'Tol']);
    expect(restored.extras.map((item) => item.amount), [20000, 150000]);
    expect(restored.totalPengeluaran, 170000);
    expect(restored.pembayaranTagihan, 0);
    expect(restored.tripPeriods, isEmpty);
    expect(restored.luarKotaCount, isNull);
    expect(restored.dalamKotaCount, isNull);
    await pumpScreen(tester, FormScreen(report: restored));
    await reveal(tester, find.widgetWithText(SectionHeading, 'Periode'));
    expect(find.text('Belum ada periode.'), findsOneWidget);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Tambah Extra'));
    expect(
        tester
            .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Nama extra 2'))
            .controller!
            .text,
        'Tol');
    expect(
        tester
            .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Harga extra 2'))
            .controller!
            .text,
        '150.000');
    expect(tester.takeException(), isNull);
  });

  testWidgets('period card keeps summary and controls without the derived span',
      (tester) async {
    await pumpScreen(tester, const FormScreen());
    final heading = find.widgetWithText(SectionHeading, 'Periode');
    await reveal(tester, find.text('Tambah periode'));
    expect(heading, findsOneWidget);
    expect(find.text('Periode LK/DK'), findsNothing);
    expect(find.text('Belum ada periode.'), findsOneWidget);
    expect(find.textContaining('Berangkat'), findsNothing);

    final start = DateTime(2026, 10, 5);
    final end = DateTime(2026, 10, 12);
    await addPeriod(tester, start, end, TripType.dalamKota);
    await reveal(tester, heading);
    expect(heading, findsOneWidget);
    expect(find.text('Periode LK/DK'), findsNothing);
    expect(find.textContaining('Berangkat'), findsNothing);
    expect(find.text('LK 0 hari, DK 8 hari.'), findsOneWidget);
    expect(find.text('Periode 1'), findsOneWidget);
    expect(find.text('8 hari DK'), findsOneWidget);
    expect(find.text('05/10/2026 - 12/10/2026'), findsOneWidget);
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'LK'))
            .selected,
        isFalse);
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'DK'))
            .selected,
        isTrue);
    final picker = await openRange(tester, 0);
    expect(picker.initialDateRange, DateTimeRange(start: start, end: end));
    await returnRange(tester, start, end);
    expect(tester.takeException(), isNull);
  });

  testWidgets('period rows add LK/DK days and validate coverage',
      (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.tap(find.text('Buat laporan baru'));
    await tester.pumpAndSettle();
    await selectBus(tester);
    // Empty periods stay optional while drafts remain incomplete.
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Keuangan Kantor'), findsOneWidget);
    await tester.tap(find.text('Kembali'));
    await tester.pumpAndSettle();
    await addPeriod(tester, DateTime(2026, 6, 12), DateTime(2026, 6, 12),
        TripType.luarKota);
    expect(find.text('LK 1 hari, DK 0 hari.'), findsOneWidget);
    expect(find.text(dayInput(DateTime(2026, 6, 12))), findsOneWidget);
    await addPeriod(tester, DateTime(2026, 6, 13), DateTime(2026, 6, 13),
        TripType.dalamKota);
    expect(find.text('LK 1 hari, DK 1 hari.'), findsOneWidget);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Keuangan Kantor'), findsOneWidget);
    await tester.tap(find.text('Kembali'));
    await tester.pumpAndSettle();
    // Removing the DK row leaves a single remaining period.
    await reveal(tester, find.byTooltip('Hapus periode 2'));
    await tester.tap(find.byTooltip('Hapus periode 2'));
    await tester.pumpAndSettle();
    expect(find.text('LK 1 hari, DK 0 hari.'), findsOneWidget);
    // Gaps stay allowed, so Next still passes with the one row.
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Keuangan Kantor'), findsOneWidget);
    await tester.tap(find.text('Kembali'));
    await tester.pumpAndSettle();
    // Incomplete drafts also block Next with short copy.
    await reveal(tester, find.text('Tambah periode'));
    await tester.tap(find.text('Tambah periode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Periode 2: pilih tanggal.'), findsWidgets);
    await reveal(tester, find.byTooltip('Hapus periode 2'));
    await tester.tap(find.byTooltip('Hapus periode 2'));
    await tester.pumpAndSettle();
    await addPeriod(tester, DateTime(2026, 6, 13), DateTime(2026, 6, 13),
        TripType.dalamKota);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Keuangan Kantor'), findsOneWidget);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan laporan'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    final restored = Report.fromMap(savedReport!);
    expect(restored.tripPeriods, hasLength(2));
    expect(restored.luarKotaCount, 1);
    expect(restored.dalamKotaCount, 1);
    expect(restored.hariTglBerangkat, 'Jumat, 12/06/2026');
    expect(restored.hariTglKembali, 'Sabtu, 13/06/2026');
    expect(tester.takeException(), isNull);
  });

  Finder destinationField(int index) =>
      find.widgetWithText(TextFormField, 'Destinasi').at(index);

  Future<void> enterDestination(
      WidgetTester tester, int index, String value) async {
    final field = destinationField(index);
    await reveal(tester, field);
    await tester.enterText(field, value);
    await tester.pumpAndSettle();
  }

  testWidgets('separate period destinations survive preview, save and reopen',
      (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.tap(find.text('Buat laporan baru'));
    await tester.pumpAndSettle();
    await selectBus(tester);
    await addPeriod(
        tester, DateTime(2026, 6, 1), DateTime(2026, 6, 2), TripType.luarKota);
    await enterDestination(tester, 0, 'Malang');
    await addPeriod(
        tester, DateTime(2026, 6, 5), DateTime(2026, 6, 5), TripType.dalamKota);
    await enterDestination(tester, 1, 'Surabaya');
    expect(tester.widget<TextFormField>(destinationField(0)).controller!.text,
        'Malang');
    expect(tester.widget<TextFormField>(destinationField(1)).controller!.text,
        'Surabaya');

    await tester.tap(find.byTooltip('Pratinjau PDF tanpa menyimpan'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final preview = tester.widget<PreviewScreen>(find.byType(PreviewScreen));
    expect(preview.report.tripPeriods!.map((period) => period.destination),
        ['Malang', 'Surabaya']);
    expect(savedReport, isNull);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan laporan'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    final restored = Report.fromMap(savedReport!);
    expect(restored.tripPeriods!.map((period) => period.destination),
        ['Malang', 'Surabaya']);
    expect(restored.luarKotaCount, 2);
    expect(restored.dalamKotaCount, 1);
    expect(restored.uangMakan, 150000);

    await pumpScreen(tester, FormScreen(report: restored));
    await reveal(tester, destinationField(1));
    expect(tester.widget<TextFormField>(destinationField(0)).controller!.text,
        'Malang');
    expect(tester.widget<TextFormField>(destinationField(1)).controller!.text,
        'Surabaya');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'empty and cleared destinations allow navigation, preview and save',
      (tester) async {
    reports = [
      fixture().copyWith(tripPeriods: [
        TripPeriod(
            start: DateTime(2026, 6, 1),
            end: DateTime(2026, 6, 1),
            type: TripType.luarKota,
            destination: 'Malang'),
        TripPeriod(
            start: DateTime(2026, 6, 5),
            end: DateTime(2026, 6, 5),
            type: TripType.dalamKota),
      ]),
    ];
    await pumpScreen(tester, const HomeScreen());
    await tester.tap(find.byTooltip('Tindakan laporan').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ubah laporan'));
    await tester.pumpAndSettle();
    await enterDestination(tester, 0, '');
    final destinationInput = tester.widget<TextField>(find.descendant(
        of: destinationField(0), matching: find.byType(TextField)));
    expect(
        tester
            .widget<EditableText>(find.descendant(
                of: destinationField(0), matching: find.byType(EditableText)))
            .focusNode
            .hasFocus,
        isTrue);
    expect(destinationInput.decoration!.labelText, 'Destinasi');
    expect(destinationInput.decoration!.hintText, isNull);
    expect(destinationInput.decoration!.helperText, isNull);
    expect(tester.widget<TextFormField>(destinationField(1)).controller!.text,
        isEmpty);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Keuangan Kantor'), findsOneWidget);
    await reveal(tester, find.text('3. Penyelesaian'));
    await tester.tap(find.text('3. Penyelesaian'));
    await tester.pumpAndSettle();
    expect(find.text('Simpan laporan'), findsOneWidget);
    await tester.tap(find.byTooltip('Pratinjau PDF tanpa menyimpan'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final preview = tester.widget<PreviewScreen>(find.byType(PreviewScreen));
    expect(preview.report.tripPeriods!.map((period) => period.destination),
        ['', '']);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan laporan'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    final restored = Report.fromMap(savedReport!);
    expect(restored.tripPeriods!.map((period) => period.destination), ['', '']);
    expect(restored.mealDays, 2);
    await pumpScreen(tester, FormScreen(report: restored));
    await reveal(tester, destinationField(1));
    expect(tester.widget<TextFormField>(destinationField(0)).controller!.text,
        isEmpty);
    expect(tester.widget<TextFormField>(destinationField(1)).controller!.text,
        isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('destination edits survive date and type changes and row removal',
      (tester) async {
    final report = fixture().copyWith(tripPeriods: [
      TripPeriod(
          start: DateTime(2026, 6, 1),
          end: DateTime(2026, 6, 1),
          type: TripType.luarKota,
          destination: 'Malang'),
      TripPeriod(
          start: DateTime(2026, 6, 5),
          end: DateTime(2026, 6, 5),
          type: TripType.luarKota,
          destination: 'Batu'),
      TripPeriod(
          start: DateTime(2026, 6, 9),
          end: DateTime(2026, 6, 9),
          type: TripType.dalamKota,
          destination: 'Surabaya'),
    ]);
    await pumpScreen(tester, FormScreen(report: report));
    await enterDestination(tester, 1, 'Batu | Selecta');
    final survivingController =
        tester.widget<TextFormField>(destinationField(1)).controller!;
    await openRange(tester, 1);
    await returnRange(tester, DateTime(2026, 6, 5), DateTime(2026, 6, 6));
    final type = find.widgetWithText(ChoiceChip, 'DK').at(1);
    await reveal(tester, type);
    await tester.tap(type);
    await tester.pumpAndSettle();
    expect(survivingController.text, 'Batu | Selecta');
    await reveal(tester, find.byTooltip('Hapus periode 1'));
    await tester.tap(find.byTooltip('Hapus periode 1'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(destinationField(0)).controller,
        same(survivingController));
    expect(survivingController.text, 'Batu | Selecta');
    expect(tester.widget<TextFormField>(destinationField(1)).controller!.text,
        'Surabaya');

    await addPeriod(tester, DateTime(2026, 6, 12), DateTime(2026, 6, 12),
        TripType.luarKota);
    expect(tester.widget<TextFormField>(destinationField(2)).controller!.text,
        isEmpty);
    await enterDestination(tester, 2, 'Kediri');
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kembali'));
    await tester.pumpAndSettle();
    await reveal(tester, destinationField(2));
    expect(tester.widget<TextFormField>(destinationField(0)).controller!.text,
        'Batu | Selecta');
    expect(tester.widget<TextFormField>(destinationField(1)).controller!.text,
        'Surabaya');
    expect(tester.widget<TextFormField>(destinationField(2)).controller!.text,
        'Kediri');
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan laporan'));
    await tester.pumpAndSettle();
    final restored = Report.fromMap(savedReport!);
    expect(restored.tripPeriods!.map((period) => period.destination),
        ['Batu | Selecta', 'Surabaya', 'Kediri']);
    expect(restored.tripPeriods!.first.start, DateTime(2026, 6, 5));
    expect(restored.tripPeriods!.first.end, DateTime(2026, 6, 6));
    expect(restored.tripPeriods!.first.type, TripType.dalamKota);
    expect(restored.luarKotaCount, 1);
    expect(restored.dalamKotaCount, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('destination-only edits mark the form dirty and can be reverted',
      (tester) async {
    await pumpScreen(
        tester,
        FormScreen(
            report: fixture().copyWith(tripPeriods: [
          TripPeriod(
              start: DateTime(2026, 6, 1),
              end: DateTime(2026, 6, 1),
              type: TripType.luarKota,
              destination: 'Malang'),
        ])));
    bool canPop() => tester
        .widget<PopScope>(
            find.byWidgetPredicate((widget) => widget is PopScope))
        .canPop;
    expect(canPop(), isTrue);
    await enterDestination(tester, 0, 'Batu');
    expect(canPop(), isFalse);
    await tester.tap(find.byTooltip('Kembali'));
    await tester.pumpAndSettle();
    expect(find.text('Keluar tanpa menyimpan?'), findsOneWidget);
    await tester.tap(find.text('Lanjut mengisi'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(destinationField(0)).controller!.text,
        'Batu');
    await enterDestination(tester, 0, 'Malang');
    expect(canPop(), isTrue);
    expect(savedReport, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('langkah pills animate selection without a checklist icon',
      (tester) async {
    await pumpScreen(tester, const FormScreen());
    await selectBus(tester);
    final first = find.widgetWithText(ChoiceChip, '1. Periode');
    await reveal(tester, first);
    final selected = tester.widget<ChoiceChip>(first);
    expect(selected.selected, isTrue);
    expect(selected.showCheckmark, isFalse);
    expect(
        find.descendant(of: first, matching: find.byIcon(Icons.check_rounded)),
        findsNothing);
    expect(find.ancestor(of: first, matching: find.byType(AnimatedScale)),
        findsOneWidget);
    final second = find.widgetWithText(ChoiceChip, '2. Keuangan Kantor');
    await reveal(tester, second);
    await tester.tap(second);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<ChoiceChip>(second).selected, isTrue);
    expect(
        find.descendant(of: second, matching: find.byIcon(Icons.check_rounded)),
        findsNothing);
    final selectionAnimation = tester.widget<AnimatedScale>(
        find.ancestor(of: second, matching: find.byType(AnimatedScale)));
    expect(selectionAnimation.scale, 1.02);
    expect(tester.takeException(), isNull);
  });

  testWidgets('period choices reuse the form theme and retain surviving rows',
      (tester) async {
    await pumpScreen(tester, const FormScreen());
    await addPeriod(tester, DateTime(2026, 6, 12), DateTime(2026, 6, 12),
        TripType.luarKota);
    await addPeriod(tester, DateTime(2026, 6, 13), DateTime(2026, 6, 13),
        TripType.dalamKota);

    final lkChoices = find.widgetWithText(ChoiceChip, 'LK');
    final dkChoices = find.widgetWithText(ChoiceChip, 'DK');
    final firstLk = tester.widget<ChoiceChip>(lkChoices.first);
    final secondDk = tester.widget<ChoiceChip>(dkChoices.last);
    expect(firstLk.selected, isTrue);
    expect(secondDk.selected, isTrue);
    // Same construction as the home filter chips: no explicit checkmark
    // setting, so the framework default animates the check on select.
    expect(firstLk.shape, isNull);
    expect(firstLk.selectedColor, isNull);
    expect(firstLk.labelStyle, isNull);
    expect(firstLk.showCheckmark, isNull);
    expect(find.byType(SegmentedButton<TripType>), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Tanggal mulai'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Tanggal selesai'), findsNothing);
    expect(find.byIcon(Icons.date_range_outlined), findsWidgets);
    expect(
        find.descendant(
            of: find.byTooltip('Hapus periode 1'),
            matching: find.byWidgetPredicate((widget) => widget is TextButton)),
        findsOneWidget);

    await reveal(tester, find.byTooltip('Hapus periode 1'));
    await tester.tap(find.byTooltip('Hapus periode 1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Periode 2'), findsNothing);
    expect(tester.widget<ChoiceChip>(lkChoices).selected, isFalse);
    expect(tester.widget<ChoiceChip>(dkChoices).selected, isTrue);
    expect(find.text(dayInput(DateTime(2026, 6, 13))), findsOneWidget);
    expect(find.text('LK 0 hari, DK 1 hari.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected period category can be cleared without crashing',
      (tester) async {
    await pumpScreen(tester, const FormScreen());
    await selectBus(tester);
    await addPeriod(tester, DateTime(2026, 6, 12), DateTime(2026, 6, 13),
        TripType.luarKota);
    final choice = find.widgetWithText(ChoiceChip, 'LK');
    await reveal(tester, choice);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Periode 1: pilih LK atau DK.'), findsWidgets);
    expect(find.text('Keuangan Kantor'), findsNothing);
  });

  testWidgets(
      'range picker blocks occupied drafts, shared boundaries and crossing',
      (tester) async {
    await pumpScreen(tester, const FormScreen());
    await selectBus(tester);
    final start = DateTime(2026, 6, 12);
    final end = DateTime(2026, 6, 14);
    await addPeriod(tester, start, end, TripType.luarKota);
    final choice = find.widgetWithText(ChoiceChip, 'LK');
    await reveal(tester, choice);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(choice).selected, isFalse);
    await reveal(tester, find.text('Tambah periode'));
    await tester.tap(find.text('Tambah periode'));
    await tester.pumpAndSettle();
    final picker = await openRange(tester, 1);
    expect(
        find.descendant(
            of: find.byType(PeriodRangePickerDialog),
            matching: find.byType(TextField)),
        findsNothing);
    final available = picker.rangeAvailable;
    for (var day = 12; day <= 14; day++) {
      expect(
          available(DateTime(2026, 6, day), DateTime(2026, 6, day)), isFalse);
    }
    expect(available(DateTime(2026, 6, 11), DateTime(2026, 6, 11)), isTrue);
    expect(available(DateTime(2026, 6, 15), DateTime(2026, 6, 15)), isTrue);
    expect(available(DateTime(2026, 6, 11), DateTime(2026, 6, 15)), isFalse);
    expect(available(DateTime(2026, 6, 15), DateTime(2026, 6, 16)), isTrue);
    // A forged dialog result is checked again before changing either date.
    await returnRange(tester, DateTime(2026, 6, 11), DateTime(2026, 6, 15));
    expect(find.text('Pilih tanggal'), findsOneWidget);
    expect(find.text('11/06/2026 - 15/06/2026'), findsNothing);
    expect(find.text('Periode bertumpuk.'), findsOneWidget);
    await openRange(tester, 1);
    await returnRange(tester, end, DateTime(2026, 6, 15));
    expect(find.text('Pilih tanggal'), findsOneWidget);
    final edit = await openRange(tester, 0);
    expect(edit.initialDateRange, DateTimeRange(start: start, end: end));
    expect(edit.rangeAvailable(start, start), isTrue);
    expect(edit.rangeAvailable(start, end), isTrue);
    await returnRange(tester, start, start);
    expect(find.text('12/06/2026'), findsOneWidget);
    await openRange(tester, 1);
    await returnRange(tester, DateTime(2026, 6, 14), DateTime(2026, 6, 14));
    expect(find.text('14/06/2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one calendar tap then Pilih accepts one day, including on edit',
      (tester) async {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, 10);
    await pumpScreen(tester, const FormScreen());
    await selectBus(tester);
    await reveal(tester, find.text('Tambah periode'));
    await tester.tap(find.text('Tambah periode'));
    await tester.pumpAndSettle();
    await openRange(tester, 0);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Pilih'))
            .onPressed,
        isNull);
    await tester.tap(calendarDay(tester, day));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pilih'));
    await tester.pumpAndSettle();
    expect(find.byType(PeriodRangePickerDialog), findsNothing);
    expect(find.text(dayInput(day)), findsOneWidget);
    final picker = await openRange(tester, 0);
    expect(picker.initialDateRange, DateTimeRange(start: day, end: day));
    // The edited row's own occupied day remains selectable.
    await tester.tap(calendarDay(tester, day));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pilih'));
    await tester.pumpAndSettle();
    final choice = find.widgetWithText(ChoiceChip, 'LK');
    await reveal(tester, choice);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    final meal = find.widgetWithText(TextFormField, 'Uang makan (1 hari)');
    await reveal(tester, meal);
    expect(tester.widget<TextFormField>(meal).controller!.text, '50.000');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'calendar taps reject occupied drafts and crossing, then extend a range',
      (tester) async {
    final now = DateTime.now();
    DateTime day(int number) => DateTime(now.year, now.month, number);
    await pumpScreen(
        tester,
        FormScreen(
            report: fixture().copyWith(tripPeriods: [
          TripPeriod(start: day(12), end: day(14), type: TripType.luarKota),
        ])));
    final choice = find.widgetWithText(ChoiceChip, 'LK');
    await reveal(tester, choice);
    await tester.tap(choice); // date-complete draft reserves dates
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(choice).selected, isFalse);
    await reveal(tester, find.text('Tambah periode'));
    await tester.tap(find.text('Tambah periode'));
    await tester.pumpAndSettle();
    await openRange(tester, 1);
    for (var number = 12; number <= 14; number++) {
      final date = calendarDay(tester, day(number));
      expect(tester.widget<Semantics>(date).properties.enabled, isFalse);
      await tester.tap(date);
      await tester.pumpAndSettle();
    }
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Pilih'))
            .onPressed,
        isNull);
    await tester.tap(calendarDay(tester, day(10)));
    await tester.pumpAndSettle();
    final crossing = calendarDay(tester, day(16));
    expect(tester.widget<Semantics>(crossing).properties.enabled, isFalse);
    await tester.tap(crossing);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pilih'));
    await tester.pumpAndSettle();
    expect(find.text(dayInput(day(10))), findsOneWidget);
    await openRange(tester, 1);
    await tester.tap(calendarDay(tester, day(15)));
    await tester.pumpAndSettle();
    await tester.tap(calendarDay(tester, day(17)));
    await tester.pumpAndSettle();
    for (final number in [15, 16, 17]) {
      expect(
          tester
              .widget<Semantics>(calendarDay(tester, day(number)))
              .properties
              .selected,
          isTrue);
    }
    await tester.tap(find.text('Pilih'));
    await tester.pumpAndSettle();
    expect(find.text('${dayInput(day(15))} - ${dayInput(day(17))}'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'calendar selection spans months and cancellation retains the saved range',
      (tester) async {
    final start = DateTime(2026, 1, 31);
    final end = DateTime(2026, 2, 2);
    await pumpScreen(
        tester,
        FormScreen(
            report: fixture().copyWith(tripPeriods: [
          TripPeriod(start: start, end: start, type: TripType.luarKota),
        ])));
    await openRange(tester, 0);
    await tester.tap(calendarDay(tester, start));
    await tester.pumpAndSettle();
    final localizations = MaterialLocalizations.of(
        tester.element(find.byType(PeriodRangePickerDialog)));
    await tester.tap(find.byTooltip(localizations.nextMonthTooltip));
    await tester.pumpAndSettle();
    await tester.tap(calendarDay(tester, end));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pilih'));
    await tester.pumpAndSettle();
    expect(find.text('31/01/2026 - 02/02/2026'), findsOneWidget);
    await openRange(tester, 0);
    await tester.tap(calendarDay(tester, DateTime(2026, 1, 30)));
    await tester.pumpAndSettle();
    // An earlier second date starts a new single-day range.
    await tester.tap(calendarDay(tester, DateTime(2026, 1, 29)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    final unchanged = await openRange(tester, 0);
    expect(unchanged.initialDateRange, DateTimeRange(start: start, end: end));
    await tester.tap(calendarDay(tester, DateTime(2026, 1, 30)));
    await tester.pumpAndSettle();
    await tester.tap(calendarDay(tester, DateTime(2026, 1, 29)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pilih'));
    await tester.pumpAndSettle();
    expect(find.text('29/01/2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'meal summary, preview and saved report use the same period calculation',
      (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.tap(find.text('Buat laporan baru'));
    await tester.pumpAndSettle();
    await selectBus(tester);
    await addPeriod(tester, DateTime(2026, 6, 12), DateTime(2026, 6, 13),
        TripType.luarKota);
    await addPeriod(tester, DateTime(2026, 6, 20), DateTime(2026, 6, 20),
        TripType.dalamKota);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    final meal = find.widgetWithText(TextFormField, 'Uang makan (3 hari)');
    await reveal(tester, meal);
    expect(tester.widget<TextFormField>(meal).controller!.text, '150.000');
    await reveal(tester, find.text('Total pengeluaran'));
    expect(find.text('Rp 150.000'), findsWidgets);
    await tester.tap(find.byTooltip('Pratinjau PDF tanpa menyimpan'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final preview = tester.widget<PreviewScreen>(find.byType(PreviewScreen));
    expect(preview.report.uangMakan, 150000);
    expect(preview.report.sisa, -150000);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan laporan'));
    await tester.pumpAndSettle();
    expect(savedReport?['uang_makan'], 150000);
    final restored = Report.fromMap(savedReport!);
    expect(restored.uangMakan, 150000);
    await pumpScreen(tester, FormScreen(report: restored));
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await reveal(tester, meal);
    expect(tester.widget<TextFormField>(meal).controller!.text, '150.000');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'untouched meal input follows added, edited and removed periods after reopening',
      (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.tap(find.text('Buat laporan baru'));
    await tester.pumpAndSettle();
    await selectBus(tester);

    Future<void> expectMeal(int days, String amount) async {
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      final meal =
          find.widgetWithText(TextFormField, 'Uang makan ($days hari)');
      await reveal(tester, meal);
      expect(tester.widget<TextFormField>(meal).controller!.text, amount);
      await tester.tap(find.text('Kembali'));
      await tester.pumpAndSettle();
    }

    await expectMeal(0, '0');
    await addPeriod(
        tester, DateTime(2026, 6, 1), DateTime(2026, 6, 2), TripType.luarKota);
    await expectMeal(2, '100.000');
    await addPeriod(
        tester, DateTime(2026, 6, 8), DateTime(2026, 6, 8), TripType.dalamKota);
    await expectMeal(3, '150.000');
    await openRange(tester, 0);
    await returnRange(tester, DateTime(2026, 6, 1), DateTime(2026, 6, 3));
    await expectMeal(4, '200.000');
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan laporan'));
    await tester.pumpAndSettle();
    final reopened = Report.fromMap(savedReport!);
    expect(reopened.uangMakanIsManual, isFalse);
    await pumpScreen(tester, FormScreen(report: reopened));
    await reveal(tester, find.byTooltip('Hapus periode 1'));
    await tester.tap(find.byTooltip('Hapus periode 1'));
    await tester.pumpAndSettle();
    await expectMeal(1, '50.000');
    await reveal(tester, find.byTooltip('Hapus periode 1'));
    await tester.tap(find.byTooltip('Hapus periode 1'));
    await tester.pumpAndSettle();
    await expectMeal(0, '0');
    expect(tester.takeException(), isNull);
  });

  for (final custom in ['123456', '150000', '0']) {
    testWidgets(
        'manual meal $custom stays fixed through day changes, save, reopen and preview',
        (tester) async {
      await pumpScreen(tester, const HomeScreen());
      await tester.tap(find.text('Buat laporan baru'));
      await tester.pumpAndSettle();
      await selectBus(tester);
      await addPeriod(tester, DateTime(2026, 6, 1), DateTime(2026, 6, 3),
          TripType.luarKota);
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      final meal = find.widgetWithText(TextFormField, 'Uang makan (3 hari)');
      await reveal(tester, meal);
      // Clear first to exercise an actual edit even when custom equals auto.
      await tester.enterText(meal, '');
      await tester.enterText(meal, custom);
      await tester.pumpAndSettle();
      final formatted = tester.widget<TextFormField>(meal).controller!.text;
      await tester.tap(find.text('Kembali'));
      await tester.pumpAndSettle();
      await addPeriod(tester, DateTime(2026, 6, 8), DateTime(2026, 6, 8),
          TripType.dalamKota);
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      final changedLabel =
          find.widgetWithText(TextFormField, 'Uang makan (4 hari)');
      await reveal(tester, changedLabel);
      expect(tester.widget<TextFormField>(changedLabel).controller!.text,
          formatted);
      await reveal(tester, find.text('Total pengeluaran'));
      expect(find.text('Rp $formatted'), findsWidgets);
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan laporan'));
      await tester.pumpAndSettle();
      var restored = Report.fromMap(savedReport!);
      expect(restored.uangMakanIsManual, isTrue);
      expect(restored.uangMakan, int.parse(custom));
      expect(restored.totalPengeluaran, int.parse(custom));
      expect(restored.sisa, -int.parse(custom));
      await pumpScreen(tester, FormScreen(report: restored));
      await openRange(tester, 0);
      await returnRange(tester, DateTime(2026, 6, 1), DateTime(2026, 6, 1));
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      final reopenedMeal =
          find.widgetWithText(TextFormField, 'Uang makan (2 hari)');
      await reveal(tester, reopenedMeal);
      expect(tester.widget<TextFormField>(reopenedMeal).controller!.text,
          formatted);
      await tester.tap(find.byTooltip('Pratinjau PDF tanpa menyimpan'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final preview = tester.widget<PreviewScreen>(find.byType(PreviewScreen));
      expect(preview.report.uangMakan, int.parse(custom));
      expect(preview.report.mealDays, 2);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan laporan'));
      await tester.pumpAndSettle();
      restored = Report.fromMap(savedReport!);
      expect(restored.uangMakan, int.parse(custom));
      expect(restored.uangMakanIsManual, isTrue);
      expect(restored.mealDays, 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'overlap is revalidated on next, direct navigation, preview and save',
      (tester) async {
    final valid = fixture().copyWith(tripPeriods: [
      TripPeriod(
          start: DateTime(2026, 6, 12),
          end: DateTime(2026, 6, 14),
          type: TripType.luarKota),
      TripPeriod(
          start: DateTime(2026, 6, 14),
          end: DateTime(2026, 6, 15),
          type: TripType.dalamKota),
    ]);
    await pumpScreen(tester, FormScreen(report: valid));
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Periode bertumpuk.'), findsWidgets);
    await reveal(tester, find.text('3. Penyelesaian'));
    await tester.tap(find.text('3. Penyelesaian'));
    await tester.pumpAndSettle();
    expect(find.text('Simpan laporan'), findsNothing);
    await tester.tap(find.byTooltip('Pratinjau PDF tanpa menyimpan'));
    await tester.pumpAndSettle();
    expect(find.byType(PreviewScreen), findsNothing);
    await openRange(tester, 1);
    await returnRange(tester, DateTime(2026, 6, 16), DateTime(2026, 6, 17));
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan laporan'));
    await tester.pumpAndSettle();
    expect(savedReport?['uang_makan'], 250000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy totals stay read-only until replaced, then clear',
      (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await reveal(tester, find.byTooltip('Tindakan laporan').first);
    await tester.tap(find.byTooltip('Tindakan laporan').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ubah laporan'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Belum dicatat.'));
    expect(find.text('Belum dicatat.'), findsOneWidget);
    // Untouched legacy rows still save null without needing step chips.
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan laporan'));
    await tester.pumpAndSettle();
    expect(savedReport?['trip_type'], '');
    expect(savedReport?['trip_periods'], isNull);
    expect(savedReport?['luar_kota_count'], isNull);
    expect(savedReport?['dalam_kota_count'], isNull);
    expect(find.byType(HomeScreen), findsOneWidget);

    reports[0] = fixture().copyWith(
        tripType: TripType.luarKota, luarKotaCount: 3, dalamKotaCount: 0);
    await tester.tap(find.byTooltip('Muat ulang'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byTooltip('Tindakan laporan').first);
    await tester.tap(find.byTooltip('Tindakan laporan').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ubah laporan'));
    await tester.pumpAndSettle();
    await reveal(tester, find.widgetWithText(SectionHeading, 'Periode'));
    expect(find.text('Periode LK/DK'), findsNothing);
    expect(find.text('LK 3 hari, DK 0 hari.'), findsOneWidget);
    expect(find.text('Isi periode'), findsOneWidget);
    await tester.tap(find.text('Isi periode'));
    await tester.pumpAndSettle();
    await addPeriod(tester, DateTime(2026, 6, 12), DateTime(2026, 6, 13),
        TripType.dalamKota);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan laporan'));
    await tester.pumpAndSettle();
    expect(savedReport?['trip_type'], '');
    expect(savedReport?['luar_kota_count'], 0);
    expect(savedReport?['dalam_kota_count'], 2);
    // Removing every replacement row clears old counts instead of restoring.
    await pumpScreen(tester, FormScreen(report: Report.fromMap(savedReport!)));
    await reveal(tester, find.widgetWithText(SectionHeading, 'Periode'));
    expect(find.text('LK 0 hari, DK 2 hari.'), findsOneWidget);
    await reveal(tester, find.byTooltip('Hapus periode 1'));
    await tester.tap(find.byTooltip('Hapus periode 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan laporan'));
    await tester.pumpAndSettle();
    expect(savedReport?['trip_periods'], '[]');
    expect(savedReport?['luar_kota_count'], isNull);
    expect(savedReport?['dalam_kota_count'], isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new report saves a chosen plate without time or KM inputs',
      (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.tap(find.text('Buat laporan baru'));
    await tester.pumpAndSettle();
    expect(find.text('Pilih bus'), findsOneWidget);
    await selectBus(tester, label: 'HG 5 • AB 7454 BK');
    expectNoBusManagement();
    expect(find.text('Jam berangkat'), findsNothing);
    expect(find.text('KM awal'), findsNothing);
    expect(find.text('KM akhir'), findsNothing);
    expect(find.text('Kilometer'), findsNothing);
    expect(find.byTooltip('Pilih jam berangkat'), findsNothing);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama crew'), 'Agus');
    await tester.tap(find.text('Simpan laporan'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Laporan berhasil disimpan.'), findsOneWidget);
    expect(savedReport?['no_polisi'], 'AB 7454 BK');
    expect(savedReport?['jam_berangkat'], '');
    expect(savedReport?['km_awal'], 0);
    expect(savedReport?['km_akhir'], 0);
    expect(savedReport?['nama_crew'], 'Agus');
    expect(savedReport?['trip_periods'], '[]');
    expect(savedReport?['luar_kota_count'], isNull);
    expect(savedReport?['dalam_kota_count'], isNull);
    await tester.tap(find.text('Buat laporan baru'));
    await tester.pumpAndSettle();
    expect(find.text('Pilih bus'), findsOneWidget);
    expect(
        tester
            .widget<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>))
            .initialValue,
        isNull);
    expect(find.text('Jam berangkat'), findsNothing);
    expect(find.text('KM awal'), findsNothing);
    expect(find.text('KM akhir'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new reports can continue and save without LK or DK counts',
      (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.tap(find.text('Buat laporan baru'));
    await tester.pumpAndSettle();
    await selectBus(tester);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Keuangan Kantor'), findsOneWidget);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Penyelesaian'), findsOneWidget);
    await tester.tap(find.text('Simpan laporan'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(savedReport?['luar_kota_count'], isNull);
    expect(savedReport?['dalam_kota_count'], isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty periods stay optional for new reports', (tester) async {
    await pumpScreen(tester, const FormScreen());
    await selectBus(tester);
    await reveal(tester, find.text('Tambah periode'));
    expect(find.text('Belum ada periode.'), findsOneWidget);
    expect(find.text('LK 0 hari, DK 0 hari.'), findsNothing);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Keuangan Kantor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'history searches fixed bus names and plates and filters deficits',
      (tester) async {
    await pumpScreen(tester, const HomeScreen());
    final search = find.byType(TextField);
    await tester.enterText(search, 'HG 3');
    await tester.pumpAndSettle();
    await reveal(tester, find.text('HG 3 • Dedi'));
    expect(find.text('HG 3 • Dedi'), findsOneWidget);
    expect(find.text('HG 2 • Budi Santoso'), findsNothing);
    await tester.enterText(search, 'AB 7317 BK');
    await tester.pumpAndSettle();
    expect(find.text('HG 2 • Budi Santoso'), findsOneWidget);
    expect(find.text('HG 3 • Dedi'), findsNothing);
    await tester.tap(find.byTooltip('Hapus pencarian'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Defisit'));
    await tester.pumpAndSettle();
    expect(find.text('HG 3 • Dedi'), findsOneWidget);
    expect(find.text('HG 2 • Budi Santoso'), findsNothing);
    expectNoBusManagement();
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing hides time and KM without clearing their stored values',
      (tester) async {
    for (final report in [fixture(), fixture().copyWith(tripPeriods: [])]) {
      await pumpScreen(tester, FormScreen(report: report));
      expect(
          tester
              .widget<DropdownButtonFormField<String>>(
                  find.byType(DropdownButtonFormField<String>))
              .initialValue,
          'AB 7317 BK');
      expect(find.text('Jam berangkat'), findsNothing);
      expect(find.text('KM awal'), findsNothing);
      expect(find.text('KM akhir'), findsNothing);
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan laporan'));
      await tester.pumpAndSettle();
      expect(savedReport?['jam_berangkat'], '08:00');
      expect(savedReport?['km_awal'], 124000);
      expect(savedReport?['km_akhir'], 124850);
      expect(savedReport?['no_polisi'], 'AB 7317 BK');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('small screen with large text has no layout overflow',
      (tester) async {
    await pumpScreen(tester, const HomeScreen(),
        size: const Size(320, 740), scale: 1.5);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await pumpScreen(tester, FormScreen(report: fixture()),
        size: const Size(320, 740), scale: 1.5);
    for (var step = 0; step < 3; step++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (step < 2) {
        await tester.tap(find.text('Lanjut'));
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets('tablet content stays width constrained', (tester) async {
    await pumpScreen(tester, const HomeScreen(), size: const Size(1100, 900));
    await capture(tester, 'home-tablet');
    final scroll = tester.getSize(find.byType(CustomScrollView));
    expect(scroll.width, lessThanOrEqualTo(760));
    expect(tester.takeException(), isNull);
  });

  testWidgets('PDF failure offers retry and disables export', (tester) async {
    await pumpScreen(
        tester,
        PreviewScreen(report: fixture(), attachmentImages: [
          Uint8List.fromList([1, 2, 3])
        ]));
    expect(find.text('PDF belum siap'), findsOneWidget);
    expect(find.text('Coba lagi'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Simpan'))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expense manager offers gallery and limits camera to non-Linux',
      (tester) async {
    await pumpScreen(tester, FormScreen(report: fixture()));
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byTooltip('Foto BBM'));
    await tester.tap(find.byTooltip('Foto BBM'));
    await tester.pumpAndSettle();
    // Camera capture is unsupported on Linux; gallery stays available.
    expect(find.text('Galeri'), findsOneWidget);
    expect(
        find.text('Kamera'), Platform.isLinux ? findsNothing : findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview keeps save and print and hides sharing on desktop',
      (tester) async {
    await pumpScreen(
        tester,
        PreviewScreen(report: fixture(), attachmentImages: [
          Uint8List.fromList([1, 2, 3])
        ]));
    final desktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;
    expect(find.text('Bagikan'), desktop ? findsNothing : findsOneWidget);
    expect(find.text('Simpan'), findsOneWidget);
    expect(find.text('Cetak'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
