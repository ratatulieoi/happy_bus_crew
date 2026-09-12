import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/report.dart';
import '../pdf/report_pdf.dart';
import '../ui/app_theme.dart';
import '../ui/components.dart';
import '../utils/format.dart';

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
  static const _appVersion = '1.1.0';
  Uint8List? _bytes;
  bool _building = true;
  String? _error;
  String? _busyAction;

  @override
  void initState() {
    super.initState();
    _buildDocument();
  }

  Future<void> _buildDocument() async {
    setState(() {
      _building = true;
      _error = null;
      _bytes = null;
    });
    try {
      final document = await ReportPdfBuilder.build(
        widget.report,
        attachmentImages: widget.attachmentImages,
      );
      final bytes = await document.save();
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _building = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _building = false;
        _error =
            'Laporan belum dapat diubah menjadi PDF. Coba buat ulang pratinjau.';
      });
    }
  }

  String get _fileBase {
    final date = widget.report.tanggalBuat;
    final day =
        '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    final reportId =
        widget.report.id?.toString() ?? date.microsecondsSinceEpoch.toString();
    // Keep the familiar version/date prefix and distinguish each export.
    return 'Laporan_Crew_v${_appVersion}_${day}_${reportId}_${DateTime.now().microsecondsSinceEpoch}';
  }

  bool get _canExport => !_building && _bytes != null && _busyAction == null;

  Future<void> _export(String action) async {
    if (!_canExport) return;
    final bytes = _bytes!;
    final filename = '$_fileBase.pdf';
    final renderBox = context.findRenderObject();
    final shareOrigin = renderBox is RenderBox && renderBox.hasSize
        ? renderBox.localToGlobal(Offset.zero) & renderBox.size
        : null;
    setState(() => _busyAction = action);
    try {
      switch (action) {
        case 'Simpan':
          final file = await _saveFile(bytes, filename);
          if (mounted) showAppMessage(context, 'PDF tersimpan: ${file.path}');
          break;
        case 'Bagikan':
          final directory = await getTemporaryDirectory();
          final file = File(p.join(directory.path, filename));
          await file.writeAsBytes(bytes, flush: true);
          if (!mounted) return;
          await Share.shareXFiles(
            [XFile(file.path)],
            text:
                'Laporan Crew ${widget.report.ringkas} (${formatTanggalPendek(widget.report.tanggalBuat)})',
            sharePositionOrigin: shareOrigin,
          );
          break;
        case 'Cetak':
          await Printing.layoutPdf(
              name: filename, onLayout: (_) async => bytes);
          break;
      }
    } catch (_) {
      if (mounted) {
        showAppMessage(
            context, 'Gagal ${action.toLowerCase()} PDF. Silakan coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<File> _saveFile(Uint8List bytes, String filename) async {
    Future<File> writeTo(Directory directory) async {
      final output = Directory(p.join(directory.path, 'HappyGroup'));
      await output.create(recursive: true);
      return File(p.join(output.path, filename))
          .writeAsBytes(bytes, flush: true);
    }

    try {
      return await writeTo(Directory('/storage/emulated/0/Download'));
    } catch (_) {
      // Some devices do not allow direct writes to the public Download folder.
    }
    try {
      final external = await getExternalStorageDirectory();
      if (external != null) return await writeTo(external);
    } catch (_) {
      // Fall back to application documents when external storage is unavailable.
    }
    return writeTo(await getApplicationDocumentsDirectory());
  }

  Widget _action(String label, IconData icon, {bool primary = false}) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22),
        const SizedBox(height: 4),
        Text(label, textAlign: TextAlign.center)
      ],
    );
    final style = ButtonStyle(
        padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 8, vertical: 12)));
    return Expanded(
      child: primary
          ? FilledButton(
              onPressed: _canExport ? () => _export(label) : null,
              style: style,
              child: content)
          : OutlinedButton(
              onPressed: _canExport ? () => _export(label) : null,
              style: style,
              child: content),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pratinjau laporan')),
      body: ContentWidth(
        maxWidth: 960,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Periksa sebelum dibagikan',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                const Text(
                    'Pastikan data perjalanan dan bukti pengeluaran sudah sesuai.',
                    style: TextStyle(color: AppColors.muted)),
                const SizedBox(height: 20),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const StatusPill(
                          label: 'Laporan crew • PDF',
                          icon: Icons.description_outlined,
                          color: AppColors.brand,
                          background: AppColors.dangerSoft),
                      const SizedBox(height: 12),
                      Text(widget.report.ringkas,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(
                          '${formatTanggalPendek(widget.report.tanggalBuat)} • ${widget.attachmentImages.length} bukti terlampir',
                          style: const TextStyle(color: AppColors.muted)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SectionHeading(
                    title: 'Dokumen PDF',
                    subtitle:
                        'Gulir halaman di dalam pratinjau untuk memeriksa seluruh laporan.'),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: (constraints.maxHeight * .78)
                        .clamp(400.0, 900.0)
                        .toDouble(),
                    child: _building
                        ? const SectionCard(
                            child: Center(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 20),
                                    Text('Menyiapkan laporan dan bukti…'),
                                  ]),
                            ),
                          )
                        : _error != null
                            ? SectionCard(
                                padding: EdgeInsets.zero,
                                child: Center(
                                  child: SingleChildScrollView(
                                    child: EmptyMessage(
                                      icon: Icons.description_outlined,
                                      title: 'PDF belum siap',
                                      message: _error!,
                                      action: FilledButton.icon(
                                          onPressed: _buildDocument,
                                          icon: const Icon(Icons.refresh),
                                          label: const Text('Coba lagi')),
                                    ),
                                  ),
                                ),
                              )
                            : PdfPreview(
                                build: (_) async => _bytes!,
                                canChangeOrientation: false,
                                canChangePageFormat: false,
                                canDebug: false,
                                allowPrinting: false,
                                allowSharing: false,
                                useActions: false,
                                pdfFileName: 'Laporan_Crew.pdf',
                              ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomActionBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_busyAction != null) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text('Memproses ${_busyAction!.toLowerCase()} PDF…',
                  semanticsLabel:
                      'Sedang memproses ${_busyAction!.toLowerCase()} PDF'),
              const SizedBox(height: 12),
            ],
            Row(children: [
              _action('Simpan', Icons.save_alt_rounded, primary: true),
              const SizedBox(width: 8),
              _action('Bagikan', Icons.ios_share_rounded),
              const SizedBox(width: 8),
              _action('Cetak', Icons.print_outlined),
            ]),
          ],
        ),
      ),
    );
  }
}
