import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bus_crew/ui/zoomable_pdf_pages.dart';
import 'package:printing/printing.dart';

void main() {
  const pages = [
    PdfPreviewPageData(
        image: AssetImage('assets/logo.png'), width: 595, height: 842),
    PdfPreviewPageData(
        image: AssetImage('assets/logo.png'), width: 595, height: 842),
  ];

  Future<void> pumpViewer(WidgetTester tester,
      {Size size = const Size(390, 844), double scale = 1}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: const ZoomablePdfPages(pages: pages),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  TransformationController controller(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!;

  testWidgets('zoom buttons reset and page controls keep all pages accessible',
      (tester) async {
    await pumpViewer(tester);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate((widget) =>
                widget is IconButton && widget.tooltip == 'Halaman sebelumnya'))
            .onPressed,
        isNull);
    await tester.tap(find.byTooltip('Perbesar PDF'));
    await tester.pump();
    expect(controller(tester).value.getMaxScaleOnAxis(), closeTo(1.5, .001));
    await tester.tap(find.byTooltip('Perkecil PDF'));
    await tester.pump();
    expect(controller(tester).value.getMaxScaleOnAxis(), 1);
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byTooltip('Perbesar PDF'));
      await tester.pump();
    }
    expect(controller(tester).value.getMaxScaleOnAxis(), 5);
    await tester.tap(find.byTooltip('Atur ulang zoom'));
    await tester.pump();
    expect(controller(tester).value.getMaxScaleOnAxis(), 1);
    await tester.tap(find.byTooltip('Perbesar PDF'));
    await tester.tap(find.byTooltip('Halaman berikutnya'));
    await tester.pump();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(controller(tester).value.getMaxScaleOnAxis(), 1);
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate((widget) =>
                widget is IconButton && widget.tooltip == 'Halaman berikutnya'))
            .onPressed,
        isNull);
    await tester.tap(find.byTooltip('Halaman sebelumnya'));
    await tester.pump();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinch zooms and double tap resets without hiding navigation',
      (tester) async {
    await pumpViewer(tester);
    final viewer = find.byType(InteractiveViewer);
    final center = tester.getCenter(viewer);
    final first =
        await tester.startGesture(center - const Offset(30, 0), pointer: 1);
    final second =
        await tester.startGesture(center + const Offset(30, 0), pointer: 2);
    await tester.pump();
    await first.moveTo(center - const Offset(40, 0));
    await second.moveTo(center + const Offset(40, 0));
    await tester.pump();
    await first.moveTo(center - const Offset(90, 0));
    await second.moveTo(center + const Offset(90, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(controller(tester).value.getMaxScaleOnAxis(), greaterThan(1));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(controller(tester).value.getMaxScaleOnAxis(), 1);
    expect(find.byTooltip('Halaman berikutnya'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zoom controls fit narrow screens with large text',
      (tester) async {
    await pumpViewer(tester, size: const Size(320, 600), scale: 1.5);
    await tester.tap(find.byTooltip('Perbesar PDF'));
    await tester.pumpAndSettle();
    expect(controller(tester).value.getMaxScaleOnAxis(), greaterThan(1));
    expect(tester.takeException(), isNull);
  });
}
