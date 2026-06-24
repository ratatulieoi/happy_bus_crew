import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../db/database.dart';
import '../models/report.dart';
import '../utils/format.dart';
import 'bus_setup_screen.dart';
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
  String _activeBusName = '';
  String _activeBusPlate = '';
  int _currentKm = 0;
  int _lastOilChangeKm = 0;
  int _oilInterval = 10000;
  bool _hasCheckedSetup = false;

  @override
  void initState() {
    super.initState();
    _checkBusSetup();
  }

  Future<void> _checkBusSetup() async {
    final db = DatabaseHelper.instance;
    final selectedBus = await db.getSetting('selected_bus_index');
    if (selectedBus == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) {
          final ok = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const BusSetupScreen(forceSetup: true),
            ),
          );
          if (ok == true) {
            setState(() {
              _hasCheckedSetup = true;
            });
            _refresh();
          }
        }
      });
    } else {
      setState(() {
        _hasCheckedSetup = true;
      });
      _refresh();
    }
  }

  void _refresh() async {
    if (!_hasCheckedSetup) return;

    final db = DatabaseHelper.instance;
    final selectedIndexStr = await db.getSetting('selected_bus_index');
    if (selectedIndexStr != null) {
      final index = int.tryParse(selectedIndexStr) ?? 0;
      final name = await db.getSetting('bus_${index}_name') ?? 'Bus ${index + 1}';
      final plate = await db.getSetting('bus_${index}_plate') ?? 'B 100${index + 1} XX';
      final lastOilStr = await db.getSetting('bus_${index}_oil_change_km') ?? '0';
      final intervalStr = await db.getSetting('bus_${index}_oil_interval') ?? '10000';
      
      final currentKm = await db.getLatestKmForPlate(plate);
      
      if (mounted) {
        setState(() {
          _activeBusName = name;
          _activeBusPlate = plate;
          _lastOilChangeKm = int.tryParse(lastOilStr) ?? 0;
          _oilInterval = int.tryParse(intervalStr) ?? 10000;
          _currentKm = currentKm;
        });
      }
    }

    if (mounted) {
      setState(() {
        _future = DatabaseHelper.instance.getAllReports();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Happy Bus — Laporan Crew', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Versi 1.1.0', style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Konfigurasi Bus',
            onPressed: () async {
              final updated = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BusSetupScreen()),
              );
              if (updated == true) {
                _refresh();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat ulang',
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_activeBusPlate.isNotEmpty) _oilStatusCard(),
          Expanded(
            child: FutureBuilder<List<Report>>(
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
                    'Sisa: ${formatRupiah(r.sisa)}',
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
    ),
  ],
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

  Widget _oilStatusCard() {
    final kmSejakGantiOli = _currentKm - _lastOilChangeKm;
    final kmSisa = _oilInterval - kmSejakGantiOli;
    final overdue = kmSisa < 0;
    
    double pct = kmSejakGantiOli / _oilInterval;
    if (pct < 0) pct = 0;
    if (pct > 1) pct = 1;
    
    Color statusColor;
    String statusText;
    
    if (kmSisa <= 0) {
      statusColor = Colors.red;
      statusText = 'Waktunya Ganti Oli!';
    } else if (kmSisa <= 2000) {
      statusColor = Colors.orange;
      statusText = 'Segera Ganti Oli';
    } else {
      statusColor = Colors.green;
      statusText = 'Kondisi Oli Baik';
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              statusColor.withOpacity(0.05),
              Theme.of(context).colorScheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.directions_bus, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _activeBusName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _activeBusPlate,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'KM Terakhir',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatNumberId(_currentKm)} km',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ganti Oli Terakhir',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatNumberId(_lastOilChangeKm)} km',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Berikutnya',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatNumberId(_lastOilChangeKm + _oilInterval)} km',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  overdue
                      ? 'Lewat: ${formatNumberId(-kmSisa)} km'
                      : 'Sisa Oli: ${formatNumberId(kmSisa)} km',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: overdue ? Colors.red : Colors.grey[700],
                  ),
                ),
                TextButton.icon(
                  onPressed: _showOilChangeDialog,
                  icon: const Icon(Icons.build_outlined, size: 16),
                  label: const Text('Catat Ganti Oli', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showOilChangeDialog() async {
    final controller = TextEditingController(text: _currentKm.toString());
    final indexStr = await DatabaseHelper.instance.getSetting('selected_bus_index');
    if (indexStr == null) return;
    final index = int.parse(indexStr);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Catat Ganti Oli Baru'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Masukkan kilometer saat ganti oli dilakukan:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Kilometer Ganti Oli',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (ok == true) {
      final inputKm = int.tryParse(controller.text) ?? _currentKm;
      await DatabaseHelper.instance.setSetting('bus_${index}_oil_change_km', inputKm.toString());
      Fluttertoast.showToast(msg: 'Data ganti oli disimpan');
      _refresh();
    }
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
