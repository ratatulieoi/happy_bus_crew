import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/bus.dart';
import '../models/report.dart';
import '../models/report_attachment.dart';
import '../utils/format.dart';

/// The approved v3 layout, with row-level pagination rather than a page limit.
class ReportPdfBuilder {
  static const _margin = 40.0;
  static const _moneyWidth = 112.0;
  static const _photoGap = 11.0;
  static const _photoHeight = 78.0;
  static const photosPerRow = 5;
  static const _ink = PdfColor(0.12, 0.12, 0.12);
  static const _muted = PdfColor(0.38, 0.38, 0.38);
  static const _hairline = PdfColor(0.52, 0.52, 0.52);
  static const _danger = PdfColor.fromInt(0xFFB32636);

  static const _body = pw.TextStyle(fontSize: 9.5, color: _ink);
  static final _bold = _body.copyWith(fontWeight: pw.FontWeight.bold);
  static final _heading = _bold.copyWith(fontSize: 10.5);
  static final _small = _body.copyWith(fontSize: 9, color: _muted);
  static final _shortDate = DateFormat('dd MMM yyyy', 'id_ID');

  static Future<pw.Document> build(
    Report report, {
    Uint8List? logoBytes,
    List<ReportAttachmentImage> attachmentImages = const [],
  }) async {
    // Bundled fonts support the route arrow without network font downloads.
    final regular =
        pw.Font.ttf(await rootBundle.load('assets/LiberationSans-Regular.ttf'));
    final bold =
        pw.Font.ttf(await rootBundle.load('assets/LiberationSans-Bold.ttf'));
    final logo = logoBytes ?? await _loadLogo();
    final doc = pw.Document(
      title: 'Laporan Pertanggungjawaban Crew',
      author: report.namaCrew,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    pw.MultiPage section(String title, List<pw.Widget> content) => pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(_margin, 30, _margin, 20),
          // This is a loop-safety bound, not a fixed report page count.
          maxPages: 10000,
          header: (_) => _header(title, logo, report),
          footer: _footer,
          build: (_) => content,
        );

    doc.addPage(section('Laporan Pertanggungjawaban Crew', [
      _identity(report),
      pw.SizedBox(height: 16),
      _periods(report),
      pw.SizedBox(height: 20),
      _ledger(
        'Uang Saku Kantor',
        report.uangSaku,
        [
          ('BBM', report.bbm),
          // A manual amount must never imply the automatic daily rate.
          (
            report.uangMakanIsManual
                ? 'Uang makan'
                : 'Uang makan · ${report.mealDays} hari × Rp50.000',
            report.uangMakan
          ),
          for (final extra in report.extras) (_extraName(extra), extra.amount),
        ],
        report.totalPengeluaran,
        report.sisa,
      ),
      if (report.hasGuestAllowance) ...[
        pw.SizedBox(height: 20),
        _ledger(
          'Uang Saku Discova',
          report.guestUangSaku,
          [
            ('Tol', report.guestTol),
            ('Penyeberangan', report.guestPenyeberangan),
            ('Parkir', report.guestParkir),
            for (final extra in report.guestExtras)
              (_extraName(extra), extra.amount),
          ],
          report.guestTotalPengeluaran,
          report.guestSisa,
        ),
      ],
      if (report.pembayaranTagihan != 0) ...[
        pw.SizedBox(height: 16),
        pw.Container(
          decoration: _border(top: true),
          padding: const pw.EdgeInsets.only(top: 8),
          child: _moneyRow('Pembayaran Tagihan',
              right: report.pembayaranTagihan, style: _heading),
        ),
      ],
    ]));

    final groups = groupAttachments(report, attachmentImages);
    doc.addPage(section('Catatan dan Lampiran', [
      if (report.catatan.trim().isNotEmpty) ...[
        _notes('Catatan Kantor', report.catatan),
        pw.SizedBox(height: 16),
      ],
      if (report.hasGuestAllowance &&
          report.guestCatatan.trim().isNotEmpty) ...[
        _notes('Catatan Discova', report.guestCatatan),
        pw.SizedBox(height: 16),
      ],
      if (groups.isNotEmpty) ...[
        pw.NewPage(freeSpace: 145),
        pw.Text('Lampiran bukti pengeluaran', style: _heading),
        pw.SizedBox(height: 16),
        for (final group in groups) ...[
          pw.NewPage(freeSpace: 113),
          _photos(group),
          pw.SizedBox(height: 16),
        ],
      ],
      pw.NewPage(freeSpace: 90),
      pw.Spacer(),
      _signature(report),
    ]));
    return doc;
  }

