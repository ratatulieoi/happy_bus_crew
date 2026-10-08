import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../db/database.dart';
import '../models/bus.dart';
import '../models/report.dart';
import '../models/report_attachment.dart';
import '../services/report_storage.dart';
import '../ui/app_theme.dart';
import '../ui/components.dart';
import '../ui/expense_photo_manager.dart';
import '../ui/period_range_picker.dart';
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
  String? _selectedPlate;
  String? _busError;
  late final TextEditingController _namaTamu;
  late final TextEditingController _pengemudi;
  late final TextEditingController _kernet;
  late final TextEditingController _namaCrew;
  late final TextEditingController _catatan;
  late final TextEditingController _uangSaku;
  late final TextEditingController _bbm;
  late final TextEditingController _uangMakan;
  late bool _uangMakanIsManual;
  late final TextEditingController _pembayaranTagihan;
  late final TextEditingController _guestUangSaku;
  late final TextEditingController _guestTol;
  late final TextEditingController _guestPenyeberangan;
  late final TextEditingController _guestParkir;
  late final TextEditingController _guestCatatan;
  final List<String> _extraIds = [];
  final List<String> _guestExtraIds = [];
  final List<TextEditingController> _extraNames = [];
  final List<TextEditingController> _extraAmounts = [];
  final List<TextEditingController> _guestExtraNames = [];
  final List<TextEditingController> _guestExtraAmounts = [];
  String? _extraError;
  String? _guestExtraError;
  late bool _hasGuest;
  final List<_TripPeriodDraft> _periods = [];
  late bool _preserveLegacyTripData;
  List<String> _initialPeriods = [];
  String? _periodError;
  final List<ReportAttachment> _attachments = [];
  List<String> _initialValues = [];
  List<ReportAttachment> _initialAttachments = [];
  bool _loading = true;
  bool _saving = false;
  bool _previewing = false;
  bool _allowPop = false;
  String? _loadError;
  int _step = 0;
  bool get _isEdit => widget.report != null;
  List<String> get _stepLabels => _hasGuest
      ? ['Periode', 'Keuangan Kantor', 'Keuangan Discova', 'Penyelesaian']
      : ['Periode', 'Keuangan Kantor', 'Penyelesaian'];
  int get _stepCount => _stepLabels.length;
  int get _completionStep => _stepCount - 1;
  bool get _busy => _saving || _previewing;
  List<String> get _currentValues => [
        ..._controllers.map((c) => c.text),
        _hasGuest.toString(),
        _selectedPlate ?? '',
        _uangMakanIsManual.toString(),
        ..._extraIds,
        ..._guestExtraIds,
      ];
  List<TextEditingController> get _controllers => [
        _namaTamu,
        _pengemudi,
        _kernet,
        _namaCrew,
        _catatan,
        _uangSaku,
        _bbm,
        _uangMakan,
        _pembayaranTagihan,
        ..._extraNames,
        ..._extraAmounts,
        _guestUangSaku,
        _guestTol,
        _guestPenyeberangan,
        _guestParkir,
        _guestCatatan,
        ..._guestExtraNames,
        ..._guestExtraAmounts,
      ];
  bool get _dirty =>
      !_loading &&
      _loadError == null &&
      (!_same(_initialValues, _currentValues) ||
          !_same(_initialPeriods, _periodValues) ||
          !_same(_initialAttachments, _attachments));

  bool _same<T>(List<T> a, List<T> b) {
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
    _hasGuest = r?.hasGuestData ?? false;
    for (final period in r?.tripPeriods ?? <TripPeriod>[]) {
      final draft = _TripPeriodDraft(
          start: period.start,
          end: period.end,
          type: period.type,
          origin: period.origin,
          destination: period.destination);
      draft.origin.addListener(_changed);
      draft.destination.addListener(_changed);
      _periods.add(draft);
    }
    String amount(int? value) =>
        value == null || value == 0 ? '' : formatNumberId(value);
    _selectedPlate = r?.noPolisi;
    _namaTamu = TextEditingController(text: r?.namaTamu ?? '');
    _pengemudi = TextEditingController(text: r?.pengemudi ?? '');
    _kernet = TextEditingController(text: r?.kernet ?? '');
    _namaCrew = TextEditingController(text: r?.namaCrew ?? '');
    _catatan = TextEditingController(text: r?.catatan ?? '');
    _uangSaku = TextEditingController(text: amount(r?.uangSaku));
    _bbm = TextEditingController(text: amount(r?.bbm));
    _uangMakanIsManual = r?.uangMakanIsManual ?? false;
    _uangMakan = TextEditingController(text: formatNumberId(r?.uangMakan ?? 0));
    _pembayaranTagihan =
        TextEditingController(text: amount(r?.pembayaranTagihan));
    _guestUangSaku = TextEditingController(text: amount(r?.guestUangSaku));
    _guestTol = TextEditingController(text: amount(r?.guestTol));
    _guestPenyeberangan =
        TextEditingController(text: amount(r?.guestPenyeberangan));
    _guestParkir = TextEditingController(text: amount(r?.guestParkir));
    _guestCatatan = TextEditingController(text: r?.guestCatatan ?? '');
    if (r != null) {
      for (final item in r.extras) {
        _extraIds.add(item.id);
        _extraNames.add(TextEditingController(text: item.name));
        _extraAmounts.add(TextEditingController(text: amount(item.amount)));
      }
      for (final item in r.guestExtras) {
        _guestExtraIds.add(item.id);
        _guestExtraNames.add(TextEditingController(text: item.name));
        _guestExtraAmounts
            .add(TextEditingController(text: amount(item.amount)));
      }
    }
    for (final c in _controllers) {
      c.addListener(_changed);
    }
    _loadInitialData();
  }

  void _changed() {
    if (mounted && !_loading) {
      setState(() {
        _extraError = null;
        _guestExtraError = null;
      });
    }
  }

  Widget _periodRangeField(int index) {
    final period = _periods[index];
    final text = period.start == null || period.end == null
        ? 'Pilih tanggal'
        : period.start == period.end
            ? _dayFormat.format(period.start!)
            : '${_dayFormat.format(period.start!)} - ${_dayFormat.format(period.end!)}';
    return Builder(
        builder: (context) => Semantics(
              button: true,
              label: 'Tanggal periode ${index + 1}',
              child: InkWell(
                key: ValueKey('period-range-$index'),
                onTap: _busy ? null : () => _pickPeriodRange(context, period),
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Tanggal periode',
                    suffixIcon: Icon(Icons.date_range_outlined, size: 20),
                  ),
                  child: Text(text),
                ),
              ),
            ));
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final db = DatabaseHelper.instance;
      final photos = _isEdit && widget.report!.id != null
          ? await db.getAttachments(widget.report!.id!)
          : <ReportAttachment>[];
      if (!mounted) return;
      _attachments
        ..clear()
        ..addAll(photos);
      _initialValues = _currentValues;
      _initialPeriods = _periodValues;
      _initialAttachments = List.of(_attachments);
      setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Lampiran gagal dimuat. Coba lagi.';
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
      period.origin.removeListener(_changed);
      period.destination.removeListener(_changed);
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
    if (step > 0 && !_validateBus()) return;
    if (step > 0 && !_validatePeriods()) {
      setState(() => _step = 0);
      showAppMessage(context, _periodError!);
      if (_scroll.hasClients) _scroll.jumpTo(0);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          bodyLarge: theme.textTheme.bodyLarge?.copyWith(fontSize: 14),
          titleMedium: theme.textTheme.titleMedium?.copyWith(fontSize: 14),
          headlineMedium:
              theme.textTheme.headlineMedium?.copyWith(fontSize: 20),
        ),
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          contentPadding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(minHeight: 48),
        ),
        materialTapTargetSize: MaterialTapTargetSize.padded,
        chipTheme: theme.chipTheme.copyWith(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: theme.filledButtonTheme.style?.copyWith(
            minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
            padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: theme.outlinedButtonTheme.style?.copyWith(
            minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
            padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
          ),
        ),
      ),
      child: Builder(builder: _buildForm),
    );
  }

  Widget _buildForm(BuildContext context) => PopScope(
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
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        children: [
                          _stepNavigation(),
                          const SizedBox(height: 16),
                          Text(
                              [
                                'Periode',
                                'Keuangan Kantor',
                                if (_hasGuest) 'Keuangan Discova',
                                'Penyelesaian'
                              ][_step],
                              style:
                                  Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 12),
                          if (_step == 0) ..._tripFields(),
                          if (_step == 1) ..._financeFields(),
                          if (_hasGuest && _step == 2) ..._guestFinanceFields(),
                          if (_step == _completionStep) ..._completionFields(),
                        ],
                      ))),
          bottomNavigationBar: _loading || _loadError != null
              ? null
              : BottomActionBar(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (_step == _completionStep) ...[
                      const Text('Laporan disimpan di perangkat ini.',
                          style:
                              TextStyle(color: AppColors.muted, fontSize: 12)),
                      const SizedBox(height: 10),
                    ],
                    Row(children: [
                      if (_step > 0) ...[
                        OutlinedButton(
                            onPressed:
                                _busy ? null : () => _goToStep(_step - 1),
                            child: const Text('Kembali')),
                        const SizedBox(width: 12)
                      ],
                      Expanded(
                          child: FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : _step < _completionStep
                                ? _nextStep
                                : _onSave,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : Icon(
                                _step < _completionStep
                                    ? Icons.arrow_forward_rounded
                                    : Icons.check_rounded,
                                size: 20),
                        label: Text(_saving
                            ? 'Menyimpan…'
                            : _step < _completionStep
                                ? 'Lanjut'
                                : 'Simpan laporan'),
                      )),
                    ]),
                  ])),
        ),
      );

  Widget _stepNavigation() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('LANGKAH ${_step + 1} DARI $_stepCount',
            style: const TextStyle(
                fontSize: 11,
                letterSpacing: 1.3,
                color: AppColors.muted,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final entry in _stepLabels.asMap().entries)
            _StepPill(
              key: ValueKey('langkah-${entry.key}'),
              label: '${entry.key + 1}. ${entry.value}',
              selected: _step == entry.key,
              onTap: () => _goToStep(entry.key),
            ),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
                value: (_step + 1) / _stepCount,
                minHeight: 4,
                backgroundColor: AppColors.border)),
      ]);

  List<Widget> _tripFields() => [
        _GuestToggle(
          value: _hasGuest,
          onChanged: (value) => setState(() {
            _hasGuest = value;
            if (!value && _step > 2) _step = 2;
          }),
        ),
        const SizedBox(height: 12),
        SectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              const SectionHeading(
                  title: 'Bus & tamu',
                  compact: true,
                  icon: Icons.route_outlined),
              DropdownButtonFormField<String>(
                value: _selectedPlate,
                isExpanded: true,
                hint: const Text('Pilih bus'),
                decoration:
                    InputDecoration(labelText: 'Bus', errorText: _busError),
                items: [
                  for (final bus in busCatalog)
                    DropdownMenuItem(
                      value: bus.plate,
                      child: Text('${bus.name} • ${bus.plate}'),
                    ),
                ],
                onChanged: (plate) => setState(() {
                  _selectedPlate = plate;
                  _busError = null;
                }),
              ),
              const SizedBox(height: 12),
              _text(_namaTamu, 'Nama tamu', hint: 'Nama tamu atau kelompok'),
            ])),
        const SizedBox(height: 12),
        _periodFields(),
        const SizedBox(height: 12),
        SectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              const SectionHeading(
                  title: 'Crew bertugas',
                  compact: true,
                  icon: Icons.people_outline_rounded),
              _text(_pengemudi, 'Nama pengemudi', hint: 'Nama sopir'),
              const SizedBox(height: 12),
              _text(_kernet, 'Nama kernet', hint: 'Nama asisten pengemudi'),
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

  /// Finished rows earn a small quiet pill (16 hari DK); unfinished rows
  /// stay plain text so the count is never confused with the row number.
  Widget _periodTitle(int index) {
    final period = _periods[index];
    final label = 'Periode ${index + 1}';
    const titleStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
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
        for (final period in _periods) ...[
          '${period.start?.toIso8601String()}|${period.end?.toIso8601String()}|${period.type?.value}',
          period.origin.text,
          period.destination.text,
        ],
      ];

  List<TripPeriod> get _completePeriods => [
        for (final period in _periods)
          if (period.start != null &&
              period.end != null &&
              !period.end!.isBefore(period.start!) &&
              period.type != null)
            TripPeriod(
                start: period.start!,
                end: period.end!,
                type: period.type!,
                origin: period.origin.text,
                destination: period.destination.text),
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
      if (!_rangeAvailable(period, period.start!, period.end!)) {
        setState(() => _periodError = 'Periode bertumpuk.');
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
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeading(
                title: 'Periode',
                compact: true,
                icon: Icons.date_range_outlined),
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
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionHeading(
              title: 'Periode',
              compact: true,
              subtitle: _periods.isEmpty ? 'Belum ada periode.' : _periodTotals,
              icon: Icons.date_range_outlined),
          const SizedBox(height: 12),
          for (var i = 0; i < _periods.length; i++) ...[
            Container(
              key: ObjectKey(_periods[i]),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _periodTitle(i),
                    const SizedBox(height: 12),
                    _periodRangeField(i),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _text(_periods[i].origin, 'Asal')),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _text(_periods[i].destination, 'Tujuan')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      for (final type in [
                        TripType.luarKota,
                        TripType.dalamKota
                      ]) ...[
                        if (type == TripType.dalamKota)
                          const SizedBox(width: 8),
                        ChoiceChip(
                            label:
                                Text(type == TripType.luarKota ? 'LK' : 'DK'),
                            selected: _periods[i].type == type,
                            onSelected: _busy
                                ? null
                                : (selected) => setState(() {
                                      _periods[i].type = selected ? type : null;
                                      _syncMealAllowance();
                                      _periodError =
                                          TripPeriod.validateNoOverlap(
                                              _completePeriods);
                                    })),
                      ],
                      const Spacer(),
                      Tooltip(
                        message: 'Hapus periode ${i + 1}',
                        child: TextButton.icon(
                            onPressed: _busy ? null : () => _removePeriod(i),
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 18),
                            label: const Text('Hapus')),
                      ),
                    ]),
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
    final period = _TripPeriodDraft();
    period.origin.addListener(_changed);
    period.destination.addListener(_changed);
    setState(() {
      _preserveLegacyTripData = false;
      _periods.add(period);
      _periodError = null;
    });
  }

  void _removePeriod(int index) {
    FocusScope.of(context).unfocus();
    final removed = _periods[index];
    removed.origin.removeListener(_changed);
    removed.destination.removeListener(_changed);
    setState(() {
      _periods.removeAt(index);
      _syncMealAllowance();
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

  bool _rangeAvailable(_TripPeriodDraft edited, DateTime start, DateTime end) =>
      !end.isBefore(start) &&
      !_periods.any((other) =>
          !identical(other, edited) &&
          other.start != null &&
          other.end != null &&
          TripPeriod.datesOverlap(start, end, other.start!, other.end!));

  Future<void> _pickPeriodRange(
      BuildContext context, _TripPeriodDraft period) async {
    final now = DateTime.now();
    final firstDate = DateTime(2020);
    final lastDate = DateTime(now.year + 10, 12, 31);
    final initial = period.start != null &&
            period.end != null &&
            _rangeAvailable(period, period.start!, period.end!)
        ? DateTimeRange(start: period.start!, end: period.end!)
        : null;
    // Flutter's showDateRangePicker keeps Pilih disabled after the first tap
    // and exposes no selection callbacks. This dialog accepts that tap as a
    // complete one-day range while still allowing a second date to extend it.
    final picked = await showDialog<DateTimeRange>(
      context: context,
      builder: (_) => PeriodRangePickerDialog(
        initialDateRange: initial,
        firstDate: firstDate,
        lastDate: lastDate,
        rangeAvailable: (start, end) => _rangeAvailable(period, start, end),
      ),
    );
    if (!mounted || picked == null || !_periods.contains(period)) return;
    if (picked.start.isBefore(firstDate) ||
        picked.end.isAfter(lastDate) ||
        !_rangeAvailable(period, picked.start, picked.end)) {
      setState(() => _periodError = 'Periode bertumpuk.');
      return;
    }
    setState(() {
      period.start = picked.start;
      period.end = picked.end;
      _syncMealAllowance();
      _periodError = null;
    });
  }

  void _syncMealAllowance() {
    if (!_uangMakanIsManual) {
      _uangMakan.text =
          formatNumberId(Report.automaticMealAllowance(_completePeriods));
    }
  }

  List<Widget> _financeFields() => [
        SectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              const SectionHeading(
                  title: 'Uang diterima',
                  compact: true,
                  icon: Icons.account_balance_wallet_outlined),
              _numberField(_uangSaku, 'Uang saku'),
            ])),
        const SizedBox(height: 12),
        SectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              const SectionHeading(
                  title: 'Rincian pengeluaran',
                  compact: true,
                  icon: Icons.receipt_long_outlined),
              _expenseField(
                  _bbm, 'BBM', const ExpenseOwner(ExpenseType.officeBbm)),
              const SizedBox(height: 12),
              _expenseField(
                  _uangMakan,
                  'Uang makan (${Report.countMealDays(_completePeriods)} hari)',
                  const ExpenseOwner(ExpenseType.officeMeal),
                  onChanged: (_) => setState(() => _uangMakanIsManual = true)),
              const SizedBox(height: 12),
              ..._extraFields(),
            ])),
        const SizedBox(height: 12),
        SectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              const SectionHeading(
                  title: 'Pembayaran tagihan',
                  compact: true,
                  subtitle: 'Titipan pelunasan bus dari tamu.',
                  icon: Icons.payments_outlined),
              _numberField(_pembayaranTagihan, 'Pembayaran tagihan'),
            ])),
        const SizedBox(height: 12),
        _balanceCard(),
      ];

  List<Widget> _guestFinanceFields() => [
        _guestAllowanceCard(),
        const SizedBox(height: 12),
        _guestExpensesCard(),
        const SizedBox(height: 12),
        _guestBalanceCard(),
      ];

  List<Widget> _completionFields() => [
        SectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              const SectionHeading(
                  title: 'Pembuat laporan',
                  compact: true,
                  icon: Icons.draw_outlined),
              _text(_namaCrew, 'Nama crew',
                  hint: 'Nama lengkap pembuat laporan'),
              const SizedBox(height: 12),
              _text(_catatan, 'Catatan tambahan',
                  hint: 'Opsional', maxLines: 3),
            ])),
        const SizedBox(height: 12),
        _balanceCard(),
        const SizedBox(height: 12),
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
          {String? hint, int maxLines = 1}) =>
      TextFormField(
        controller: controller,
        maxLines: maxLines,
        textCapitalization: TextCapitalization.words,
        textInputAction:
            maxLines > 1 ? TextInputAction.newline : TextInputAction.next,
        decoration: InputDecoration(labelText: label, hintText: hint),
      );

  Widget _numberField(TextEditingController controller, String label,
          {ValueChanged<String>? onChanged}) =>
      TextFormField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        inputFormatters: [ThousandsSeparatorFormatter()],
        decoration:
            InputDecoration(labelText: label, hintText: '0', prefixText: 'Rp '),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: deficit ? AppColors.dangerSoft : AppColors.successSoft,
          borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _summaryRow('Uang saku', formatRupiah(report.uangSaku)),
        const SizedBox(height: 8),
        _summaryRow('Uang makan (${report.mealDays} hari)',
            formatRupiah(report.uangMakan)),
        const SizedBox(height: 8),
        _summaryRow('Total pengeluaran', formatRupiah(report.totalPengeluaran)),
        const Divider(height: 20),
        Text(deficit ? 'Defisit kantor' : 'Sisa uang kantor',
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(formatRupiah(report.sisa),
            style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -.5)),
      ]),
    );
  }

  Widget _guestAllowanceCard() => SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        const SectionHeading(
            title: 'Uang saku Discova',
            compact: true,
            icon: Icons.account_balance_wallet_outlined),
        _numberField(_guestUangSaku, 'Uang saku diterima'),
      ]));

  Widget _guestExpensesCard() => SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        const SectionHeading(
            title: 'Pengeluaran Discova',
            compact: true,
            icon: Icons.receipt_long_outlined),
        _expenseField(
            _guestTol, 'Tol', const ExpenseOwner(ExpenseType.discovaTol)),
        const SizedBox(height: 12),
        _expenseField(_guestPenyeberangan, 'Penyeberangan',
            const ExpenseOwner(ExpenseType.discovaCrossing)),
        const SizedBox(height: 12),
        _expenseField(_guestParkir, 'Parkir',
            const ExpenseOwner(ExpenseType.discovaParking)),
        const SizedBox(height: 12),
        ..._guestExtraFields(),
        const SizedBox(height: 12),
        _text(_guestCatatan, 'Catatan Discova', hint: 'Opsional', maxLines: 3),
      ]));

  List<Widget> _guestExtraFields() => [
        for (var i = 0; i < _guestExtraNames.length; i++) ...[
          Container(
            key: ObjectKey(_guestExtraNames[i]),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              _text(_guestExtraNames[i], 'Nama extra Discova ${i + 1}'),
              const SizedBox(height: 12),
              _expenseField(
                  _guestExtraAmounts[i],
                  'Harga extra Discova ${i + 1}',
                  ExpenseOwner(ExpenseType.discovaExtra,
                      extraId: _guestExtraIds[i]),
                  photoLabel: _guestExtraNames[i].text.trim().isEmpty
                      ? 'Extra Discova ${i + 1}'
                      : '${_guestExtraNames[i].text.trim()} • Discova'),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _busy ? null : () => _removeGuestExtra(i),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Hapus'),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        if (_guestExtraError != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Text(_guestExtraError!,
                style: const TextStyle(color: AppColors.danger, fontSize: 12)),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: _busy ? null : _addGuestExtra,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Tambah Extra Discova'),
        ),
      ];

  Widget _guestBalanceCard() {
    final report = _buildReport();
    final deficit = report.guestSisa < 0;
    final color = deficit ? AppColors.danger : AppColors.success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: deficit ? AppColors.dangerSoft : AppColors.successSoft,
          borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _summaryRow('Uang saku Discova', formatRupiah(report.guestUangSaku)),
        const SizedBox(height: 8),
        _summaryRow('Total pengeluaran Discova',
            formatRupiah(report.guestTotalPengeluaran)),
        const Divider(height: 20),
        Text(deficit ? 'Defisit uang Discova' : 'Sisa uang Discova',
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(formatRupiah(report.guestSisa),
            style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -.5)),
      ]),
    );
  }

  Widget _expenseField(
      TextEditingController controller, String label, ExpenseOwner owner,
      {String? photoLabel, ValueChanged<String>? onChanged}) {
    final count = _attachments.where((photo) => photo.owner == owner).length;
    final title = photoLabel ?? label;
    return Row(children: [
      Expanded(child: _numberField(controller, label, onChanged: onChanged)),
      const SizedBox(width: 8),
      Tooltip(
        message: 'Foto $title',
        child: OutlinedButton.icon(
          key: ValueKey(owner),
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(48, 48)),
          onPressed: _busy ? null : () => _managePhotos(owner, title),
          icon: Icon(
              count == 0
                  ? Icons.add_photo_alternate_outlined
                  : Icons.photo_library_outlined,
              size: 20),
          label: Text(count == 0 ? '+' : '$count'),
        ),
      ),
    ]);
  }

  Future<void> _managePhotos(ExpenseOwner owner, String label) async {
    FocusScope.of(context).unfocus();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExpensePhotoManager(
        owner: owner,
        label: label,
        photos: _attachments.where((photo) => photo.owner == owner).toList(),
        onChanged: (photos) {
          if (!mounted) return;
          setState(() {
            // Preserve the report-wide order used by the generic PDF appendix.
            final remaining = List<ReportAttachment>.of(photos);
            _attachments.removeWhere(
                (photo) => photo.owner == owner && !remaining.remove(photo));
            _attachments.addAll(remaining);
          });
        },
      ),
    );
  }

  Future<bool> _confirmExtraRemoval(ExpenseOwner owner) async {
    final count = _attachments.where((photo) => photo.owner == owner).length;
    if (count == 0) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Hapus extra beserta fotonya?'),
            content:
                Text('$count foto akan dilepas dari laporan saat disimpan.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Batal')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Hapus extra')),
            ],
          ),
        ) ==
        true;
  }

  List<Widget> _extraFields() => [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Extra',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 8),
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
              _expenseField(_extraAmounts[i], 'Harga extra ${i + 1}',
                  ExpenseOwner(ExpenseType.officeExtra, extraId: _extraIds[i]),
                  photoLabel: _extraNames[i].text.trim().isEmpty
                      ? 'Extra ${i + 1}'
                      : _extraNames[i].text.trim()),
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

  void _addGuestExtra() {
    final name = TextEditingController();
    final amount = TextEditingController();
    name.addListener(_changed);
    amount.addListener(_changed);
    setState(() {
      _guestExtraIds.add(ExtraExpense.createId());
      _guestExtraNames.add(name);
      _guestExtraAmounts.add(amount);
      _guestExtraError = null;
    });
  }

  Future<void> _removeGuestExtra(int index) async {
    final owner =
        ExpenseOwner(ExpenseType.discovaExtra, extraId: _guestExtraIds[index]);
    if (!await _confirmExtraRemoval(owner) || !mounted) return;
    FocusScope.of(context).unfocus();
    final name = _guestExtraNames[index];
    final amount = _guestExtraAmounts[index];
    name.removeListener(_changed);
    amount.removeListener(_changed);
    setState(() {
      _attachments.removeWhere((photo) => photo.owner == owner);
      _guestExtraIds.removeAt(index);
      _guestExtraNames.removeAt(index);
      _guestExtraAmounts.removeAt(index);
      _guestExtraError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      name.dispose();
      amount.dispose();
    });
  }

  void _addExtra() {
    final name = TextEditingController();
    final amount = TextEditingController();
    name.addListener(_changed);
    amount.addListener(_changed);
    setState(() {
      _extraIds.add(ExtraExpense.createId());
      _extraNames.add(name);
      _extraAmounts.add(amount);
      _extraError = null;
    });
  }

  Future<void> _removeExtra(int index) async {
    final owner =
        ExpenseOwner(ExpenseType.officeExtra, extraId: _extraIds[index]);
    if (!await _confirmExtraRemoval(owner) || !mounted) return;
    FocusScope.of(context).unfocus();
    final name = _extraNames[index];
    final amount = _extraAmounts[index];
    name.removeListener(_changed);
    amount.removeListener(_changed);
    setState(() {
      _attachments.removeWhere((photo) => photo.owner == owner);
      _extraIds.removeAt(index);
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

  bool _validateBus() {
    if (busCatalog.any((bus) => bus.plate == _selectedPlate)) return true;
    setState(() {
      _busError = 'Pilih bus terlebih dahulu.';
      _step = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    return false;
  }

  void _nextStep() {
    if (!_validateBus()) return;
    if (_step == 0 && !_validatePeriods()) {
      showAppMessage(context, _periodError!);
      return;
    }
    if (_step == 1 && !_validateExtras()) {
      showAppMessage(context, _extraError!);
      return;
    }
    if (_hasGuest && _step == 2 && !_validateGuestExtras()) {
      showAppMessage(context, _guestExtraError!);
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

  bool _validateGuestExtras() {
    if (!_hasGuest) {
      setState(() => _guestExtraError = null);
      return true;
    }
    for (var i = 0; i < _guestExtraNames.length; i++) {
      final name = _guestExtraNames[i].text.trim();
      final amount = parseRupiahInput(_guestExtraAmounts[i].text);
      final row = i + 1;
      if (name.isEmpty && _guestExtraAmounts[i].text.trim().isEmpty) {
        setState(() => _guestExtraError =
            'Extra Discova $row belum diisi. Isi atau hapus.');
        return false;
      }
      if (name.isEmpty) {
        setState(() => _guestExtraError = 'Isi nama untuk extra Discova $row.');
        return false;
      }
      if (amount <= 0) {
        setState(() =>
            _guestExtraError = 'Isi harga untuk "$name" lebih dari Rp 0.');
        return false;
      }
    }
    setState(() => _guestExtraError = null);
    return true;
  }

  /// Report dates are derived from periods; legacy reports keep their stored
  /// dates until the crew adds periods.
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
        jamBerangkat: existing.jamBerangkat,
        hariTglKembali: existing.hariTglKembali,
        noPolisi: _selectedPlate!,
        namaTamu: _namaTamu.text.trim(),
        pengemudi: _pengemudi.text.trim(),
        kernet: _kernet.text.trim(),
        tripType: existing.tripType,
        luarKotaCount: existing.luarKotaCount,
        dalamKotaCount: existing.dalamKotaCount,
        kmAwal: existing.kmAwal,
        kmAkhir: existing.kmAkhir,
        uangSaku: parseRupiahInput(_uangSaku.text),
        bbm: parseRupiahInput(_bbm.text),
        uangMakan: parseRupiahInput(_uangMakan.text),
        uangMakanIsManual: _uangMakanIsManual,
        pembayaranTagihan: parseRupiahInput(_pembayaranTagihan.text),
        namaCrew: _namaCrew.text.trim(),
        catatan: _catatan.text.trim(),
        extras: [
          for (var i = 0; i < _extraNames.length; i++)
            ExtraExpense(
                id: _extraIds[i],
                name: _extraNames[i].text.trim(),
                amount: parseRupiahInput(_extraAmounts[i].text)),
        ],
        hasGuestAllowance: _hasGuest,
        guestUangSaku: parseRupiahInput(_guestUangSaku.text),
        guestTol: parseRupiahInput(_guestTol.text),
        guestPenyeberangan: parseRupiahInput(_guestPenyeberangan.text),
        guestParkir: parseRupiahInput(_guestParkir.text),
        guestExtras: [
          for (var i = 0; i < _guestExtraNames.length; i++)
            ExtraExpense(
                id: _guestExtraIds[i],
                name: _guestExtraNames[i].text.trim(),
                amount: parseRupiahInput(_guestExtraAmounts[i].text)),
        ],
        guestCatatan: _guestCatatan.text.trim(),
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
      jamBerangkat: saved?.jamBerangkat ?? '',
      hariTglKembali: _derivedSpanLabel(false, derived),
      noPolisi: _selectedPlate!,
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
      kmAwal: saved?.kmAwal ?? 0,
      kmAkhir: saved?.kmAkhir ?? 0,
      uangSaku: parseRupiahInput(_uangSaku.text),
      bbm: parseRupiahInput(_bbm.text),
      uangMakan: parseRupiahInput(_uangMakan.text),
      uangMakanIsManual: _uangMakanIsManual,
      pembayaranTagihan: parseRupiahInput(_pembayaranTagihan.text),
      namaCrew: _namaCrew.text.trim(),
      catatan: _catatan.text.trim(),
      extras: [
        for (var i = 0; i < _extraNames.length; i++)
          ExtraExpense(
              id: _extraIds[i],
              name: _extraNames[i].text.trim(),
              amount: parseRupiahInput(_extraAmounts[i].text)),
      ],
      hasGuestAllowance: _hasGuest,
      guestUangSaku: parseRupiahInput(_guestUangSaku.text),
      guestTol: parseRupiahInput(_guestTol.text),
      guestPenyeberangan: parseRupiahInput(_guestPenyeberangan.text),
      guestParkir: parseRupiahInput(_guestParkir.text),
      guestExtras: [
        for (var i = 0; i < _guestExtraNames.length; i++)
          ExtraExpense(
              id: _guestExtraIds[i],
              name: _guestExtraNames[i].text.trim(),
              amount: parseRupiahInput(_guestExtraAmounts[i].text)),
      ],
      guestCatatan: _guestCatatan.text.trim(),
    );
  }

  Future<void> _onSave() async {
    if (_busy || _loading) return;
    FocusScope.of(context).unfocus();
    if (!_validateBus()) return;
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
    if (!_validateGuestExtras()) {
      if (_hasGuest) _goToStep(2);
      showAppMessage(context, _guestExtraError!);
      return;
    }
    setState(() => _saving = true);
    try {
      await ReportStorage.save(_buildReport(), List.of(_attachments));
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
    if (!_validateBus()) return;
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
    if (!_validateGuestExtras()) {
      if (_hasGuest) _goToStep(2);
      showAppMessage(context, _guestExtraError!);
      return;
    }
    setState(() => _previewing = true);
    try {
      final report = _buildReport();
      final images = <ReportAttachmentImage>[];
      for (final attachment in _attachments) {
        images.add(ReportAttachmentImage(
            bytes: await File(attachment.filePath).readAsBytes(),
            owner: attachment.owner));
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

/// Pill for one langkah. The selected pill grows slightly, without a checkmark.
class _StepPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _StepPill(
      {super.key,
      required this.label,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) => AnimatedScale(
        scale: selected ? 1.02 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => onTap(),
        ),
      );
}

/// Guest allowance toggle with the same fill as text inputs and a thin border,
/// instead of the stock Material switch's thick track.
class _GuestToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _GuestToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final trackFill =
        Theme.of(context).inputDecorationTheme.fillColor ?? Colors.white;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: 46,
            height: 26,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: trackFill,
              border:
                  Border.all(color: value ? AppColors.brand : AppColors.border),
            ),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? AppColors.brand : Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('Tamu Discova')),
        ]),
      ),
    );
  }
}

class _TripPeriodDraft {
  DateTime? start;
  DateTime? end;
  TripType? type;
  final TextEditingController origin;
  final TextEditingController destination;

  _TripPeriodDraft({
    this.start,
    this.end,
    this.type,
    String origin = '',
    String destination = '',
  })  : origin = TextEditingController(text: origin),
        destination = TextEditingController(text: destination);

  void dispose() {
    origin.dispose();
    destination.dispose();
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
