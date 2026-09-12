import 'dart:convert';

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

  test('financial and mileage calculations retain existing contract', () {
    final r = report();
    expect(r.totalPengeluaran, 800000);
    expect(r.sisa, 200000);
    expect(r.jarakTempuh, 250);
    expect(r.copyWith(uangSaku: 500000).sisa, -300000);
    expect(r.copyWith(uangSaku: 800000).sisa, 0);
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

  test('unchanged PDF builder produces PDF and one page per receipt', () async {
    final logo =
        (await rootBundle.load('assets/logo.png')).buffer.asUint8List();
    final doc = await ReportPdfBuilder.build(report(),
        attachmentImages: [logo, logo, Uint8List(0)]);
    final bytes = await doc.save();
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    final raw = latin1.decode(bytes);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(raw).length, 3);
  });
}