  static pw.Widget _header(String title, Uint8List logo, Report report) {
    final bus = _busName(report.noPolisi);
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.SizedBox(
                width: 119,
                height: 33,
                child: logo.isEmpty
                    ? pw.SizedBox()
                    : pw.Image(pw.MemoryImage(logo),
                        alignment: pw.Alignment.topLeft,
                        fit: pw.BoxFit.contain),
              ),
              pw.Spacer(),
              pw.Text(
                [
                  'LPJ',
                  if (bus.isNotEmpty) bus,
                  DateFormat('MM.yyyy').format(report.tanggalBuat)
                ].join(' / '),
                style: _small.copyWith(fontSize: 8.5),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.SizedBox(
            width: double.infinity,
            child: pw.Text(title,
                style: _bold.copyWith(fontSize: 18),
                textAlign: pw.TextAlign.center),
          ),
          pw.SizedBox(height: 10),
          _rule(width: 0.75, color: const PdfColor(0.22, 0.22, 0.22)),
        ],
      ),
    );
  }

  static pw.Widget _footer(pw.Context context) => pw.Column(children: [
        pw.SizedBox(height: 10),
        _rule(color: const PdfColor(0.65, 0.65, 0.65)),
        pw.SizedBox(height: 6),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('${context.pageNumber} / ${context.pagesCount}',
              style: _small.copyWith(fontSize: 8)),
        ),
      ]);

  static String _busName(String plate) {
    for (final bus in busCatalog) {
      if (bus.plate == plate) return bus.name;
    }
    return '';
  }

  static pw.Widget _identity(Report report) {
    final periods = report.tripPeriods ?? const <TripPeriod>[];
    final bus = _busName(report.noPolisi);
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _identityGroup('Jadwal', 146, [
          _pair('Berangkat', spanStartLabel(report, periods), 56),
          _pair('Kembali', spanEndLabel(report, periods), 56),
        ]),
        _identityGroup('Bus', 107, [
          if (bus.isNotEmpty) pw.Text(bus, style: _bold),
          if (report.noPolisi.trim().isNotEmpty)
            pw.Text(report.noPolisi.trim(), style: _body),
        ]),
        _identityGroup('Crew', 157, [
          _pair('Pengemudi', report.pengemudi, 58),
          _pair('Kernet', report.kernet, 58),
        ]),
        if (report.namaTamu.trim().isNotEmpty)
          pw.Expanded(
              child: _identityGroup('Tamu', null, [
            pw.Text(report.namaTamu.trim(), style: _body),
          ])),
      ],
    );
  }

  static pw.Widget _identityGroup(
          String title, double? width, List<pw.Widget> fields) =>
      pw.SizedBox(
        width: width,
        child: pw.Padding(
          padding: const pw.EdgeInsets.only(right: 8),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title, style: _heading),
              pw.SizedBox(height: 10),
              for (final field in fields) ...[
                field,
                pw.SizedBox(height: 6),
              ],
            ],
          ),
        ),
      );

  static pw.Widget _pair(String label, String value, double labelWidth) => value
          .trim()
          .isEmpty
      ? pw.SizedBox()
      : pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: labelWidth, child: pw.Text(label, style: _small)),
          pw.Expanded(child: pw.Text(value.trim(), style: _body)),
        ]);

  static String spanStartLabel(Report report, List<TripPeriod> periods) {
    final first = TripPeriod.spanStart(periods);
    return first == null
        ? report.hariTglBerangkat.trim()
        : _shortDate.format(first);
  }

  static String spanEndLabel(Report report, List<TripPeriod> periods) {
    final last = TripPeriod.spanEnd(periods);
    return last == null
        ? report.hariTglKembali.trim()
        : _shortDate.format(last);
  }

  static String _route(TripPeriod period) => [
        period.origin.trim(),
        period.destination.trim()
      ].where((part) => part.isNotEmpty).join(' → ');

  static pw.Widget _periods(Report report) {
    final lk = report.luarKotaCount;
    final dk = report.dalamKotaCount;
    final counted = lk != null || dk != null;
    return _rowTable([
      _tableHeading('Periode'),
      for (final period in report.tripPeriods ?? const <TripPeriod>[])
        pw.TableRow(children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4.25),
            child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _textColumn(_shortDate.format(period.start), 96),
                  _textColumn(_shortDate.format(period.end), 104),
                  pw.Expanded(
                      child: pw.Text(_route(period),
                          style: _body.copyWith(fontSize: 9.25))),
                  _textColumn('${period.days}', 40, right: true),
                  _textColumn(period.type.shortLabel, 100, right: true),
                ]),
          ),
        ]),
      pw.TableRow(decoration: _border(top: true), children: [
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8, bottom: 2),
          child: pw.Row(children: [
            pw.Expanded(child: pw.Text('Total periode', style: _bold)),
            pw.Text(counted ? '${(lk ?? 0) + (dk ?? 0)} hari' : '-',
                style: _bold),
            pw.SizedBox(
                width: 100,
                child: pw.Text(
                    counted ? 'LK ${lk ?? '-'} / DK ${dk ?? '-'}' : '-',
                    style: _bold,
                    textAlign: pw.TextAlign.right)),
          ]),
        ),
      ]),
      if (report.tripPeriods == null &&
          !counted &&
          report.tripType != TripType.unspecified)
        pw.TableRow(children: [
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: pw.Text('Kategori lama: ${report.tripType.label}',
                style: _small),
          )
        ]),
    ]);
  }

  static pw.Widget _textColumn(String value, double width,
          {bool right = false}) =>
      pw.SizedBox(
          width: width,
          child: pw.Text(value,
              style: _body.copyWith(fontSize: 9.25),
              textAlign: right ? pw.TextAlign.right : pw.TextAlign.left));

  static pw.Widget _ledger(String title, int received,
          List<(String, int)> expenses, int total, int balance) =>
      _rowTable([
        _tableHeading(title, received: received),
        for (final (name, amount) in expenses)
          pw.TableRow(children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3.25),
              child: _moneyRow(name, left: amount),
            )
          ]),
        // Keep the total, separating rule and balance together on overflow.
        pw.TableRow(children: [
          pw.Column(children: [
            pw.SizedBox(height: 4),
            _rule(),
            pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 7),
                child:
                    _moneyRow('Total pengeluaran', left: total, style: _bold)),
            _rule(),
            pw.Padding(
                padding: const pw.EdgeInsets.only(top: 7),
                child: _moneyRow(balance < 0 ? 'Defisit' : 'Sisa',
                    right: balance,
                    style: _bold.copyWith(fontSize: 10),
                    rightColor: balance < 0 ? _danger : _ink)),
          ])
        ]),
      ]);

  static pw.Widget _moneyRow(String title,
      {int? left, int? right, pw.TextStyle? style, PdfColor? rightColor}) {
    final textStyle = style ?? _body;
    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Expanded(
          child: pw.Padding(
              padding: const pw.EdgeInsets.only(right: 8),
              child: pw.Text(title, style: textStyle))),
      pw.SizedBox(
          width: _moneyWidth,
          child: pw.Text(left == null ? '' : _money(left),
              style: textStyle, textAlign: pw.TextAlign.right)),
      pw.SizedBox(
          width: _moneyWidth,
          child: pw.Text(right == null ? '' : _money(right),
              style: textStyle.copyWith(color: rightColor ?? _ink),
              textAlign: pw.TextAlign.right)),
    ]);
  }

  static String _money(int value) =>
      formatRupiah(value).replaceAll('Rp ', 'Rp');
  static String _extraName(ExtraExpense extra) =>
      extra.name.trim().isEmpty ? 'Extra lama' : extra.name.trim();

  static pw.Table _rowTable(List<pw.TableRow> rows) =>
      pw.Table(columnWidths: const {0: pw.FlexColumnWidth()}, children: rows);

  static pw.TableRow _tableHeading(String title,
          {int? received, bool rule = true}) =>
      pw.TableRow(repeat: true, children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          _moneyRow(title, right: received, style: _heading),
          pw.SizedBox(height: 8),
          if (rule) _rule(),
          pw.SizedBox(height: 6),
        ]),
      ]);

  static pw.Widget _rule({double width = 0.45, PdfColor color = _hairline}) =>
      pw.Container(width: double.infinity, height: width, color: color);

  static pw.BoxDecoration _border({required bool top}) => pw.BoxDecoration(
      border: top
          ? const pw.Border(top: pw.BorderSide(width: 0.45, color: _hairline))
          : const pw.Border(
              bottom: pw.BorderSide(width: 0.45, color: _hairline)));

  // Small text rows let arbitrarily long notes continue with their own heading.
  // Splits retain every character and don't shrink the type to fit a page.
  static Iterable<String> _noteChunks(String text) sync* {
    var remaining = text.trim();
    while (remaining.isNotEmpty) {
      // Bound explicit line breaks too: a short list can be taller than a
      // long paragraph. Each row must fit under its repeated note heading.
      final breaks = '\n'.allMatches(remaining).take(16).toList();
      final lineLimit =
          breaks.length == 16 ? breaks.last.end : remaining.length;
      final limit = lineLimit < 600 ? lineLimit : 600;
      if (remaining.length <= limit) break;
      var end = limit;
      if (limit == 600) {
        final wordEnd = remaining.lastIndexOf(RegExp(r'\s'), limit);
        if (wordEnd > 0) end = wordEnd;
      }
      yield remaining.substring(0, end);
      remaining = remaining.substring(end);
    }
    if (remaining.isNotEmpty) yield remaining;
  }

  static pw.Widget _notes(String title, String text) => _rowTable([
        _tableHeading(title, rule: false),
        for (final chunk in _noteChunks(text))
          pw.TableRow(children: [
            pw.Text(chunk, style: _body.copyWith(lineSpacing: 3))
          ]),
      ]);

  /// Group by stable owner, never by a name that can be duplicated or edited.
  /// Disabled Discova receipts and legacy unassigned receipts remain visible.
  static List<ReportPhotoGroup> groupAttachments(
      Report report, List<ReportAttachmentImage> attachments) {
    final byOwner = <ExpenseOwner?, List<ReportAttachmentImage>>{};
    for (final image in attachments) {
      if (image.bytes.isEmpty) continue;
      byOwner.putIfAbsent(image.owner, () => []).add(image);
    }
    final order = [
      const ExpenseOwner(ExpenseType.officeBbm),
      const ExpenseOwner(ExpenseType.officeMeal),
      for (final extra in report.extras)
        ExpenseOwner(ExpenseType.officeExtra, extraId: extra.id),
      const ExpenseOwner(ExpenseType.discovaTol),
      const ExpenseOwner(ExpenseType.discovaCrossing),
      const ExpenseOwner(ExpenseType.discovaParking),
      for (final extra in report.guestExtras)
        ExpenseOwner(ExpenseType.discovaExtra, extraId: extra.id),
      // Retain unmatched owners as well as pre-ownership attachments.
      ...byOwner.keys,
    ];
    final groups = <ReportPhotoGroup>[];
    for (final owner in order) {
      final images = byOwner.remove(owner);
      if (images == null) continue;
      groups.add(ReportPhotoGroup(owner, _photoTitle(report, owner), images));
    }
    return groups;
  }

  static String _photoTitle(Report report, ExpenseOwner? owner) {
    if (owner == null) return 'Lampiran belum dikelompokkan';
    switch (owner.type) {
      case ExpenseType.officeBbm:
        return 'Kantor · BBM';
      case ExpenseType.officeMeal:
        return 'Kantor · Uang makan';
      case ExpenseType.discovaTol:
        return 'Discova · Tol';
      case ExpenseType.discovaCrossing:
        return 'Discova · Penyeberangan';
      case ExpenseType.discovaParking:
        return 'Discova · Parkir';
      case ExpenseType.officeExtra:
      case ExpenseType.discovaExtra:
        final office = owner.type == ExpenseType.officeExtra;
        final extras = office ? report.extras : report.guestExtras;
        final index = extras.indexWhere((extra) => extra.id == owner.extraId);
        final name = index < 0 ? 'Extra lama' : _extraName(extras[index]);
        // Row numbers disambiguate equal names without printing opaque IDs.
        final duplicate =
            extras.where((extra) => _extraName(extra) == name).length > 1;
        return '${office ? 'Kantor' : 'Discova'} · $name'
            '${duplicate ? ' · Extra ${index + 1}' : ''}';
    }
  }

  static pw.Widget _photos(ReportPhotoGroup group) => _rowTable([
        pw.TableRow(repeat: true, children: [
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 12),
            child: pw.Text(group.title, style: _heading),
          )
        ]),
        for (final row in group.rows)
          pw.TableRow(children: [
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    for (var column = 0; column < photosPerRow; column++) ...[
                      if (column > 0) pw.SizedBox(width: _photoGap),
                      pw.Expanded(
                          child: pw.SizedBox(
                        height: _photoHeight,
                        child: pw.Align(
                          alignment: pw.Alignment.topCenter,
                          child: column >= row.length
                              ? pw.SizedBox()
                              : pw.Image(
                                  pw.MemoryImage(row[column].bytes),
                                  fit: pw.BoxFit.contain,
                                ),
                        ),
                      )),
                    ],
                  ]),
            )
          ]),
      ]);

  static pw.Widget _signature(Report report) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.SizedBox(
            width: 176,
            child: pw.Column(children: [
              pw.Text(formatTanggalId(report.tanggalBuat),
                  style: _body, textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 38),
              _rule(color: const PdfColor(0.4, 0.4, 0.4)),
              pw.SizedBox(height: 5),
              if (report.namaCrew.trim().isNotEmpty)
                pw.Text(report.namaCrew.trim(),
                    style: _bold, textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 3),
              pw.Text('Nama pembuat laporan',
                  style: _small.copyWith(fontSize: 8.5)),
            ])),
      );

  static Uint8List? _cachedLogo;
  static Future<Uint8List> _loadLogo() async {
    if (_cachedLogo != null) return _cachedLogo!;
    try {
      return _cachedLogo = (await rootBundle.load('assets/logo-monochrome.png'))
          .buffer
          .asUint8List();
    } catch (_) {
      return Uint8List(0);
    }
  }
}

class ReportPhotoGroup {
  final ExpenseOwner? owner;
  final String title;
  final List<ReportAttachmentImage> images;

  ReportPhotoGroup(this.owner, this.title, List<ReportAttachmentImage> images)
      : images = List.unmodifiable(images);

  Iterable<List<ReportAttachmentImage>> get rows sync* {
    for (var start = 0;
        start < images.length;
        start += ReportPdfBuilder.photosPerRow) {
      final end = start + ReportPdfBuilder.photosPerRow;
      yield images.sublist(start, end > images.length ? images.length : end);
    }
  }
}
