import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/report.dart';
import '../utils/format.dart';

/// Membangun dokumen PDF A4 portrait yang mereproduksi tampilan
/// "Laporan Pertanggungjawaban Crew — Happy Bus" sesuai contoh.
class ReportPdfBuilder {
  static const _pageFormat = PdfPageFormat.a4;

  // Warna tema (mendekati dokumen asli: teks hitam, header tebal).
  static const _black = PdfColor(0, 0, 0);
  static const _gray = PdfColor(0.4, 0.4, 0.4);
  static const _lightGray = PdfColor(0.92, 0.92, 0.92);
  static const _line = PdfColor(0.7, 0.7, 0.7);

  /// Membuat [pw.Document] dari sebuah [Report].
  /// [logoBytes] opsional; bila null akan memuat aset default.
  static Future<pw.Document> build(Report r, {Uint8List? logoBytes}) async {
    final logo = logoBytes ?? await _loadLogo();

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: _pageFormat,
        margin: const pw.EdgeInsets.all(40),
        header: (ctx) => _buildHeader(logo),
        build: (ctx) => [
          _buildTitle(),
          pw.SizedBox(height: 12),
          _buildHeaderInfo(r),
          pw.SizedBox(height: 14),
          _buildSectionTitle('Rincian Keuangan'),
          _buildFinanceTable(r),
          pw.SizedBox(height: 12),
          _buildSummary(r),
          pw.SizedBox(height: 24),
          _buildSignature(r),
        ],
      ),
    );

    return doc;
  }

  // ---------------------------------------------------------------- header
  static pw.Widget _buildHeader(Uint8List logo) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (logo.isNotEmpty)
          pw.Image(pw.MemoryImage(logo), width: 46, height: 46),
        pw.SizedBox(width: 10),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'HAPPY BUS',
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold, color: _black),
            ),
            pw.Text(
              'Perusahaan PO Bus',
              style: pw.TextStyle(fontSize: 9, color: _gray),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildTitle() {
    return pw.Center(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _black, width: 1.2),
        ),
        child: pw.Text(
          'LAPORAN PERTANGGUNGJAWABAN CREW',
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------- info header
  static pw.Widget _buildHeaderInfo(Report r) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _line)),
      child: pw.Column(
        children: [
          _infoRow([
            _field('Hari/Tgl Berangkat', r.hariTglBerangkat),
            _field('Jam', r.jamBerangkat),
          ]),
          _infoRow([
            _field('Hari/Tgl Kembali', r.hariTglKembali),
            _field('No. Polisi', r.noPolisi),
          ]),
          _infoRow([
            _field('Pengemudi', r.pengemudi),
            _field('Kernet', r.kernet),
          ]),
          _infoRow([
            _field('KM Awal', formatNumberId(r.kmAwal)),
            _field('KM Akhir', formatNumberId(r.kmAkhir)),
          ]),
          _infoRow([
            _field('Jarak Tempuh', '${formatNumberId(r.jarakTempuh)} KM'),
            _field('', ''),
          ]),
        ],
      ),
    );
  }

  static pw.Widget _infoRow(List<pw.Widget> cells) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: cells
          .map((c) => pw.Expanded(child: pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                child: c,
              )))
          .toList(),
    );
  }

  static pw.Widget _field(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label,
            style: pw.TextStyle(fontSize: 8, color: _gray)),
        pw.SizedBox(height: 2),
        pw.Text(value.isEmpty ? '-' : value,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  // --------------------------------------------------------------- finance table
  static pw.Widget _buildSectionTitle(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _buildFinanceTable(Report r) {
    final items = [
      {'label': 'Uang Saku', 'value': r.uangSaku},
      {'label': 'BBM', 'value': r.bbm},
      {'label': 'Uang Makan', 'value': r.uangMakan},
      {'label': 'Extra', 'value': r.extra},
      {'label': 'Tagihan', 'value': r.tagihan},
    ];

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _lightGray),
        children: [
          _tableCell('No', bold: true, align: pw.TextAlign.center),
          _tableCell('Keterangan', bold: true),
          _tableCell('Jumlah (Rp)', bold: true, align: pw.TextAlign.right),
        ],
      ),
      for (int i = 0; i < items.length; i++)
        pw.TableRow(
          children: [
            _tableCell('${i + 1}', align: pw.TextAlign.center),
            _tableCell(items[i]['label'] as String),
            _tableCell(formatNumberId(items[i]['value'] as int),
                align: pw.TextAlign.right),
          ],
        ),
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _lightGray),
        children: [
          _tableCell('', bold: true),
          _tableCell('SISA', bold: true),
          _tableCell(formatNumberId(r.sisa), bold: true, align: pw.TextAlign.right),
        ],
      ),
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: _line, width: 0.5),
      columnWidths: const {
        0: pw.FixedColumnWidth(34),
        1: pw.FlexColumnWidth(3),
        2: pw.FlexColumnWidth(2),
      },
      children: rows,
    );
  }

  static pw.Widget _tableCell(String text,
      {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 9.5,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  // --------------------------------------------------------------- summary
  static pw.Widget _buildSummary(Report r) {
    final isPositif = r.sisa >= 0;
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: const PdfColor(0.97, 0.97, 0.97),
        border: pw.Border.all(color: _line),
      ),
      child: pw.Column(
        children: [
          _summaryRow('Uang Saku', formatRupiah(r.uangSaku)),
          _summaryRow('Total Pengeluaran', formatRupiah(r.totalPengeluaran)),
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 6),
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: _black, width: 1)),
            ),
            child: _summaryRow(
              isPositif ? 'SISA' : 'DEFISIT',
              formatRupiah(r.sisa),
              bold: true,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryRow(String label, String value, {bool bold = false}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label,
            style: pw.TextStyle(
                fontSize: 11,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        pw.Text(value,
            style: pw.TextStyle(
                fontSize: 11,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      ],
    );
  }

  // ------------------------------------------------------------- signature
  static pw.Widget _buildSignature(Report r) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(formatTanggalId(r.tanggalBuat),
                style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 4),
            pw.Text('Dibuat oleh,',
                style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 50),
            pw.Text(
              r.namaCrew.isEmpty ? '( ........................ )' : r.namaCrew,
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.Container(
              width: 180,
              margin: const pw.EdgeInsets.only(top: 2),
              decoration: const pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: _black, width: 0.8)),
              ),
            ),
            pw.Text('Crew',
                style: pw.TextStyle(fontSize: 9, color: _gray)),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------- helpers
  static Future<Uint8List> _loadLogo() async {
    try {
      return (await rootBundle.load('assets/logo.png')).buffer.asUint8List();
    } catch (_) {
      return Uint8List(0); // logo belum tersedia → dilewati
    }
  }
}
