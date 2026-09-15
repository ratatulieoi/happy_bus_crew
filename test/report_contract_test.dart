import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bus_crew/models/report.dart';
import 'package:happy_bus_crew/pdf/report_pdf.dart';
import 'package:happy_bus_crew/screens/form_screen.dart';
import 'package:happy_bus_crew/utils/format.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('id_ID'));

  Report report() => Report(
        id: 4,
        tanggalBuat: DateTime(2026, 6, 12),
        hariTglBerangkat: 'Jumat, 12/06/2026',
        jamBerangkat: '08:00',
        hariTglKembali: 'Sabtu, 13/06/2026',
        noPolisi: 'B 1001 XX',
        pengemudi: 'Budi',
        kernet: 'Agus',
        kmAwal: 1000,
        kmAkhir: 1250,
        uangSaku: 1000000,
        bbm: 600000,
        uangMakan: 100000,
        extra: 50000,
        tagihan: 50000,
        namaCrew: 'Budi',
        catatan: 'Catatan perjalanan',
      );

  test('all saved fields round-trip and editing retains identity', () {
    final original = report();
    final restored = Report.fromMap(original.toMap());
    expect(restored.toMap(), original.toMap());
    final changed = original.copyWith(catatan: 'Diubah');
    expect(changed.id, original.id);
    expect(changed.tanggalBuat, original.tanggalBuat);
    expect(changed.catatan, 'Diubah');
  });

  test('financial calculations retain existing contract', () {
    final r = report();
    expect(r.totalPengeluaran, 800000);
    expect(r.sisa, 200000);
    expect(r.copyWith(uangSaku: 500000).sisa, -300000);
    expect(r.copyWith(uangSaku: 800000).sisa, 0);
  });

  test('km awal and km akhir persist as manual per-report inputs', () {
    final r = report();
    expect(r.kmAwal, 1000);
    expect(r.kmAkhir, 1250);
    expect(r.toMap()['km_awal'], 1000);
    expect(r.toMap()['km_akhir'], 1250);
    final restored = Report.fromMap(r.toMap());
    expect(restored.kmAwal, 1000);
    expect(restored.kmAkhir, 1250);
    final edited = r.copyWith(kmAwal: 2000, kmAkhir: 2750);
    expect(edited.kmAwal, 2000);
    expect(edited.kmAkhir, 2750);
    // No derived distance is stored: only the entered values round-trip.
    expect(edited.toMap()['km_awal'], 2000);
    expect(edited.toMap()['km_akhir'], 2750);
  });

  test('whole rupiah input stays Indonesian', () {
    expect(parseRupiahInput('Rp 1.250.000'), 1250000);
    expect(parseRupiahInput(''), 0);
    expect(formatNumberId(1250000), '1.250.000');
    expect(formatRupiah(1250000), 'Rp 1.250.000');
  });

  test('thousands formatter handles typing and middle edits', () {
    final formatter = ThousandsSeparatorFormatter();
    expect(
        formatter
            .formatEditUpdate(
                TextEditingValue.empty,
                const TextEditingValue(
                    text: '1250000',
                    selection: TextSelection.collapsed(offset: 7)))
            .text,
        '1.250.000');
    final middle = formatter.formatEditUpdate(
        const TextEditingValue(text: '12.000'),
        const TextEditingValue(
            text: '192.000', selection: TextSelection.collapsed(offset: 2)));
    expect(middle.text, '192.000');
    expect(middle.selection.extentOffset, 2);
    expect(
        formatter
            .formatEditUpdate(
                TextEditingValue.empty, const TextEditingValue(text: ''))
            .text,
        '');
  });

  test('PDF contains manual KM and receipts without calculated distance', () async {
    final logo =
        (await rootBundle.load('assets/logo.png')).buffer.asUint8List();
    final doc = await ReportPdfBuilder.build(report(),
        attachmentImages: [logo, logo, Uint8List(0)]);
    final bytes = await doc.save();
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    final raw = latin1.decode(bytes);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(raw).length, 3);
    final streams = <String>[];
    for (final match in RegExp(r'stream\r?\n(.*?)\r?\nendstream', dotAll: true).allMatches(raw)) {
      final data = latin1.encode(match.group(1)!);
      try {
        streams.add(latin1.decode(zlib.decode(data)));
      } on FormatException {
        streams.add(match.group(1)!);
      }
    }
    final content = streams.join('\n');
    expect(content, contains('Awal'));
    expect(content, contains('Akhir'));
    expect(content, contains('1.000'));
    expect(content, contains('1.250'));
    expect(content, isNot(contains('Jarak')));
    expect(content, isNot(contains('Tempuh')));
    final output = Platform.environment['PDF_TEST_OUTPUT'];
    if (output != null) await File(output).writeAsBytes(bytes);
  });
}
