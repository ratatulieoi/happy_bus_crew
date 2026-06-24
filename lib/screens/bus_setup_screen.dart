import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../db/database.dart';

class BusSetupScreen extends StatefulWidget {
  final bool forceSetup;
  const BusSetupScreen({super.key, this.forceSetup = false});

  @override
  State<BusSetupScreen> createState() => _BusSetupScreenState();
}

class _BusSetupScreenState extends State<BusSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final List<TextEditingController> _nameControllers = [];
  final List<TextEditingController> _plateControllers = [];
  int _selectedBusIndex = 0;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Initialize 6 slots
    for (int i = 0; i < 6; i++) {
      _nameControllers.add(TextEditingController());
      _plateControllers.add(TextEditingController());
    }
    _loadBusData();
  }

  @override
  void dispose() {
    for (var c in _nameControllers) {
      c.dispose();
    }
    for (var c in _plateControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadBusData() async {
    final db = DatabaseHelper.instance;
    final selectedIndexStr = await db.getSetting('selected_bus_index');
    if (selectedIndexStr != null) {
      _selectedBusIndex = int.tryParse(selectedIndexStr) ?? 0;
    }

    for (int i = 0; i < 6; i++) {
      final name = await db.getSetting('bus_${i}_name');
      final plate = await db.getSetting('bus_${i}_plate');
      _nameControllers[i].text = name ?? 'Bus ${i + 1}';
      _plateControllers[i].text = plate ?? 'B 100${i + 1} XX';
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveData() async {
    if (!_formKey.currentState!.validate()) {
      Fluttertoast.showToast(msg: 'Mohon lengkapi semua nama dan nomor polisi bus.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final db = DatabaseHelper.instance;
      await db.setSetting('selected_bus_index', _selectedBusIndex.toString());

      for (int i = 0; i < 6; i++) {
        final name = _nameControllers[i].text.trim();
        final plate = _plateControllers[i].text.trim().toUpperCase();
        await db.setSetting('bus_${i}_name', name);
        await db.setSetting('bus_${i}_plate', plate);
      }

      // Initialize oil change KM for the newly selected bus if it doesn't exist
      final oilChangeKey = 'bus_${_selectedBusIndex}_oil_change_km';
      final currentOilChange = await db.getSetting(oilChangeKey);
      if (currentOilChange == null) {
        await db.setSetting(oilChangeKey, '0');
      }

      Fluttertoast.showToast(msg: 'Konfigurasi bus berhasil disimpan!');
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      Fluttertoast.showToast(msg: 'Gagal menyimpan: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.forceSetup,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.forceSetup ? 'Setup Awal Bus' : 'Konfigurasi Bus'),
          automaticallyImplyLeading: !widget.forceSetup,
        ),
        body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Konfigurasi Perangkat',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Isi data 6 bus utama dan pilih salah satu bus yang digunakan oleh HP ini.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: 6,
                      itemBuilder: (context, i) {
                        final isSelected = _selectedBusIndex == i;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          elevation: isSelected ? 4 : 1,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.directions_bus,
                                      color: isSelected
                                          ? Theme.of(context).colorScheme.primary
                                          : Colors.grey,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Slot Bus ${i + 1}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    Radio<int>(
                                      value: i,
                                      groupValue: _selectedBusIndex,
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() {
                                            _selectedBusIndex = val;
                                          });
                                        }
                                      },
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _selectedBusIndex = i;
                                        });
                                      },
                                      child: Text(
                                        'Pilih HP Ini',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: isSelected
                                              ? Theme.of(context).colorScheme.primary
                                              : Colors.grey[700],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: TextFormField(
                                        controller: _nameControllers[i],
                                        decoration: const InputDecoration(
                                          labelText: 'Nama Bus / Label',
                                          hintText: 'mis. Bus A',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                        validator: (v) => v == null || v.trim().isEmpty
                                            ? 'Wajib diisi'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        controller: _plateControllers[i],
                                        decoration: const InputDecoration(
                                          labelText: 'No. Polisi',
                                          hintText: 'mis. B 1234 XX',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                        textCapitalization: TextCapitalization.characters,
                                        validator: (v) => v == null || v.trim().isEmpty
                                            ? 'Wajib diisi'
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: FilledButton(
                      onPressed: _isSaving ? null : _saveData,
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Simpan & Lanjutkan'),
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}
