import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bus_crew/models/bus.dart';
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
        noPolisi: 'AB 7317 BK',
        namaTamu: 'Bpk. Hartono',
        pengemudi: 'Budi',
        kernet: 'Agus',
        kmAwal: 1000,
        kmAkhir: 1250,
        uangSaku: 1000000,
        bbm: 600000,
        extras: [
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
            'JADWAL Berangkat Jumat, 12/06/2026 Kembali Selasa, 16/06/2026'));
    expect(text, contains('BUS Nama Bus HG 2 No. Polisi AB 7317 BK'));
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
    expect(text, contains('Uang Makan 250.000'));
    expect(text, contains('Total Pengeluaran 900.000'));
    expect(
        text,
        contains('Uang Saku Rp 1.000.000 Total Pengeluaran Rp 900.000 '
            'SISA Rp 100.000 Pembayaran tagihan Rp 50.000'));
    expect(RegExp(r'\b50\.000\b').allMatches(text), hasLength(1));
    expect(text, contains('Catatan perjalanan'));
    expect(text, contains('Dibuat oleh, Budi'));
    expect(text, contains('Hal. 1 / 1'));
    expect(text, isNot(contains('KM')));
    expect(text, isNot(contains('Jam')));
    expect(text, isNot(contains('08:00')));
    expect(text, contains('No. Polisi AB 7317 BK'));
    expect(text, contains('Pengemudi Budi'));
    expect(text, contains('Kernet Agus'));
  });

  test('PDF meals and office balance count entered days and exclude gaps',
      () async {
    final report = baseReport().copyWith(tripPeriods: [
      TripPeriod(
          start: DateTime(2026, 6, 12),
          end: DateTime(2026, 6, 13),
          type: TripType.luarKota),
      TripPeriod(
          start: DateTime(2026, 6, 20),
          end: DateTime(2026, 6, 20),
          type: TripType.dalamKota),
    ]);
    final doc = await ReportPdfBuilder.build(report);
    final text = normalizePdfText((await pdfPageText(doc)).join(' '));
    expect(text, contains('Uang Makan 150.000'));
    expect(text, contains('Total Pengeluaran Rp 800.000'));
    expect(text, contains('SISA Rp 200.000'));
    final empty =
        await ReportPdfBuilder.build(report.copyWith(tripPeriods: []));
    expect(normalizePdfText((await pdfPageText(empty)).join(' ')),
        contains('Uang Makan 0'));
  });

  test('PDF omits time and kilometer rows for filled and empty stored values',
      () async {
    for (final report in [
      baseReport(),
      baseReport().copyWith(jamBerangkat: '', kmAwal: 0, kmAkhir: 0)
    ]) {
      final doc = await ReportPdfBuilder.build(report);
      final text = normalizePdfText((await pdfPageText(doc)).single);
      expect(text, isNot(contains('Jam')));
      expect(text, isNot(contains('KM')));
      expect(text, isNot(contains('08:00')));
      expect(text, contains('Kembali Selasa, 16/06/2026 BUS Nama Bus HG 2'));
      expect(text, contains('No. Polisi AB 7317 BK CREW Pengemudi Budi'));
    }
  });

  test('Discova finance stays fixed when the trip guest name changes',
      () async {
    String? firstFinance;
    for (final name in ['Bpk. Hartono', 'Ibu Ratna', '']) {
      final doc = await ReportPdfBuilder.build(baseReport().copyWith(
        namaTamu: name,
        hasGuestAllowance: true,
        guestUangSaku: 100000,
        guestTol: 10000,
        guestPenyeberangan: 20000,
        guestParkir: 5000,
        guestExtras: [ExtraExpense(name: 'Bagasi', amount: 3000)],
        guestCatatan: 'Catatan khusus tamu',
      ));
      final text = normalizePdfText((await pdfPageText(doc)).join(' '));
      final summary = text.indexOf('Ringkasan');
      final discova = text.indexOf('Uang Saku Discova');
      final note = text.indexOf('Catatan perjalanan');

      expect(summary, greaterThanOrEqualTo(0));
      expect(discova, greaterThan(summary));
      expect(note, greaterThan(discova));
      if (name.isEmpty) {
        expect(text, isNot(contains('TAMU')));
      } else {
        expect(text, contains('TAMU Nama $name'));
      }
      final finance = text.substring(discova, note);
      firstFinance ??= finance;
      expect(finance, firstFinance);
      expect(finance, contains('Uang Saku Discova No Keterangan Jumlah'));
      expect(finance, contains('Tol 10.000'));
      expect(finance, contains('Penyeberangan 20.000'));
      expect(finance, contains('Parkir 5.000'));
      expect(finance, contains('Bagasi 3.000'));
      expect(finance, contains('Total Pengeluaran Discova 38.000'));
      expect(finance, contains('Uang Saku Discova Rp 100.000'));
      expect(finance, contains('SISA DISCOVA Rp 62.000'));
      expect(finance, contains('Catatan khusus tamu'));
      expect(finance, isNot(contains('Uang Saku Tamu')));
      expect(finance, isNot(contains('Total Pengeluaran Tamu')));
      expect(finance, isNot(contains('SISA TAMU')));
      if (name.isNotEmpty) {
        expect(finance, isNot(contains(name)));
      }
    }
  });

  test('Discova deficit and zero balance use fixed labels', () async {
    for (final allowance in [1000, 10000]) {
      final doc = await ReportPdfBuilder.build(baseReport().copyWith(
        namaTamu: 'Ibu Ratna',
        hasGuestAllowance: true,
        guestUangSaku: allowance,
        guestTol: 10000,
      ));
      final text = normalizePdfText((await pdfPageText(doc)).join(' '));
      expect(text, contains('TAMU Nama Ibu Ratna'));
      expect(text, contains('Uang Saku Discova No Keterangan Jumlah'));
      expect(text, contains('Total Pengeluaran Discova 10.000'));
      expect(text, contains('Uang Saku Discova ${formatRupiah(allowance)}'));
      expect(
          text,
          contains(allowance == 1000
              ? 'DEFISIT DISCOVA -Rp 9.000'
              : 'SISA DISCOVA Rp 0'));
      expect(text, isNot(contains('DEFISIT TAMU')));
      expect(text, contains('SISA Rp 350.000'));
    }
  });

  test('guest allowance block is hidden unless enabled', () async {
    final doc = await ReportPdfBuilder.build(baseReport().copyWith(
      hasGuestAllowance: false,
      guestUangSaku: 100000,
      guestTol: 10000,
      guestCatatan: 'Catatan khusus tamu',
    ));
    final text = normalizePdfText((await pdfPageText(doc)).join(' '));

    expect(text, isNot(contains('Uang Saku Discova')));
    expect(text, isNot(contains('Total Pengeluaran Discova')));
    expect(text, isNot(contains('SISA DISCOVA')));
    expect(text, isNot(contains('DEFISIT DISCOVA')));
    expect(text, isNot(contains('Catatan khusus tamu')));
    expect(text, contains('TAMU Nama Bpk. Hartono'));
  });

  test('PDF derives each bus name from the stored plate in the fixed catalog',
      () async {
    for (final bus in busCatalog) {
      final doc = await ReportPdfBuilder.build(
        baseReport().copyWith(noPolisi: bus.plate),
      );
      final pages = await pdfPageText(doc);
      expect(pages, hasLength(1));
      final text = normalizePdfText(pages.single);
      expect(
          text, contains('BUS Nama Bus ${bus.name} No. Polisi ${bus.plate}'));
      expect(text, contains('TAMU Nama Bpk. Hartono'));
    }

    final plain =
        await ReportPdfBuilder.build(baseReport().copyWith(namaTamu: ''));
    final plainText = normalizePdfText((await pdfPageText(plain)).single);
    expect(plainText, isNot(contains('TAMU')));
    expect(plainText, contains('BUS Nama Bus HG 2 No. Polisi AB 7317 BK'));
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
    expect(text, contains('DEFISIT ${formatRupiah(r.sisa)}'));
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
    for (final allowance in [500000, 650000]) {
      final r =
          baseReport().copyWith(uangSaku: allowance, pembayaranTagihan: 900000);
      final doc = await ReportPdfBuilder.build(r);
      final text = normalizePdfText((await pdfPageText(doc)).join('\n'));
      expect(text, contains('Total Pengeluaran Rp 650.000'));
      expect(text, contains('Pembayaran tagihan Rp 900.000'));
      expect(text,
          contains(allowance == 500000 ? 'DEFISIT -Rp 150.000' : 'SISA Rp 0'));
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
