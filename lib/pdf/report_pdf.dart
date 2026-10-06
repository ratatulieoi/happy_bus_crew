import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/report.dart';
import '../utils/format.dart';

/// A4 portrait crew report.
///
/// The page answers the questions a supervisor asks in order: which trip,
/// which bus, who travelled, what was spent, what is left, who signs. It is
/// a plain form: black text on white, thin grey rules under the table rows,
/// small caps labels for the groups, and one red figure when the crew owes
/// money. Nothing is filled, boxed or coloured to decorate.
class ReportPdfBuilder {
  static const _pageFormat = PdfPageFormat.a4;
  static const _marginX = 34.0;
  static const _marginTop = 28.0;
  static const _marginBottom = 26.0;

  // Mirrors lib/ui/app_theme.dart so print matches what the app shows. The
  // page is black, grey and hairlines on white, with a single red figure for
  // a deficit. Grouping comes from the small caps labels and from spacing,
  // never from tinted panels or rules under the headings.
  static const _ink = PdfColor.fromInt(0xFF20252B);
  static const _muted = PdfColor.fromInt(0xFF667078);
  static const _hairline = PdfColor.fromInt(0xFFBFC3C8);
  static const _faint = PdfColor.fromInt(0xFFDDE0E3);
  static const _danger = PdfColor.fromInt(0xFFB32636);

