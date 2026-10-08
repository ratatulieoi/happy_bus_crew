import 'package:flutter/material.dart';

/// Calendar-only period picker. One tap selects a complete one-day range;
/// the next tap on or after its start extends it. A third tap starts again.
class PeriodRangePickerDialog extends StatefulWidget {
  const PeriodRangePickerDialog({
    super.key,
    required this.firstDate,
    required this.lastDate,
    required this.rangeAvailable,
    this.initialDateRange,
  });

  final DateTime firstDate;
  final DateTime lastDate;
  final DateTimeRange? initialDateRange;
  final bool Function(DateTime start, DateTime end) rangeAvailable;

  @override
  State<PeriodRangePickerDialog> createState() =>
      _PeriodRangePickerDialogState();
}

class _PeriodRangePickerDialogState extends State<PeriodRangePickerDialog> {
  late DateTime _month;
  DateTime? _start;
  DateTime? _end;
  bool _awaitingEnd = false;
  bool _choosingYear = false;

  @override
  void initState() {
    super.initState();
    _start = widget.initialDateRange?.start;
    _end = widget.initialDateRange?.end;
    final date = _start ?? DateTime.now();
    final bounded = date.isBefore(widget.firstDate)
        ? widget.firstDate
        : date.isAfter(widget.lastDate)
            ? widget.lastDate
            : date;
    _month = DateTime(bounded.year, bounded.month);
  }

  bool _selectable(DateTime day) {
    if (day.isBefore(widget.firstDate) || day.isAfter(widget.lastDate)) {
      return false;
    }
    if (_awaitingEnd && !day.isBefore(_start!)) {
      return widget.rangeAvailable(_start!, day);
    }
    return widget.rangeAvailable(day, day);
  }

  void _select(DateTime day) {
    if (!_selectable(day)) return;
    setState(() {
      if (_awaitingEnd && !day.isBefore(_start!)) {
        _end = day;
        _awaitingEnd = false;
      } else {
        _start = _end = day;
        _awaitingEnd = true;
      }
    });
  }

  void _changeMonth(int offset) => setState(() {
        _month = DateUtils.addMonthsToMonthDate(_month, offset);
      });

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = _start != null && _end != null;
    final dateLabel = selected
        ? '${localizations.formatMediumDate(_start!)} - '
            '${localizations.formatMediumDate(_end!)}'
        : 'Pilih tanggal';
    final firstOffset =
        DateUtils.firstDayOffset(_month.year, _month.month, localizations);
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);

    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: const Text('Tanggal periode'),
          actions: [
            TextButton(
              onPressed: selected && widget.rangeAvailable(_start!, _end!)
                  ? () => Navigator.pop(
                      context, DateTimeRange(start: _start!, end: _end!))
                  : null,
              child: const Text('Pilih'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(dateLabel,
                        style: theme.textTheme.titleMedium,
                        semanticsLabel: 'Tanggal periode: $dateLabel'),
                  ),
                  Row(children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () =>
                            setState(() => _choosingYear = !_choosingYear),
                        child: Text(localizations.formatMonthYear(_month)),
                      ),
                    ),
                    IconButton(
                      tooltip: localizations.previousMonthTooltip,
                      onPressed:
                          DateUtils.monthDelta(widget.firstDate, _month) > 0
                              ? () => _changeMonth(-1)
                              : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    IconButton(
                      tooltip: localizations.nextMonthTooltip,
                      onPressed:
                          DateUtils.monthDelta(_month, widget.lastDate) > 0
                              ? () => _changeMonth(1)
                              : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ]),
                  if (_choosingYear)
                    Expanded(
                      child: YearPicker(
                        firstDate: widget.firstDate,
                        lastDate: widget.lastDate,
                        selectedDate: _month,
                        onChanged: (date) => setState(() {
                          final month = DateTime(date.year, _month.month);
                          _month = month.isBefore(widget.firstDate)
                              ? DateTime(
                                  widget.firstDate.year, widget.firstDate.month)
                              : month.isAfter(widget.lastDate)
                                  ? DateTime(widget.lastDate.year,
                                      widget.lastDate.month)
                                  : month;
                          _choosingYear = false;
                        }),
                      ),
                    )
                  else ...[
                    Row(children: [
                      for (var i = 0; i < 7; i++)
                        Expanded(
                          child: Center(
                            child: Text(localizations.narrowWeekdays[
                                (localizations.firstDayOfWeekIndex + i) % 7]),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 8),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7, mainAxisExtent: 48),
                        itemCount: firstOffset + days,
                        itemBuilder: (context, index) {
                          if (index < firstOffset) {
                            return const SizedBox.shrink();
                          }
                          final day = DateTime(_month.year, _month.month,
                              index - firstOffset + 1);
                          final enabled = _selectable(day);
                          final endpoint = day == _start || day == _end;
                          final inRange = selected &&
                              !day.isBefore(_start!) &&
                              !day.isAfter(_end!);
                          return Semantics(
                            label: localizations.formatFullDate(day),
                            button: true,
                            enabled: enabled,
                            selected: inRange,
                            onTap: enabled ? () => _select(day) : null,
                            child: ExcludeSemantics(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 3),
                                child: Material(
                                  color: inRange
                                      ? colors.primaryContainer
                                      : Colors.transparent,
                                  child: InkWell(
                                    onTap: enabled ? () => _select(day) : null,
                                    child: Container(
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: endpoint ? colors.primary : null,
                                      ),
                                      child: Text(
                                        localizations.formatDecimal(day.day),
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          color: endpoint
                                              ? colors.onPrimary
                                              : !enabled
                                                  ? theme.disabledColor
                                                  : inRange
                                                      ? colors
                                                          .onPrimaryContainer
                                                      : colors.onSurface,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
