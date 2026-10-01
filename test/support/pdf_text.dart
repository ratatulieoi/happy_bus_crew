import 'dart:convert';

import 'package:pdf/widgets.dart' as pw;

/// Read this builder's standard-font text from page content streams only.
/// Images are excluded, and kerning-split literals stay in drawing order.
Future<List<String>> pdfPageText(pw.Document document) async {
  await document.save();
  return [
    for (final page in document.document.pdfPageList.pages)
      [
        for (final stream in page.contents)
          _text(latin1.decode((stream as dynamic).buf.output() as List<int>)),
      ].join('\n'),
  ];
}

String normalizePdfText(String text) => text.replaceAll(RegExp(r'\s+'), ' ');

String _text(String content) => RegExp(
      r'\[(.*?)\]\s*TJ|\((?:\\.|[^\\()])*\)\s*Tj',
      dotAll: true,
    ).allMatches(content).map((match) {
      final source = match.group(1) ?? match.group(0)!;
      return RegExp(r'\((?:\\.|[^\\()])*\)', dotAll: true)
          .allMatches(source)
          .map((literal) {
        final text = literal.group(0)!;
        return text.substring(1, text.length - 1).replaceAllMapped(
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
              _ => code,
            };
          },
        );
      }).join();
    }).join('\n');
