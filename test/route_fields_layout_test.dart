import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bus_crew/models/report.dart';
import 'package:happy_bus_crew/screens/form_screen.dart';
import 'package:happy_bus_crew/ui/app_theme.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
    // Use real text metrics instead of the test-only Ahem font for fit checks.
    final fontRoot =
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    final fonts = FontLoader('Roboto')
      ..addFont(File('$fontRoot/Roboto-Regular.ttf')
          .readAsBytes()
          .then(ByteData.sublistView))
      ..addFont(File('$fontRoot/Roboto-Bold.ttf')
          .readAsBytes()
          .then(ByteData.sublistView));
    await fonts.load();
  });

  for (final width in [320.0, 390.0]) {
    testWidgets('period fields and actions stay in rows and work at $width px',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final report = Report(
        hariTglBerangkat: '',
        jamBerangkat: '',
        hariTglKembali: '',
        noPolisi: 'AB 7317 BK',
        namaTamu: '',
        pengemudi: '',
        kernet: '',
        kmAwal: 0,
        kmAkhir: 0,
        uangSaku: 0,
        bbm: 0,
        pembayaranTagihan: 0,
        namaCrew: '',
        tripPeriods: [
          TripPeriod(
            start: DateTime(2026, 6, 12),
            end: DateTime(2026, 6, 12),
            type: TripType.luarKota,
            origin: 'Surabaya',
            destination: 'Malang',
          ),
          TripPeriod(
            start: DateTime(2026, 6, 13),
            end: DateTime(2026, 6, 13),
            type: TripType.dalamKota,
            origin: 'Malang',
            destination: 'Batu',
          ),
        ],
      );
      final theme = buildAppTheme();
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('id', 'ID'),
        supportedLocales: const [Locale('id', 'ID')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
          primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Roboto'),
          chipTheme: theme.chipTheme.copyWith(
            labelStyle:
                theme.chipTheme.labelStyle!.copyWith(fontFamily: 'Roboto'),
          ),
        ),
        home: FormScreen(report: report),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Periode 1'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();

      final origins = find.widgetWithText(TextFormField, 'Asal');
      final destinations = find.widgetWithText(TextFormField, 'Tujuan');
      expect(origins, findsNWidgets(2));
      expect(destinations, findsNWidgets(2));

      for (var i = 0; i < 2; i++) {
        final origin = origins.at(i);
        final destination = destinations.at(i);
        await tester.ensureVisible(origin);
        await tester.pumpAndSettle();

        final originRect = tester.getRect(origin);
        final destinationRect = tester.getRect(destination);
        expect(originRect.top, closeTo(destinationRect.top, 0.01));
        expect(originRect.width, closeTo(destinationRect.width, 0.01));
        expect(destinationRect.left - originRect.right, closeTo(12, 0.01));

        await tester.enterText(origin, 'Asal baru $i');
        await tester.pumpAndSettle();
        expect(tester.widget<TextFormField>(destination).controller!.text,
            report.tripPeriods![i].destination);
        await tester.enterText(destination, 'Tujuan baru $i');
        await tester.pumpAndSettle();
        expect(tester.widget<TextFormField>(origin).controller!.text,
            'Asal baru $i');
      }

      for (var i = 0; i < 2; i++) {
        expect(tester.widget<TextFormField>(origins.at(i)).controller!.text,
            'Asal baru $i');
        expect(
            tester.widget<TextFormField>(destinations.at(i)).controller!.text,
            'Tujuan baru $i');
      }
      final lkChips = find.widgetWithText(ChoiceChip, 'LK');
      final dkChips = find.widgetWithText(ChoiceChip, 'DK');
      final deleteButtons = find.ancestor(
        of: find.text('Hapus'),
        matching: find.byWidgetPredicate((widget) => widget is TextButton),
      );
      for (var i = 0; i < 2; i++) {
        final lk = lkChips.at(i);
        final dk = dkChips.at(i);
        final delete = deleteButtons.at(i);
        await tester.ensureVisible(lk);
        await tester.pumpAndSettle();

        final lkRect = tester.getRect(lk);
        final dkRect = tester.getRect(dk);
        final deleteRect = tester.getRect(delete);
        expect(lkRect.center.dy, closeTo(dkRect.center.dy, 0.01));
        expect(lkRect.center.dy, closeTo(deleteRect.center.dy, 0.01));
        expect(lkRect.left, closeTo(tester.getRect(origins.at(i)).left, 0.01));
        expect(dkRect.left - lkRect.right, closeTo(8, 0.01));
        expect(deleteRect.left, greaterThanOrEqualTo(dkRect.right));
        expect(deleteRect.right,
            closeTo(tester.getRect(destinations.at(i)).right, 0.01));
        for (final rect in [lkRect, dkRect, deleteRect]) {
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(rect.width, greaterThanOrEqualTo(48));
        }

        await tester.tap(dk);
        await tester.pumpAndSettle();
        expect(tester.widget<ChoiceChip>(lk).selected, isFalse);
        expect(tester.widget<ChoiceChip>(dk).selected, i == 0);
        await tester.tap(lk);
        await tester.pumpAndSettle();
        expect(tester.widget<ChoiceChip>(lk).selected, isTrue);
        expect(tester.widget<ChoiceChip>(dk).selected, isFalse);
      }

      await tester.ensureVisible(deleteButtons.first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Hapus periode 1'), findsOneWidget);
      await tester.tap(deleteButtons.first);
      await tester.pumpAndSettle();
      expect(origins, findsOneWidget);
      expect(destinations, findsOneWidget);
      expect(deleteButtons, findsOneWidget);
      expect(tester.widget<TextFormField>(origins).controller!.text,
          'Asal baru 1');
      expect(tester.widget<TextFormField>(destinations).controller!.text,
          'Tujuan baru 1');
      expect(tester.widget<ChoiceChip>(lkChips).selected, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
