import 'dart:convert';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Read text operators and the document's font maps, never rendered pixels.
Future<List<String>> pdfPageText(pw.Document document) async {
  await document.save();
  final fonts = {for (final font in document.document.fonts) font.name: font};
  return [
    for (final page in document.document.pdfPageList.pages)
      [
        for (final stream in page.contents)
          _text(latin1.decode((stream as dynamic).buf.output() as List<int>),
              fonts),
      ].join('\n'),
  ];
}

String normalizePdfText(String text) => text.replaceAll(RegExp(r'\s+'), ' ');

String _text(String content, Map<String, PdfFont> fonts) {
  PdfFont? font;
  final text = <String>[];
  final tokens = RegExp(
    r'(/F\d+)\s+[\d.]+\s+Tf|\[(.*?)\]\s*TJ|(<[0-9a-fA-F]+>|\((?:\\.|[^\\()])*\))\s*Tj',
    dotAll: true,
  );
  for (final match in tokens.allMatches(content)) {
    if (match.group(1) != null) {
      font = fonts[match.group(1)];
      continue;
    }
    final source = match.group(2) ?? match.group(3)!;
    text.add(RegExp(r'<[0-9a-fA-F]+>|\((?:\\.|[^\\()])*\)', dotAll: true)
        .allMatches(source)
        .map((literal) {
      final value = literal.group(0)!;
      if (value.startsWith('<')) {
        final ttf = font as PdfTtfFont;
        final hex = value.substring(1, value.length - 1);
        return String.fromCharCodes([
          for (var i = 0; i < hex.length; i += 4)
            ttf.unicodeCMap.cmap[int.parse(hex.substring(i, i + 4), radix: 16)],
        ]);
      }
      return value.substring(1, value.length - 1).replaceAllMapped(
        RegExp(r'\\([0-7]{1,3}|.)', dotAll: true),
        (escape) {
          final code = escape.group(1)!;
          if (RegExp(r'^[0-7]+$').hasMatch(code)) {
            return String.fromCharCode(int.parse(code, radix: 8));
          }
          return switch (code) {
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            _ => code
          };
        },
      );
    }).join());
  }
  return text.join('\n');
}
