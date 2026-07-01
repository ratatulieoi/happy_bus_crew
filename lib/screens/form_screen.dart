import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

  // Lampiran foto struk
  final List<File> _attachments = [];
  final _picker = ImagePicker();

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
    _loadExistingAttachments();
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
            const SizedBox(height: 16),
            _sectionTitle('Lampiran Struk BBM'),
            _attachmentSection(),
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

  Widget _attachmentSection() {
    return Column(
      children: [
        if (_attachments.isNotEmpty)
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _attachments.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        _attachments[i],
                        width: 100,
                        height: 120,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => setState(() => _attachments.removeAt(i)),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Kamera'),
                onPressed: () => _pickImage(ImageSource.camera),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Galeri'),
                onPressed: () => _pickImage(ImageSource.gallery),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        final picked = await _picker.pickMultiImage(imageQuality: 85);
        if (picked.isNotEmpty) {
          setState(() {
            _attachments.addAll(picked.map((x) => File(x.path)));
          });
        }
      } else {
        final picked = await _picker.pickImage(source: source, imageQuality: 85);
        if (picked != null) {
          setState(() {
            _attachments.add(File(picked.path));
          });
        }
      }
    } catch (e) {
      Fluttertoast.showToast(msg: 'Gagal mengambil foto: $e');
    }
  }

  Future<void> _loadExistingAttachments() async {
    if (_isEdit && widget.report?.id != null) {
      final paths = await DatabaseHelper.instance.getAttachments(widget.report!.id!);
      final files = <File>[];
      for (final path in paths) {
        final f = File(path);
        if (await f.exists()) files.add(f);
      }
      if (mounted && files.isNotEmpty) {
        setState(() {
          _attachments.addAll(files);
        });
      }
    }
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
      int reportId;
      if (_isEdit) {
        await DatabaseHelper.instance.updateReport(r);
        reportId = r.id!;
        // Hapus lampiran lama, simpan ulang
        await DatabaseHelper.instance.deleteAttachments(reportId);
      } else {
        reportId = await DatabaseHelper.instance.insertReport(r);
      }
      // Simpan lampiran ke storage dan database
      final appDir = await getApplicationDocumentsDirectory();
      final attachDir = Directory(p.join(appDir.path, 'attachments', '$reportId'));
      if (!attachDir.existsSync()) attachDir.createSync(recursive: true);
      for (int i = 0; i < _attachments.length; i++) {
        final ext = p.extension(_attachments[i].path);
        final dest = File(p.join(attachDir.path, 'struk_${i + 1}$ext'));
        await _attachments[i].copy(dest.path);
        await DatabaseHelper.instance.insertAttachment(reportId, dest.path);
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
    final imgBytes = <Uint8List>[];
    for (final f in _attachments) {
      imgBytes.add(await f.readAsBytes());
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreviewScreen(
          report: r,
          attachmentImages: imgBytes,
        ),
      ),
    );
  }
}
