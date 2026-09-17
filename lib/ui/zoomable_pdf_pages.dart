import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// Displays rendered PDF pages with pinch zoom, panning and page navigation.
class ZoomablePdfPages extends StatefulWidget {
  final List<PdfPreviewPageData> pages;

  const ZoomablePdfPages({super.key, required this.pages});

  @override
  State<ZoomablePdfPages> createState() => _ZoomablePdfPagesState();
}

class _ZoomablePdfPagesState extends State<ZoomablePdfPages> {
  final _transform = TransformationController();
  Size _viewport = Size.zero;
  int _page = 0;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _reset() => _transform.value = Matrix4.identity();

  void _changePage(int page) {
    _reset();
    setState(() => _page = page);
  }

  void _zoom(double factor) {
    final current = _transform.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(1.0, 5.0).toDouble();
    if (next == 1) {
      _reset();
      return;
    }
    final center = _viewport.center(Offset.zero);
    final point = _transform.toScene(center);
    _transform.value = Matrix4.identity()
      ..translate(center.dx - point.dx * next, center.dy - point.dy * next)
      ..scale(next);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final page = _page.clamp(0, widget.pages.length - 1);
    return Column(children: [
      Expanded(
        child: LayoutBuilder(builder: (context, constraints) {
          _viewport = constraints.biggest;
          return GestureDetector(
            onDoubleTap: () {
              if (_transform.value.getMaxScaleOnAxis() > 1) {
                _reset();
              } else {
                _zoom(2);
              }
            },
            child: InteractiveViewer(
              transformationController: _transform,
              minScale: 1,
              maxScale: 5,
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: Image(
                  image: widget.pages[page].image,
                  fit: BoxFit.contain,
                  semanticLabel: 'Halaman PDF ${page + 1}',
                ),
              ),
            ),
          );
        }),
      ),
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            tooltip: 'Halaman sebelumnya',
            onPressed: page > 0 ? () => _changePage(page - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text('${page + 1} / ${widget.pages.length}'),
          IconButton(
            tooltip: 'Halaman berikutnya',
            onPressed: page + 1 < widget.pages.length
                ? () => _changePage(page + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: 'Perkecil PDF',
            onPressed: () => _zoom(1 / 1.5),
            icon: const Icon(Icons.zoom_out),
          ),
          IconButton(
            tooltip: 'Perbesar PDF',
            onPressed: () => _zoom(1.5),
            icon: const Icon(Icons.zoom_in),
          ),
          IconButton(
            tooltip: 'Atur ulang zoom',
            onPressed: _reset,
            icon: const Icon(Icons.fit_screen),
          ),
        ],
      ),
    ]);
  }
}
