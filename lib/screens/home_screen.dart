import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/database.dart';
import '../models/report.dart';
import '../ui/app_theme.dart';
import '../ui/components.dart';
import '../utils/format.dart';
import 'bus_setup_screen.dart';
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
  String _busName = '';
  String _plate = '';
  int _busIndex = 0;
  int _currentKm = 0;
  int _lastOilKm = 0;
  int _oilInterval = 10000;
  int _filter = 0;
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
    try {
      final selected =
          await DatabaseHelper.instance.getSetting('selected_bus_index');
      if (!mounted) return;
      if (selected == null) {
        await Navigator.push<bool>(
            context,
            MaterialPageRoute(
                builder: (_) => const BusSetupScreen(forceSetup: true)));
        if (!mounted) return;
      }
      await _refresh();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Data di perangkat belum dapat dibuka. Coba muat ulang.';
        });
      }
    }
  }

  Future<void> _refresh() async {
    try {
      final db = DatabaseHelper.instance;
      final index =
          int.tryParse(await db.getSetting('selected_bus_index') ?? '') ?? 0;
      final name =
          await db.getSetting('bus_${index}_name') ?? 'Bus ${index + 1}';
      final plate =
          await db.getSetting('bus_${index}_plate') ?? 'B 100${index + 1} XX';
      final lastOil = int.tryParse(
              await db.getSetting('bus_${index}_oil_change_km') ?? '') ??
          0;
      final interval = int.tryParse(
              await db.getSetting('bus_${index}_oil_interval') ?? '') ??
          10000;
      final km = await db.getLatestKmForPlate(plate);
      final reports = await db.getAllReports();
      if (!mounted) return;
      setState(() {
        _busIndex = index;
        _busName = name;
        _plate = plate;
        _lastOilKm = lastOil;
        _oilInterval = interval > 0 ? interval : 10000;
        _currentKm = km;
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

  Future<void> _configure() async {
    final updated = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => const BusSetupScreen()));
    if (mounted && updated == true) await _refresh();
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
      if (_filter == 1 && r.noPolisi != _plate) return false;
      if (_filter == 2 && r.sisa >= 0) return false;
      return '${r.noPolisi} ${r.pengemudi} ${r.kernet} ${r.namaCrew} ${r.hariTglBerangkat} ${formatTanggalPendek(r.tanggalBuat)}'
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
            width: 154, semanticLabel: 'Happy Group'),
        actions: [
          IconButton(
              onPressed: _loading ? null : _configure,
              tooltip: 'Konfigurasi bus',
              icon: const Icon(Icons.tune_rounded)),
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
                                const StatusPill(
                                    label: 'Tersimpan di perangkat',
                                    icon: Icons.offline_pin_outlined,
                                    color: AppColors.success,
                                    background: AppColors.successSoft),
                                const SizedBox(height: 16),
                                Text('Laporan crew',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineLarge),
                                const SizedBox(height: 6),
                                const Text(
                                    'Catat perjalanan dan kelola pengeluaran bus.',
                                    style: TextStyle(color: AppColors.muted)),
                                const SizedBox(height: 24),
                                _busCard(),
                                const SizedBox(height: 12),
                                _oilCard(),
                                const SizedBox(height: 28),
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
                                        'Cari plat, nama crew, atau tanggal',
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
                                  for (final entry in [
                                    'Semua bus',
                                    'Bus aktif',
                                    'Defisit'
                                  ].asMap().entries)
                                    ChoiceChip(
                                        label: Text(entry.value),
                                        selected: _filter == entry.key,
                                        onSelected: (_) => setState(
                                            () => _filter = entry.key)),
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
                                    ? 'Buat laporan untuk mencatat kilometer, uang saku, dan struk perjalanan.'
                                    : 'Coba kata kunci lain atau tampilkan semua bus.',
                                action: _reports.isEmpty
                                    ? null
                                    : TextButton(
                                        onPressed: () {
                                          _search.clear();
                                          setState(() => _filter = 0);
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

  Widget _busCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
            color: AppColors.ink, borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.directions_bus_rounded,
                    color: Colors.white, size: 24)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('BUS AKTIF',
                      style: TextStyle(
                          color: Color(0xFFBFC5CB),
                          fontSize: 11,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(_busName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                ])),
            IconButton(
                onPressed: _configure,
                tooltip: 'Ganti bus aktif',
                icon:
                    const Icon(Icons.swap_horiz_rounded, color: Colors.white)),
          ]),
          const SizedBox(height: 22),
          Wrap(
              spacing: 24,
              runSpacing: 18,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Nomor polisi',
                      style: TextStyle(color: Color(0xFFBFC5CB), fontSize: 12)),
                  const SizedBox(height: 6),
                  Text(_plate,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: Colors.white)),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Kilometer terakhir',
                      style: TextStyle(color: Color(0xFFBFC5CB), fontSize: 12)),
                  const SizedBox(height: 6),
                  Text('${formatNumberId(_currentKm)} km',
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ]),
              ]),
        ]),
      );

  Widget _oilCard() {
    final used = _currentKm - _lastOilKm;
    final remaining = _oilInterval - used;
    final due = remaining <= 0;
    final soon = remaining <= 2000;
    final color = due
        ? AppColors.danger
        : soon
            ? AppColors.warning
            : AppColors.success;
    final background = due
        ? AppColors.dangerSoft
        : soon
            ? AppColors.warningSoft
            : AppColors.successSoft;
    return SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Perawatan oli',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            StatusPill(
                label: due
                    ? 'Waktunya ganti oli'
                    : soon
                        ? 'Segera ganti oli'
                        : 'Kondisi oli baik',
                color: color,
                background: background,
                icon: due
                    ? Icons.warning_amber_rounded
                    : Icons.oil_barrel_outlined),
          ]),
      const SizedBox(height: 16),
      ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
              value: (used / _oilInterval).clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: AppColors.canvas,
              color: color)),
      const SizedBox(height: 10),
      Text(
          remaining < 0
              ? 'Lewat ${formatNumberId(-remaining)} km dari jadwal'
              : remaining == 0
                  ? 'Jadwal ganti oli sudah tercapai'
                  : '${formatNumberId(remaining)} km menuju ganti oli',
          style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Text(
          'Terakhir ${formatNumberId(_lastOilKm)} km  •  Berikutnya ${formatNumberId(_lastOilKm + _oilInterval)} km',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
              onPressed: _recordOil,
              icon: const Icon(Icons.build_outlined, size: 18),
              label: const Text('Catat ganti oli'))),
    ]));
  }

  Widget _reportCard(Report report) {
    final deficit = report.sisa < 0;
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
              Text(
                  report.pengemudi.isEmpty
                      ? 'Pengemudi belum diisi'
                      : report.pengemudi,
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
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Jarak tempuh',
                              style: Theme.of(context).textTheme.bodySmall),
                          Text('${formatNumberId(report.jarakTempuh)} km',
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w600)),
                        ]),
                  ])),
            ])),
      ),
    );
  }

  Future<void> _recordOil() async {
    final km = await showDialog<int>(
        context: context,
        builder: (_) => _OilChangeDialog(currentKm: _currentKm));
    if (km == null || !mounted) return;
    try {
      await DatabaseHelper.instance
          .setSetting('bus_${_busIndex}_oil_change_km', '$km');
      if (!mounted) return;
      showAppMessage(context, 'Catatan ganti oli disimpan.');
      await _refresh();
    } catch (_) {
      if (mounted) {
        showAppMessage(
            context, 'Gagal menyimpan catatan ganti oli. Coba lagi.');
      }
    }
  }

  Future<void> _openPreview(Report report) async {
    setState(() => _opening = true);
    try {
      final images = <Uint8List>[];
      if (report.id != null) {
        for (final path
            in await DatabaseHelper.instance.getAttachments(report.id!)) {
          final file = File(path);
          if (await file.exists()) images.add(await file.readAsBytes());
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

class _OilChangeDialog extends StatefulWidget {
  final int currentKm;
  const _OilChangeDialog({required this.currentKm});

  @override
  State<_OilChangeDialog> createState() => _OilChangeDialogState();
}

class _OilChangeDialogState extends State<_OilChangeDialog> {
  final _key = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: '${widget.currentKm}');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Catat ganti oli'),
        content: Form(
            key: _key,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'Isi angka odometer saat oli diganti. Pengingat berikutnya dihitung dari angka ini.'),
                  const SizedBox(height: 20),
                  TextFormField(
                      controller: _controller,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                          labelText: 'Kilometer ganti oli', suffixText: 'km'),
                      validator: (v) => int.tryParse(v ?? '') == null
                          ? 'Masukkan kilometer yang valid'
                          : null),
                ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () {
                if (_key.currentState!.validate()) {
                  Navigator.pop(context, int.parse(_controller.text));
                }
              },
              child: const Text('Simpan'))
        ],
      );
}
