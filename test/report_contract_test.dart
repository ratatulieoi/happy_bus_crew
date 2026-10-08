import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bus_crew/models/report.dart';
import 'package:happy_bus_crew/models/report_attachment.dart';
import 'package:happy_bus_crew/pdf/report_pdf.dart';
import 'package:happy_bus_crew/screens/form_screen.dart';
import 'package:happy_bus_crew/utils/format.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/pdf_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('id_ID'));

  Report report() => Report(
        id: 4,
        tanggalBuat: DateTime(2026, 6, 12),
        hariTglBerangkat: 'Jumat, 12/06/2026',
        jamBerangkat: '08:00',
        hariTglKembali: 'Sabtu, 13/06/2026',
        noPolisi: 'AB 7317 BK',
        namaTamu: 'Bpk. Hartono',
        pengemudi: 'Budi',
        kernet: 'Agus',
        kmAwal: 1000,
        kmAkhir: 1250,
        uangSaku: 1000000,
        bbm: 600000,
        tripPeriods: [
          TripPeriod(
              start: DateTime(2026, 6, 12),
              end: DateTime(2026, 6, 13),
              type: TripType.luarKota),
        ],
        extras: [
          ExtraExpense(name: 'Parkir', amount: 20000),
          ExtraExpense(name: 'Tol', amount: 30000),
        ],
        pembayaranTagihan: 50000,
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

  test('guest allowance fields round-trip and copy independently', () {
    final original = report().copyWith(
      hasGuestAllowance: true,
      guestUangSaku: 250000,
      guestTol: 15000,
      guestPenyeberangan: 25000,
      guestParkir: 10000,
      guestExtras: [ExtraExpense(name: 'Bagasi', amount: 5000)],
      guestCatatan: 'Titipan tamu',
    );
    final restored = Report.fromMap(original.toMap());

    expect(restored.toMap(), original.toMap());
    expect(restored.hasGuestAllowance, isTrue);
    expect(restored.guestUangSaku, 250000);
    expect(restored.guestTol, 15000);
    expect(restored.guestPenyeberangan, 25000);
    expect(restored.guestParkir, 10000);
    expect(restored.guestExtras.single.name, 'Bagasi');
    expect(restored.guestExtras.single.amount, 5000);
    expect(restored.guestCatatan, 'Titipan tamu');

    final changed = restored.copyWith(
      guestTol: 20000,
      guestCatatan: 'Catatan baru',
    );
    expect(changed.guestTol, 20000);
    expect(changed.guestCatatan, 'Catatan baru');
    expect(changed.guestUangSaku, original.guestUangSaku);
    expect(changed.guestPenyeberangan, original.guestPenyeberangan);
    expect(changed.guestParkir, original.guestParkir);
    expect(changed.guestExtras.map((item) => item.name), ['Bagasi']);
    expect(changed.guestExtras.map((item) => item.amount), [5000]);
    expect(changed.hasGuestAllowance, isTrue);
  });

  test('guest totals include guest costs only', () {
    final r = report().copyWith(
      hasGuestAllowance: true,
      guestUangSaku: 100000,
      guestTol: 10000,
      guestPenyeberangan: 20000,
      guestParkir: 5000,
      guestExtras: [
        ExtraExpense(name: 'Bagasi', amount: 3000),
        ExtraExpense(name: 'Air minum', amount: 2000),
      ],
    );

    expect(r.guestExtraTotal, 5000);
    expect(r.guestTotalPengeluaran, 40000);
    expect(r.guestSisa, 60000);
    expect(r.totalPengeluaran, 750000);
    expect(r.sisa, 250000);
    expect(r.copyWith(guestUangSaku: 1000).totalPengeluaran, 750000);
    expect(r.copyWith(guestTol: 0).sisa, 250000);
  });

  test('hasGuestData reflects the toggle and every guest field', () {
    expect(report().hasGuestData, isFalse);
    expect(report().copyWith(hasGuestAllowance: true).hasGuestData, isTrue);
    expect(report().copyWith(guestUangSaku: 1).hasGuestData, isTrue);
    expect(report().copyWith(guestTol: 1).hasGuestData, isTrue);
    expect(report().copyWith(guestPenyeberangan: 1).hasGuestData, isTrue);
    expect(report().copyWith(guestParkir: 1).hasGuestData, isTrue);
    expect(
        report().copyWith(guestExtras: [
          ExtraExpense(name: 'Bagasi', amount: 0)
        ]).hasGuestData,
        isTrue);
    expect(report().copyWith(guestCatatan: 'Catatan').hasGuestData, isTrue);
    expect(
        report()
            .copyWith(hasGuestAllowance: false, guestUangSaku: 1)
            .hasGuestData,
        isTrue);
  });

  test('malformed guest extra details fall back to an empty list', () {
    for (final details in [
      'not json',
      '{}',
      '[{"name":5,"amount":20000}]',
      '[{"name":"Bagasi","amount":"20000"}]',
      '[{"name":"Bagasi","amount":20000},null]',
    ]) {
      expect(Report.fromMap({'guest_extra_details': details}).guestExtras,
          isEmpty);
    }
  });

  test('trip types round-trip, copy and preserve unspecified legacy reports',
      () {
    for (final type in TripType.values) {
      final original =
          Report.fromMap({...report().toMap(), 'trip_periods': null})
              .copyWith(tripType: type);
      expect(original.toMap()['trip_type'], type.value);
      final restored = Report.fromMap(original.toMap());
      expect(restored.tripType, type);
      expect(restored.copyWith(catatan: 'Edited').tripType, type);
      expect(restored.totalPengeluaran, 650000);
    }
    for (final value in [null, '', 'unknown', 123]) {
      expect(
          Report.fromMap({'trip_type': value}).tripType, TripType.unspecified);
    }
    expect(Report.fromMap({}).tripType.label, '-');
  });

  test('trip counts round-trip independently and preserve zero', () {
    for (final counts in [
      [3, 5],
      [3, 0],
      [0, 5],
      [0, 0]
    ]) {
      final original =
          Report.fromMap({...report().toMap(), 'trip_periods': null})
              .copyWith(luarKotaCount: counts[0], dalamKotaCount: counts[1]);
      final restored = Report.fromMap(original.toMap());
      expect(restored.luarKotaCount, counts[0]);
      expect(restored.dalamKotaCount, counts[1]);
      expect(restored.hasTripCounts, isTrue);
      expect(restored.copyWith(catatan: 'Edited').toMap(),
          {...original.toMap(), 'catatan': 'Edited'});
      expect(restored.copyWith(luarKotaCount: 0).luarKotaCount, 0);
      expect(restored.copyWith(dalamKotaCount: 0).dalamKotaCount, 0);
      expect(restored.totalPengeluaran, 650000);
    }
    for (final type in TripType.values) {
      final legacy = Report.fromMap({'trip_type': type.value});
      expect(legacy.luarKotaCount, isNull);
      expect(legacy.dalamKotaCount, isNull);
      expect(legacy.hasTripCounts, isFalse);
      expect(Report.fromMap(legacy.toMap()).tripType, type);
    }
  });

  test('PDF shows both trip counts, including zero, instead of old category',
      () async {
    for (final counts in [
      [3, 5],
      [0, 5],
      [3, 0],
      [0, 0]
    ]) {
      final doc = await ReportPdfBuilder.build(
          Report.fromMap({...report().toMap(), 'trip_periods': null}).copyWith(
              tripType: TripType.luarKota,
              luarKotaCount: counts[0],
              dalamKotaCount: counts[1]));
      final text = normalizePdfText((await pdfPageText(doc)).join('\n'));
      expect(
          text,
          contains('Total periode ${counts[0] + counts[1]} hari '
              'LK ${counts[0]} / DK ${counts[1]}'));
      expect(text, isNot(contains('Kategori lama')));
    }
  });

  test('PDF retains old trip category without inventing counts', () async {
    for (final type in TripType.values) {
      final doc = await ReportPdfBuilder.build(Report.fromMap({
        ...report().toMap(),
        'trip_periods': null,
        'luar_kota_count': null,
        'dalam_kota_count': null,
      }).copyWith(tripType: type));
      final text = normalizePdfText((await pdfPageText(doc)).join('\n'));
      expect(text, contains('Total periode - -'));
      if (type == TripType.unspecified) {
        expect(text, isNot(contains('Kategori lama')));
      } else {
        expect(text, contains('Kategori lama: ${type.label}'));
      }
      expect(RegExp(r'\d{2}/\d{2}/\d{4}').allMatches(text), hasLength(2));
    }
  });

  test('client bus-fee payments stay separate from expenses and balance', () {
    final r = report();
    expect(r.pembayaranTagihan, 50000);
    expect(r.toMap()['pembayaran_tagihan'], 50000);
    expect(Report.fromMap(r.toMap()).pembayaranTagihan, 50000);
    expect(r.extra, 50000);
    expect(r.totalPengeluaran, 750000);
    expect(r.sisa, 250000);
    expect(r.copyWith(pembayaranTagihan: 900000).sisa, 250000);
    expect(r.copyWith(uangSaku: 500000).sisa, -250000);
    expect(r.copyWith(uangSaku: 750000).sisa, 0);
  });

  test('multiple extras sum exactly once and round-trip with names', () {
    final r = report().copyWith(extras: [
      ExtraExpense(name: 'Parkir', amount: 20000),
      ExtraExpense(name: 'Tol', amount: 150000),
      ExtraExpense(name: 'Cuci bus', amount: 50000),
    ]);
    expect(r.extra, 220000);
    expect(r.totalPengeluaran, 600000 + 100000 + 220000);
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
      'pembayaran_tagihan': 40000,
    });
    expect(restored.extras, hasLength(1));
    expect(restored.extras.single.name, 'Extra lama');
    expect(restored.extras.single.amount, 75000);
    expect(restored.extra, 75000);
    expect(restored.pembayaranTagihan, 40000);
    expect(restored.totalPengeluaran, 175000);
    final resaved = Report.fromMap(restored.toMap());
    expect(resaved.extras.single.amount, 75000);
    expect(resaved.pembayaranTagihan, 40000);
    expect(resaved.totalPengeluaran, 175000);
  });

  test('malformed extra details fall back to the complete saved total', () {
    for (final details in [
      'not json',
      '[]',
      '[{"name":5,"amount":20000}]',
      '[{"name":"Parkir","amount":"20000"}]',
      '[{"name":"Parkir","amount":20000},null]',
    ]) {
      final restored =
          Report.fromMap({'extra': 75000, 'extra_details': details});
      expect(restored.extras.single.name, 'Extra lama');
      expect(restored.extra, 75000);
    }
  });

  test('removing all extras clears the stored legacy total too', () {
    final cleared = report().copyWith(extras: []);
    expect(cleared.toMap()['extra'], 0);
    expect(cleared.toMap()['extra_details'], '[]');
    expect(Report.fromMap(cleared.toMap()).extras, isEmpty);
    expect(cleared.totalPengeluaran, 700000);
  });

  test('guest name round-trips, survives edits and defaults when absent', () {
    final r = report();
    expect(r.namaTamu, 'Bpk. Hartono');
    expect(r.toMap()['nama_tamu'], 'Bpk. Hartono');
    expect(Report.fromMap(r.toMap()).namaTamu, 'Bpk. Hartono');
    expect(r.copyWith(catatan: 'Edit').namaTamu, 'Bpk. Hartono');
    final legacy = r.toMap()..remove('nama_tamu');
    expect(Report.fromMap(legacy).namaTamu, isEmpty);
  });

  test('stored kilometer fields still round-trip without form inputs', () {
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
    final text = normalizePdfText((await pdfPageText(doc)).join('\n'));
    expect(text, contains('BBM Rp600.000'));
    expect(text, contains('Uang makan · 2 hari × Rp50.000 Rp100.000'));
    expect(text, contains('Parkir Rp20.000'));
    expect(text, contains('Tol Rp30.000'));
    expect(text.indexOf('BBM'), lessThan(text.indexOf('Uang makan')));
    expect(text.indexOf('Uang makan'), lessThan(text.indexOf('Parkir')));
    expect(text.indexOf('Parkir'), lessThan(text.indexOf('Tol')));
    expect(text, contains('Total pengeluaran Rp750.000'));
    expect(text, contains('Sisa Rp250.000'));
    expect(text, contains('Pembayaran Tagihan Rp50.000'));
  });

  test('manual meal amount round-trips into PDF expenses and office balance',
      () async {
    for (final amount in [0, 100000, 123456]) {
      final manual = report().copyWith(
          uangMakan: amount,
          uangMakanIsManual: true,
          hasGuestAllowance: true,
          guestUangSaku: 200000,
          guestTol: 10000);
      final reopened = Report.fromMap(manual.toMap());
      expect(reopened.uangMakanIsManual, isTrue);
      expect(reopened.copyWith(tripPeriods: []).uangMakan, amount);
      final doc = await ReportPdfBuilder.build(reopened);
      final text = normalizePdfText((await pdfPageText(doc)).join('\n'));
      expect(text, contains('Uang makan Rp${formatNumberId(amount)}'));
      expect(text,
          contains('Total pengeluaran Rp${formatNumberId(650000 + amount)}'));
      expect(text, contains('Sisa Rp${formatNumberId(350000 - amount)}'));
      expect(text, contains('Pembayaran Tagihan Rp50.000'));
      expect(text, contains('Sisa Rp190.000'));
    }
  });

  test('PDF paginates many extras without dropping entries', () async {
    final r = report().copyWith(extras: [
      for (var i = 0; i < 80; i++)
        ExtraExpense(name: 'Item${i.toString().padLeft(3, '0')}', amount: 1000),
    ]);
    final doc = await ReportPdfBuilder.build(r);
    final raw = latin1.decode(await doc.save());
    expect(RegExp(r'/Type\s*/Page\b').allMatches(raw).length, greaterThan(1));
    final content = (await pdfPageText(doc)).join('\n');
    expect(content, contains('Item000'));
    expect(content, contains('Item079'));
    expect(r.extra, 80000);
  });

  test('PDF retains receipts but omits time and kilometer output', () async {
    final logo =
        (await rootBundle.load('assets/logo.png')).buffer.asUint8List();
    final doc = await ReportPdfBuilder.build(report(), attachmentImages: [
      ReportAttachmentImage(bytes: logo),
      ReportAttachmentImage(bytes: logo),
      ReportAttachmentImage(bytes: Uint8List(0)),
    ]);
    final bytes = await doc.save();
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    final pdfPages = doc.document.pdfPageList.pages;
    final attachmentPageContent = <String>[];
    for (final page in pdfPages.skip(1)) {
      for (final contentStream in page.contents) {
        final bytes = (contentStream as dynamic).buf.output() as List<int>;
        attachmentPageContent.add(latin1.decode(bytes));
      }
    }
    final raw = latin1.decode(bytes);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(raw).length, 2);
    final content = (await pdfPageText(doc)).join('\n');
    expect(content, isNot(contains('Awal')));
    expect(content, isNot(contains('Akhir')));
    expect(content, isNot(contains('Jam')));
    expect(content, isNot(contains('08:00')));
    expect(attachmentPageContent, hasLength(1));
    expect(normalizePdfText(content), contains('Lampiran belum dikelompokkan'));
    expect(content, isNot(contains('Struk Pembelian Bensin')));
    expect(content, isNot(contains('Bensin')));
    expect(content, isNot(contains('(1.000)')));
    expect(content, isNot(contains('(1.250)')));
    expect(content, isNot(contains('Jarak')));
    expect(content, isNot(contains('Tempuh')));
    final output = Platform.environment['PDF_TEST_OUTPUT'];
    if (output != null) await File(output).writeAsBytes(bytes);
  });
}
