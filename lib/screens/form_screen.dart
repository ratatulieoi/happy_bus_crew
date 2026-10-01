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
  late final TextEditingController _jam;
  late final TextEditingController _polisi;
  late final TextEditingController _namaTamu;
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
  final List<_TripPeriodDraft> _periods = [];
  late bool _preserveLegacyTripData;
  List<String> _initialPeriods = [];
  String? _periodError;
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
        _jam,
        _polisi,
        _namaTamu,
        _pengemudi,
        _kernet,
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
          !_same(_initialPeriods, _periodValues) ||
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
    _preserveLegacyTripData = r == null || r.tripPeriods == null;
    for (final period in r?.tripPeriods ?? <TripPeriod>[]) {
      _periods.add(_TripPeriodDraft(
          start: period.start, end: period.end, type: period.type));
    }
    String amount(int? value) =>
        value == null || value == 0 ? '' : formatNumberId(value);
    _jam = TextEditingController(text: r?.jamBerangkat ?? '');
    _polisi = TextEditingController(text: r?.noPolisi ?? '');
    _namaTamu = TextEditingController(text: r?.namaTamu ?? '');
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
    // Every shared controller reports here on each keystroke. The period
    // rows keep their own controllers off this listener: recomputing the
    // overlap on every keypress would flash the error while a date is
    // half-typed, so those fields refresh it through onChanged instead.
    if (mounted && !_loading) {
      setState(() {
        _extraError = null;
      });
    }
  }

  int _periodFieldSalt = 0;

  Widget _periodDayField(int index, bool isStart) {
    final period = _periods[index];
    final label = isStart ? 'Tanggal mulai' : 'Tanggal selesai';
    return TextFormField(
      key: ValueKey('${identityHashCode(period)}-$label-$_periodFieldSalt'),
      initialValue: isStart ? _dayText(period.start) : _dayText(period.end),
      keyboardType: TextInputType.datetime,
      decoration: InputDecoration(
          labelText: label,
          hintText: 'dd/MM/yyyy',
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20)),
      onChanged: (value) => _onPeriodDayText(index, isStart, value),
      onTap: _busy ? null : () => _pickPeriodDay(index, isStart),
    );
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
      _initialPeriods = _periodValues;
      _initialAttachments = _attachments.map((f) => f.path).toList();
      setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Data bus atau lampiran gagal dimuat. Coba lagi.';
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
    for (final period in _periods) {
      period.dispose();
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
                content: const Text('Perubahan belum disimpan.'),
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
                                'Jadwal, crew, dan kilometer bus.',
                                'Uang saku dan pengeluaran.',
                                'Nama pembuat, catatan, dan lampiran.'
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
              title: 'Bus & jadwal', icon: Icons.route_outlined),
          _text(_polisi, 'Nomor polisi',
              readOnly: true,
              suffixIcon: const Icon(Icons.lock_outline, size: 18)),
          const SizedBox(height: 16),
          _text(_namaTamu, 'Nama tamu', hint: 'Nama tamu atau kelompok'),
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
        _periodFields(),
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
          const SectionHeading(title: 'Kilometer', icon: Icons.speed_rounded),
          AdaptivePair(
              first: _numberField(_kmAwal, 'KM awal', money: false),
              second: _numberField(_kmAkhir, 'KM akhir', money: false)),
        ])),
      ];

  String get _periodTotals {
    var lk = 0;
    var dk = 0;
    for (final period in _completePeriods) {
      if (period.type == TripType.luarKota) {
        lk += period.days;
      } else {
        dk += period.days;
      }
    }
    return 'LK $lk hari, DK $dk hari.';
  }

  static final _spanFormat = DateFormat('EEEE, dd/MM/yyyy', 'id_ID');

  /// The trip span is derived, not typed: the earliest start and latest end
  /// across the rows. Empty until a first complete row exists.
  String get _tripSpanText {
    final start = TripPeriod.spanStart(_completePeriods);
    final end = TripPeriod.spanEnd(_completePeriods);
    if (start == null || end == null) return 'Berangkat - Kembali: belum ada.';
    return 'Berangkat ${_spanFormat.format(start)} - '
        'Kembali ${_spanFormat.format(end)}.';
  }

  /// Finished rows earn a small quiet pill (16 hari DK); unfinished rows
  /// stay plain text so the count is never confused with the row number.
  Widget _periodTitle(int index) {
    final period = _periods[index];
    final label = 'Periode ${index + 1}';
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    if (period.start == null || period.end == null || period.type == null) {
      return Text(label, style: titleStyle);
    }
    final days =
        DateTime.utc(period.end!.year, period.end!.month, period.end!.day)
                .difference(DateTime.utc(
                    period.start!.year, period.start!.month, period.start!.day))
                .inDays +
            1;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(label, style: titleStyle),
        StatusPill(label: '$days hari ${period.type!.shortLabel}'),
      ],
    );
  }

  List<String> get _periodValues => [
        if (_preserveLegacyTripData) 'legacy' else 'periods',
        for (final period in _periods)
          '${period.start?.toIso8601String()}|${period.end?.toIso8601String()}|${period.type?.value}',
      ];

  List<TripPeriod> get _completePeriods => [
        for (final period in _periods)
          if (period.start != null &&
              period.end != null &&
              !period.end!.isBefore(period.start!) &&
              period.type != null)
            TripPeriod(
                start: period.start!, end: period.end!, type: period.type!),
      ];

  /// Empty is allowed for now. Otherwise every row needs its own dates and
  /// one type, and rows may sit apart but never overlap.
  bool _validatePeriods() {
    // Untouched legacy counts stay valid until the crew adds a row.
    if (_preserveLegacyTripData && _periods.isEmpty) {
      setState(() => _periodError = null);
      return true;
    }
    for (var i = 0; i < _periods.length; i++) {
      final period = _periods[i];
      if (period.start == null || period.end == null) {
        setState(() => _periodError = 'Periode ${i + 1}: pilih tanggal.');
        return false;
      }
      if (period.end!.isBefore(period.start!)) {
        setState(() => _periodError = 'Periode ${i + 1}: tanggal terbalik.');
        return false;
      }
      if (period.type == null) {
        setState(() => _periodError = 'Periode ${i + 1}: pilih LK atau DK.');
        return false;
      }
    }
    final error = TripPeriod.validateNoOverlap(_completePeriods);
    setState(() => _periodError = error);
    return error == null;
  }

  Widget _periodFields() {
    final report = widget.report;
    if (_preserveLegacyTripData && report != null && _periods.isEmpty) {
      final details = report.hasTripCounts
          ? 'LK ${report.luarKotaCount} hari, DK ${report.dalamKotaCount} hari.'
          : report.tripType == TripType.unspecified
              ? 'Belum dicatat.'
              : '${report.tripType.label}, jumlah belum dicatat.';
      return SectionCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeading(
            title: 'Periode LK/DK', icon: Icons.date_range_outlined),
        Text(details),
        const SizedBox(height: 12),
        OutlinedButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _preserveLegacyTripData = false;
                    }),
            child: const Text('Isi periode')),
      ]));
    }
    return SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeading(
          title: 'Periode LK/DK',
          subtitle: _periods.isEmpty ? 'Belum ada periode.' : _periodTotals,
          icon: Icons.date_range_outlined),
      Text(_tripSpanText, style: const TextStyle(color: AppColors.muted)),
      const SizedBox(height: 12),
      for (var i = 0; i < _periods.length; i++) ...[
        Container(
          key: ObjectKey(_periods[i]),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: AppColors.canvas, borderRadius: BorderRadius.circular(12)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _periodTitle(i),
            const SizedBox(height: 12),
            AdaptivePair(
              first: _periodDayField(i, true),
              second: _periodDayField(i, false),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final type in [TripType.luarKota, TripType.dalamKota])
                ChoiceChip(
                    label: Text(type == TripType.luarKota
                        ? 'Luar Kota (LK)'
                        : 'Dalam Kota (DK)'),
                    selected: _periods[i].type == type,
                    onSelected: _busy
                        ? null
                        : (selected) => setState(() {
                              _periods[i].type = selected ? type : null;
                              _periodError = TripPeriod.validateNoOverlap(
                                  _completePeriods);
                            })),
            ]),
            Align(
              alignment: Alignment.centerRight,
              child: Tooltip(
                message: 'Hapus periode ${i + 1}',
                child: TextButton.icon(
                    onPressed: _busy ? null : () => _removePeriod(i),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Hapus')),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
      ],
      if (_periodError != null) ...[
        Text(_periodError!,
            style: const TextStyle(color: AppColors.danger, fontSize: 12)),
        const SizedBox(height: 12),
      ],
      OutlinedButton.icon(
        onPressed: _busy ? null : _addPeriod,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text('Tambah periode'),
      ),
    ]));
  }

  void _addPeriod() {
    setState(() {
      _preserveLegacyTripData = false;
      _periods.add(_TripPeriodDraft());
      _periodError = null;
    });
  }

  void _removePeriod(int index) {
    FocusScope.of(context).unfocus();
    final removed = _periods[index];
    setState(() {
      _periods.removeAt(index);
      _periodError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      removed.dispose();
      if (mounted && !_loading) {
        setState(() {
          _periodError = TripPeriod.validateNoOverlap(_completePeriods);
        });
      }
    });
  }

  static final _dayFormat = DateFormat('dd/MM/yyyy', 'id_ID');

  String _dayText(DateTime? day) => day == null ? '' : _dayFormat.format(day);

  void _setPeriodDay(int index, bool isStart, DateTime day) {
    final period = _periods[index];
    if (isStart) {
      period.start = day;
    } else {
      period.end = day;
    }
    // Remount the row's fields so the fresh ones show the picked day; the
    // salt in the key below forces new state with the formatted value.
    _periodFieldSalt++;
    if (mounted && !_loading) {
      setState(() {
        _periodError = TripPeriod.validateNoOverlap(_completePeriods);
      });
    }
  }

  void _onPeriodDayText(int index, bool isStart, String value) {
    final parsed = _parseDayInput(value);
    final period = _periods[index];
    if (isStart) {
      period.start = parsed;
    } else {
      period.end = parsed;
    }
    if (mounted && !_loading) {
      setState(() {
        _periodError = TripPeriod.validateNoOverlap(_completePeriods);
      });
    }
  }

  DateTime? _parseDayInput(String value) {
    try {
      return _dayFormat.parseStrict(value.trim());
    } on FormatException {
      return null;
    }
  }

  Future<void> _pickPeriodDay(int index, bool isStart) async {
    final period = _periods[index];
    final now = DateTime.now();
    final current = isStart ? period.start : period.end;
    final picked = await showDatePicker(
        context: context,
        initialDate: current ?? now,
        firstDate: DateTime(2020),
        lastDate: DateTime(now.year + 10, 12, 31),
        locale: const Locale('id', 'ID'));
    if (picked != null && mounted) {
      _setPeriodDay(index, isStart, picked);
    }
  }

  List<Widget> _financeFields() => [
        SectionCard(
            child: Column(children: [
          const SectionHeading(
              title: 'Uang diterima',
              subtitle: 'Uang saku diterima dari kantor.',
              icon: Icons.account_balance_wallet_outlined),
          _numberField(_uangSaku, 'Uang saku'),
        ])),
        const SizedBox(height: 16),
        SectionCard(
            child: Column(children: [
          const SectionHeading(
              title: 'Rincian pengeluaran',
              subtitle: 'Kosongkan jika tidak ada.',
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
              subtitle: 'Titipan pembayaran pelunasan bus dari tamu jika ada.',
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
              subtitle: 'Nama untuk tanda tangan PDF.',
              icon: Icons.draw_outlined),
          _text(_namaCrew, 'Nama crew', hint: 'Nama lengkap pembuat laporan'),
          const SizedBox(height: 16),
          _text(_catatan, 'Catatan tambahan', hint: 'Opsional', maxLines: 3),
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
        const Text('Pratinjau tidak menyimpan perubahan.',
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
                : 'Uang saku dikurangi pengeluaran.',
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
        // Camera capture is unsupported on Linux; gallery stays available.
        if (!Platform.isLinux)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined, size: 20),
                label: const Text('Kamera')),
          ),
        if (!Platform.isLinux) const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
              onPressed: () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined, size: 20),
              label: const Text('Galeri')),
        ),
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
          child: Text('Nama dan harga pengeluaran tambahan.',
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
    if (_step == 0 && !_validatePeriods()) {
      showAppMessage(context, _periodError!);
      return;
    }
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
        setState(() => _extraError = 'Extra $row belum diisi. Isi atau hapus.');
        return false;
      }
      if (name.isEmpty) {
        setState(() => _extraError = 'Isi nama untuk extra $row.');
        return false;
      }
      if (amount <= 0) {
        setState(
            () => _extraError = 'Isi harga untuk "$name" lebih dari Rp 0.');
        return false;
      }
    }
    setState(() => _extraError = null);
    return true;
  }

  /// The span shown on the form is derived; stored dates only matter for
  /// legacy reports, which keep their values until the crew adds periods.
  String _derivedSpanLabel(bool isStart, List<TripPeriod> periods) {
    final day =
        isStart ? TripPeriod.spanStart(periods) : TripPeriod.spanEnd(periods);
    if (day == null) return '';
    return _spanFormat.format(day);
  }

  Report _buildReport() {
    final existing = widget.report;
    final legacy = existing?.tripPeriods == null;
    if (_preserveLegacyTripData && legacy && existing != null) {
      return Report(
        id: existing.id,
        tanggalBuat: existing.tanggalBuat,
        hariTglBerangkat: existing.hariTglBerangkat,
        jamBerangkat: _jam.text.trim(),
        hariTglKembali: existing.hariTglKembali,
        noPolisi: _polisi.text.trim(),
        namaTamu: _namaTamu.text.trim(),
        pengemudi: _pengemudi.text.trim(),
        kernet: _kernet.text.trim(),
        tripType: existing.tripType,
        luarKotaCount: existing.luarKotaCount,
        dalamKotaCount: existing.dalamKotaCount,
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
    }
    final Report? saved = existing;
    final keepSavedEmptyTripData = _preserveLegacyTripData &&
        saved?.tripPeriods != null &&
        _periods.isEmpty;
    final derived = _completePeriods;
    return Report(
      id: saved?.id,
      tanggalBuat: saved?.tanggalBuat ?? DateTime.now(),
      hariTglBerangkat: _derivedSpanLabel(true, derived),
      jamBerangkat: _jam.text.trim(),
      hariTglKembali: _derivedSpanLabel(false, derived),
      noPolisi: _polisi.text.trim(),
      namaTamu: _namaTamu.text.trim(),
      pengemudi: _pengemudi.text.trim(),
      kernet: _kernet.text.trim(),
      tripType: keepSavedEmptyTripData && saved != null
          ? saved.tripType
          : TripType.unspecified,
      luarKotaCount:
          keepSavedEmptyTripData && saved != null ? saved.luarKotaCount : null,
      dalamKotaCount:
          keepSavedEmptyTripData && saved != null ? saved.dalamKotaCount : null,
      resetTripData: _periods.isEmpty && !keepSavedEmptyTripData,
      tripPeriods: derived,
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
  }

  Future<void> _onSave() async {
    if (_busy || _loading) return;
    FocusScope.of(context).unfocus();
    if (!_validatePeriods()) {
      _goToStep(0);
      showAppMessage(context, _periodError!);
      return;
    }
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
        showAppMessage(context, 'Gagal menyimpan. Isian tetap ada. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onPreview() async {
    if (_busy || _loading) return;
    FocusScope.of(context).unfocus();
    if (!_validatePeriods()) {
      _goToStep(0);
      showAppMessage(context, _periodError!);
      return;
    }
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
        showAppMessage(
            context, 'Pratinjau gagal. Periksa lampiran dan coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }
}

class _TripPeriodDraft {
  DateTime? start;
  DateTime? end;
  TripType? type;

  _TripPeriodDraft({this.start, this.end, this.type});

  void dispose() {}
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
