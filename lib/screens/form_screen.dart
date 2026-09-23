import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../db/database.dart';
import '../models/report.dart';
import '../services/report_storage.dart';
import '../ui/app_theme.dart';
import '../ui/components.dart';
import '../utils/format.dart';
import 'preview_screen.dart';

class FormScreen extends StatefulWidget {
  final Report? report;
  const FormScreen({super.key, this.report});

  @override
  State<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends State<FormScreen> {
  final _scroll = ScrollController();
  final _picker = ImagePicker();
  late final TextEditingController _berangkat;
  late final TextEditingController _jam;
  late final TextEditingController _kembali;
  late final TextEditingController _polisi;
  late final TextEditingController _pengemudi;
  late final TextEditingController _kernet;
  late final TextEditingController _kmAwal;
  late final TextEditingController _kmAkhir;
  late final TextEditingController _namaCrew;
  late final TextEditingController _catatan;
  late final TextEditingController _uangSaku;
  late final TextEditingController _bbm;
  late final TextEditingController _uangMakan;
  late final TextEditingController _pembayaranTagihan;
  final List<TextEditingController> _extraNames = [];
  final List<TextEditingController> _extraAmounts = [];
  String? _extraError;
  late final TextEditingController _luarKotaCount;
  late final TextEditingController _dalamKotaCount;
  final List<File> _attachments = [];
  List<String> _initialValues = [];
  List<String> _initialAttachments = [];
  bool _loading = true;
  bool _saving = false;
  bool _previewing = false;
  bool _picking = false;
  bool _allowPop = false;
  String? _loadError;
  int _step = 0;
  bool get _isEdit => widget.report != null;
  bool get _busy => _saving || _previewing || _picking;
  List<TextEditingController> get _controllers => [
        _berangkat,
        _jam,
        _kembali,
        _polisi,
        _pengemudi,
        _kernet,
        _luarKotaCount,
        _dalamKotaCount,
        _kmAwal,
        _kmAkhir,
        _namaCrew,
        _catatan,
        _uangSaku,
        _bbm,
        _uangMakan,
        _pembayaranTagihan,
        ..._extraNames,
        ..._extraAmounts,
      ];
  bool get _dirty =>
      !_loading &&
      _loadError == null &&
      (!_same(_initialValues, _controllers.map((c) => c.text).toList()) ||
          !_same(
              _initialAttachments, _attachments.map((f) => f.path).toList()));

  bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    final r = widget.report;
    _luarKotaCount =
        TextEditingController(text: r?.luarKotaCount?.toString() ?? '');
    _dalamKotaCount =
        TextEditingController(text: r?.dalamKotaCount?.toString() ?? '');
    String amount(int? value) =>
        value == null || value == 0 ? '' : formatNumberId(value);
    _berangkat = TextEditingController(text: r?.hariTglBerangkat ?? '');
    _jam = TextEditingController(text: r?.jamBerangkat ?? '');
    _kembali = TextEditingController(text: r?.hariTglKembali ?? '');
    _polisi = TextEditingController(text: r?.noPolisi ?? '');
    _pengemudi = TextEditingController(text: r?.pengemudi ?? '');
    _kernet = TextEditingController(text: r?.kernet ?? '');
    _kmAwal =
        TextEditingController(text: r == null ? '' : formatNumberId(r.kmAwal));
    _kmAkhir =
        TextEditingController(text: r == null ? '' : formatNumberId(r.kmAkhir));
    _namaCrew = TextEditingController(text: r?.namaCrew ?? '');
    _catatan = TextEditingController(text: r?.catatan ?? '');
    _uangSaku = TextEditingController(text: amount(r?.uangSaku));
    _bbm = TextEditingController(text: amount(r?.bbm));
    _uangMakan = TextEditingController(text: amount(r?.uangMakan));
    _pembayaranTagihan =
        TextEditingController(text: amount(r?.pembayaranTagihan));
    if (r != null) {
      for (final item in r.extras) {
        _extraNames.add(TextEditingController(text: item.name));
        _extraAmounts.add(TextEditingController(text: amount(item.amount)));
      }
    }
    for (final c in _controllers) {
      c.addListener(_changed);
    }
    _loadInitialData();
  }

