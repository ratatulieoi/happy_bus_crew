import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bus_crew/main.dart';
import 'package:happy_bus_crew/models/report.dart';
import 'package:happy_bus_crew/screens/bus_setup_screen.dart';
import 'package:happy_bus_crew/screens/form_screen.dart';
import 'package:happy_bus_crew/screens/home_screen.dart';
import 'package:happy_bus_crew/screens/preview_screen.dart';
import 'package:happy_bus_crew/ui/app_theme.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite/sqflite.dart';

Report fixture(
        {int id = 1,
        String plate = 'B 1001 XX',
        String driver = 'Budi Santoso',
        int allowance = 2000000}) =>
    Report(
      id: id,
      tanggalBuat: DateTime(2026, 6, 12),
      hariTglBerangkat: 'Jumat, 12/06/2026',
      jamBerangkat: '08:00',
      hariTglKembali: 'Sabtu, 13/06/2026',
      noPolisi: plate,
      pengemudi: driver,
      kernet: 'Agus',
      kmAwal: 124000,
      kmAkhir: 124850,
      uangSaku: allowance,
      bbm: 900000,
      uangMakan: 150000,
      extra: 50000,
      tagihan: 100000,
      namaCrew: 'Budi Santoso',
      catatan: 'Perjalanan lancar.',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final settings = <String, String>{};
  var reports = <Report>[];
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
    settings
      ..clear()
      ..addAll({
        'selected_bus_index': '0',
        'bus_0_name': 'Happy Bus 01',
        'bus_0_plate': 'B 1001 XX',
        'bus_0_oil_change_km': '120000'
      });
    reports = [
      fixture(),
      fixture(id: 2, plate: 'B 1002 XX', driver: 'Dedi', allowance: 500000)
    ];
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
          final values = args['arguments'] as List? ?? [];
          if (sql.contains('PRAGMA user_version')) {
            return [
              {'user_version': 5}
            ];
          }
          if (sql.contains('FROM settings')) {
            final key = values.first as String;
            return settings.containsKey(key)
                ? [
                    {'key': key, 'value': settings[key]}
                  ]
                : <Map<String, Object?>>[];
          }
          if (sql.contains('MAX(km_akhir)')) {
            return [
              {'max_km': 124850}
            ];
          }
          if (sql.contains('FROM reports')) {
            return reports.map((r) => r.toMap()).toList();
          }
          return <Map<String, Object?>>[];
        case 'insert':
          if ((args['sql'] as String).contains('settings')) {
            final values = args['arguments'] as List;
            settings[values[0] as String] = values[1] as String;
          }
          return 3;
        case 'update':
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

  testWidgets('first launch opens required setup without a late future error',
      (tester) async {
    settings.clear();
    await tester.pumpWidget(const HappyBusApp());
    await tester.pumpAndSettle();
    expect(find.byType(BusSetupScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Simpan & lanjutkan'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(settings['selected_bus_index'], '0');
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard loads, searches, filters and opens edit',
      (tester) async {
    await pumpScreen(tester, const HomeScreen());
    expect(find.text('Happy Bus 01'), findsOneWidget);
    expect(find.text('Kondisi oli baik'), findsOneWidget);
    await capture(tester, 'home');
    final search = find.byType(TextField);
    await tester.ensureVisible(search);
    await tester.enterText(search, 'Dedi');
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Dedi'), findsNWidgets(2));
    expect(find.text('Budi Santoso'), findsNothing);
    await tester.tap(find.byTooltip('Hapus pencarian'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bus aktif'));
    await tester.pumpAndSettle();
    expect(find.text('Dedi'), findsNothing);
    expect(find.text('Budi Santoso'), findsOneWidget);
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

  testWidgets('report steps retain all values and update balance',
      (tester) async {
    await pumpScreen(tester, FormScreen(report: fixture()));
    expect(
        tester
            .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Jam berangkat'))
            .controller!
            .text,
        '08:00');
    await capture(tester, 'report-trip');
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await capture(tester, 'report-finance');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Uang saku'), '1000000');
    await tester.drag(find.byType(ListView).first, const Offset(0, -550));
    await tester.pumpAndSettle();
    expect(find.text('Defisit perjalanan'), findsOneWidget);
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

  testWidgets('new report inherits bus mileage and saves without losing fields',
      (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.tap(find.text('Buat laporan baru'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Nomor polisi'))
            .controller!
            .text,
        'B 1001 XX');
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'KM awal'))
            .controller!
            .text,
        '124.850');
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
    expect(tester.takeException(), isNull);
  });

  testWidgets('oil log validates mileage and refreshes next service',
      (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Catat ganti oli'));
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextFormField, 'Kilometer ganti oli');
    await tester.enterText(field, '');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(find.text('Masukkan kilometer yang valid'), findsOneWidget);
    await tester.enterText(field, '124850');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(settings['bus_0_oil_change_km'], '124850');
    expect(find.text('10.000 km menuju ganti oli'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('setup validates offscreen slots and shows chosen bus',
      (tester) async {
    await pumpScreen(tester, const BusSetupScreen());
    await capture(tester, 'bus-setup');
    final names =
        tester.widgetList<TextFormField>(find.byType(TextFormField)).toList();
    names.last.controller!.clear();
    await tester.tap(find.text('Simpan pengaturan'));
    await tester.pumpAndSettle();
    expect(find.text('Isi nomor polisi.'), findsOneWidget);
    expect(find.byType(BusSetupScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    await pumpScreen(tester, const BusSetupScreen(),
        size: const Size(320, 740), scale: 1.5);
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
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
}
