import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bus_crew/models/report.dart';
import 'package:happy_bus_crew/pdf/report_pdf.dart';
import 'package:happy_bus_crew/utils/format.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pdf/pdf.dart';

import 'support/pdf_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('id_ID'));

  Report baseReport() => Report(
        id: 4,
        tanggalBuat: DateTime(2026, 6, 12),
        hariTglBerangkat: 'Jumat, 12/06/2026',
        jamBerangkat: '08:00',
        hariTglKembali: 'Selasa, 16/06/2026',
        noPolisi: 'B 1001 XX',
        namaTamu: 'Bpk. Hartono',
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
        pembayaranTagihan: 50000,
        namaCrew: 'Budi',
        catatan: 'Catatan perjalanan',
      );

  List<TripPeriod> samplePeriods() => [
        TripPeriod(
            start: DateTime(2026, 6, 12),
            end: DateTime(2026, 6, 14),
            type: TripType.luarKota),
        TripPeriod(
            start: DateTime(2026, 6, 15),
            end: DateTime(2026, 6, 16),
            type: TripType.dalamKota),
      ];

  test('normal report fits on one A4 page with trip first', () async {
    final r = baseReport().copyWith(tripPeriods: samplePeriods());
    final doc = await ReportPdfBuilder.build(r);
    final pages = await pdfPageText(doc);
    expect(pages, hasLength(1));
    final page = doc.document.pdfPageList.pages.single;
    expect(page.pageFormat.width, PdfPageFormat.a4.width);
    expect(page.pageFormat.height, PdfPageFormat.a4.height);

    final text = normalizePdfText(pages.single);
    expect(text, contains('LAPORAN PERTANGGUNGJAWABAN CREW'));
    expect(
        text,
        contains(
            'JADWAL Berangkat Jumat, 12/06/2026 Kembali Selasa, 16/06/2026 '
            'Jam 08:00'));
    expect(text,
        contains('BUS No. Polisi B 1001 XX KM Awal 1.000 KM Akhir 1.250'));
    expect(text, contains('CREW Pengemudi Budi Kernet Agus'));
    expect(text, contains('TAMU Nama Bpk. Hartono'));
    expect(text, contains('No Periode Kategori Hari'));
    expect(text, contains('12/06/2026 - 14/06/2026 LK 3'));
    expect(text, contains('15/06/2026 - 16/06/2026 DK 2'));
    expect(text, contains('Total LK 3 / DK 2 5'));
    expect(text.indexOf('Perjalanan'), lessThan(text.indexOf('Pengeluaran')));
    expect(text.indexOf('Pengeluaran'), lessThan(text.indexOf('Ringkasan')));
    expect(text, contains('Parkir 20.000'));
    expect(text, contains('Tol 30.000'));
    expect(text, contains('Total Pengeluaran 750.000'));
    expect(
        text,
        contains('Uang Saku Rp 1.000.000 Total Pengeluaran Rp 750.000 '
            'SISA Rp 250.000 Pembayaran tagihan Rp 50.000'));
    expect(RegExp(r'\b50\.000\b').allMatches(text), hasLength(1));
    expect(text, contains('Catatan perjalanan'));
    expect(text, contains('Dibuat oleh, Budi'));
    expect(text, contains('Hal. 1 / 1'));
    expect(text, contains('KM Awal 1.000'));
    expect(text, contains('KM Akhir 1.250'));
    expect(text, contains('Jam 08:00'));
    expect(text, contains('No. Polisi B 1001 XX'));
    expect(text, contains('Pengemudi Budi'));
    expect(text, contains('Kernet Agus'));
  });

  test('guest allowance prints after the summary and before trip notes',
      () async {
    final doc = await ReportPdfBuilder.build(baseReport().copyWith(
      hasGuestAllowance: true,
      guestUangSaku: 100000,
      guestTol: 10000,
      guestPenyeberangan: 20000,
      guestParkir: 5000,
      guestExtras: const [ExtraExpense(name: 'Bagasi', amount: 3000)],
      guestCatatan: 'Catatan khusus tamu',
    ));
    final text = normalizePdfText((await pdfPageText(doc)).join(' '));
    final summary = text.indexOf('Ringkasan');
    final guest = text.indexOf('Uang Saku Tamu Bpk. Hartono');
    final note = text.indexOf('Catatan perjalanan');

    expect(summary, greaterThanOrEqualTo(0));
    expect(guest, greaterThan(summary));
    expect(note, greaterThan(guest));
    expect(text, contains('Tol 10.000'));
    expect(text, contains('Penyeberangan 20.000'));
    expect(text, contains('Parkir 5.000'));
    expect(text, contains('Bagasi 3.000'));
    expect(text, contains('Total Pengeluaran Tamu 38.000'));
    expect(text, contains('SISA TAMU Rp 62.000'));
    expect(text, contains('Catatan khusus tamu'));
  });

  test('guest allowance block is hidden unless enabled', () async {
    final doc = await ReportPdfBuilder.build(baseReport().copyWith(
      hasGuestAllowance: false,
      guestUangSaku: 100000,
      guestTol: 10000,
      guestCatatan: 'Catatan khusus tamu',
    ));
    final text = normalizePdfText((await pdfPageText(doc)).join(' '));

    expect(text, isNot(contains('Uang Saku Tamu')));
    expect(text, isNot(contains('Total Pengeluaran Tamu')));
    expect(text, isNot(contains('SISA TAMU')));
    expect(text, isNot(contains('Catatan khusus tamu')));
  });

  test('bus name and guest name join the band only when recorded', () async {
    final named = await ReportPdfBuilder.build(
      baseReport().copyWith(namaTamu: 'Bpk. Hartono'),
      busName: 'Happy Bus 01',
    );
    final text = normalizePdfText((await pdfPageText(named)).single);
    expect(
        text,
        contains(
            'BUS Nama Bus Happy Bus 01 No. Polisi B 1001 XX KM Awal 1.000'));
    expect(text, contains('TAMU Nama Bpk. Hartono'));

    final plain =
        await ReportPdfBuilder.build(baseReport().copyWith(namaTamu: ''));
    final plainText = normalizePdfText((await pdfPageText(plain)).single);
    expect(plainText, isNot(contains('TAMU')));
    expect(plainText, isNot(contains('Nama Bus')));
    expect(plainText, contains('BUS No. Polisi B 1001 XX'));
  });

  test('a long guest name wraps inside its column instead of clipping',
      () async {
    // Regression read: 'Discova Anjay Mabar Haha Hihi' once ran past the
    // TAMU column edge, where the PDF renderer cut it off mid-word.
    final doc = await ReportPdfBuilder.build(baseReport().copyWith(
      namaTamu: 'Discova Anjay Mabar Haha Hihi',
    ));
    final pages = await pdfPageText(doc);
    expect(pages, hasLength(1));
    final text = normalizePdfText(pages.single);
    expect(text, contains('TAMU Nama Discova Anjay Mabar Haha Hihi'));
  });

  test('trip totals stay on one unbroken line for big day counts', () async {
    // Regression read: with LK 40 the fixed Kategori column broke the label
    // and left a lone '0' hanging on the second line.
    final doc = await ReportPdfBuilder.build(
      baseReport().copyWith(luarKotaCount: 40, dalamKotaCount: 0),
    );
    final pages = await pdfPageText(doc);
    final text = normalizePdfText(pages.join('\n'));
    expect(text, contains('Total LK 40 / DK 0 40'));
  });

  test('title and report survive a missing logo', () async {
    final doc =
        await ReportPdfBuilder.build(baseReport(), logoBytes: Uint8List(0));
    final pages = await pdfPageText(doc);
    expect(pages, hasLength(1));
    expect(normalizePdfText(pages.single),
        contains('LAPORAN PERTANGGUNGJAWABAN CREW'));
  });

  test('long tables repeat headers and retain every row before attachments',
      () async {
    final periods = [
      for (var i = 0; i < 40; i++)
        TripPeriod(
            start: DateTime(2026, 6, 12 + i),
            end: DateTime(2026, 6, 12 + i),
            type: TripType.luarKota),
    ];
    final r = baseReport().copyWith(
      hariTglKembali: 'Selasa, 21/07/2026',
      tripPeriods: periods,
      extras: [
        for (var i = 0; i < 60; i++)
          ExtraExpense(
              name: 'Extra${i.toString().padLeft(3, '0')}', amount: 1000),
      ],
      catatan: '',
    );
    final logo =
        (await rootBundle.load('assets/logo.png')).buffer.asUint8List();
    final doc = await ReportPdfBuilder.build(r, attachmentImages: [logo]);
    final pages = await pdfPageText(doc);
    expect(pages.length, greaterThan(2));
    expect(normalizePdfText(pages.last).trim(), 'Lampiran');
    final reportPages = pages.take(pages.length - 1).toList();
    final text = normalizePdfText(reportPages.join('\n'));
    expect('Periode'.allMatches(text).length, greaterThanOrEqualTo(2));
    expect('Keterangan'.allMatches(text).length, greaterThanOrEqualTo(2));
    for (final page in reportPages) {
      final normalized = normalizePdfText(page);
      if (normalized.contains(RegExp(r'Extra\d{3}'))) {
        expect(normalized, contains('Keterangan'));
      }
      if (normalized.contains(RegExp(r'\d{2}/\d{2}/2026 LK 1'))) {
        expect(normalized, contains('No Periode Kategori Hari'));
      }
    }
    for (var i = 0; i < 60; i++) {
      expect('Extra${i.toString().padLeft(3, '0')}'.allMatches(text),
          hasLength(1));
    }
    for (final period in periods) {
      final date = '${period.start.day.toString().padLeft(2, '0')}/'
          '${period.start.month.toString().padLeft(2, '0')}/2026';
      expect('$date LK 1'.allMatches(text), hasLength(1));
    }
    expect(text, contains('LK 40 / DK 0 40'));
    expect(text, isNot(contains('Tidak ada periode')));
    expect(text,
        contains('Total Pengeluaran ${formatNumberId(r.totalPengeluaran)}'));
    expect(text, contains('SISA ${formatRupiah(r.sisa)}'));
    expect(text,
        contains('Pembayaran tagihan ${formatRupiah(r.pembayaranTagihan)}'));
    expect(normalizePdfText(reportPages.last), contains('Dibuat oleh, Budi'));
  });

  test('legacy stored counts show without invented period dates', () async {
    final doc = await ReportPdfBuilder.build(
        baseReport().copyWith(luarKotaCount: 3, dalamKotaCount: 5));
    final pages = await pdfPageText(doc);
    final text = normalizePdfText(pages.join('\n'));
    expect(text, contains('LK 3 / DK 5'));
    expect(text, isNot(contains('Kategori lama')));
    // Only the departure/return fields carry numeric dates.
    expect(RegExp(r'\d{2}/\d{2}/\d{4}').allMatches(text), hasLength(2));
  });

  test('legacy category and explicitly cleared periods stay distinct',
      () async {
    final legacy = baseReport().copyWith(tripType: TripType.luarKota);
    for (final report in [legacy, legacy.copyWith(tripPeriods: [])]) {
      final doc = await ReportPdfBuilder.build(report);
      final pages = await pdfPageText(doc);
      final text = normalizePdfText(pages.join('\n'));
      if (report.tripPeriods == null) {
        expect(text, contains('Kategori lama: Luar Kota'));
      } else {
        expect(text, isNot(contains('Kategori lama')));
      }
      expect(text, contains('Total - -'));
      expect(RegExp(r'\d{2}/\d{2}/\d{4}').allMatches(text), hasLength(2));
    }
  });

  test('deficit and zero balance exclude payments from expenses', () async {
    for (final allowance in [500000, 750000]) {
      final r =
          baseReport().copyWith(uangSaku: allowance, pembayaranTagihan: 900000);
      final doc = await ReportPdfBuilder.build(r);
      final text = normalizePdfText((await pdfPageText(doc)).join('\n'));
      expect(text, contains('Total Pengeluaran Rp 750.000'));
      expect(text, contains('Pembayaran tagihan Rp 900.000'));
      expect(text,
          contains(allowance == 500000 ? 'DEFISIT -Rp 250.000' : 'SISA Rp 0'));
    }
  });

  test('attachments follow the report as generic Lampiran pages', () async {
    final logo =
        (await rootBundle.load('assets/logo.png')).buffer.asUint8List();
    final doc = await ReportPdfBuilder.build(baseReport(),
        attachmentImages: [logo, Uint8List(0), logo]);
    final pages = await pdfPageText(doc);
    expect(pages, hasLength(3));
    for (final page in pages.skip(1)) {
      expect(normalizePdfText(page).trim(), 'Lampiran');
    }
    final report = normalizePdfText(pages.first);
    expect(report, contains('Total Pengeluaran'));
    expect(report, contains('SISA'));
    expect(report, isNot(contains('Bensin')));
  });
}
