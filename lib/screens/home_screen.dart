import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../db/database.dart';
import '../models/report.dart';
import '../utils/format.dart';
import 'form_screen.dart';
import 'preview_screen.dart';

/// Halaman utama: daftar laporan tersimpan + tombol buat baru.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Report>> _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _future = DatabaseHelper.instance.getAllReports();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Happy Bus — Laporan Crew'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat ulang',
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<List<Report>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Gagal memuat: ${snap.error}'));
          }
          final reports = snap.data ?? [];
          if (reports.isEmpty) {
            return _emptyState();
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: reports.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final r = reports[i];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.description_outlined),
                  ),
                  title: Text(
                    r.ringkas,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${formatTanggalPendek(r.tanggalBuat)} • '
                    'Sisa: ${formatRupiah(r.selisih)}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) => _onMenu(v, r),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'preview', child: Text('Lihat / PDF')),
                      PopupMenuItem(value: 'edit', child: Text('Ubah')),
                      PopupMenuItem(value: 'delete', child: Text('Hapus')),
                    ],
                  ),
                  onTap: () => _openPreview(r),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Buat Laporan'),
        onPressed: () async {
          await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const FormScreen()),
          );
          if (mounted) _refresh();
        },
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inbox_outlined, size: 72, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('Belum ada laporan'),
          const SizedBox(height: 4),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.add),
            label: const Text('Buat Laporan Baru'),
            onPressed: () async {
              await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => const FormScreen()),
              );
              if (mounted) _refresh();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _onMenu(String value, Report r) async {
    switch (value) {
      case 'preview':
        await _openPreview(r);
        break;
      case 'edit':
        final saved = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => FormScreen(report: r)),
        );
        if (saved == true && mounted) _refresh();
        break;
      case 'delete':
        await _confirmDelete(r);
        break;
    }
  }

  Future<void> _openPreview(Report r) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PreviewScreen(report: r)),
    );
  }

  Future<void> _confirmDelete(Report r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus laporan?'),
        content: Text('Laporan ${r.ringkas} akan dihapus permanen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await DatabaseHelper.instance.deleteReport(r.id!);
      Fluttertoast.showToast(msg: 'Laporan dihapus');
      _refresh();
    }
  }
}