  void _changed() {
    if (mounted && !_loading) {
      setState(() => _extraError = null);
    }
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final db = DatabaseHelper.instance;
      final files = <File>[];
      if (_isEdit && widget.report!.id != null) {
        for (final path in await db.getAttachments(widget.report!.id!)) {
          final file = File(path);
          if (await file.exists()) files.add(file);
        }
      } else if (!_isEdit) {
        final bus = await db.getSelectedBus();
        if (bus == null) throw StateError('Tambahkan bus terlebih dahulu.');
        if (!mounted) return;
        _polisi.text = bus.plate;
      }
      if (!mounted) return;
      _attachments
        ..clear()
        ..addAll(files);
      _initialValues = _controllers.map((c) => c.text).toList();
      _initialAttachments = _attachments.map((f) => f.path).toList();
      setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError =
              'Data bus atau lampiran belum dapat dimuat. Coba lagi sebelum mengubah laporan.';
        });
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.removeListener(_changed);
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    if (_busy) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                title: const Text('Keluar tanpa menyimpan?'),
                content: const Text(
                    'Perubahan pada laporan ini belum disimpan. Kembali ke formulir untuk melanjutkan.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Lanjut mengisi')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Keluar'))
                ],
              ));
      if (discard != true || !mounted) return;
    }
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  void _goToStep(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _allowPop || (!_dirty && !_busy),
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _leave();
        },
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
                onPressed: _busy ? null : _leave,
                tooltip: 'Kembali',
                icon: const Icon(Icons.arrow_back_rounded)),
            title: Text(_isEdit ? 'Ubah laporan' : 'Laporan baru'),
            actions: [
              IconButton(
                  onPressed: _loading || _busy || _loadError != null
                      ? null
                      : _onPreview,
                  tooltip: 'Pratinjau PDF tanpa menyimpan',
                  icon: const Icon(Icons.picture_as_pdf_outlined)),
              const SizedBox(width: 8)
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
                  ? Center(
                      child: EmptyMessage(
                          icon: Icons.error_outline,
                          title: 'Data belum siap',
                          message: _loadError!,
                          action: FilledButton(
                              onPressed: _loadInitialData,
                              child: const Text('Coba lagi'))))
                  : AbsorbPointer(
                      absorbing: _busy,
                      child: ContentWidth(
                          child: ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                        children: [
                          _stepNavigation(),
                          const SizedBox(height: 24),
                          Text(
                              [
                                'Detail perjalanan',
                                'Keuangan perjalanan',
                                'Lengkapi laporan'
                              ][_step],
                              style:
                                  Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 6),
                          Text(
                              [
                                'Isi jadwal, nama crew, dan kilometer bus.',
                                'Catat uang saku dan rincian pengeluaran.',
                                'Tambahkan nama pembuat, catatan, dan lampiran.'
                              ][_step],
                              style: const TextStyle(color: AppColors.muted)),
                          const SizedBox(height: 24),
                          if (_step == 0) ..._tripFields(),
                          if (_step == 1) ..._financeFields(),
                          if (_step == 2) ..._completionFields(),
                        ],
                      ))),
          bottomNavigationBar: _loading || _loadError != null
              ? null
              : BottomActionBar(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_step == 2) ...[
                    const Text('Laporan disimpan di perangkat ini.',
                        style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    const SizedBox(height: 10),
                  ],
                  Row(children: [
                    if (_step > 0) ...[
                      OutlinedButton(
                          onPressed: _busy ? null : () => _goToStep(_step - 1),
                          child: const Text('Kembali')),
                      const SizedBox(width: 12)
                    ],
                    Expanded(
                        child: FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : _step < 2
                              ? _nextStep
                              : _onSave,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(
                              _step < 2
                                  ? Icons.arrow_forward_rounded
                                  : Icons.check_rounded,
                              size: 20),
                      label: Text(_saving
                          ? 'Menyimpan…'
                          : _step < 2
                              ? 'Lanjut'
                              : 'Simpan laporan'),
                    )),
                  ]),
                ])),
        ),
      );

  Widget _stepNavigation() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('LANGKAH ${_step + 1} DARI 3',
            style: const TextStyle(
                fontSize: 11,
                letterSpacing: 1.3,
                color: AppColors.muted,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final entry
              in ['Perjalanan', 'Keuangan', 'Lampiran'].asMap().entries)
            ChoiceChip(
                label: Text('${entry.key + 1}. ${entry.value}'),
                selected: _step == entry.key,
                showCheckmark: false,
                onSelected: (_) => _goToStep(entry.key)),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
                value: (_step + 1) / 3,
                minHeight: 4,
                backgroundColor: AppColors.border)),
      ]);

  List<Widget> _tripFields() => [
        SectionCard(
            child: Column(children: [
          const SectionHeading(
              title: 'Bus & jadwal',
              subtitle: 'Nomor polisi mengikuti bus yang dipilih.',
              icon: Icons.route_outlined),
          _text(_polisi, 'Nomor polisi',
              readOnly: true,
              suffixIcon: const Icon(Icons.lock_outline, size: 18)),
          const SizedBox(height: 16),
          _tripCountFields(),
          const SizedBox(height: 16),
          _dateField(_berangkat, 'Tanggal berangkat'),
          const SizedBox(height: 16),
          _dateField(_kembali, 'Tanggal kembali'),
          if (_dateOrderWarning) ...[
            const SizedBox(height: 12),
            _notice(
                'Tanggal kembali lebih awal dari keberangkatan. Periksa kembali jadwalnya.')
          ],
          const SizedBox(height: 16),
          _text(_jam, 'Jam berangkat',
              hint: '08:00',
              keyboardType: TextInputType.datetime,
              suffixIcon: IconButton(
                  onPressed: _pickTime,
                  tooltip: 'Pilih jam berangkat',
                  icon: const Icon(Icons.schedule_rounded, size: 20))),
        ])),
        const SizedBox(height: 16),
        SectionCard(
            child: Column(children: [
          const SectionHeading(
              title: 'Crew bertugas', icon: Icons.people_outline_rounded),
          _text(_pengemudi, 'Nama pengemudi', hint: 'Nama sopir'),
          const SizedBox(height: 16),
          _text(_kernet, 'Nama kernet', hint: 'Nama asisten pengemudi'),
        ])),
        const SizedBox(height: 16),
        SectionCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeading(
              title: 'Kilometer',
              subtitle: 'Isi KM awal dan KM akhir secara manual untuk laporan ini.',
              icon: Icons.speed_rounded),
          AdaptivePair(
              first: _numberField(_kmAwal, 'KM awal', money: false),
              second: _numberField(_kmAkhir, 'KM akhir', money: false)),
        ])),
      ];

  Widget _tripCountFields() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Jumlah perjalanan',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Opsional. Isi jumlah LK dan DK jika diperlukan.',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 16),
          AdaptivePair(
            first: _countField(_luarKotaCount, 'Luar Kota (LK)'),
            second: _countField(_dalamKotaCount, 'Dalam Kota (DK)'),
          ),
          if (_isEdit && !widget.report!.hasTripCounts)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  widget.report!.tripType == TripType.unspecified
                      ? 'Jumlah perjalanan belum dicatat pada laporan lama.'
                      : 'Data lama: ${widget.report!.tripType.label}. Jumlah perjalanan belum dicatat.',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ),
        ],
      );

  Widget _countField(TextEditingController controller, String label) =>
      TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        inputFormatters: [
          TextInputFormatter.withFunction((oldValue, newValue) =>
              RegExp(r'^[0-9]*$').hasMatch(newValue.text) ? newValue : oldValue),
        ],
        decoration: InputDecoration(labelText: label, hintText: '0'),
      );

  List<Widget> _financeFields() => [
        SectionCard(
            child: Column(children: [
          const SectionHeading(
              title: 'Uang diterima',
              subtitle: 'Uang saku yang diberikan untuk perjalanan.',
              icon: Icons.account_balance_wallet_outlined),
          _numberField(_uangSaku, 'Uang saku'),
        ])),
        const SizedBox(height: 16),
        SectionCard(
            child: Column(children: [
          const SectionHeading(
              title: 'Rincian pengeluaran',
              subtitle: 'Biarkan kosong jika tidak ada pengeluaran.',
              icon: Icons.receipt_long_outlined),
          _numberField(_bbm, 'BBM'),
          const SizedBox(height: 16),
          _numberField(_uangMakan, 'Uang makan'),
          const SizedBox(height: 16),
          ..._extraFields(),
        ])),
        const SizedBox(height: 16),
        SectionCard(
            child: Column(children: [
          const SectionHeading(
              title: 'Pembayaran tagihan',
              subtitle:
                  'Uang tunai dari klien untuk biaya bus yang dibayarkan kepada crew. Tidak masuk hitungan pengeluaran atau sisa uang saku.',
              icon: Icons.payments_outlined),
          _numberField(_pembayaranTagihan, 'Pembayaran tagihan'),
        ])),
        const SizedBox(height: 16),
        _balanceCard(),
      ];

  List<Widget> _completionFields() => [
        SectionCard(
            child: Column(children: [
          const SectionHeading(
              title: 'Pembuat laporan',
              subtitle: 'Nama ini dicantumkan pada area tanda tangan PDF.',
              icon: Icons.draw_outlined),
          _text(_namaCrew, 'Nama crew', hint: 'Nama lengkap pembuat laporan'),
          const SizedBox(height: 16),
          _text(_catatan, 'Catatan tambahan',
              hint: 'Opsional, misalnya kendala selama perjalanan',
              maxLines: 3),
        ])),
        const SizedBox(height: 16),
        SectionCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionHeading(
              title: 'Lampiran',
              subtitle: '${_attachments.length} gambar dilampirkan.',
              icon: Icons.photo_library_outlined),
          _attachmentSection(),
        ])),
        const SizedBox(height: 16),
        _balanceCard(),
        const SizedBox(height: 16),
        OutlinedButton.icon(
            onPressed: _busy ? null : _onPreview,
            icon: _previewing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_outlined),
            label: Text(
                _previewing ? 'Menyiapkan PDF…' : 'Periksa pratinjau PDF')),
        const SizedBox(height: 8),
        const Text('Pratinjau tidak menyimpan perubahan laporan.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12)),
      ];

  Widget _text(TextEditingController controller, String label,
          {String? hint,
          bool readOnly = false,
          int maxLines = 1,
          TextInputType? keyboardType,
          Widget? suffixIcon}) =>
      TextFormField(
        controller: controller,
        readOnly: readOnly,
        maxLines: maxLines,
        keyboardType: keyboardType,
        textCapitalization: keyboardType == null
            ? TextCapitalization.words
            : TextCapitalization.none,
        textInputAction:
            maxLines > 1 ? TextInputAction.newline : TextInputAction.next,
        decoration: InputDecoration(
            labelText: label, hintText: hint, suffixIcon: suffixIcon),
      );

  Widget _numberField(TextEditingController controller, String label,
          {bool money = true}) =>
      TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        inputFormatters: [ThousandsSeparatorFormatter()],
        decoration: InputDecoration(
            labelText: label,
            hintText: '0',
            prefixText: money ? 'Rp ' : null,
            suffixText: money ? null : 'km'),
      );

  DateTime? _parseDate(String value) {
    try {
      return DateFormat('EEEE, dd/MM/yyyy', 'id_ID').parseStrict(value);
    } catch (_) {
      return null;
    }
  }

  bool get _dateOrderWarning {
    final departure = _parseDate(_berangkat.text);
    final returning = _parseDate(_kembali.text);
    return departure != null &&
        returning != null &&
        returning.isBefore(departure);
  }

  Widget _dateField(TextEditingController controller, String label) =>
      TextFormField(
        controller: controller,
        readOnly: true,
        decoration: InputDecoration(
            labelText: label,
            hintText: 'Pilih tanggal',
            suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20)),
        onTap: () async {
          final now = DateTime.now();
          final selected = _parseDate(controller.text) ?? now;
          final picked = await showDatePicker(
              context: context,
              initialDate: selected,
              firstDate: DateTime(selected.year < 2020 ? selected.year : 2020),
              lastDate: DateTime(
                  selected.year > now.year + 10 ? selected.year : now.year + 10,
                  12,
                  31),
              locale: const Locale('id', 'ID'));
          if (picked != null && mounted) {
            controller.text =
                DateFormat('EEEE, dd/MM/yyyy', 'id_ID').format(picked);
          }
        },
      );

  Future<void> _pickTime() async {
    final parts = _jam.text.split(':');
    final hour = int.tryParse(parts.first) ?? 8;
    final minute = parts.length == 2 ? int.tryParse(parts.last) ?? 0 : 0;
    final picked = await showTimePicker(
        context: context,
        initialTime:
            TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59)),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!));
    if (picked != null && mounted) {
      _jam.text =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    }
  }

  Widget _notice(String message) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppColors.warningSoft,
            borderRadius: BorderRadius.circular(10)),
        child: Text(message,
            style: const TextStyle(color: AppColors.warning, fontSize: 13)),
      );

  Widget _summaryRow(String label, String value) => Wrap(
        spacing: 16,
        runSpacing: 4,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700))
        ],
      );

  Widget _balanceCard() {
    final report = _buildReport();
    final deficit = report.sisa < 0;
    final color = deficit ? AppColors.danger : AppColors.success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: deficit ? AppColors.dangerSoft : AppColors.successSoft,
          borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _summaryRow('Uang saku', formatRupiah(report.uangSaku)),
        const SizedBox(height: 8),
        _summaryRow('Total pengeluaran', formatRupiah(report.totalPengeluaran)),
        const Divider(height: 28),
        Text(deficit ? 'Defisit perjalanan' : 'Sisa uang perjalanan',
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(formatRupiah(report.sisa),
            style: TextStyle(
                color: color,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -.5)),
        const SizedBox(height: 6),
        Text(
            deficit
                ? 'Pengeluaran melebihi uang saku.'
                : 'Dihitung otomatis dari uang saku dan pengeluaran.',
            style: TextStyle(color: color, fontSize: 12)),
      ]),
    );
  }

  Widget _attachmentSection() => Column(children: [
        if (_attachments.isEmpty)
          Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(12)),
              child: const Column(children: [
                Icon(Icons.add_photo_alternate_outlined,
                    size: 32, color: AppColors.muted),
                SizedBox(height: 10),
                Text('Belum ada lampiran',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ]))
        else
          SizedBox(
              height: 156,
              child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _attachments.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) => SizedBox(
                      width: 128,
                      child: Stack(fit: StackFit.expand, children: [
                        ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(_attachments[i],
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const ColoredBox(
                                    color: AppColors.canvas,
                                    child: Center(
                                        child: Icon(
                                            Icons.broken_image_outlined))))),
                        Positioned(
                            bottom: 8,
                            left: 8,
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                    color: AppColors.ink,
                                    borderRadius: BorderRadius.circular(6)),
                                child: Text('Lampiran ${i + 1}',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 11)))),
                        Positioned(
                            top: 0,
                            right: 0,
                            child: IconButton.filled(
                                tooltip: 'Hapus lampiran ${i + 1}',
                                style: IconButton.styleFrom(
                                    backgroundColor: AppColors.ink,
                                    foregroundColor: Colors.white),
                                onPressed: () =>
                                    setState(() => _attachments.removeAt(i)),
                                icon:
                                    const Icon(Icons.close_rounded, size: 18))),
                      ])))),
        const SizedBox(height: 16),
        AdaptivePair(
            first: OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined, size: 20),
                label: const Text('Kamera')),
            second: OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined, size: 20),
                label: const Text('Galeri'))),
        if (_picking)
          const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator()),
      ]);

  Future<void> _pickImage(ImageSource source) async {
    if (_busy) return;
    setState(() => _picking = true);
    try {
      final List<XFile> picked;
      if (source == ImageSource.gallery) {
        picked = await _picker.pickMultiImage(imageQuality: 85);
      } else {
        final image = await _picker.pickImage(source: source, imageQuality: 85);
        picked = image == null ? [] : [image];
      }
      if (mounted) {
        setState(
            () => _attachments.addAll(picked.map((image) => File(image.path))));
      }
    } catch (_) {
      if (mounted) {
        showAppMessage(context,
            'Foto belum dapat diambil. Periksa izin kamera atau galeri.');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  List<Widget> _extraFields() => [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Extra',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 4),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
              'Tulis nama dan harga setiap pengeluaran extra. Semua harga dijumlahkan ke total.',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _extraNames.length; i++) ...[
          Container(
            key: ObjectKey(_extraNames[i]),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              _text(_extraNames[i], 'Nama extra ${i + 1}',
                  hint: 'Misalnya parkir, tol, atau cuci bus'),
              const SizedBox(height: 12),
              _numberField(_extraAmounts[i], 'Harga extra ${i + 1}'),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _busy ? null : () => _removeExtra(i),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Hapus'),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        if (_extraError != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Text(_extraError!,
                style: const TextStyle(color: AppColors.danger, fontSize: 12)),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: _busy ? null : _addExtra,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Tambah Extra'),
        ),
      ];

  void _addExtra() {
    final name = TextEditingController();
    final amount = TextEditingController();
    name.addListener(_changed);
    amount.addListener(_changed);
    setState(() {
      _extraNames.add(name);
      _extraAmounts.add(amount);
      _extraError = null;
    });
  }

  void _removeExtra(int index) {
    FocusScope.of(context).unfocus();
    final name = _extraNames[index];
    final amount = _extraAmounts[index];
    name.removeListener(_changed);
    amount.removeListener(_changed);
    setState(() {
      _extraNames.removeAt(index);
      _extraAmounts.removeAt(index);
      _extraError = null;
    });
    // Wait until the removed fields have unmounted before disposing controllers.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      name.dispose();
      amount.dispose();
    });
  }

  void _nextStep() {
    if (_step == 1 && !_validateExtras()) {
      showAppMessage(context, _extraError!);
      return;
    }
    _goToStep(_step + 1);
  }

  /// Each added extra row must carry both a name and a positive price.
  bool _validateExtras() {
    for (var i = 0; i < _extraNames.length; i++) {
      final name = _extraNames[i].text.trim();
      final amount = parseRupiahInput(_extraAmounts[i].text);
      final row = i + 1;
      if (name.isEmpty && _extraAmounts[i].text.trim().isEmpty) {
        setState(() => _extraError = 'Extra $row belum diisi. '
            'Isi nama dan harga, atau hapus barisnya.');
        return false;
      }
      if (name.isEmpty) {
        setState(() =>
            _extraError = 'Isi nama untuk extra $row, misalnya parkir.');
        return false;
      }
      if (amount <= 0) {
        setState(() =>
            _extraError = 'Isi harga untuk "$name" lebih dari Rp 0.');
        return false;
      }
    }
    setState(() => _extraError = null);
    return true;
  }

  Report _buildReport() => Report(
        id: widget.report?.id,
        tanggalBuat: widget.report?.tanggalBuat ?? DateTime.now(),
        hariTglBerangkat: _berangkat.text.trim(),
        jamBerangkat: _jam.text.trim(),
        hariTglKembali: _kembali.text.trim(),
        noPolisi: _polisi.text.trim(),
        pengemudi: _pengemudi.text.trim(),
        kernet: _kernet.text.trim(),
        tripType: widget.report?.tripType ?? TripType.unspecified,
        luarKotaCount: int.tryParse(_luarKotaCount.text),
        dalamKotaCount: int.tryParse(_dalamKotaCount.text),
        kmAwal: parseRupiahInput(_kmAwal.text),
        kmAkhir: parseRupiahInput(_kmAkhir.text),
        uangSaku: parseRupiahInput(_uangSaku.text),
        bbm: parseRupiahInput(_bbm.text),
        uangMakan: parseRupiahInput(_uangMakan.text),
        pembayaranTagihan: parseRupiahInput(_pembayaranTagihan.text),
        namaCrew: _namaCrew.text.trim(),
        catatan: _catatan.text.trim(),
        extras: [
          for (var i = 0; i < _extraNames.length; i++)
            ExtraExpense(
                name: _extraNames[i].text.trim(),
                amount: parseRupiahInput(_extraAmounts[i].text)),
        ],
      );

  Future<void> _onSave() async {
    if (_busy || _loading) return;
    FocusScope.of(context).unfocus();
    if (!_validateExtras()) {
      _goToStep(1);
      showAppMessage(context, _extraError!);
      return;
    }
    setState(() => _saving = true);
    try {
      await ReportStorage.save(_buildReport(), List<File>.of(_attachments));
      if (!mounted) return;
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        showAppMessage(context,
            'Laporan gagal disimpan. Isian Anda tetap ada, silakan coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onPreview() async {
    if (_busy || _loading) return;
    FocusScope.of(context).unfocus();
    if (!_validateExtras()) {
      _goToStep(1);
      showAppMessage(context, _extraError!);
      return;
    }
    setState(() => _previewing = true);
    try {
      final report = _buildReport();
      final images = <Uint8List>[];
      for (final file in _attachments) {
        images.add(await file.readAsBytes());
      }
      if (!mounted) return;
      await Navigator.push<void>(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  PreviewScreen(report: report, attachmentImages: images)));
    } catch (_) {
      if (mounted) {
        showAppMessage(context,
            'Pratinjau belum dapat dibuat. Periksa lampiran lalu coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }
}

/// Keeps the caret beside the edited digits, including edits in the middle.
class ThousandsSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    final formatted = buffer.toString();
    final end = newValue.selection.extentOffset.clamp(0, newValue.text.length);
    final digitsBefore = newValue.text
        .substring(0, end)
        .replaceAll(RegExp(r'[^0-9]'), '')
        .length;
    var offset = 0;
    var count = 0;
    while (offset < formatted.length && count < digitsBefore) {
      if (formatted[offset] != '.') count++;
      offset++;
    }
    return TextEditingValue(
        text: formatted, selection: TextSelection.collapsed(offset: offset));
  }
}
