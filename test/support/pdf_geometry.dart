import 'dart:convert';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Nonvisual paint positions, in PDF points measured from the lower-left.
/// The builder uses axis-aligned transforms only. Reject skew/rotation rather
/// than silently treating them as translations in a layout assertion.
class PdfPaintGeometry {
  final text =
      <({String value, double x, double y, double width, double size})>[];
  final images = <({double x, double y, double width, double height})>[];
  final rules = <({double x, double y, double width, double height})>[];
}

Future<List<PdfPaintGeometry>> pdfGeometry(pw.Document document) async {
  await document.save();
  final fonts = {for (final font in document.document.fonts) font.name: font};
  return [
    for (final page in document.document.pdfPageList.pages)
      _parse(
          page.contents
              .map((stream) =>
                  latin1.decode((stream as dynamic).buf.output() as List<int>))
              .join(),
          fonts),
  ];
}

PdfPaintGeometry _parse(String content, Map<String, PdfFont> fonts) {
  final result = PdfPaintGeometry();
  var transform = (sx: 1.0, sy: 1.0, x: 0.0, y: 0.0);
  final stack = <({double sx, double sy, double x, double y})>[];
  PdfTtfFont? font;
  double fontSize = 0, tx = 0, ty = 0;
  const number = r'-?\d+(?:\.\d+)?';
  final operators = RegExp(
    '\\bq\\b|\\bQ\\b|(?:$number\\s+){6}cm|'
    '/I\\w+\\s+Do|/F\\d+\\s+$number\\s+Tf|'
    '$number\\s+$number\\s+Td|\\[(?:[^\\]])*\\]TJ|'
    '(?:$number\\s+){4}re|'
    '$number\\s+$number\\s+m\\s+$number\\s+$number\\s+l\\s+S',
  );
  for (final match in operators.allMatches(content)) {
    final op = match.group(0)!;
    final values = RegExp(number)
        .allMatches(op)
        .map((m) => double.parse(m.group(0)!))
        .toList();
    if (op == 'q') {
      stack.add(transform);
    } else if (op == 'Q') {
      transform = stack.removeLast();
    } else if (op.endsWith('cm')) {
      if (values[1] != 0 || values[2] != 0) {
        throw StateError('Geometry test does not support rotated content');
      }
      transform = (
        sx: transform.sx * values[0],
        sy: transform.sy * values[3],
        x: transform.x + transform.sx * values[4],
        y: transform.y + transform.sy * values[5],
      );
    } else if (op.endsWith('Do')) {
      result.images.add((
        x: transform.x,
        y: transform.y,
        width: transform.sx,
        height: transform.sy
      ));
    } else if (op.endsWith('Tf')) {
      font = fonts[op.split(' ').first] as PdfTtfFont;
      fontSize = values.last;
    } else if (op.endsWith('Td')) {
      tx = values[0];
      ty = values[1];
    } else if (op.endsWith('TJ')) {
      final value = RegExp(r'<([0-9a-fA-F]+)>').allMatches(op).map((m) {
        final hex = m.group(1)!;
        return String.fromCharCodes([
          for (var i = 0; i < hex.length; i += 4)
            font!.unicodeCMap
                .cmap[int.parse(hex.substring(i, i + 4), radix: 16)],
        ]);
      }).join();
      result.text.add((
        value: value,
        x: transform.x + tx * transform.sx,
        y: transform.y + ty * transform.sy,
        width:
            font!.stringMetrics(value).advanceWidth * fontSize * transform.sx,
        size: fontSize
      ));
    } else if (op.endsWith('re') && values[3] <= 1) {
      result.rules.add((
        x: transform.x + values[0] * transform.sx,
        y: transform.y + values[1] * transform.sy,
        width: values[2] * transform.sx,
        height: values[3] * transform.sy
      ));
    } else if (op.endsWith('S') && values[1] == values[3]) {
      result.rules.add((
        x: transform.x + values[0] * transform.sx,
        y: transform.y + values[1] * transform.sy,
        width: (values[2] - values[0]) * transform.sx,
        height: 0.45
      ));
    }
  }
  return result;
}
