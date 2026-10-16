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
  static const photoGap = 8.0;
  static const maxPhotoRowWidth = 515.0;
  static const photosPerRow = 3;
  static const photoLeftIndent = 22.0;
  static const photoSize = 138.0;
  static const photoHeightPortrait = photoSize;
  static const photoHeightLandscape = photoSize;
  static const _moneyWidth = 75.0;
  static const _ink = PdfColor(0.12, 0.12, 0.12);
  static const _muted = PdfColor(0.38, 0.38, 0.38);
  static const _hairline = PdfColor(0.52, 0.52, 0.52);
  static const _danger = PdfColor.fromInt(0xFFB32636);

  static const _body = pw.TextStyle(fontSize: 9.5, color: _ink);
  static final _bold = _body.copyWith(fontWeight: pw.FontWeight.bold);
  static final _heading = _bold.copyWith(fontSize: 10.5);
  static final _small = _body.copyWith(fontSize: 9, color: _muted);

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
          margin: const pw.EdgeInsets.fromLTRB(_margin, 26, _margin, 20),
          // This is a loop-safety bound, not a fixed report page count.
          maxPages: 10000,
          header: (_) => _header(title, logo, report),
          footer: _footer,
          build: (_) => content,
        );
    final hasNotes = report.catatan.trim().isNotEmpty ||
        (report.hasGuestAllowance && report.guestCatatan.trim().isNotEmpty);

    doc.addPage(section('LPJ CREW', [
      _identity(report),
      pw.SizedBox(height: 16),
      _periods(report),
      pw.SizedBox(height: 18),
      _ledger(
        'LPJ Kantor',
        report.uangSaku,
        [
          ('BBM', report.bbm),
          // A manual amount must never imply the automatic daily rate.
          (
            report.uangMakanIsManual
                ? 'Uang Makan'
                : 'Uang Makan · ${report.mealDays} hari × Rp40.000',
            report.uangMakan
          ),
          for (final extra in report.extras) (_extraName(extra), extra.amount),
        ],
        report.totalPengeluaran,
        report.sisa,
      ),
      if (report.hasGuestAllowance) ...[
        pw.SizedBox(height: 18),
        _ledger(
          'LPJ Discova',
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
      if (hasNotes) ...[
        pw.SizedBox(height: 18),
        _rule(),
        pw.SizedBox(height: 8),
        _bulletTitle('Catatan'),
        pw.SizedBox(height: 6),
        if (report.catatan.trim().isNotEmpty) ...[
          _noteCard('Catatan Kantor', report.catatan),
          pw.SizedBox(height: 8),
        ],
        if (report.hasGuestAllowance &&
            report.guestCatatan.trim().isNotEmpty) ...[
          _noteCard('Catatan Discova', report.guestCatatan),
          pw.SizedBox(height: 8),
        ],
      ],
    ]));

    final groups = groupAttachments(report, attachmentImages);
    if (groups.isNotEmpty) {
      final officeGroups =
          groups.where((g) => _isOfficeOwner(g.owner)).toList();
      final discovaGroups =
          groups.where((g) => _isDiscovaOwner(g.owner)).toList();
      final otherGroups = groups
          .where((g) => !_isOfficeOwner(g.owner) && !_isDiscovaOwner(g.owner))
          .toList();

      var photoNumber = 1;
      pw.Widget buildGroup(ReportPhotoGroup group, int index) {
        final widget =
            _photoGroup(group, index, report, startNumber: photoNumber);
        photoNumber += group.images.length;
        return widget;
      }

      doc.addPage(section('Lampiran', [
        if (officeGroups.isNotEmpty) ...[
          _rule(),
          pw.SizedBox(height: 8),
          _bulletTitle('LPJ Kantor'),
          pw.SizedBox(height: 6),
          for (var i = 0; i < officeGroups.length; i++) ...[
            if (i > 0) pw.NewPage(freeSpace: 165),
            buildGroup(officeGroups[i], i),
            pw.SizedBox(height: 8),
          ],
          pw.SizedBox(height: 10),
        ],
        if (discovaGroups.isNotEmpty) ...[
          if (officeGroups.isNotEmpty) pw.NewPage(freeSpace: 190),
          _rule(),
          pw.SizedBox(height: 8),
          _bulletTitle('LPJ Discova'),
          pw.SizedBox(height: 6),
          for (var i = 0; i < discovaGroups.length; i++) ...[
            if (i > 0) pw.NewPage(freeSpace: 165),
            buildGroup(discovaGroups[i], i),
            pw.SizedBox(height: 8),
          ],
          pw.SizedBox(height: 10),
        ],
        if (otherGroups.isNotEmpty) ...[
          if (officeGroups.isNotEmpty || discovaGroups.isNotEmpty)
            pw.NewPage(freeSpace: 190),
          _rule(),
          pw.SizedBox(height: 8),
          _bulletTitle('Lampiran Lainnya'),
          pw.SizedBox(height: 6),
          for (var i = 0; i < otherGroups.length; i++) ...[
            if (i > 0) pw.NewPage(freeSpace: 165),
            buildGroup(otherGroups[i], i),
            pw.SizedBox(height: 8),
          ],
        ],
      ]));
    }
    return doc;
  }

  static pw.Widget _header(String title, Uint8List logo, Report report) {
    final bus = _busName(report.noPolisi);
    final busLabel = bus.isNotEmpty ? bus : report.noPolisi.trim();
    final dateStr =
        DateFormat('dd.MM.yyyy').format(report.tanggalBuat);
    final code = [
      'LPJ',
      if (busLabel.isNotEmpty) busLabel,
      dateStr,
    ].join(' / ');

    final pj = report.namaCrew.trim();

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      child: pw.Column(
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 120,
                height: 33,
                child: logo.isEmpty
                    ? pw.SizedBox()
                    : pw.Image(pw.MemoryImage(logo),
                        alignment: pw.Alignment.topLeft,
                        fit: pw.BoxFit.contain),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(title,
                        style: _bold.copyWith(
                            fontSize: 14, letterSpacing: 0.5)),
                    pw.SizedBox(height: 3),
                    pw.Text(code, style: _body.copyWith(fontSize: 9.5)),
                  ],
                ),
              ),
              pw.SizedBox(
                width: 130,
                child: pw.Align(
                  alignment: pw.Alignment.topRight,
                  child: pw.Text(
                    pj.isEmpty ? '' : 'PJ : $pj',
                    style: _bold.copyWith(fontSize: 12),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          _rule(width: 1.5, color: _ink),
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

  static final _dayDate = DateFormat('EEEE, dd/MM/yyyy', 'id_ID');

  static String _formatDateValue(DateTime? date, String fallback) {
    if (date != null) return _dayDate.format(date);
    final trimmed = fallback.trim();
    if (trimmed.isEmpty) return '-';
    try {
      final parsed = DateFormat('dd/MM/yyyy', 'id_ID').parseStrict(trimmed);
      return _dayDate.format(parsed);
    } catch (_) {
      return trimmed;
    }
  }

  static String spanStartLabel(Report report, List<TripPeriod> periods) {
    final first = TripPeriod.spanStart(periods);
    return _formatDateValue(first, report.hariTglBerangkat);
  }

  static String spanEndLabel(Report report, List<TripPeriod> periods) {
    final last = TripPeriod.spanEnd(periods);
    return _formatDateValue(last, report.hariTglKembali);
  }

  static String _route(TripPeriod period) => [
        period.origin.trim(),
        period.destination.trim()
      ].where((part) => part.isNotEmpty).join(' → ');

  static pw.Widget _identity(Report report) {
    final periods = report.tripPeriods ?? const <TripPeriod>[];
    final bus = _busName(report.noPolisi);
    final busPlate = report.noPolisi.trim();

    String busDisplay;
    if (bus.isNotEmpty && busPlate.isNotEmpty) {
      busDisplay = '$bus ($busPlate)';
    } else if (bus.isNotEmpty) {
      busDisplay = bus;
    } else if (busPlate.isNotEmpty) {
      busDisplay = busPlate;
    } else {
      busDisplay = '-';
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _identityGroup('JADWAL', 170, [
          _pair('Berangkat', spanStartLabel(report, periods)),
          _pair('Kembali', spanEndLabel(report, periods)),
        ]),
        _identityGroup('ARMADA', 95, [
          pw.Text(busDisplay, style: _body),
        ]),
        _identityGroup('CREW', 115, [
          _pair('Pengemudi',
              report.pengemudi.isEmpty ? '-' : report.pengemudi),
          _pair('Kernet', report.kernet.isEmpty ? '-' : report.kernet),
        ]),
        pw.Expanded(
          child: _identityGroup('TAMU', null, [
            _pair('Nama',
                report.namaTamu.trim().isEmpty ? '-' : report.namaTamu.trim()),
            _pair(
              'Pelunasan',
              report.pembayaranTagihan > 0
                  ? _money(report.pembayaranTagihan)
                  : 'Rp0',
            ),
          ], rightPadding: 0),
        ),
      ],
    );
  }

  static pw.Widget _identityGroup(
          String title, double? width, List<pw.Widget> fields,
          {double rightPadding = 12}) =>
      pw.SizedBox(
        width: width,
        child: pw.Padding(
          padding: pw.EdgeInsets.only(right: rightPadding),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title, style: _bold),
              pw.SizedBox(height: 8),
              for (final field in fields) ...[
                field,
                pw.SizedBox(height: 4),
              ],
            ],
          ),
        ),
      );

  static pw.Widget _pair(String label, String value) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: _body),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Text(
              value.trim(),
              style: _body,
              textAlign: pw.TextAlign.right,
            ),
          ),
        ],
      );

  static pw.Widget _bulletTitle(
    String title, {
    int? amount,
    bool twoColumn = false,
  }) =>
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 5.5,
            height: 5.5,
            decoration: const pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              color: _ink,
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Text(title, style: _bold.copyWith(fontSize: 10.5)),
          ),
          if (twoColumn) ...[
            pw.SizedBox(width: _moneyWidth),
            pw.SizedBox(
              width: _moneyWidth,
              child: pw.Text(
                amount == null ? '' : _money(amount),
                style: _bold.copyWith(fontSize: 10.5),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ] else if (amount != null) ...[
            pw.Text(_money(amount), style: _bold.copyWith(fontSize: 10.5)),
          ],
        ],
      );

  static pw.Widget _periods(Report report) {
    final lk = report.luarKotaCount;
    final dk = report.dalamKotaCount;
    final counted = lk != null || dk != null;
    final totalDays = (lk ?? 0) + (dk ?? 0);

    return _rowTable([
      pw.TableRow(repeat: true, children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _rule(),
            pw.SizedBox(height: 8),
            _bulletTitle('Periode'),
            pw.SizedBox(height: 6),
          ],
        ),
      ]),
      for (final period in report.tripPeriods ?? const <TripPeriod>[])
        pw.TableRow(children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 3.5),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(width: 22),
                pw.SizedBox(
                  width: 200,
                  child: pw.Text(
                    '${_dayDate.format(period.start)} — ${_dayDate.format(period.end)}',
                    style: _body,
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(_route(period), style: _body),
                ),
                pw.SizedBox(
                  width: 60,
                  child: pw.Text(
                    '${period.days} Hari',
                    style: _body,
                    textAlign: pw.TextAlign.right,
                  ),
                ),
                pw.SizedBox(
                  width: 75,
                  child: pw.Text(
                    period.type.shortLabel,
                    style: _body,
                    textAlign: pw.TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ]),
      pw.TableRow(children: [
        pw.Column(children: [
          pw.Row(children: [
            pw.Expanded(child: pw.SizedBox()),
            pw.SizedBox(
              width: 135,
              child: _rule(width: 0.75),
            ),
          ]),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 3.5),
            child: pw.Row(children: [
              pw.SizedBox(width: 22),
              pw.Expanded(
                child: pw.Text('Total Periode', style: _body),
              ),
              pw.SizedBox(
                width: 60,
                child: pw.Text(
                  counted ? '$totalDays Hari' : '-',
                  style: _body,
                  textAlign: pw.TextAlign.right,
                ),
              ),
              pw.SizedBox(
                width: 75,
                child: pw.Text(
                  counted ? 'LK ${lk ?? '-'} / DK ${dk ?? '-'}' : '-',
                  style: _body,
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ]),
          ),
        ]),
      ]),
      if (report.tripPeriods == null &&
          !counted &&
          report.tripType != TripType.unspecified)
        pw.TableRow(children: [
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: pw.Row(children: [
              pw.SizedBox(width: 22),
              pw.Expanded(
                child: pw.Text(
                  'Kategori lama: ${report.tripType.label}',
                  style: _small,
                ),
              ),
            ]),
          ),
        ]),
    ]);
  }

  static pw.Widget _moneyRow(
    String title, {
    int? left,
    int? right,
    pw.TextStyle? style,
    PdfColor? rightColor,
    bool indent = false,
  }) {
    final textStyle = style ?? _body;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (indent) pw.SizedBox(width: 22),
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.only(right: 8),
            child: pw.Text(title, style: textStyle),
          ),
        ),
        pw.SizedBox(
          width: _moneyWidth,
          child: pw.Text(
            left == null ? '' : _money(left),
            style: textStyle,
            textAlign: pw.TextAlign.right,
          ),
        ),
        pw.SizedBox(
          width: _moneyWidth,
          child: pw.Text(
            right == null ? '' : _money(right),
            style: textStyle.copyWith(color: rightColor ?? _ink),
            textAlign: pw.TextAlign.right,
          ),
        ),
      ],
    );
  }

  static pw.Widget _ledger(
    String title,
    int received,
    List<(String, int)> expenses,
    int total,
    int balance,
  ) =>
      _rowTable([
        pw.TableRow(repeat: true, children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _rule(),
              pw.SizedBox(height: 8),
              _bulletTitle(title, amount: received, twoColumn: true),
              pw.SizedBox(height: 6),
            ],
          ),
        ]),
        for (final (name, amount) in expenses)
          pw.TableRow(children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3.25),
              child: _moneyRow(name, left: amount, indent: true),
            ),
          ]),
        pw.TableRow(children: [
          pw.Column(children: [
            _partialRuleRow(left: true),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3.25),
              child: _moneyRow('Total Pengeluaran', left: total, indent: true),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3.25),
              child: _moneyRow(
                balance < 0 ? 'Defisit' : 'Sisa',
                right: balance < 0 ? balance.abs() : balance,
                rightColor: balance < 0 ? _danger : _ink,
                indent: true,
              ),
            ),
          ]),
        ]),
      ]);

  static pw.Widget _partialRuleRow({
    bool left = false,
    bool right = false,
    double width = 0.75,
  }) =>
      pw.Row(
        children: [
          pw.Expanded(child: pw.SizedBox()),
          pw.SizedBox(
            width: _moneyWidth,
            child: left ? _rule(width: width) : pw.SizedBox(),
          ),
          pw.SizedBox(
            width: _moneyWidth,
            child: right ? _rule(width: width) : pw.SizedBox(),
          ),
        ],
      );

  static String _money(int value) =>
      formatRupiah(value).replaceAll('Rp ', 'Rp');
  static String _extraName(ExtraExpense extra) =>
      extra.name.trim().isEmpty ? 'Extra lama' : extra.name.trim();

  static pw.Table _rowTable(List<pw.TableRow> rows) =>
      pw.Table(columnWidths: const {0: pw.FlexColumnWidth()}, children: rows);

  static pw.TableRow _tableHeading(String title, {bool rule = true}) =>
      pw.TableRow(repeat: true, children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(title, style: _heading),
          pw.SizedBox(height: 8),
          if (rule) _rule(),
          pw.SizedBox(height: 6),
        ]),
      ]);

  static pw.Widget _rule({double width = 0.75, PdfColor color = _hairline}) =>
      pw.Container(width: double.infinity, height: width, color: color);


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

  static bool _isOfficeOwner(ExpenseOwner? owner) {
    if (owner == null) return false;
    return owner.type == ExpenseType.officeBbm ||
        owner.type == ExpenseType.officeMeal ||
        owner.type == ExpenseType.officeExtra;
  }

  static bool _isDiscovaOwner(ExpenseOwner? owner) {
    if (owner == null) return false;
    return owner.type == ExpenseType.discovaTol ||
        owner.type == ExpenseType.discovaCrossing ||
        owner.type == ExpenseType.discovaParking ||
        owner.type == ExpenseType.discovaExtra;
  }

  static String _expenseItemLabel(Report report, ExpenseOwner? owner) {
    if (owner == null) return 'Lampiran belum dikelompokkan';
    switch (owner.type) {
      case ExpenseType.officeBbm:
        return 'BBM';
      case ExpenseType.officeMeal:
        return 'Uang Makan';
      case ExpenseType.discovaTol:
        return 'Tol';
      case ExpenseType.discovaCrossing:
        return 'Penyeberangan';
      case ExpenseType.discovaParking:
        return 'Parkir';
      case ExpenseType.officeExtra:
      case ExpenseType.discovaExtra:
        final office = owner.type == ExpenseType.officeExtra;
        final extras = office ? report.extras : report.guestExtras;
        final index = extras.indexWhere((extra) => extra.id == owner.extraId);
        final name = index < 0 ? 'Extra lama' : _extraName(extras[index]);
        final duplicate =
            extras.where((extra) => _extraName(extra) == name).length > 1;
        return duplicate ? '$name (${index + 1})' : name;
    }
  }

  static pw.Widget _noteCard(String title, String text) {
    if (text.length > 500) {
      return _notes(title, text);
    }
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: pw.BoxDecoration(
        color: const PdfColor(0.97, 0.97, 0.98),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(
          color: const PdfColor(0.85, 0.85, 0.88),
          width: 0.6,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: _bold.copyWith(fontSize: 10)),
          pw.SizedBox(height: 5),
          pw.Text(
            text.trim(),
            style: _body.copyWith(fontSize: 9.5, lineSpacing: 2.5),
          ),
        ],
      ),
    );
  }

  static double imageAspectRatio(ReportAttachmentImage image) {
    if (image.bytes.isEmpty) return 0.75;
    try {
      final mem = pw.MemoryImage(image.bytes);
      final w = mem.width ?? 0;
      final h = mem.height ?? 0;
      if (w > 0 && h > 0) {
        return w / h;
      }
    } catch (_) {}
    return 0.75;
  }

  static (double width, double height) photoDimensions(
      ReportAttachmentImage image) {
    return (photoSize, photoSize);
  }

  static pw.Widget _buildPhotoWidget(ReportAttachmentImage image,
      [int? number]) {
    final (width, height) = photoDimensions(image);
    final photo = pw.SizedBox(
      width: width,
      height: height,
      child: pw.Image(
        pw.MemoryImage(image.bytes),
        fit: pw.BoxFit.contain,
      ),
    );
    if (number == null) return photo;
    return pw.Stack(
      children: [
        photo,
        pw.Positioned(
          left: 4,
          top: 4,
          child: pw.Container(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
            decoration: const pw.BoxDecoration(
              color: _ink,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(2)),
            ),
            child: pw.Text(
              '$number',
              style: _bold.copyWith(fontSize: 8, color: PdfColors.white),
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _photoGroup(
    ReportPhotoGroup group,
    int index,
    Report report, {
    int startNumber = 1,
  }) {
    final letter = String.fromCharCode(65 + (index % 26));
    final name = _expenseItemLabel(report, group.owner);
    final label = '$letter. $name';
    var currentNumber = startNumber;
    return _rowTable([
      pw.TableRow(repeat: true, children: [
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: photoLeftIndent, bottom: 6),
          child: pw.Text(label, style: _bold.copyWith(fontSize: 10.5)),
        ),
      ]),
      for (final row in group.rows)
        pw.TableRow(children: [
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: photoLeftIndent, bottom: 6),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (var column = 0; column < row.length; column++) ...[
                  if (column > 0) pw.SizedBox(width: photoGap),
                  _buildPhotoWidget(row[column], currentNumber++),
                ],
              ],
            ),
          ),
        ]),
    ]);
  }

  static Uint8List? _cachedLogo;
  static Future<Uint8List> _loadLogo() async {
    if (_cachedLogo != null) return _cachedLogo!;
    try {
      return _cachedLogo = (await rootBundle.load('assets/logo.png'))
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
    if (images.isEmpty) return;

    for (var i = 0; i < images.length; i += ReportPdfBuilder.photosPerRow) {
      final end = (i + ReportPdfBuilder.photosPerRow < images.length)
          ? i + ReportPdfBuilder.photosPerRow
          : images.length;
      yield images.sublist(i, end);
    }
  }
}
