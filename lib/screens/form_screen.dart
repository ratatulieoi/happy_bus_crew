import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';

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

  late List<LineItem> _pendapatan;
  late List<LineItem> _pengeluaran;

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
    _pendapatan = List<LineItem>.from(r?.pendapatan ?? [LineItem(keterangan: '', jumlah: 0)]);
    _pengeluaran = List<LineItem>.from(r?.pengeluaran ?? [LineItem(keterangan: '', jumlah: 0)]);
  }

  @override
  void dispose() {
    for (final c in [
      _berangkat, _jam, _kembali, _polisi, _pengemudi,
      _kernet, _kmAwal, _kmAkhir, _namaCrew,
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
            _text(_berangkat, 'Hari/Tgl Berangkat', hint: 'mis. Senin, 01/01/2024'),
            _text(_jam, 'Jam Berangkat', hint: 'mis. 08:00', keyboardType: TextInputType.datetime),
            _text(_kembali, 'Hari/Tgl Kembali', hint: 'mis. Rabu, 03/01/2024'),
            _text(_polisi, 'No. Polisi', hint: 'mis. B 1234 XX'),
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
            _sectionTitle('A. Rincian Pendapatan'),
            _itemEditor(_pendapatan),
            _totalChip('Total Pendapatan', _sum(_pendapatan)),
            const SizedBox(height: 12),
            _sectionTitle('B. Rincian Pengeluaran'),
            _itemEditor(_pengeluaran),
            _totalChip('Total Pengeluaran', _sum(_pengeluaran)),
            const SizedBox(height: 8),
            _selisihCard(),
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
      {String? hint, TextInputType? keyboardType, bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: c,
        keyboardType: keyboardType,
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

  Widget _itemEditor(List<LineItem> list) {
    return Column(
      children: [
        for (int i = 0; i < list.length; i++) ...[
          _itemRow(list, i),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Tambah Baris'),
            onPressed: () => setState(() =>
                list.add(LineItem(keterangan: '', jumlah: 0))),
          ),
        ),
      ],
    );
  }

  Widget _itemRow(List<LineItem> list, int i) {
    final item = list[i];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: TextFormField(
            initialValue: item.keterangan,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Keterangan',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => item.keterangan = v,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextFormField(
            initialValue: item.jumlah == 0 ? '' : formatNumberId(item.jumlah),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Jumlah (Rp)',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              item.jumlah = parseRupiahInput(v);
              setState(() {});
            },
          ),
        ),
        IconButton(
          tooltip: 'Hapus baris',
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: list.length <= 1
              ? null
              : () => setState(() => list.removeAt(i)),
        ),
      ],
    );
  }

  Widget _totalChip(String label, int total) => Align(
        alignment: Alignment.centerRight,
        child: Chip(
          label: Text('$label: ${formatRupiah(total)}'),
          backgroundColor: Colors.grey.shade200,
        ),
      );

  Widget _selisihCard() {
    final p = _sum(_pendapatan);
    final k = _sum(_pengeluaran);
    final s = p - k;
    final positif = s >= 0;
    return Card(
      color: positif ? Colors.green.shade50 : Colors.red.shade50,
      child: ListTile(
        title: Text(positif ? 'SISA (SURPLUS)' : 'DEFISIT'),
        trailing: Text(
          formatRupiah(s),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- actions
  int _sum(List<LineItem> l) => l.fold(0, (s, e) => s + e.jumlah);

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
      pendapatan: _pendapatan.where((e) => e.keterangan.isNotEmpty || e.jumlah > 0).toList(),
      pengeluaran: _pengeluaran.where((e) => e.keterangan.isNotEmpty || e.jumlah > 0).toList(),
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

  Future<void> _onPreview() async {
    // Pratinjau langsung tanpa wajib menyimpan.
    final r = _buildReport();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PreviewScreen(report: r)),
    );
  }
}
