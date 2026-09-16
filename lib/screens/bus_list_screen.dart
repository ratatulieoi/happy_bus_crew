import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../db/database.dart';
import '../models/bus.dart';
import '../ui/app_theme.dart';
import '../ui/components.dart';

class BusListScreen extends StatefulWidget {
  final bool requireBus;
  const BusListScreen({super.key, this.requireBus = false});

  @override
  State<BusListScreen> createState() => _BusListScreenState();
}

class _BusListScreenState extends State<BusListScreen> {
  List<Bus> _buses = [];
  Map<int, bool> _usedByReports = {};
  int? _selectedId;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = DatabaseHelper.instance;
      final buses = await db.getBuses();
      final selected = await db.getSelectedBus();
      final usage = <int, bool>{};
      for (final bus in buses) {
        usage[bus.id] = await db.isBusUsed(bus);
      }
      if (!mounted) return;
      setState(() {
        _usedByReports = usage;
        _buses = buses;
        _selectedId = selected?.id;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Daftar bus belum dapat dimuat. Coba lagi.';
      });
    }
  }

  Future<void> _finish() async {
    // Update PopScope before leaving mandatory first-run setup.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _editBus([Bus? bus]) async {
    if (_busy) return;
    setState(() => _busy = true);
    final saved = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => AddBusScreen(bus: bus)));
    if (!mounted) return;
    setState(() => _busy = false);
    if (saved == true) {
      await _load();
      if (mounted && widget.requireBus && _buses.isNotEmpty) await _finish();
    }
  }

  Future<void> _deleteBus(Bus bus) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Hapus bus ini?'),
              content: Text(
                  '${bus.name} (${bus.plate}) akan dihapus dari daftar bus. Tindakan ini tidak dapat dibatalkan.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Batal')),
                FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Hapus bus'))
              ],
            ));
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await DatabaseHelper.instance.deleteBus(bus.id);
      if (!mounted) return;
      showAppMessage(context, 'Bus dihapus.');
      await _load();
    } on StateError catch (error) {
      if (mounted) showAppMessage(context, error.message);
    } catch (_) {
      if (mounted) {
        showAppMessage(context, 'Bus belum dapat dihapus. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select(Bus bus) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await DatabaseHelper.instance.selectBus(bus.id);
      if (!mounted) return;
      setState(() {
        _selectedId = bus.id;
        _busy = false;
      });
      await _finish();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppMessage(context, 'Bus belum dapat dipilih. Coba lagi.');
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop:
            !_busy && (!widget.requireBus || (!_loading && _buses.isNotEmpty)),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Daftar bus'),
            automaticallyImplyLeading: !widget.requireBus && !_busy,
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: SingleChildScrollView(
                        child: EmptyMessage(
                          icon: Icons.directions_bus_outlined,
                          title: 'Data bus belum tersedia',
                          message: _error!,
                          action: FilledButton(
                              onPressed: _load, child: const Text('Coba lagi')),
                        ),
                      ),
                    )
                  : ContentWidth(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        children: [
                          Text(
                              _buses.isEmpty
                                  ? 'Tambahkan bus pertama'
                                  : 'Pilih bus untuk laporan',
                              style:
                                  Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 8),
                          Text(
                              _buses.isEmpty
                                  ? 'Tambahkan nama bus dan nomor polisi sebelum membuat laporan.'
                                  : 'Tambah bus sesuai kebutuhan. Ketuk bus untuk menggunakannya.',
                              style: const TextStyle(color: AppColors.muted)),
                          const SizedBox(height: 24),
                          for (final bus in _buses)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: SectionCard(
                                padding: EdgeInsets.zero,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ListTile(
                                      enabled: !_busy,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 8),
                                      leading: Icon(
                                          bus.id == _selectedId
                                              ? Icons.check_circle
                                              : Icons.directions_bus_outlined,
                                          color: bus.id == _selectedId
                                              ? AppColors.brand
                                              : AppColors.muted),
                                      title: Text(bus.name),
                                      subtitle: Text(bus.plate),
                                      onTap: () => _select(bus),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: 'Ubah ${bus.plate}',
                                            onPressed: _busy
                                                ? null
                                                : () => _editBus(bus),
                                            icon:
                                                const Icon(Icons.edit_outlined),
                                          ),
                                          IconButton(
                                            tooltip: 'Hapus ${bus.plate}',
                                            onPressed: _busy ||
                                                    _usedByReports[bus.id] == true
                                                ? null
                                                : () => _deleteBus(bus),
                                            color: AppColors.danger,
                                            icon: const Icon(
                                                Icons.delete_outline_rounded),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_usedByReports[bus.id] == true)
                                      const Padding(
                                        padding:
                                            EdgeInsets.fromLTRB(16, 0, 16, 12),
                                        child: Text(
                                            'Memiliki laporan tersimpan dan tidak dapat dihapus.',
                                            style: TextStyle(
                                                color: AppColors.muted,
                                                fontSize: 12)),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
          bottomNavigationBar: BottomActionBar(
            child: FilledButton.icon(
              onPressed:
                  _loading || _busy || _error != null ? null : () => _editBus(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Tambah bus'),
            ),
          ),
        ),
      );
}

class AddBusScreen extends StatefulWidget {
  final Bus? bus;
  const AddBusScreen({super.key, this.bus});

  @override
  State<AddBusScreen> createState() => _AddBusScreenState();
}

class _AddBusScreenState extends State<AddBusScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.bus?.name ?? '');
  late final _plate = TextEditingController(text: widget.bus?.plate ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _plate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await DatabaseHelper.instance
          .saveBus(id: widget.bus?.id, name: _name.text, plate: _plate.text);
      if (!mounted) return;
      setState(() => _saving = false);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is DatabaseException && error.isUniqueConstraintError()
            ? 'Nomor polisi sudah terdaftar. Gunakan bus yang ada atau masukkan nomor lain.'
            : 'Bus gagal disimpan. Isian Anda tetap ada, silakan coba lagi.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.bus == null ? 'Tambah bus' : 'Ubah bus'),
            automaticallyImplyLeading: !_saving,
          ),
          body: ContentWidth(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeading(
                        title: 'Identitas bus',
                        subtitle:
                            'Nomor polisi digunakan pada laporan dan PDF.',
                        icon: Icons.directions_bus_outlined,
                      ),
                      TextFormField(
                        controller: _name,
                        enabled: !_saving,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                            labelText: 'Nama bus',
                            hintText: 'Contoh: Happy Bus 01'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Isi nama bus.'
                                : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _plate,
                        enabled: !_saving,
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _save(),
                        decoration: const InputDecoration(
                            labelText: 'Nomor polisi',
                            hintText: 'Contoh: B 1234 XX'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Isi nomor polisi.'
                                : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(_error!,
                            style: const TextStyle(color: AppColors.danger)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          bottomNavigationBar: BottomActionBar(
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_rounded),
              label: Text(_saving ? 'Menyimpan…' : 'Simpan bus'),
            ),
          ),
        ),
      );
}
