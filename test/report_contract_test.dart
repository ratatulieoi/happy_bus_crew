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
        extras: const [
          ExtraExpense(name: 'Parkir', amount: 20000),
          ExtraExpense(name: 'Tol', amount: 30000),
        ],
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

  test('trip types round-trip, copy and preserve unspecified legacy reports', () {
    for (final type in TripType.values) {
      final original = report().copyWith(tripType: type);
      expect(original.toMap()['trip_type'], type.value);
      final restored = Report.fromMap(original.toMap());
      expect(restored.tripType, type);
      expect(restored.copyWith(catatan: 'Edited').tripType, type);
      expect(restored.totalPengeluaran, report().totalPengeluaran);
    }
    for (final value in [null, '', 'unknown', 123]) {
      expect(Report.fromMap({'trip_type': value}).tripType, TripType.unspecified);
    }
    expect(Report.fromMap({}).tripType.label, '-');
  });

  test('PDF shows the chosen trip type without assuming one for old reports',
      () async {
    for (final type in TripType.values) {
      final doc = await ReportPdfBuilder.build(report().copyWith(tripType: type));
      final raw = latin1.decode(await doc.save());
      final streams = <String>[];
      for (final match in RegExp(r'stream\r?\n(.*?)\r?\nendstream', dotAll: true)
          .allMatches(raw)) {
        try {
          streams.add(latin1.decode(zlib.decode(latin1.encode(match.group(1)!))));
        } on FormatException {
          streams.add(match.group(1)!);
        }
      }
      final content = streams.join('\n');
      expect(content, contains('Jenis'));
      if (type == TripType.unspecified) {
        expect(content, isNot(contains('Luar')));
        expect(content, isNot(contains('Dalam')));
      } else {
        expect(content, contains(type == TripType.luarKota ? 'Luar' : 'Dalam'));
        expect(content, contains('Kota'));
      }
    }
  });

  test('financial calculations retain existing contract', () {
    final r = report();
    expect(r.extra, 50000);
    expect(r.totalPengeluaran, 800000);
    expect(r.sisa, 200000);
    expect(r.copyWith(uangSaku: 500000).sisa, -300000);
    expect(r.copyWith(uangSaku: 800000).sisa, 0);
  });

  test('multiple extras sum exactly once and round-trip with names', () {
    final r = report().copyWith(extras: const [
      ExtraExpense(name: 'Parkir', amount: 20000),
      ExtraExpense(name: 'Tol', amount: 150000),
      ExtraExpense(name: 'Cuci bus', amount: 50000),
    ]);
    expect(r.extra, 220000);
    expect(r.totalPengeluaran, 600000 + 100000 + 50000 + 220000);
    final restored = Report.fromMap(r.toMap());
    expect(restored.extras.map((item) => item.name),
        ['Parkir', 'Tol', 'Cuci bus']);
    expect(restored.extras.map((item) => item.amount), [20000, 150000, 50000]);
    expect(restored.extra, 220000);
    expect(restored.toMap(), r.toMap());
  });

  test('legacy extra amounts load as Extra lama with the same total', () {
    final restored = Report.fromMap({
      'id': 9,
      'bbm': 100000,
      'uang_makan': 50000,
      'extra': 75000,
      'tagihan': 25000,
    });
    expect(restored.extras, hasLength(1));
    expect(restored.extras.single.name, 'Extra lama');
    expect(restored.extras.single.amount, 75000);
    expect(restored.extra, 75000);
    expect(restored.totalPengeluaran, 250000);
    final resaved = Report.fromMap(restored.toMap());
    expect(resaved.extras.single.amount, 75000);
    expect(resaved.totalPengeluaran, 250000);
  });

  test('malformed extra details fall back to the complete saved total', () {
    for (final details in [
      'not json',
      '[]',
      '[{"name":5,"amount":20000}]',
      '[{"name":"Parkir","amount":"20000"}]',
      '[{"name":"Parkir","amount":20000},null]',
    ]) {
      final restored = Report.fromMap({'extra': 75000, 'extra_details': details});
      expect(restored.extras.single.name, 'Extra lama');
      expect(restored.extra, 75000);
    }
  });

  test('removing all extras clears the stored legacy total too', () {
    final cleared = report().copyWith(extras: []);
    expect(cleared.toMap()['extra'], 0);
    expect(cleared.toMap()['extra_details'], '[]');
    expect(Report.fromMap(cleared.toMap()).extras, isEmpty);
    expect(cleared.totalPengeluaran, 750000);
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

  test('PDF lists each extra by name and keeps totals consistent', () async {
    final doc = await ReportPdfBuilder.build(report());
    final bytes = await doc.save();
    final raw = latin1.decode(bytes);
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
    expect(content, contains('Parkir'));
    expect(content, contains('Tol'));
    expect(content, contains('20.000'));
    expect(content, contains('30.000'));
    expect(content, contains('50.000'));
    // PDF text streams can split words into separate drawing commands.
    expect(content.indexOf('BBM'), lessThan(content.indexOf('Makan')));
    expect(content.indexOf('Makan'), lessThan(content.indexOf('Tagihan')));
    expect(content.indexOf('Tagihan'), lessThan(content.indexOf('Extra')));
  });

  test('PDF paginates many extras without dropping entries', () async {
    final r = report().copyWith(extras: [
      for (var i = 0; i < 80; i++)
        ExtraExpense(name: 'Item${i.toString().padLeft(3, '0')}', amount: 1000),
    ]);
    final doc = await ReportPdfBuilder.build(r);
    final raw = latin1.decode(await doc.save());
    expect(RegExp(r'/Type\s*/Page\b').allMatches(raw).length, greaterThan(1));
    final streams = <String>[];
    for (final match in RegExp(r'stream\r?\n(.*?)\r?\nendstream', dotAll: true)
        .allMatches(raw)) {
      try {
        streams.add(latin1.decode(zlib.decode(latin1.encode(match.group(1)!))));
      } on FormatException {
        streams.add(match.group(1)!);
      }
    }
    final content = streams.join('\n');
    expect(content, contains('Item000'));
    expect(content, contains('Item079'));
    expect(r.extra, 80000);
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
