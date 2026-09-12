import 'package:flutter/material.dart';

import '../db/database.dart';
import '../ui/app_theme.dart';
import '../ui/components.dart';

class BusSetupScreen extends StatefulWidget {
  final bool forceSetup;
  const BusSetupScreen({super.key, this.forceSetup = false});

  @override
  State<BusSetupScreen> createState() => _BusSetupScreenState();
}

class _BusSetupScreenState extends State<BusSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameControllers = List.generate(6, (_) => TextEditingController());
  final _plateControllers = List.generate(6, (_) => TextEditingController());
  int _selectedBusIndex = 0;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _saved = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadBusData();
  }

  @override
  void dispose() {
    for (final controller in [..._nameControllers, ..._plateControllers]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadBusData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final db = DatabaseHelper.instance;
      final selected =
          int.tryParse(await db.getSetting('selected_bus_index') ?? '') ?? 0;
      final names = <String>[];
      final plates = <String>[];
      for (int i = 0; i < 6; i++) {
        names.add(await db.getSetting('bus_${i}_name') ?? 'Bus ${i + 1}');
        plates.add(await db.getSetting('bus_${i}_plate') ?? 'B 100${i + 1} XX');
      }
      if (!mounted) return;
      setState(() {
        _selectedBusIndex = selected >= 0 && selected < 6 ? selected : 0;
        for (int i = 0; i < 6; i++) {
          _nameControllers[i].text = names[i];
          _plateControllers[i].text = plates[i];
        }
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError =
            'Data bus belum dapat dimuat. Periksa kembali dengan mencoba ulang.';
      });
    }
  }

  Future<void> _saveData() async {
    if (_isSaving || _saved || _isLoading || _loadError != null) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      showAppMessage(
          context, 'Lengkapi nama dan nomor polisi untuk keenam bus.');
      return;
    }
    FocusScope.of(context).unfocus();
    final names =
        _nameControllers.map((controller) => controller.text.trim()).toList();
    final plates = _plateControllers
        .map((controller) => controller.text.trim().toUpperCase())
        .toList();
    setState(() => _isSaving = true);
    try {
      final db = DatabaseHelper.instance;
      await db.setSetting('selected_bus_index', _selectedBusIndex.toString());
      for (int i = 0; i < 6; i++) {
        await db.setSetting('bus_${i}_name', names[i]);
        await db.setSetting('bus_${i}_plate', plates[i]);
      }
      final oilChangeKey = 'bus_${_selectedBusIndex}_oil_change_km';
      if (await db.getSetting(oilChangeKey) == null) {
        await db.setSetting(oilChangeKey, '0');
      }
      if (!mounted) return;
      setState(() {
        _saved = true;
        _isSaving = false;
      });
      showAppMessage(context, 'Konfigurasi bus berhasil disimpan.');
      // Let PopScope receive the successful setup state before leaving.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
    } catch (_) {
      if (mounted) {
        showAppMessage(
            context, 'Konfigurasi gagal disimpan. Silakan coba simpan lagi.');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _busCard(int index) {
    final selected = index == _selectedBusIndex;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioListTile<int>(
              contentPadding: EdgeInsets.zero,
              value: index,
              groupValue: _selectedBusIndex,
              onChanged: _isSaving
                  ? null
                  : (value) => setState(() => _selectedBusIndex = value!),
              title: Text('Bus ${index + 1}',
                  style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text(selected
                  ? 'Digunakan di perangkat ini'
                  : 'Pilih untuk perangkat ini'),
              activeColor: AppColors.brand,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameControllers[index],
              enabled: !_isSaving,
              decoration: const InputDecoration(
                  labelText: 'Nama bus / label', hintText: 'Contoh: Bus A'),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Isi nama bus.'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _plateControllers[index],
              enabled: !_isSaving,
              decoration: const InputDecoration(
                  labelText: 'Nomor polisi', hintText: 'Contoh: B 1234 XX'),
              textCapitalization: TextCapitalization.characters,
              textInputAction:
                  index == 5 ? TextInputAction.done : TextInputAction.next,
              onChanged: (_) => setState(() {}),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Isi nomor polisi.'
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _nameControllers[_selectedBusIndex].text.trim();
    final plate =
        _plateControllers[_selectedBusIndex].text.trim().toUpperCase();
    return PopScope(
      canPop: !_isSaving && (!widget.forceSetup || _saved),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.forceSetup ? 'Pengaturan awal' : 'Pengaturan bus'),
          automaticallyImplyLeading: !widget.forceSetup && !_isSaving,
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                    semanticsLabel: 'Memuat data bus'))
            : _loadError != null
                ? Center(
                    child: SingleChildScrollView(
                      child: EmptyMessage(
                        icon: Icons.directions_bus_outlined,
                        title: 'Data bus belum tersedia',
                        message: _loadError!,
                        action: FilledButton.icon(
                            onPressed: _loadBusData,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Coba lagi')),
                      ),
                    ),
                  )
                : ContentWidth(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Siapkan bus Anda',
                                style:
                                    Theme.of(context).textTheme.headlineMedium),
                            const SizedBox(height: 8),
                            const Text(
                                'Lengkapi data 6 bus, lalu pilih satu bus yang digunakan di perangkat ini.',
                                style: TextStyle(color: AppColors.muted)),
                            if (widget.forceSetup) ...[
                              const SizedBox(height: 8),
                              const Text(
                                  'Simpan pengaturan ini sebelum membuat laporan.'),
                            ],
                            const SizedBox(height: 24),
                            SectionCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const StatusPill(
                                      label: 'Bus perangkat ini',
                                      icon: Icons.check_circle_outline,
                                      color: AppColors.brand,
                                      background: AppColors.dangerSoft),
                                  const SizedBox(height: 12),
                                  Text(
                                      name.isEmpty
                                          ? 'Bus ${_selectedBusIndex + 1}'
                                          : name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge),
                                  const SizedBox(height: 4),
                                  Text(
                                      plate.isEmpty
                                          ? 'Nomor polisi belum diisi'
                                          : plate,
                                      style: const TextStyle(
                                          color: AppColors.muted)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            const SectionHeading(
                                title: 'Daftar bus',
                                subtitle:
                                    'Semua nama dan nomor polisi wajib diisi.'),
                            // Keep all fields mounted so validation includes all six slots.
                            for (int i = 0; i < 6; i++) _busCard(i),
                          ],
                        ),
                      ),
                    ),
                  ),
        bottomNavigationBar: BottomActionBar(
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isLoading || _isSaving || _loadError != null
                  ? null
                  : _saveData,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_rounded),
              label: Text(_isSaving
                  ? 'Menyimpan…'
                  : widget.forceSetup
                      ? 'Simpan & lanjutkan'
                      : 'Simpan pengaturan'),
            ),
          ),
        ),
      ),
    );
  }
}
