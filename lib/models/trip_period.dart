// Unspecified preserves reports created before trip types were recorded.
enum TripType {
  unspecified('', '-'),
  luarKota('luar_kota', 'Luar Kota'),
  dalamKota('dalam_kota', 'Dalam Kota');

  const TripType(this.value, this.label);
  final String value;
  final String label;

  String get shortLabel => switch (this) {
        luarKota => 'LK',
        dalamKota => 'DK',
        unspecified => '-',
      };

  static TripType fromValue(Object? value) => values.firstWhere(
        (type) => type.value == value,
        orElse: () => unspecified,
      );
}

/// Inclusive calendar dates, independent of time of day and daylight saving.
class TripPeriod {
  final DateTime start;
  final DateTime end;
  final TripType type;

  TripPeriod({
    required DateTime start,
    required DateTime end,
    required this.type,
  })  : start = DateTime(start.year, start.month, start.day),
        end = DateTime(end.year, end.month, end.day) {
    if (_day(this.end).isBefore(_day(this.start))) {
      throw ArgumentError('Tanggal akhir sebelum tanggal awal.');
    }
    if (type == TripType.unspecified) {
      throw ArgumentError('Pilih LK atau DK.');
    }
  }

  int get days => _day(end).difference(_day(start)).inDays + 1;

  Map<String, dynamic> toMap() => {
        'start': _dateString(start),
        'end': _dateString(end),
        'type': type.value,
      };

  factory TripPeriod.fromMap(Map<String, dynamic> map) {
    final type = TripType.fromValue(map['type']);
    final start = _parseDate(map['start']);
    final end = _parseDate(map['end']);
    if (type == TripType.unspecified || end.isBefore(start)) {
      throw const FormatException('Invalid trip period');
    }
    return TripPeriod(start: start, end: end, type: type);
  }

  /// Empty periods are optional. Otherwise every trip day must occur once.
  /// The trip span comes from the rows themselves, so rows may sit apart
  /// but two rows must never claim the same day.
  static String? validateNoOverlap(List<TripPeriod> periods) {
    if (periods.isEmpty) return null;
    final sorted = List<TripPeriod>.of(periods)
      ..sort((a, b) => a.start.compareTo(b.start));
    var takenUntil = _day(sorted.first.start).subtract(const Duration(days: 1));
    for (final period in sorted) {
      final start = _day(period.start);
      final end = _day(period.end);
      if (!start.isAfter(takenUntil)) return 'Periode bertumpuk.';
      takenUntil = end.isAfter(takenUntil) ? end : takenUntil;
    }
    return null;
  }

  /// Earliest start across the rows, or null when no row is complete.
  static DateTime? spanStart(List<TripPeriod> periods) {
    DateTime? first;
    for (final period in periods) {
      if (first == null || period.start.isBefore(first)) {
        first = period.start;
      }
    }
    return first;
  }

  /// Latest end across the rows, or null when no row is complete.
  static DateTime? spanEnd(List<TripPeriod> periods) {
    DateTime? last;
    for (final period in periods) {
      if (last == null || period.end.isAfter(last)) {
        last = period.end;
      }
    }
    return last;
  }

  static DateTime _day(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);

  static String _dateString(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static DateTime _parseDate(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const FormatException('Invalid period date');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null || _dateString(parsed) != value) {
      throw const FormatException('Invalid period date');
    }
    return parsed;
  }
}
