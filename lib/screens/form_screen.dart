import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';

import '../db/database.dart';
import '../models/report.dart';
import '../utils/format.dart';
import 'preview_screen.dart';

/// Form input untuk seluruh field laporan. Bila [report] diberikan,
/// berarti mode edit; jika tidak, mode tambah.
class FormScreen extends StatefulWidget {
  final Report? report;
  const FormScreen({super.key, this.report});

  @override
  State<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends State<FormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _berangkat;
  late final TextEditingController _jam;
  late final TextEditingController _kembali;
  late final TextEditingController _polisi;
  late final TextEditingController _pengemudi;
  late final TextEditingController _kernet;
  late final TextEditingController _kmAwal;
  late final TextEditingController _kmAkhir;
  late final TextEditingController _namaCrew;

  // Keuangan
  late final TextEditingController _uangSaku;
  late final TextEditingController _bbm;
  late final TextEditingController _uangMakan;
  late final TextEditingController _extra;
  late final TextEditingController _tagihan;

  // Tanggal yang dipilih via date picker
  DateTime? _tglBerangkat;
  DateTime? _tglKembali;

  bool _saving = false;
  bool get _isEdit => widget.report != null;

  @override
  void initState() {
    super.initState();
    final r = widget.report;
    _berangkat = TextEditingController(text: r?.hariTglBerangkat ?? '');
    _jam = TextEditingController(text: r?.jamBerangkat ?? '');
    _kembali = TextEditingController(text: r?.hariTglKembali ?? '');
    _polisi = TextEditingController(text: r?.noPolisi ?? '');
    _pengemudi = TextEditingController(text: r?.pengemudi ?? '');
    _kernet = TextEditingController(text: r?.kernet ?? '');
    _kmAwal = TextEditingController(text: r == null ? '' : formatNumberId(r.kmAwal));
    _kmAkhir = TextEditingController(text: r == null ? '' : formatNumberId(r.kmAkhir));
    _namaCrew = TextEditingController(text: r?.namaCrew ?? '');
    _uangSaku = TextEditingController(text: r == null || r.uangSaku == 0 ? '' : formatNumberId(r.uangSaku));
    _bbm = TextEditingController(text: r == null || r.bbm == 0 ? '' : formatNumberId(r.bbm));
    _uangMakan = TextEditingController(text: r == null || r.uangMakan == 0 ? '' : formatNumberId(r.uangMakan));
    _extra = TextEditingController(text: r == null || r.extra == 0 ? '' : formatNumberId(r.extra));
    _tagihan = TextEditingController(text: r == null || r.tagihan == 0 ? '' : formatNumberId(r.tagihan));
    _loadBusInfo();
  }

  @override
  void dispose() {
    for (final c in [
      _berangkat, _jam, _kembali, _polisi, _pengemudi,
      _kernet, _kmAwal, _kmAkhir, _namaCrew,
      _uangSaku, _bbm, _uangMakan, _extra, _tagihan,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Ubah Laporan' : 'Buat Laporan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Pratinjau PDF',
            onPressed: _onPreview,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('Informasi Perjalanan'),
            _datePicker(
              controller: _berangkat,
              label: 'Hari/Tgl Berangkat',
              selectedDate: _tglBerangkat,
              onDateSelected: (d) => setState(() {
                _tglBerangkat = d;
                _berangkat.text = DateFormat('EEEE, dd/MM/yyyy', 'id_ID').format(d);
              }),
            ),
            _text(_jam, 'Jam Berangkat', hint: 'mis. 08:00', keyboardType: TextInputType.datetime),
            _datePicker(
              controller: _kembali,
              label: 'Hari/Tgl Kembali',
              selectedDate: _tglKembali,
              onDateSelected: (d) => setState(() {
                _tglKembali = d;
                _kembali.text = DateFormat('EEEE, dd/MM/yyyy', 'id_ID').format(d);
              }),
            ),
            _text(_polisi, 'No. Polisi', hint: 'mis. B 1234 XX', readOnly: true),
            _text(_pengemudi, 'Pengemudi', hint: 'Nama sopir'),
            _text(_kernet, 'Kernet', hint: 'Nama kernet/asisten'),
            const SizedBox(height: 8),
            _sectionTitle('Kilometer'),
            Row(
              children: [
                Expanded(child: _rupiahField(_kmAwal, 'KM Awal')),
                const SizedBox(width: 12),
                Expanded(child: _rupiahField(_kmAkhir, 'KM Akhir')),
              ],
            ),
            const SizedBox(height: 16),
            _sectionTitle('Keuangan'),
            _rupiahField(_uangSaku, 'Uang Saku'),
            _rupiahField(_bbm, 'BBM'),
            _rupiahField(_uangMakan, 'Uang Makan'),
            _rupiahField(_extra, 'Extra'),
            _rupiahField(_tagihan, 'Tagihan'),
            const SizedBox(height: 8),
            _sisaCard(),
            const SizedBox(height: 16),
            _sectionTitle('Tanda Tangan'),
            _text(_namaCrew, 'Nama Crew (Pembuat Laporan)', hint: 'Nama lengkap'),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.save_outlined),
              label: Text(_isEdit ? 'Simpan Perubahan' : 'Simpan Laporan'),
              onPressed: _saving ? null : _onSave,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Pratinjau PDF'),
              onPressed: _onPreview,
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ builders
  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      );

  Widget _text(TextEditingController c, String label,
      {String? hint, TextInputType? keyboardType, bool required = false, bool readOnly = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: c,
        keyboardType: keyboardType,
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        validator: (v) => required && (v == null || v.trim().isEmpty)
            ? '$label wajib diisi'
            : null,
      ),
    );
  }

