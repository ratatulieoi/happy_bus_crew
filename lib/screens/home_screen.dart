import 'dart:io';

import 'package:flutter/material.dart';

import '../db/database.dart';
import '../models/bus.dart';
import '../models/report.dart';
import '../models/report_attachment.dart';
import '../ui/app_theme.dart';
import '../ui/components.dart';
import '../utils/format.dart';
import 'form_screen.dart';
import 'preview_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  List<Report> _reports = [];
  String? _filterPlate;
  bool _loading = true;
  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    try {
      final reports = await DatabaseHelper.instance.getAllReports();
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Laporan belum dapat dimuat. Data Anda tidak dihapus.';
        });
      }
    }
  }

  Future<void> _edit([Report? report]) async {
    final saved = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => FormScreen(report: report)));
    if (mounted && saved == true) {
      await _refresh();
      if (mounted) showAppMessage(context, 'Laporan berhasil disimpan.');
    }
  }

  List<Report> get _filteredReports {
    final query = _search.text.trim().toLowerCase();
    return _reports.where((r) {
      if (_filterPlate != null && r.noPolisi != _filterPlate) return false;
      final busName = busNameForPlate(r.noPolisi);
      return '${r.noPolisi} $busName ${r.pengemudi} ${r.kernet} ${r.namaCrew} ${r.hariTglBerangkat} ${formatTanggalPendek(r.tanggalBuat)}'
          .toLowerCase()
          .contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visibleReports = _filteredReports;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        title: Image.asset('assets/logo.png',
            width: 154,
            semanticLabel: 'Happy Group',
            // A failed asset load must not leave a blank app bar.
            errorBuilder: (context, error, stackTrace) => const Text(
                'Happy Group',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
        actions: [
          IconButton(
              onPressed: _loading ? null : _initialize,
              tooltip: 'Muat ulang',
              icon: const Icon(Icons.refresh_rounded)),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: EmptyMessage(
                      icon: Icons.cloud_off_outlined,
                      title: 'Belum bisa memuat data',
                      message: _error!,
                      action: FilledButton.icon(
                          onPressed: _initialize,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Coba lagi'))))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ContentWidth(
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                          sliver: SliverToBoxAdapter(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text('LPJ Crew',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineLarge),
                                const SizedBox(height: 24),
                                Row(children: [
                                  Expanded(
                                      child: Text('Riwayat laporan',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge)),
                                  StatusPill(
                                      label: '${_reports.length} laporan'),
                                ]),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _search,
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    hintText:
                                        'Cari armada, plat, crew, atau tanggal',
                                    prefixIcon:
                                        const Icon(Icons.search_rounded),
                                    suffixIcon: _search.text.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: 'Hapus pencarian',
                                            onPressed: () {
                                              _search.clear();
                                              setState(() {});
                                            },
                                            icon: const Icon(Icons.close)),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(spacing: 8, runSpacing: 4, children: [
                                  ChoiceChip(
                                      label: const Text('Semua armada'),
                                      selected: _filterPlate == null,
                                      onSelected: (_) =>
                                          setState(() => _filterPlate = null)),
                                  for (final bus in busCatalog)
                                    ChoiceChip(
                                        label: Text(bus.name),
                                        selected: _filterPlate == bus.plate,
                                        onSelected: (_) => setState(
                                            () => _filterPlate = bus.plate)),
                                ]),
                                const SizedBox(height: 16),
                                if (_opening)
                                  const Padding(
                                      padding: EdgeInsets.only(bottom: 12),
                                      child: LinearProgressIndicator()),
                              ])),
                        ),
                        if (visibleReports.isEmpty)
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            sliver: SliverToBoxAdapter(
                                child: SectionCard(
                              padding: EdgeInsets.zero,
                              child: EmptyMessage(
                                icon: _reports.isEmpty
                                    ? Icons.edit_note_rounded
                                    : Icons.search_off_rounded,
                                title: _reports.isEmpty
                                    ? 'Perjalanan pertama dimulai di sini'
                                    : 'Tidak ada laporan yang cocok',
                                message: _reports.isEmpty
                                    ? 'Buat laporan untuk mencatat perjalanan dan lampiran gambar.'
                                    : 'Coba kata kunci lain atau tampilkan semua armada.',
                                action: _reports.isEmpty
                                    ? null
                                    : TextButton(
                                        onPressed: () {
                                          _search.clear();
                                          setState(() {
                                            _filterPlate = null;
                                          });
                                        },
                                        child: const Text('Reset pencarian')),
                              ),
                            )),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                              (context, i) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _reportCard(visibleReports[i])),
                              childCount: visibleReports.length,
                            )),
                          ),
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ],
                    ),
                  ),
                ),
      bottomNavigationBar: BottomActionBar(
          child: FilledButton.icon(
              onPressed: _loading || _error != null ? null : () => _edit(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Buat laporan baru'))),
    );
  }

  Widget _reportCard(Report report) {
    final deficit = report.sisa < 0;
    final busName = busNameForPlate(report.noPolisi);
    final driver =
        report.pengemudi.isEmpty ? 'Sopir belum diisi' : report.pengemudi;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _opening ? null : () => _openPreview(report),
        child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 10, 18),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.description_outlined,
                    size: 18, color: AppColors.muted),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(formatTanggalPendek(report.tanggalBuat),
                        style: Theme.of(context).textTheme.bodySmall)),
                PopupMenuButton<String>(
                  tooltip: 'Tindakan laporan',
                  onSelected: (value) {
                    if (value == 'edit') _edit(report);
                    if (value == 'preview' && !_opening) _openPreview(report);
                    if (value == 'delete') _delete(report);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'preview', child: Text('Lihat PDF')),
                    PopupMenuItem(value: 'edit', child: Text('Ubah laporan')),
                    PopupMenuItem(
                        value: 'delete',
                        child: Text('Hapus laporan',
                            style: TextStyle(color: AppColors.danger))),
                  ],
                ),
              ]),
              Text(
                  report.noPolisi.isEmpty
                      ? 'Nomor polisi belum diisi'
                      : report.noPolisi,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('$busName • $driver',
                  style: const TextStyle(color: AppColors.muted)),
              const Divider(height: 24),
              Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Wrap(spacing: 20, runSpacing: 12, children: [
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(deficit ? 'Defisit' : 'Sisa uang',
                              style: Theme.of(context).textTheme.bodySmall),
                          Text(formatRupiah(report.sisa),
                              style: TextStyle(
                                  color: deficit
                                      ? AppColors.danger
                                      : AppColors.success,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700)),
                        ]),
                  ])),
            ])),
      ),
    );
  }

  Future<void> _openPreview(Report report) async {
    setState(() => _opening = true);
    try {
      final images = <ReportAttachmentImage>[];
      if (report.id != null) {
        for (final attachment
            in await DatabaseHelper.instance.getAttachments(report.id!)) {
          final file = File(attachment.filePath);
          if (await file.exists()) {
            images.add(ReportAttachmentImage(
                bytes: await file.readAsBytes(), owner: attachment.owner));
          }
        }
      }
      if (!mounted) return;
      await Navigator.push<void>(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  PreviewScreen(report: report, attachmentImages: images)));
    } catch (_) {
      if (mounted) {
        showAppMessage(context, 'Laporan belum dapat dibuka. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _delete(Report report) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Hapus laporan ini?'),
              content: Text(
                  '${report.ringkas}\n${formatTanggalPendek(report.tanggalBuat)}\n\nLaporan dan tautan lampirannya akan dihapus dari aplikasi. Tindakan ini tidak dapat dibatalkan.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Batal')),
                FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Hapus laporan'))
              ],
            ));
    if (confirmed != true || report.id == null) return;
    try {
      await DatabaseHelper.instance.deleteReport(report.id!);
      if (!mounted) return;
      showAppMessage(context, 'Laporan dihapus.');
      await _refresh();
    } catch (_) {
      if (mounted) {
        showAppMessage(context, 'Gagal menghapus laporan. Coba lagi.');
      }
    }
  }
}
