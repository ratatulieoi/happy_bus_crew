import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bus_crew/models/bus.dart';
import 'package:happy_bus_crew/models/report.dart';
import 'package:happy_bus_crew/models/report_attachment.dart';
import 'package:happy_bus_crew/pdf/report_pdf.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pdf/pdf.dart';

import 'support/pdf_text.dart';
import 'support/pdf_geometry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('id_ID'));

  Report report() => Report.fromMap({
        'id': 4,
        'tanggal_buat': '2026-10-12T00:00:00',
        'hari_tgl_berangkat': 'older stored date',
        'hari_tgl_kembali': 'older stored return',
        'jam_berangkat': '08:00',
        'km_awal': 12345,
        'km_akhir': 98765,
        'no_polisi': 'AB 7317 BK',
        'nama_tamu': 'Dewi Lestari',
        'pengemudi': 'Budi Santoso',
        'kernet': 'Agus Prasetyo',
        'nama_crew': 'Rani Wulandari',
      }).copyWith(
        tripPeriods: [
          TripPeriod(
              start: DateTime(2026, 10, 7),
              end: DateTime(2026, 10, 9),
              type: TripType.luarKota,
              origin: 'Malang',
              destination: 'Surabaya'),
          TripPeriod(
              start: DateTime(2026, 10, 1),
              end: DateTime(2026, 10, 2),
              type: TripType.dalamKota,
              destination: 'Sleman'),
          TripPeriod(
              start: DateTime(2026, 10, 3),
              end: DateTime(2026, 10, 4),
              type: TripType.dalamKota,
              origin: 'Yogyakarta'),
          TripPeriod(
              start: DateTime(2026, 10, 10),
              end: DateTime(2026, 10, 11),
              type: TripType.luarKota),
        ],
        uangSaku: 3000000,
        bbm: 1800000,
        extras: [
          ExtraExpense(id: 'wash', name: 'Cuci bus', amount: 75000),
          ExtraExpense(id: 'water', name: 'Air mineral', amount: 60000),
          ExtraExpense(
              id: 'clean', name: 'Perlengkapan kebersihan', amount: 40000),
        ],
        hasGuestAllowance: true,
        guestUangSaku: 2000000,
        guestTol: 750000,
        guestPenyeberangan: 650000,
        guestParkir: 200000,
        guestExtras: [
          ExtraExpense(id: 'ticket', name: 'Retribusi wisata', amount: 125000),
          ExtraExpense(id: 'permit', name: 'Izin masuk kawasan', amount: 75000),
        ],
        pembayaranTagihan: 12000000,
        catatan: 'Jeda tanggal 5 dan 6 tidak dihitung.',
        guestCatatan: 'Izin masuk kawasan sudah dibayar.',
      );

  Future<Uint8List> image() async =>
      (await rootBundle.load('assets/logo.png')).buffer.asUint8List();

  test('v3 uses real identities, routes, totals and two A4 sections', () async {
    final doc = await ReportPdfBuilder.build(report());
    final pages = (await pdfPageText(doc)).map(normalizePdfText).toList();
    expect(pages, hasLength(2));
    for (final page in doc.document.pdfPageList.pages) {
      expect(page.pageFormat.width, PdfPageFormat.a4.width);
      expect(page.pageFormat.height, PdfPageFormat.a4.height);
    }
    final finance = pages.first;
    expect(finance, contains('Laporan Pertanggungjawaban Crew'));
    expect(
        finance, contains('Jadwal Berangkat 01 Okt 2026 Kembali 11 Okt 2026'));
    expect(finance, contains('Bus HG 2 AB 7317 BK'));
    expect(
        finance, contains('Crew Pengemudi Budi Santoso Kernet Agus Prasetyo'));
    expect(finance, contains('Tamu Dewi Lestari'));
    expect(finance, contains('07 Okt 2026 09 Okt 2026 Malang → Surabaya 3 LK'));
    expect(finance, contains('01 Okt 2026 02 Okt 2026 Sleman 2 DK'));
    expect(finance, contains('03 Okt 2026 04 Okt 2026 Yogyakarta 2 DK'));
    expect(finance, contains('10 Okt 2026 11 Okt 2026 2 LK'));
    expect(finance, contains('Total periode 9 hari LK 5 / DK 4'));
    expect(finance, contains('Uang Saku Kantor Rp3.000.000 BBM Rp1.800.000'));
    expect(finance, contains('Uang makan · 9 hari × Rp50.000 Rp450.000'));
    expect(finance, contains('Cuci bus Rp75.000 Air mineral Rp60.000'));
    expect(finance, contains('Total pengeluaran Rp2.425.000 Sisa Rp575.000'));
    expect(finance, contains('Uang Saku Discova Rp2.000.000 Tol Rp750.000'));
    expect(finance, contains('Total pengeluaran Rp1.800.000 Sisa Rp200.000'));
    expect(finance, contains('Pembayaran Tagihan Rp12.000.000'));
    expect('Pembayaran Tagihan'.allMatches(pages.join()), hasLength(1));
    expect(pages.last, contains('Catatan dan Lampiran'));
    expect(pages.last,
        contains('Catatan Kantor Jeda tanggal 5 dan 6 tidak dihitung.'));
    expect(pages.last,
        contains('Catatan Discova Izin masuk kawasan sudah dibayar.'));
    expect(pages.last,
        contains('Senin, 12 Oktober 2026 Rani Wulandari Nama pembuat laporan'));
    expect(pages.first, isNot(contains('Rani Wulandari')));
    for (final removed in [
      'Diterima',
      'Keterangan',
      'Kategori Hari',
      'No Periode',
      'Jam',
      'KM',
      '08:00',
      '12345',
      '98765',
      'Total tagihan',
      'Sisa tagihan',
      'Lunas',
      'ilustratif',
      'prototype'
    ]) {
      expect(pages.join(), isNot(contains(removed)));
    }
  });

  test('source geometry matches v3 title, columns, rules and signature',
      () async {
    final doc = await ReportPdfBuilder.build(report());
    final pages = await pdfGeometry(doc);
    final finance = pages.first;
    final title = finance.text.where((word) => word.size == 18).toList();
    final titleLeft = title.first.x;
    final titleRight = title.last.x + title.last.width;
    expect(
        (titleLeft + titleRight) / 2, closeTo(PdfPageFormat.a4.width / 2, 0.1));
    expect(PdfPageFormat.a4.height - title.first.y, closeTo(91, 1));
    for (final amount in ['Rp1.800.000', 'Rp450.000', 'Rp2.425.000']) {
      final word = finance.text.firstWhere((word) => word.value == amount);
      expect(
          word.x + word.width, closeTo(PdfPageFormat.a4.width - 40 - 112, 0.1));
    }
    for (final amount in ['Rp3.000.000', 'Rp575.000', 'Rp12.000.000']) {
      final word = finance.text.firstWhere((word) => word.value == amount);
      expect(word.x + word.width, closeTo(PdfPageFormat.a4.width - 40, 0.1));
    }
    final expense = finance.text.firstWhere((word) => word.value == 'Rp40.000');
    final total =
        finance.text.firstWhere((word) => word.value == 'Rp2.425.000');
    final balance =
        finance.text.firstWhere((word) => word.value == 'Rp575.000');
    expect(finance.rules.any((rule) => rule.y > total.y && rule.y < expense.y),
        isTrue);
    expect(finance.rules.any((rule) => rule.y > balance.y && rule.y < total.y),
        isTrue);
    final payment =
        finance.text.firstWhere((word) => word.value == 'Rp12.000.000');
    expect(
        finance.rules
            .any((rule) => rule.y > payment.y && rule.y < payment.y + 20),
        isTrue);
    final signature =
        pages.last.text.firstWhere((word) => word.value == 'Rani');
    expect(signature.x, greaterThan(PdfPageFormat.a4.width / 2));
    expect(signature.y, lessThan(90));
  });

  test('manual meals, zero and deficit preserve finance and single payment',
      () async {
    for (final allowance in [100000, 1943456]) {
      final r = report().copyWith(
          uangSaku: allowance,
          uangMakan: 123456,
          uangMakanIsManual: true,
          extras: [ExtraExpense(name: 'Parkir', amount: 20000)],
          guestUangSaku: 1000,
          guestTol: 10000,
          guestPenyeberangan: 0,
          guestParkir: 0,
          guestExtras: [],
          pembayaranTagihan: 9999999);
      final doc = await ReportPdfBuilder.build(r);
      final text = normalizePdfText((await pdfPageText(doc)).join());
      expect(text, contains('Uang makan Rp123.456'));
      expect(text, isNot(contains('× Rp50.000')));
      expect(text, contains('Total pengeluaran Rp1.943.456'));
      expect(text,
          contains(allowance == 100000 ? 'Defisit -Rp1.843.456' : 'Sisa Rp0'));
      expect(text, contains('Defisit -Rp9.000'));
      expect(text, contains('Pembayaran Tagihan Rp9.999.999'));
      final streams = doc.document.pdfPageList.pages
          .expand((p) => p.contents)
          .map((s) => latin1.decode((s as dynamic).buf.output() as List<int>))
          .join();
      expect(streams, contains('0.70196 0.14902 0.21176 rg'));
    }
  });

  test('empty optional data has no invented identities, route or note groups',
      () async {
    final doc = await ReportPdfBuilder.build(
        Report.fromMap({
          'tanggal_buat': '2026-10-12T00:00:00',
          'nama_crew': 'Penulis',
        }),
        logoBytes: Uint8List(0));
    final pages = (await pdfPageText(doc)).map(normalizePdfText).toList();
    expect(pages, hasLength(2));
    expect(pages.first, contains('Total periode - -'));
    for (final omitted in [
      'Pengemudi',
      'Kernet',
      'Berangkat',
      'Kembali',
      'Tamu',
      'Pembayaran Tagihan',
      'Discova',
      '→'
    ]) {
      expect(pages.first, isNot(contains(omitted)));
    }
    for (final omitted in [
      'Catatan Kantor',
      'Catatan Discova',
      'Lampiran bukti'
    ]) {
      expect(pages.last, isNot(contains(omitted)));
    }
    expect(pages.last, contains('Penulis Nama pembuat laporan'));
  });

  test('bus names use the catalog and long guest identities wrap', () async {
    for (final bus in busCatalog) {
      final doc = await ReportPdfBuilder.build(report().copyWith(
        noPolisi: bus.plate,
        namaTamu: 'Discova Anjay Mabar Haha Hihi',
      ));
      final text = normalizePdfText((await pdfPageText(doc)).first);
      expect(text, contains('Bus ${bus.name} ${bus.plate}'));
      expect(text, contains('Tamu Discova Anjay Mabar Haha Hihi'));
    }
  });

  test('legacy counts/category remain distinct from cleared periods', () async {
    for (final r in [
      Report.fromMap({'luar_kota_count': 40, 'dalam_kota_count': 0}),
      Report.fromMap({'trip_type': 'luar_kota'}),
      Report.fromMap({'trip_type': 'luar_kota', 'trip_periods': '[]'}),
    ]) {
      final text = normalizePdfText(
          (await pdfPageText(await ReportPdfBuilder.build(r))).first);
      if (r.hasTripCounts) {
        expect(text, contains('Total periode 40 hari LK 40 / DK 0'));
      } else {
        expect(text, contains('Total periode - -'));
        expect(text.contains('Kategori lama'), r.tripPeriods == null);
      }
      expect(text, isNot(contains('→')));
    }
  });

  test('disabled Discova hides its finance/notes but retains owned receipts',
      () async {
    final bytes = await image();
    final r = report().copyWith(hasGuestAllowance: false);
    final doc = await ReportPdfBuilder.build(r, attachmentImages: [
      ReportAttachmentImage(
          bytes: bytes, owner: const ExpenseOwner(ExpenseType.discovaTol)),
      ReportAttachmentImage(bytes: bytes),
    ]);
    final pages = (await pdfPageText(doc)).map(normalizePdfText).toList();
    expect(pages.first, isNot(contains('Uang Saku Discova')));
    expect(pages.last, isNot(contains('Catatan Discova')));
    expect(pages.last, isNot(contains(r.guestCatatan)));
    expect(pages.last, contains('Discova · Tol'));
    expect(pages.last, contains('Lampiran belum dikelompokkan'));
  });

  test('stable extra IDs separate duplicate names and retain unknown owners',
      () async {
    final bytes = await image();
    final r = report().copyWith(extras: [
      ExtraExpense(id: 'a', name: 'Tol', amount: 1000),
      ExtraExpense(id: 'b', name: 'Tol', amount: 2000),
    ]);
    final attachments = [
      for (final id in ['b', 'a', 'gone'])
        ReportAttachmentImage(
            bytes: bytes,
            owner: ExpenseOwner(ExpenseType.officeExtra, extraId: id)),
      ReportAttachmentImage(bytes: bytes),
      ReportAttachmentImage(bytes: Uint8List(0)),
    ];
    final groups = ReportPdfBuilder.groupAttachments(r, attachments);
    expect(groups.map((g) => g.owner?.extraId), ['a', 'b', 'gone', null]);
    expect(groups.map((g) => g.title), [
      'Kantor · Tol · Extra 1',
      'Kantor · Tol · Extra 2',
      'Kantor · Extra lama',
      'Lampiran belum dikelompokkan'
    ]);
    expect(groups.first.images.single, same(attachments[1]));
    final text = normalizePdfText((await pdfPageText(
            await ReportPdfBuilder.build(r, attachmentImages: attachments)))
        .join());
    for (final group in groups) {
      expect(text, contains(group.title));
    }
  });

  test(
      'photo rows have five original images with complete overflow and context',
      () async {
    final bytes = await image();
    final attachments = [
      for (var i = 0; i < 83; i++)
        ReportAttachmentImage(
            bytes: bytes, owner: const ExpenseOwner(ExpenseType.officeBbm))
    ];
    final r = report().copyWith(catatan: '', guestCatatan: '');
    final group = ReportPdfBuilder.groupAttachments(r, attachments).single;
    expect(group.rows.map((row) => row.length), [...List.filled(16, 5), 3]);
    expect(group.rows.expand((row) => row), orderedEquals(attachments));
    expect(
        group.images.every((photo) => identical(photo.bytes, bytes)), isTrue);
    final doc = await ReportPdfBuilder.build(r,
        attachmentImages: attachments, logoBytes: Uint8List(0));
    final pages = (await pdfPageText(doc)).map(normalizePdfText).toList();
    expect(pages.length, greaterThan(2));
    var images = 0;
    for (var i = 1; i < pages.length; i++) {
      final streams = doc.document.pdfPageList.pages[i].contents
          .map((s) => latin1.decode((s as dynamic).buf.output() as List<int>))
          .join();
      final count = RegExp(r'/I\w+\s+Do').allMatches(streams).length;
      images += count;
      if (count > 0) expect(pages[i], contains('Kantor · BBM'));
      expect(pages[i], contains('Catatan dan Lampiran'));
    }
    expect(images, 83);
    final geometry = await pdfGeometry(doc);
    final source = ByteData.sublistView(bytes);
    final aspect = source.getUint32(16) / source.getUint32(20);
    final width = (PdfPageFormat.a4.width - 80 - 4 * 11) / 5;
    for (final page in geometry.skip(1)) {
      final rows = <String, List<double>>{};
      for (final image in page.images) {
        expect(image.width / image.height, closeTo(aspect, 0.001));
        expect(image.width, closeTo(width, 0.01));
        expect(image.y, greaterThanOrEqualTo(40));
        expect(image.y + image.height, lessThan(PdfPageFormat.a4.height - 110));
        rows.putIfAbsent(image.y.toStringAsFixed(2), () => []).add(image.x);
      }
      for (final row in rows.values) {
        expect(row.length, lessThanOrEqualTo(5));
        for (var i = 0; i < row.length; i++) {
          expect(row[i], closeTo(40 + i * (width + 11), 0.01));
        }
      }
    }
    expect(pages.last, contains('Rani Wulandari'));
  });

  test('newline-heavy notes continue under the correct group heading',
      () async {
    final notes =
        List.generate(240, (i) => 'Line${i.toString().padLeft(3, '0')}')
            .join('\n');
    final pages = (await pdfPageText(await ReportPdfBuilder.build(
            report().copyWith(catatan: notes, guestCatatan: ''))))
        .map(normalizePdfText)
        .toList();
    expect(pages.length, greaterThan(3));
    final text = pages.join(' ');
    for (var i = 0; i < 240; i++) {
      expect(
          'Line${i.toString().padLeft(3, '0')}'.allMatches(text), hasLength(1));
    }
    for (final page
        in pages.where((page) => page.contains(RegExp(r'Line\d')))) {
      expect(page, contains('Catatan Kantor'));
    }
    expect(pages.last, contains('Nama pembuat laporan'));
  });

  test('many periods, extras and long notes paginate without missing text',
      () async {
    final r = report().copyWith(
      tripPeriods: [
        for (var i = 0; i < 80; i++)
          TripPeriod(
              start: DateTime(2026, 1, i + 1),
              end: DateTime(2026, 1, i + 1),
              type: TripType.luarKota,
              origin: 'Origin$i',
              destination: 'Destination$i')
      ],
      extras: [
        for (var i = 0; i < 140; i++)
          ExtraExpense(
              name: 'Office${i.toString().padLeft(3, '0')}', amount: 1000)
      ],
      guestExtras: [
        for (var i = 0; i < 90; i++)
          ExtraExpense(
              name: 'Guest${i.toString().padLeft(3, '0')}', amount: 1000)
      ],
      catatan: List.generate(1600, (i) => 'Note${i.toString().padLeft(4, '0')}')
          .join(' '),
    );
    final pages = (await pdfPageText(await ReportPdfBuilder.build(r)))
        .map(normalizePdfText)
        .toList();
    expect(pages.length, greaterThan(6));
    final text = pages.join(' ');
    for (var i = 0; i < 80; i++) {
      expect('Origin$i → Destination$i '.allMatches(text), hasLength(1));
    }
    for (var i = 0; i < 140; i++) {
      expect('Office${i.toString().padLeft(3, '0')}'.allMatches(text),
          hasLength(1));
    }
    for (var i = 0; i < 90; i++) {
      expect('Guest${i.toString().padLeft(3, '0')}'.allMatches(text),
          hasLength(1));
    }
    for (var i = 0; i < 1600; i++) {
      expect(
          'Note${i.toString().padLeft(4, '0')}'.allMatches(text), hasLength(1));
    }
    for (final page in pages) {
      if (page.contains(RegExp(r'Origin\d'))) expect(page, contains('Periode'));
      if (page.contains(RegExp(r'Office\d'))) {
        expect(page, contains('Uang Saku Kantor'));
      }
      if (page.contains(RegExp(r'Guest\d'))) {
        expect(page, contains('Uang Saku Discova'));
      }
      if (page.contains(RegExp(r'Note\d'))) {
        expect(page, contains('Catatan Kantor'));
      }
      expect(page, isNot(contains('Keterangan')));
    }
    expect(text, contains('Total periode 80 hari LK 80 / DK 0'));
    expect('Pembayaran Tagihan'.allMatches(text), hasLength(1));
    expect(pages.last, contains('Rani Wulandari'));
  });
}