  /// Date picker field — taps open a calendar.
  Widget _datePicker({
    required TextEditingController controller,
    required String label,
    required DateTime? selectedDate,
    required ValueChanged<DateTime> onDateSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          hintText: 'Pilih tanggal',
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today),
        ),
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: selectedDate ?? now,
            firstDate: DateTime(2020),
            lastDate: DateTime(2030),
            locale: const Locale('id', 'ID'),
          );
          if (picked != null) {
            onDateSelected(picked);
          }
        },
      ),
    );
  }

  /// Field angka yang otomatis memformat dengan pemisah ribuan.
  Widget _rupiahField(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _sisaCard() {
    final uangSaku = parseRupiahInput(_uangSaku.text);
    final pengeluaran = parseRupiahInput(_bbm.text) +
        parseRupiahInput(_uangMakan.text) +
        parseRupiahInput(_extra.text) +
        parseRupiahInput(_tagihan.text);
    final sisa = uangSaku - pengeluaran;
    final positif = sisa >= 0;
    return Card(
      color: positif ? Colors.green.shade50 : Colors.red.shade50,
      child: ListTile(
        title: Text(positif ? 'SISA' : 'DEFISIT'),
        trailing: Text(
          formatRupiah(sisa),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- actions
  Report _buildReport() {
    return Report(
      id: widget.report?.id,
      tanggalBuat: widget.report?.tanggalBuat ?? DateTime.now(),
      hariTglBerangkat: _berangkat.text.trim(),
      jamBerangkat: _jam.text.trim(),
      hariTglKembali: _kembali.text.trim(),
      noPolisi: _polisi.text.trim(),
      pengemudi: _pengemudi.text.trim(),
      kernet: _kernet.text.trim(),
      kmAwal: parseRupiahInput(_kmAwal.text),
      kmAkhir: parseRupiahInput(_kmAkhir.text),
      uangSaku: parseRupiahInput(_uangSaku.text),
      bbm: parseRupiahInput(_bbm.text),
      uangMakan: parseRupiahInput(_uangMakan.text),
      extra: parseRupiahInput(_extra.text),
      tagihan: parseRupiahInput(_tagihan.text),
      namaCrew: _namaCrew.text.trim(),
    );
  }

  Future<void> _onSave() async {
    setState(() => _saving = true);
    try {
      final r = _buildReport();
      if (_isEdit) {
        await DatabaseHelper.instance.updateReport(r);
      } else {
        await DatabaseHelper.instance.insertReport(r);
      }
      Fluttertoast.showToast(msg: 'Laporan tersimpan');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      Fluttertoast.showToast(msg: 'Gagal menyimpan: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadBusInfo() async {
    if (!_isEdit) {
      final db = DatabaseHelper.instance;
      final selectedIndexStr = await db.getSetting('selected_bus_index');
      if (selectedIndexStr != null) {
        final index = int.parse(selectedIndexStr);
        final plate = await db.getSetting('bus_${index}_plate');
        if (plate != null && mounted) {
          setState(() {
            _polisi.text = plate;
          });
          final latestKm = await db.getLatestKmForPlate(plate);
          if (latestKm > 0 && mounted) {
            setState(() {
              _kmAwal.text = formatNumberId(latestKm);
            });
          }
        }
      }
    }
  }

  Future<void> _onPreview() async {
    // Pratinjau langsung tanpa wajib menyimpan.
    final r = _buildReport();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PreviewScreen(report: r)),
    );
  }
}
