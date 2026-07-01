import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/report.dart';
import '../pdf/report_pdf.dart';
import '../utils/format.dart';

/// Pratinjau PDF + tombol simpan/bagikan/cetak.
class PreviewScreen extends StatefulWidget {
  final Report report;
  final List<Uint8List> attachmentImages;
  const PreviewScreen({
    super.key,
    required this.report,
    this.attachmentImages = const [],
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  late Future<pw.Document> _docFuture;

  @override
  void initState() {
    super.initState();
    _docFuture = ReportPdfBuilder.build(
      widget.report,
      attachmentImages: widget.attachmentImages,
    );
  }

  static const _appVersion = '1.1.0';

  String get _fileBase {
    final t = widget.report.tanggalBuat;
    return 'Laporan_Crew_v${_appVersion}_${t.year}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pratinjau Laporan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Cetak',
            onPressed: _onPrint,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Bagikan',
            onPressed: _onShare,
          ),
          IconButton(
            icon: const Icon(Icons.save_alt),
            tooltip: 'Simpan ke perangkat',
            onPressed: _onSave,
          ),
        ],
      ),
      body: FutureBuilder<pw.Document>(
        future: _docFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Gagal membuat PDF: ${snap.error}'));
          }
          return PdfPreview(
            build: (format) => snap.data!.save(),
            canChangeOrientation: false,
            canChangePageFormat: false,

          );
        },
      ),
    );
  }

  // ----- aksi
  Future<void> _onPrint() async {
    try {
      final doc = await _docFuture;
      await Printing.layoutPdf(onLayout: (_) => doc.save());
    } catch (e) {
      Fluttertoast.showToast(msg: 'Gagal mencetak: $e');
    }
  }

  Future<void> _onShare() async {
    try {
      final doc = await _docFuture;
      final bytes = await doc.save();
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, '$_fileBase.pdf'));
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)],
          text: 'Laporan Crew ${widget.report.ringkas} '
              '(${formatTanggalPendek(widget.report.tanggalBuat)})');
    } catch (e) {
      Fluttertoast.showToast(msg: 'Gagal membagikan: $e');
    }
  }

  Future<void> _onSave() async {
    try {
      final doc = await _docFuture;
      final bytes = await doc.save();
      // Simpan ke folder Download bawaan HP
      final downloadDir = Directory('/storage/emulated/0/Download');
      final out = Directory(p.join(downloadDir.path, 'HappyGroup'));
      if (!out.existsSync()) out.createSync(recursive: true);
      final file = File(p.join(out.path, '$_fileBase.pdf'));
      await file.writeAsBytes(bytes);
      Fluttertoast.showToast(msg: 'Tersimpan di Download/HappyGroup/');
    } catch (e) {
      // Fallback ke app directory jika gagal
      try {
        final doc = await _docFuture;
        final bytes = await doc.save();
        Directory? dir = await getExternalStorageDirectory();
        dir ??= await getApplicationDocumentsDirectory();
        final out = Directory(p.join(dir.path, 'HappyGroup'));
        if (!out.existsSync()) out.createSync(recursive: true);
        final file = File(p.join(out.path, '$_fileBase.pdf'));
        await file.writeAsBytes(bytes);
        Fluttertoast.showToast(msg: 'Tersimpan: ${file.path}');
      } catch (e2) {
        Fluttertoast.showToast(msg: 'Gagal menyimpan: $e2');
      }
    }
  }
}