  // One type scale. Only the title, the day-mix numbers and the balance
  // leave the table size, and each of those earns it.
  static final _title =
      pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _ink);
  static final _titleSmall = pw.TextStyle(
      fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _muted);
  static final _section =
      pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _ink);
  static final _groupLabel =
      pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: _muted);
  static final _label = pw.TextStyle(fontSize: 8, color: _muted);
  static final _value =
      pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _ink);
  static final _head =
      pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: _muted);
  static final _table = pw.TextStyle(fontSize: 9, color: _ink);
  static final _tableBold =
      pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink);
  static final _index = pw.TextStyle(fontSize: 8, color: _muted);
  static final _note = pw.TextStyle(fontSize: 8.5, color: _muted);
  static final _money =
      pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _ink);
  static final _balanceLabel = pw.TextStyle(fontSize: 10, color: _muted);
  static final _moneyStrong =
      pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _ink);
  static final _moneyDanger = pw.TextStyle(
      fontSize: 15, fontWeight: pw.FontWeight.bold, color: _danger);
  static final _signatureName =
      pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _ink);
  static final _foot = pw.TextStyle(fontSize: 7, color: _muted);

  /// Builds a [pw.Document] from a [Report].
  /// [logoBytes] overrides the default asset. [attachmentImages] append
  /// one generic Lampiran page per image after the report.
  static Future<pw.Document> build(
    Report r, {
    String? busName,
    Uint8List? logoBytes,
    List<Uint8List> attachmentImages = const [],
  }) async {
    final logo = logoBytes ?? await _loadLogo();

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: _pageFormat,
        margin: const pw.EdgeInsets.fromLTRB(
            _marginX, _marginTop, _marginX, _marginBottom),
        header: (ctx) => _buildHeader(logo, ctx),
        footer: (ctx) => _buildFooter(r, ctx),
        build: (ctx) => [
          _buildIdentity(r, busName ?? ''),
          pw.SizedBox(height: 12),
          _buildSection('Perjalanan'),
          _buildTripTable(r),
          if (_legacyLabel(r) != null)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 5),
              child: pw.Text(_legacyLabel(r)!, style: _note),
            ),
          pw.SizedBox(height: 12),
          _buildSection('Pengeluaran'),
          _buildExpenseTable(r),
          pw.SizedBox(height: 12),
          _buildSection('Ringkasan'),
          _buildBalance(r),
          if (r.hasGuestAllowance) ...[
            pw.SizedBox(height: 12),
            _buildGuestBlock(r),
          ],
          if (r.catatan.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            _buildSection('Catatan'),
            _buildNote(r.catatan),
          ],
          pw.SizedBox(height: 16),
          _buildSignature(r),
        ],
      ),
    );

    for (final imgBytes in attachmentImages) {
      if (imgBytes.isEmpty) continue;
      doc.addPage(
        pw.Page(
          pageFormat: _pageFormat,
          margin: const pw.EdgeInsets.fromLTRB(
              _marginX, _marginTop, _marginX, _marginBottom),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Lampiran', style: _section),
              pw.SizedBox(height: 5),
              _ruleLine(0.8, _ink),
              pw.SizedBox(height: 12),
              pw.Expanded(
                child: pw.Center(
                  child: pw.Image(
                    pw.MemoryImage(imgBytes),
                    fit: pw.BoxFit.contain,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return doc;
  }

  // ---------------------------------------------------------------- header
  static pw.Widget _buildHeader(Uint8List logo, pw.Context ctx) {
    if (ctx.pageNumber > 1) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('LAPORAN PERTANGGUNGJAWABAN CREW', style: _titleSmall),
            pw.SizedBox(height: 4),
            _ruleLine(0.5, _hairline),
          ],
        ),
      );
    }
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              if (logo.isNotEmpty) ...[
                pw.Image(pw.MemoryImage(logo), height: 36),
                pw.SizedBox(width: 10),
              ],
              pw.Expanded(
                child: pw.Text(
                  'LAPORAN PERTANGGUNGJAWABAN CREW',
                  style: _title,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 7),
          _ruleLine(1.1, _ink),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(Report r, pw.Context ctx) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _ruleLine(0.5, _faint),
          pw.SizedBox(height: 5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                r.noPolisi.isEmpty
                    ? 'Laporan pertanggungjawaban crew'
                    : 'Bus ${r.noPolisi}',
                style: _foot,
              ),
              pw.Text(
                ctx.pagesCount > 0
                    ? 'Hal. ${ctx.pageNumber} / ${ctx.pagesCount}'
                    : 'Hal. ${ctx.pageNumber}',
                style: _foot,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSection(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(text, style: _section),
    );
  }

  // --------------------------------------------------------------- identity
  static pw.Widget _buildIdentity(Report r, String busName) {
    final groups = <(String, int, List<(String, String)>)>[
      (
        'Jadwal',
        3,
        [
          ('Berangkat', spanStartLabel(r, r.tripPeriods ?? const [])),
          ('Kembali', spanEndLabel(r, r.tripPeriods ?? const [])),
          ('Jam', r.jamBerangkat),
        ]
      ),
      (
        'Bus',
        3,
        [
          if (busName.trim().isNotEmpty) ('Nama Bus', busName.trim()),
          ('No. Polisi', r.noPolisi),
          ('KM Awal', formatNumberId(r.kmAwal)),
          ('KM Akhir', formatNumberId(r.kmAkhir)),
        ]
      ),
      (
        'Crew',
        3,
        [
          ('Pengemudi', r.pengemudi),
          ('Kernet', r.kernet),
        ]
      ),
      if (r.namaTamu.trim().isNotEmpty)
        ('Tamu', 2, [('Nama', r.namaTamu.trim())]),
    ];

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final (title, flex, fields) in groups)
            _group(title, flex, fields),
        ],
      ),
    );
  }

  static pw.Widget _group(
      String title, int flex, List<(String, String)> fields) {
    return pw.Expanded(
      flex: flex,
      child: pw.Padding(
        padding: const pw.EdgeInsets.only(right: 10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title.toUpperCase(), style: _groupLabel),
            pw.SizedBox(height: 5),
            for (final (label, value) in fields) _pair(label, value),
          ],
        ),
      ),
    );
  }

  static pw.Widget _pair(String label, String value) {
    // The value takes the remaining width and wraps: in a Row a bare Text
    // gets unbounded width, so a long guest name drew past the column edge
    // and was clipped instead of breaking onto the next line.
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: _label),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              value.isEmpty ? '-' : value,
              textAlign: pw.TextAlign.right,
              style: _value,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------- trip
  static String? _legacyLabel(Report r) {
    if (r.tripPeriods != null) return null;
    if (r.hasTripCounts) return null;
    if (r.tripType == TripType.unspecified) return null;
    return 'Kategori lama: ${r.tripType.label}';
  }

  static String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';

  static String _periodLabel(TripPeriod p) {
    if (p.start.year == p.end.year &&
        p.start.month == p.end.month &&
        p.start.day == p.end.day) {
      return _date(p.start);
    }
    return '${_date(p.start)} - ${_date(p.end)}';
  }

  static final _dayMonthYear = DateFormat('EEEE, dd/MM/yyyy', 'id_ID');

  /// Berangkat/Kembali are derived from the rows on save, which keeps the
  /// identity band readable when a report has no periods yet.
  static String spanStartLabel(Report r, List<TripPeriod> periods) {
    final stored = r.hariTglBerangkat.trim();
    if (stored.isNotEmpty) return stored;
    final first = TripPeriod.spanStart(periods);
    return first == null ? '-' : _dayMonthYear.format(first);
  }

  static String spanEndLabel(Report r, List<TripPeriod> periods) {
    final stored = r.hariTglKembali.trim();
    if (stored.isNotEmpty) return stored;
    final last = TripPeriod.spanEnd(periods);
    return last == null ? '-' : _dayMonthYear.format(last);
  }

  static String _totalsLabel(int? lk, int? dk) {
    if (lk == null && dk == null) return '-';
    return 'LK ${lk ?? '-'} / DK ${dk ?? '-'}';
  }

  static String _totalDays(int? lk, int? dk) {
    if (lk == null && dk == null) return '-';
    return '${(lk ?? 0) + (dk ?? 0)}';
  }

  /// Says which state the row list is in, so an empty table is never a
  /// blank that could be mistaken for a rendering failure.
  static String _periodPlaceholder(Report r) {
    if (r.tripPeriods != null) return 'Tidak ada periode';
    if (r.hasTripCounts) return 'Total hari tersimpan';
    return 'Belum diisi';
  }

  static pw.Widget _buildTripTable(Report r) {
    final periods = r.tripPeriods;
    final lk = r.luarKotaCount;
    final dk = r.dalamKotaCount;

    final rows = <pw.TableRow>[
      pw.TableRow(
        repeat: true,
        decoration: _rule(0.8, _hairline, top: true),
        children: [
          _cell('No', style: _head),
          _cell('Periode', style: _head),
          _cell('Kategori', style: _head, align: pw.TextAlign.center),
          _cell('Hari', style: _head, align: pw.TextAlign.right),
        ],
      ),
    ];

    if (periods != null && periods.isNotEmpty) {
      for (int i = 0; i < periods.length; i++) {
        final period = periods[i];
        rows.add(pw.TableRow(
          decoration: _rule(0.5, _faint, top: true),
          children: [
            _cell('${i + 1}', style: _index, align: pw.TextAlign.center),
            _cell(_periodLabel(period)),
            _cell(
              period.type.shortLabel,
              style: _tableBold,
              align: pw.TextAlign.center,
            ),
            _cell('${period.days}',
                style: _tableBold, align: pw.TextAlign.right),
          ],
        ));
      }
    } else {
      rows.add(pw.TableRow(
        decoration: _rule(0.5, _faint, top: true),
        children: [
          _cell(''),
          _cell(_periodPlaceholder(r), style: _note),
          _cell(''),
          _cell(''),
        ],
      ));
    }

    rows.add(pw.TableRow(
      decoration: _rule(0.9, _ink, top: true),
      children: [
        _cell(''),
        _cell('Total', style: _tableBold),
        _cell(_totalsLabel(lk, dk),
            style: _tableBold, align: pw.TextAlign.center),
        _cell(_totalDays(lk, dk), style: _tableBold, align: pw.TextAlign.right),
      ],
    ));

    return pw.Table(
      // Kategori holds 'LK 40 / DK 0' (~53pt in bold 9pt); at 46pt the
      // count wrapped and left a lone digit on the second line.
      columnWidths: const {
        0: pw.FixedColumnWidth(22),
        1: pw.FlexColumnWidth(4),
        2: pw.FixedColumnWidth(72),
        3: pw.FixedColumnWidth(32),
      },
      children: rows,
    );
  }

  // ---------------------------------------------------------------- expense
  static pw.Widget _buildExpenseTable(Report r) {
    return pw.Table(
      columnWidths: const {
        0: pw.FixedColumnWidth(22),
        1: pw.FlexColumnWidth(5),
        2: pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          repeat: true,
          decoration: _rule(0.8, _hairline, top: true),
          children: [
            _cell('No', style: _head),
            _cell('Keterangan', style: _head),
            _cell('Jumlah', style: _head, align: pw.TextAlign.right),
          ],
        ),
        _expenseRow('1', 'BBM', r.bbm),
        _expenseRow('2', 'Uang Makan', r.uangMakan),
        for (int i = 0; i < r.extras.length; i++)
          _expenseRow(
            '${i + 3}',
            r.extras[i].name.isEmpty ? 'Extra lama' : r.extras[i].name,
            r.extras[i].amount,
          ),
        pw.TableRow(
          decoration: _rule(0.9, _ink, top: true),
          children: [
            _cell(''),
            _cell('Total Pengeluaran', style: _tableBold),
            _cell(formatNumberId(r.totalPengeluaran),
                style: _tableBold, align: pw.TextAlign.right),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildGuestBlock(Report r) {
    final guestName = r.namaTamu.trim();
    final guestSisa = r.guestSisa;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildSection(
          guestName.isEmpty ? 'Uang Saku Tamu' : 'Uang Saku Tamu $guestName',
        ),
        pw.Table(
          columnWidths: const {
            0: pw.FixedColumnWidth(22),
            1: pw.FlexColumnWidth(5),
            2: pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(
              repeat: true,
              decoration: _rule(0.8, _hairline, top: true),
              children: [
                _cell('No', style: _head),
                _cell('Keterangan', style: _head),
                _cell('Jumlah', style: _head, align: pw.TextAlign.right),
              ],
            ),
            _expenseRow('1', 'Tol', r.guestTol),
            _expenseRow('2', 'Penyeberangan', r.guestPenyeberangan),
            _expenseRow('3', 'Parkir', r.guestParkir),
            for (int i = 0; i < r.guestExtras.length; i++)
              _expenseRow(
                '${i + 4}',
                r.guestExtras[i].name.trim().isEmpty
                    ? 'Extra lama'
                    : r.guestExtras[i].name.trim(),
                r.guestExtras[i].amount,
              ),
            pw.TableRow(
              decoration: _rule(0.9, _ink, top: true),
              children: [
                _cell(''),
                _cell('Total Pengeluaran Tamu', style: _tableBold),
                _cell(formatNumberId(r.guestTotalPengeluaran),
                    style: _tableBold, align: pw.TextAlign.right),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        _balanceRow('Uang Saku Tamu', formatRupiah(r.guestUangSaku)),
        pw.SizedBox(height: 5),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              guestSisa >= 0 ? 'SISA TAMU' : 'DEFISIT TAMU',
              style: _balanceLabel,
            ),
            pw.Text(
              formatRupiah(guestSisa),
              style: guestSisa >= 0 ? _moneyStrong : _moneyDanger,
            ),
          ],
        ),
        if (r.guestCatatan.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          _buildNote(r.guestCatatan),
        ],
      ],
    );
  }

  static pw.TableRow _expenseRow(String no, String name, int amount) {
    return pw.TableRow(
      decoration: _rule(0.5, _faint, top: true),
      children: [
        _cell(no, style: _index, align: pw.TextAlign.center),
        _cell(name),
        _cell(formatNumberId(amount), align: pw.TextAlign.right),
      ],
    );
  }

  static pw.Widget _cell(
    String text, {
    pw.TextStyle? style,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4.5),
      child: pw.Text(text, textAlign: align, style: style ?? _table),
    );
  }

  /// A hairline used as a table row border. [top] draws it above the row,
  /// which keeps the rule attached to the row that follows it.
  static pw.BoxDecoration _rule(double width, PdfColor color,
      {bool top = false}) {
    final side = pw.BorderSide(color: color, width: width);
    return pw.BoxDecoration(
      border: top ? pw.Border(top: side) : pw.Border(bottom: side),
    );
  }

  static pw.Widget _ruleLine(double width, PdfColor color) =>
      pw.Container(width: double.infinity, height: width, color: color);

  // ---------------------------------------------------------------- balance
  static pw.Widget _buildBalance(Report r) {
    final positif = r.sisa >= 0;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _balanceRow('Uang Saku', formatRupiah(r.uangSaku)),
        _balanceRow('Total Pengeluaran', formatRupiah(r.totalPengeluaran)),
        pw.SizedBox(height: 8),
        _ruleLine(1, _ink),
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(positif ? 'SISA' : 'DEFISIT', style: _balanceLabel),
            pw.Text(
              formatRupiah(r.sisa),
              style: positif ? _moneyStrong : _moneyDanger,
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        _balanceRow(
          'Pembayaran tagihan',
          formatRupiah(r.pembayaranTagihan),
          muted: true,
        ),
      ],
    );
  }

  static pw.Widget _balanceRow(String label, String value,
      {bool muted = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: _balanceLabel),
          pw.Text(value, style: muted ? _note : _money),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------- note
  static pw.Widget _buildNote(String text) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.only(left: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(left: pw.BorderSide(color: _muted, width: 2)),
      ),
      child: pw.Text(text, style: _table),
    );
  }

  // --------------------------------------------------------------- signature
  static pw.Widget _buildSignature(Report r) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _ruleLine(0.5, _faint),
        pw.SizedBox(height: 12),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(formatTanggalId(r.tanggalBuat), style: _note),
                pw.SizedBox(height: 2),
                pw.Text('Dibuat oleh,', style: _label),
                pw.SizedBox(height: 30),
                pw.Text(
                  r.namaCrew.isEmpty
                      ? '( ........................ )'
                      : r.namaCrew,
                  style: _signatureName,
                ),
                pw.SizedBox(height: 2),
                pw.Container(width: 170, height: 0.8, color: _ink),
                pw.SizedBox(height: 2),
                pw.Text('Crew', style: _foot),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- helpers
  /// Cached because the asset is fixed for the life of the process, and
  /// retried once because a desktop hot restart can hand the bundle an
  /// incomplete asset manifest for a moment.
  static Uint8List? _cachedLogo;

  static Future<Uint8List> _loadLogo() async {
    final cached = _cachedLogo;
    if (cached != null) return cached;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      try {
        final bytes =
            (await rootBundle.load('assets/logo.png')).buffer.asUint8List();
        _cachedLogo = bytes;
        return bytes;
      } catch (_) {
        // Try once more, then let the report print without a logo.
      }
    }
    return Uint8List(0);
  }
}
