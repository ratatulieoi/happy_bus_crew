import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bus_crew/main.dart';
import 'package:happy_bus_crew/models/report.dart';
import 'package:happy_bus_crew/screens/bus_list_screen.dart';
import 'package:happy_bus_crew/screens/form_screen.dart';
import 'package:happy_bus_crew/screens/home_screen.dart';
import 'package:happy_bus_crew/screens/preview_screen.dart';
import 'package:happy_bus_crew/ui/app_theme.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite/sqflite.dart';

Report fixture(
        {int id = 1,
        DateTime? tanggalBuat,
        String plate = 'B 1001 XX',
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
      uangMakan: 150000,
      extras: const [
        ExtraExpense(name: 'Parkir', amount: 20000),
        ExtraExpense(name: 'Tol', amount: 30000),
      ],
      pembayaranTagihan: 100000,
      namaCrew: 'Budi Santoso',
      catatan: 'Perjalanan lancar.',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final settings = <String, String>{};
  final settingsRead = <String>[];
  final settingsWritten = <String>[];
  var reports = <Report>[];
  final buses = <Map<String, Object?>>[];
  Map<String, Object?>? savedReport;
  var failQueries = false;
  var failBusSave = false;
  var failBusDelete = false;
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
        'selected_bus_id': '1',
      });
    settingsRead.clear();
    settingsWritten.clear();
    reports = [
      fixture(),
      fixture(
          id: 2,
          tanggalBuat: DateTime(2026, 6, 11),
          plate: 'B 1002 XX',
          driver: 'Dedi',
          allowance: 500000)
    ];
    buses
      ..clear()
      ..addAll([
        {'id': 1, 'name': 'Happy Bus 01', 'plate': 'B 1001 XX'},
        {'id': 2, 'name': 'Happy Bus 02', 'plate': 'B 1002 XX'},
      ]);
    savedReport = null;
    failQueries = false;
    failBusSave = false;
    failBusDelete = false;
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
              {'user_version': 12}
            ];
          }
          if (sql.contains('FROM settings')) {
            final key = values.first as String;
            settingsRead.add(key);
            return settings.containsKey(key)
                ? [
                    {'key': key, 'value': settings[key]}
                  ]
                : <Map<String, Object?>>[];
          }
          if (sql.contains('MAX(km_akhir)')) {
            fail('Mileage tracking queries must not run.');
          }
          if (sql.contains('FROM reports') &&
              sql.contains('UPPER(TRIM(no_polisi))')) {
            final plate = (values.first as String).toUpperCase();
            return reports
                .where(
                    (report) => report.noPolisi.trim().toUpperCase() == plate)
                .take(1)
                .map((report) => {'id': report.id})
                .toList();
          }
          if (sql.contains('FROM buses')) {
            return sql.contains('WHERE id = ?')
                ? buses.where((bus) => bus['id'] == values.first).toList()
                : buses;
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
          if (sql.contains('settings')) {
            settingsWritten.add(values[0] as String);
            settings[values[0] as String] = values[1] as String;
          } else if (sql.contains('INTO buses')) {
            if (failBusSave) throw PlatformException(code: 'disk_full');
            final id = buses.length + 1;
            buses.add({'id': id, 'name': values[0], 'plate': values[1]});
            return id;
          } else if (sql.contains('INTO reports')) {
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
          if (sql.startsWith('UPDATE buses')) {
            final bus = buses.firstWhere((bus) => bus['id'] == values.last);
            bus['name'] = values[0];
            bus['plate'] = values[1];
          } else if (sql.startsWith('UPDATE reports')) {
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
          } else if (sql.startsWith('DELETE FROM buses')) {
            if (failBusDelete) throw PlatformException(code: 'disk_error');
            buses.removeWhere((bus) => bus['id'] == values.first);
          } else if (sql.startsWith('DELETE FROM settings')) {
            settings.remove(values.first);
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

  /// Add one row via Tambah periode, fill its start and end dates, then
  /// choose LK/DK through that row's visible control.
  Future<void> addPeriod(
      WidgetTester tester, DateTime start, DateTime end, TripType type) async {
    await reveal(tester, find.text('Tambah periode'));
    await tester.tap(find.text('Tambah periode'));
    await tester.pumpAndSettle();
    final rows =
        find.widgetWithText(TextFormField, 'Tanggal mulai').evaluate().length;
    final startField = find.widgetWithText(TextFormField, 'Tanggal mulai').last;
    final endField = find.widgetWithText(TextFormField, 'Tanggal selesai').last;
    await reveal(tester, startField);
    await tester.enterText(startField, dayInput(start));
    await reveal(tester, endField);
    await tester.enterText(endField, dayInput(end));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Hapus periode $rows'), findsOneWidget);
    final label =
        type == TripType.luarKota ? 'Luar Kota (LK)' : 'Dalam Kota (DK)';
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
    buses.clear();
    await tester.pumpWidget(const HappyBusApp());
    await tester.pumpAndSettle();
    expect(find.byType(BusListScreen), findsOneWidget);
    expect(find.text('Tambahkan bus pertama'), findsOneWidget);
    expect(find.text('Buat laporan baru'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(BusListScreen), findsOneWidget);
    await tester.tap(find.text('Tambah bus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan bus'));
    await tester.pumpAndSettle();
    expect(find.text('Isi nama bus.'), findsOneWidget);
    expect(find.text('Isi nomor polisi.'), findsOneWidget);
    expect(buses, isEmpty);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama bus'), 'Bus pertama');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nomor polisi'), ' b 9999 xy ');
    await tester.tap(find.text('Simpan bus'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Bus pertama'), findsOneWidget);
    expect(buses, [
      {'id': 1, 'name': 'Bus pertama', 'plate': 'B 9999 XY'}
    ]);
    expect(settings, {'selected_bus_id': '1'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard loads, searches, filters and opens edit',
      (tester) async {
    await pumpScreen(tester, const HomeScreen());
    expect(find.text('Happy Bus 01'), findsWidgets);
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
    expect(find.text('Happy Bus 02 • Dedi'), findsOneWidget);
    expect(find.text('Happy Bus 01 • Budi Santoso'), findsNothing);
    await tester.tap(find.byTooltip('Hapus pencarian'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bus aktif'));
    await tester.pumpAndSettle();
    expect(find.text('Happy Bus 02 • Dedi'), findsNothing);
    expect(find.text('Happy Bus 01 • Budi Santoso'), findsOneWidget);
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
    expect(find.text('Jam berangkat'), findsOneWidget);
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
    await reveal(tester, find.text('Defisit perjalanan'));
    expect(find.text('Rp 1.100.000'), findsOneWidget);
    expect(find.text('-Rp 100.000'), findsOneWidget);
    final paymentField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Pembayaran tagihan'));
    expect(paymentField.controller!.text, '100.000');
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

  testWidgets('extra rows can be added, edited and removed in expense order',
      (tester) async {
    await pumpScreen(tester, FormScreen(report: fixture()));
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Tambah Extra'));
    final labels = ['BBM', 'Uang makan'];
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
    expect(find.text('Rp 1.250.000'), findsOneWidget);
    for (var i = 0; i < 2; i++) {
      await reveal(tester, find.text('Hapus').first);
      await tester.tap(find.text('Hapus').first);
      await tester.pumpAndSettle();
    }
    expect(find.widgetWithText(TextFormField, 'Nama extra 1'), findsNothing);
    await reveal(tester, find.text('Total pengeluaran'));
    expect(find.text('Rp 1.050.000'), findsOneWidget);
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
    await tester.scrollUntilVisible(find.text('3. Lampiran'), -250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('3. Lampiran'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan laporan'));
    await tester.pumpAndSettle();
    expect(savedReport, isNull);
    expect(find.textContaining('Isi harga untuk "Parkir"'), findsWidgets);
    await fillExtra(tester, 1, 'Parkir', '20000');
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Lengkapi laporan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving multiple extras retains names and prices when reopened',
      (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.tap(find.text('Buat laporan baru'));
    await tester.pumpAndSettle();
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
    await reveal(tester, find.text('Periode LK/DK'));
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

  testWidgets('period rows add LK/DK days and validate coverage',
      (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.tap(find.text('Buat laporan baru'));
    await tester.pumpAndSettle();
    // Empty periods stay optional while drafts remain incomplete.
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Keuangan perjalanan'), findsOneWidget);
    await tester.tap(find.text('Kembali'));
    await tester.pumpAndSettle();
    await addPeriod(tester, DateTime(2026, 6, 12), DateTime(2026, 6, 12),
        TripType.luarKota);
    expect(find.text('LK 1 hari, DK 0 hari.'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, dayInput(DateTime(2026, 6, 12))),
        findsWidgets);
    await addPeriod(tester, DateTime(2026, 6, 13), DateTime(2026, 6, 13),
        TripType.dalamKota);
    expect(find.text('LK 1 hari, DK 1 hari.'), findsOneWidget);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Keuangan perjalanan'), findsOneWidget);
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
    expect(find.text('Keuangan perjalanan'), findsOneWidget);
    await tester.tap(find.text('Kembali'));
    await tester.pumpAndSettle();
    // Incomplete drafts also block Next with short copy.
    await reveal(tester, find.text('Tambah periode'));
    await tester.tap(find.text('Tambah periode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Periode 2: pilih tanggal.'), findsWidgets);
    await tester.tap(find.byTooltip('Hapus periode 2'));
    await tester.pumpAndSettle();
    await addPeriod(tester, DateTime(2026, 6, 13), DateTime(2026, 6, 13),
        TripType.dalamKota);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Keuangan perjalanan'), findsOneWidget);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan laporan'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    final restored = Report.fromMap(savedReport!);
    expect(restored.tripPeriods, hasLength(2));
    expect(restored.luarKotaCount, 1);
    expect(restored.dalamKotaCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('period choices reuse the form theme and retain surviving rows',
      (tester) async {
    await pumpScreen(tester, const FormScreen());
    await addPeriod(tester, DateTime(2026, 6, 12), DateTime(2026, 6, 12),
        TripType.luarKota);
    await addPeriod(tester, DateTime(2026, 6, 13), DateTime(2026, 6, 13),
        TripType.dalamKota);

    final lkChoices = find.widgetWithText(ChoiceChip, 'Luar Kota (LK)');
    final dkChoices = find.widgetWithText(ChoiceChip, 'Dalam Kota (DK)');
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
    final dateField = find.descendant(
        of: find.widgetWithText(TextFormField, 'Tanggal selesai').last,
        matching: find.byType(TextField));
    expect(
        (tester.widget<TextField>(dateField).decoration?.suffixIcon as Icon)
            .icon,
        Icons.calendar_today_outlined);
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
    final survivor =
        find.widgetWithText(TextFormField, 'Tanggal selesai').evaluate().single;
    expect((survivor.widget as TextFormField).initialValue,
        dayInput(DateTime(2026, 6, 13)));
    expect(find.text('LK 0 hari, DK 1 hari.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected period category can be cleared without crashing',
      (tester) async {
    await pumpScreen(tester, const FormScreen());
    await addPeriod(tester, DateTime(2026, 6, 12), DateTime(2026, 6, 13),
        TripType.luarKota);
    final choice = find.widgetWithText(ChoiceChip, 'Luar Kota (LK)');
    await reveal(tester, choice);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Periode 1: pilih LK atau DK.'), findsWidgets);
    expect(find.text('Keuangan perjalanan'), findsNothing);
  });

  testWidgets(
      'invalid period edits block next preview and save without crashing',
      (tester) async {
    await pumpScreen(tester, const FormScreen());
    await addPeriod(tester, DateTime(2026, 6, 12), DateTime(2026, 6, 13),
        TripType.luarKota);
    final endField = find.widgetWithText(TextFormField, 'Tanggal selesai');
    await reveal(tester, endField);
    await tester.enterText(endField, '12/06/2026');
    final startField = find.widgetWithText(TextFormField, 'Tanggal mulai');
    await reveal(tester, startField);
    await tester.enterText(startField, '13/06/2026');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Periode 1: tanggal terbalik.'), findsWidgets);
    await tester.tap(find.byTooltip('Pratinjau PDF tanpa menyimpan'));
    await tester.pumpAndSettle();
    expect(find.byType(PreviewScreen), findsNothing);
    await tester.scrollUntilVisible(find.text('3. Lampiran'), -250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('3. Lampiran'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Simpan laporan'));
    await tester.pumpAndSettle();
    expect(savedReport, isNull);
    expect(find.text('Periode 1: tanggal terbalik.'), findsWidgets);

    // Impossible dates never parse; the form must reject them.
    await reveal(tester, startField);
    await tester.enterText(startField, '29/02/2026');
    await reveal(tester, endField);
    await tester.enterText(endField, '29/02/2026');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Periode 1: pilih tanggal.'), findsWidgets);
    expect(find.text('Keuangan perjalanan'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overlapping period rows block the next step until fixed',
      (tester) async {
    await pumpScreen(tester, const FormScreen());
    await addPeriod(tester, DateTime(2026, 6, 12), DateTime(2026, 6, 14),
        TripType.luarKota);
    await addPeriod(tester, DateTime(2026, 6, 14), DateTime(2026, 6, 15),
        TripType.dalamKota);
    expect(find.text('Periode bertumpuk.'), findsWidgets);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Periode bertumpuk.'), findsWidgets);
    expect(find.text('Keuangan perjalanan'), findsNothing);
    // Fixing the second row clears the overlap and unblocks the step: type
    // the start first so day two is free before the end moves onto its row.
    // The blocked Lanjut above left a SnackBar with the same text, so wait
    // for it to fade before asserting the inline error is gone.
    final endFields = find.widgetWithText(TextFormField, 'Tanggal selesai');
    final startFields = find.widgetWithText(TextFormField, 'Tanggal mulai');
    await reveal(tester, startFields.last);
    await tester.enterText(startFields.last, dayInput(DateTime(2026, 6, 15)));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.text('Periode bertumpuk.'), findsNothing);
    await reveal(tester, endFields.last);
    await tester.enterText(endFields.last, dayInput(DateTime(2026, 6, 16)));
    await tester.pumpAndSettle();
    expect(find.text('LK 3 hari, DK 2 hari.'), findsOneWidget);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Keuangan perjalanan'), findsOneWidget);
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
    await reveal(tester, find.text('Periode LK/DK'));
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
    await reveal(tester, find.text('Periode LK/DK'));
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

  testWidgets(
      'new report uses selected plate and saves manual KM without tracking',
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
        '');
    final kmAwal = find.widgetWithText(TextFormField, 'KM awal');
    final kmAkhir = find.widgetWithText(TextFormField, 'KM akhir');
    expect(tester.widget<TextFormField>(kmAkhir).controller!.text, '');
    await tester.enterText(kmAwal, '120');
    await tester.enterText(kmAkhir, '480');
    expect(find.text('Jarak tempuh'), findsNothing);
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
    expect(savedReport?['no_polisi'], 'B 1001 XX');
    expect(savedReport?['km_awal'], 120);
    expect(savedReport?['km_akhir'], 480);
    expect(savedReport?['nama_crew'], 'Agus');
    expect(savedReport?['trip_periods'], '[]');
    expect(savedReport?['luar_kota_count'], isNull);
    expect(savedReport?['dalam_kota_count'], isNull);
    await tester.tap(find.text('Buat laporan baru'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(kmAwal).controller!.text, '');
    expect(tester.widget<TextFormField>(kmAkhir).controller!.text, '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('new reports can continue and save without LK or DK counts',
      (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.tap(find.text('Buat laporan baru'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Keuangan perjalanan'), findsOneWidget);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Lengkapi laporan'), findsOneWidget);
    await tester.tap(find.text('Simpan laporan'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(savedReport?['luar_kota_count'], isNull);
    expect(savedReport?['dalam_kota_count'], isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty periods stay optional for new reports', (tester) async {
    await pumpScreen(tester, const FormScreen());
    await reveal(tester, find.text('Tambah periode'));
    expect(find.text('Belum ada periode.'), findsOneWidget);
    expect(find.text('LK 0 hari, DK 0 hari.'), findsNothing);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Keuangan perjalanan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LPJ dashboard and bus setup ignore legacy oil settings',
      (tester) async {
    final legacySettings = {
      'bus_0_oil_change_km': '120000',
      'bus_0_oil_interval': '10000',
    };
    settings.addAll(legacySettings);
    await pumpScreen(tester, const HomeScreen());
    expect(find.text('Kilometer terakhir'), findsNothing);
    expect(find.text('124.850 km'), findsNothing);
    expect(find.text('Perawatan oli'), findsNothing);
    expect(find.text('Catat ganti oli'), findsNothing);
    expect(find.byIcon(Icons.oil_barrel_outlined), findsNothing);
    await tester.tap(find.byTooltip('Daftar bus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Happy Bus 01').last);
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Happy Bus 01'), findsWidgets);
    expect(find.text('124.850 km'), findsNothing);
    expect(settingsRead.where((key) => key.contains('_oil_')), isEmpty);
    expect(settingsWritten.where((key) => key.contains('_oil_')), isEmpty);
    for (final entry in legacySettings.entries) {
      expect(settings[entry.key], entry.value);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('add bus retries failed saves and selection updates new reports',
      (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.tap(find.byTooltip('Daftar bus'));
    await tester.pumpAndSettle();
    await capture(tester, 'bus-list');
    expect(find.byType(TextFormField), findsNothing);
    await tester.tap(find.text('Tambah bus'));
    await tester.pumpAndSettle();
    await capture(tester, 'add-bus');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama bus'), 'Bus wisata');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nomor polisi'), 'L 8888 AB');
    failBusSave = true;
    await tester.tap(find.text('Simpan bus'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bus gagal disimpan'), findsOneWidget);
    expect(find.text('Bus wisata'), findsOneWidget);
    failBusSave = false;
    await tester.tap(find.text('Simpan bus'));
    await tester.pumpAndSettle();
    expect(find.text('Bus wisata'), findsOneWidget);
    await tester.tap(find.text('Bus wisata'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Bus wisata'), findsOneWidget);
    expect(settings['selected_bus_id'], '3');
    await tester.tap(find.text('Buat laporan baru'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Nomor polisi'))
            .controller!
            .text,
        'L 8888 AB');
    expect(tester.takeException(), isNull);
  });

  testWidgets('used buses explain why deletion is disabled', (tester) async {
    await pumpScreen(tester, const BusListScreen());
    expect(find.text('Memiliki laporan tersimpan dan tidak dapat dihapus.'),
        findsNWidgets(2));
    for (final plate in ['B 1001 XX', 'B 1002 XX']) {
      final deleteButton = find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Hapus $plate');
      expect(tester.widget<IconButton>(deleteButton).onPressed, isNull);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('unused bus deletion can be cancelled and retried after failure',
      (tester) async {
    reports = [fixture()];
    final originalReports = reports.map((report) => report.toMap()).toList();
    await pumpScreen(tester, const HomeScreen());
    await tester.tap(find.byTooltip('Daftar bus'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Hapus B 1002 XX'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(buses, hasLength(2));

    failBusDelete = true;
    await tester.tap(find.byTooltip('Hapus B 1002 XX'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus bus'));
    await tester.pumpAndSettle();
    expect(buses, hasLength(2));
    expect(find.text('Bus belum dapat dihapus. Coba lagi.'), findsOneWidget);

    failBusDelete = false;
    await tester.tap(find.byTooltip('Hapus B 1002 XX'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus bus'));
    await tester.pumpAndSettle();
    expect(buses.map((bus) => bus['id']), [1]);
    expect(settings['selected_bus_id'], '1');
    expect(find.text('Bus dihapus.'), findsOneWidget);
    expect(reports.map((report) => report.toMap()).toList(), originalReports);
    await tester.tap(find.text('Happy Bus 01'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting the active bus falls back to the remaining bus',
      (tester) async {
    reports = [fixture()];
    settings['selected_bus_id'] = '2';
    await pumpScreen(tester, const HomeScreen());
    await tester.tap(find.byTooltip('Daftar bus'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Hapus B 1002 XX'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus bus'));
    await tester.pumpAndSettle();
    expect(settings['selected_bus_id'], isNull);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Happy Bus 01'), findsOneWidget);
    expect(find.text('Happy Bus 02'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting the last bus returns to setup and allows a replacement',
      (tester) async {
    reports = [];
    buses.removeLast();
    await pumpScreen(tester, const HomeScreen());
    await tester.tap(find.byTooltip('Daftar bus'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Hapus B 1001 XX'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus bus'));
    await tester.pumpAndSettle();
    expect(buses, isEmpty);
    expect(settings['selected_bus_id'], isNull);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Tambahkan bus pertama'), findsOneWidget);
    expect(find.text('Belum bisa memuat data'), findsNothing);
    await tester.tap(find.text('Tambah bus'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama bus'), 'Pengganti');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nomor polisi'), 'L 9999 XX');
    await tester.tap(find.text('Simpan bus'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Pengganti'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'history shows and searches bus names with a legacy plate fallback',
      (tester) async {
    reports.add(fixture(id: 3, plate: 'L 9999 XX', driver: 'Legacy driver'));
    await pumpScreen(tester, const HomeScreen());
    final search = find.byType(TextField);
    await tester.enterText(search, 'Happy Bus 02');
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Happy Bus 02 • Dedi'), findsOneWidget);
    expect(find.text('Happy Bus 01 • Budi Santoso'), findsNothing);
    await tester.enterText(search, 'L 9999 XX');
    await tester.pumpAndSettle();
    expect(find.text('Legacy driver'), findsOneWidget);
    expect(
        find.byWidgetPredicate(
            (widget) => widget is Text && widget.data == 'L 9999 XX'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bus identity can be corrected without changing previous reports',
      (tester) async {
    final originalReports = reports.map((report) => report.toMap()).toList();
    await pumpScreen(tester, const HomeScreen());
    await tester.tap(find.byTooltip('Daftar bus'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ubah B 1001 XX'));
    await tester.pumpAndSettle();
    expect(find.text('Ubah bus'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama bus'), 'Bus baru');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nomor polisi'), 'L 7777 ZZ');
    await tester.tap(find.text('Simpan bus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bus baru'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Bus baru'), findsOneWidget);
    expect(find.text('L 7777 ZZ'), findsOneWidget);
    expect(reports.map((report) => report.toMap()).toList(), originalReports);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'editing a report retains its plate and manual KM after bus changes',
      (tester) async {
    settings['selected_bus_id'] = '2';
    await pumpScreen(tester, FormScreen(report: fixture()));
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
        '124.000');
    expect(
        tester
            .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'KM akhir'))
            .controller!
            .text,
        '124.850');
    expect(find.text('Jarak tempuh'), findsNothing);
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
    await pumpScreen(tester, const BusListScreen(),
        size: const Size(320, 740), scale: 1.5);
    await tester.tap(find.text('Tambah bus'));
    await tester.pumpAndSettle();
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

  testWidgets('receipt step offers gallery and limits camera to non-Linux',
      (tester) async {
    await pumpScreen(tester, FormScreen(report: fixture()));
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    await reveal(tester, find.text('Galeri'));
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
