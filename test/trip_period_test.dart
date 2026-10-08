import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bus_crew/models/report.dart';

TripPeriod period(int start, int end, [TripType type = TripType.luarKota]) =>
    TripPeriod(
      start: DateTime(2026, 9, start),
      end: DateTime(2026, 9, end),
      type: type,
    );

Report legacyReport() => Report.fromMap({
      'id': 7,
      'tanggal_buat': '2026-09-01T08:00:00',
      'hari_tgl_berangkat': 'Selasa, 01/09/2026',
      'hari_tgl_kembali': 'Sabtu, 05/09/2026',
      'trip_type': 'luar_kota',
      'luar_kota_count': 3,
      'dalam_kota_count': 2,
      'uang_saku': 1000000,
      'bbm': 300000,
      'uang_makan': 100000,
      'pembayaran_tagihan': 500000,
      'extra': 50000,
    });

void main() {
  group('TripPeriod', () {
    test('counts inclusive calendar days and discards time of day', () {
      final single = TripPeriod(
        start: DateTime(2026, 9, 1, 23, 59),
        end: DateTime(2026, 9, 1, 1),
        type: TripType.dalamKota,
      );
      expect(single.start, DateTime(2026, 9, 1));
      expect(single.end, DateTime(2026, 9, 1));
      expect(single.days, 1);
      expect(period(1, 5).days, 5);
      expect(
        TripPeriod(
          start: DateTime(2024, 2, 28),
          end: DateTime(2024, 3, 1),
          type: TripType.luarKota,
        ).days,
        3,
      );
      expect(
        TripPeriod(
          start: DateTime(2026, 12, 31),
          end: DateTime(2027, 1, 1),
          type: TripType.luarKota,
        ).days,
        2,
      );
    });

    test('rejects reversed dates and unspecified categories', () {
      expect(() => period(5, 1), throwsArgumentError);
      expect(() => period(1, 5, TripType.unspecified), throwsArgumentError);
    });

    test('round-trips date-only values and rejects malformed entries', () {
      for (final type in [TripType.luarKota, TripType.dalamKota]) {
        final original = period(1, 5, type);
        expect(original.toMap(), {
          'start': '2026-09-01',
          'end': '2026-09-05',
          'type': type.value,
        });
        expect(TripPeriod.fromMap(original.toMap()).toMap(), original.toMap());
      }
      for (final entry in <Map<String, dynamic>>[
        {},
        {...period(1, 5).toMap(), 'start': null},
        {...period(1, 5).toMap(), 'start': '2026-02-30'},
        {...period(1, 5).toMap(), 'end': '2026-13-01'},
        {...period(1, 5).toMap(), 'start': '2026-9-01'},
        {...period(1, 5).toMap(), 'start': '2026-09-01T08:00:00'},
        {...period(1, 5).toMap(), 'end': '2026-08-31'},
        {...period(1, 5).toMap(), 'type': ''},
        {...period(1, 5).toMap(), 'type': 1},
      ]) {
        expect(() => TripPeriod.fromMap(entry), throwsFormatException,
            reason: '$entry');
      }
    });

    test('allows empty periods and disjoint rows in any input order', () {
      expect(TripPeriod.validateNoOverlap([]), isNull);
      final periods = [period(4, 5, TripType.dalamKota), period(1, 3)];
      expect(TripPeriod.validateNoOverlap(periods), isNull);
      expect(periods.first.start.day, 4,
          reason: 'Validation must not sort input');
      expect(TripPeriod.validateNoOverlap([period(1, 1)]), isNull);
    });

    test('rejects overlaps and duplicates', () {
      for (final periods in [
        [period(1, 3), period(3, 5)],
        [period(1, 5), period(1, 5)],
        [period(4, 5, TripType.dalamKota), period(1, 4)],
      ]) {
        expect(TripPeriod.validateNoOverlap(periods), 'Periode bertumpuk.');
      }
    });

    test('derives the span from the earliest start and latest end', () {
      final periods = [period(4, 5, TripType.dalamKota), period(1, 3)];
      expect(TripPeriod.spanStart(periods), DateTime(2026, 9, 1));
      expect(TripPeriod.spanEnd(periods), DateTime(2026, 9, 5));
      expect(TripPeriod.spanStart([]), isNull);
      expect(TripPeriod.spanEnd([]), isNull);
    });
  });

  test(
      'meals use inclusive period days, not the span, category or stored amount',
      () {
    final report = legacyReport().copyWith(tripPeriods: [
      period(1, 2),
      period(8, 8, TripType.dalamKota),
    ], hasGuestAllowance: true, guestUangSaku: 100000, guestTol: 10000);
    expect(report.mealDays, 3);
    expect(report.uangMakan, 150000);
    expect(report.totalPengeluaran, 500000);
    expect(report.sisa, 500000);
    expect(report.guestSisa, 90000);
    expect(report.pembayaranTagihan, 500000);
    final restored = Report.fromMap({...report.toMap(), 'uang_makan': 999999});
    expect(restored.uangMakan, 150000);
    expect(restored.toMap()['uang_makan'], 150000);
    expect(
        restored.copyWith(
            tripPeriods: [period(1, 3, TripType.dalamKota)]).uangMakan,
        150000);
    expect(restored.copyWith(tripPeriods: []).uangMakan, 0);
    expect(legacyReport().uangMakan, 0);
  });

  test('date overlap includes shared boundaries and ignores time of day', () {
    expect(
        TripPeriod.datesOverlap(DateTime(2026, 9, 1), DateTime(2026, 9, 8),
            DateTime(2026, 9, 3), DateTime(2026, 9, 5)),
        isTrue);
    expect(
        TripPeriod.datesOverlap(DateTime(2026, 9, 1), DateTime(2026, 9, 3, 1),
            DateTime(2026, 9, 3, 23), DateTime(2026, 9, 5)),
        isTrue);
    expect(
        TripPeriod.datesOverlap(DateTime(2026, 9, 1), DateTime(2026, 9, 2),
            DateTime(2026, 9, 3), DateTime(2026, 9, 5)),
        isFalse);
  });

  group('Report period contract', () {
    test('derives counts, preserves finances, and freezes input periods', () {
      final input = [period(1, 2), period(3, 5, TripType.dalamKota)];
      final original = legacyReport().copyWith(tripPeriods: input);
      input.clear();
      expect(original.tripPeriods, hasLength(2));
      expect(() => original.tripPeriods!.clear(), throwsUnsupportedError);
      expect(original.luarKotaCount, 2);
      expect(original.dalamKotaCount, 3);
      expect(original.uangMakan, 250000);
      expect(original.totalPengeluaran, 600000);
      expect(original.sisa, 400000);
      expect(original.pembayaranTagihan, legacyReport().pembayaranTagihan);
      final restored = Report.fromMap(original.toMap());
      expect(restored.toMap(), original.toMap());
      final edited = restored.copyWith(catatan: 'Edited');
      expect(edited.toMap(), {...original.toMap(), 'catatan': 'Edited'});
      expect(edited.id, 7);
      expect(edited.tanggalBuat, original.tanggalBuat);
      final onlyLk = original.copyWith(tripPeriods: [period(1, 5)]);
      expect(onlyLk.luarKotaCount, 5);
      expect(onlyLk.dalamKotaCount, 0);
    });

    test('retains legacy counts and category without inventing dates', () {
      final original = legacyReport();
      final edited =
          Report.fromMap(original.toMap()).copyWith(catatan: 'Edited');
      expect(edited.tripPeriods, isNull);
      expect(edited.toMap()['trip_periods'], isNull);
      expect(edited.luarKotaCount, 3);
      expect(edited.dalamKotaCount, 2);
      expect(edited.tripType, TripType.luarKota);
      final unknown = Report.fromMap({'trip_type': 'dalam_kota'});
      expect(unknown.tripPeriods, isNull);
      expect(unknown.luarKotaCount, isNull);
      expect(unknown.dalamKotaCount, isNull);
      expect(unknown.tripType, TripType.dalamKota);
    });

    test('clearing periods cannot resurrect legacy counts on later edits', () {
      for (final original in [
        legacyReport(),
        legacyReport().copyWith(tripPeriods: [period(1, 5)]),
      ]) {
        for (final cleared in [
          original.copyWith(tripPeriods: []),
          original.copyWith(resetTripData: true),
        ]) {
          expect(cleared.toMap()['trip_periods'], '[]');
          final restored = Report.fromMap(cleared.toMap()).copyWith(id: 99);
          expect(restored.tripPeriods, isEmpty);
          expect(restored.luarKotaCount, isNull);
          expect(restored.dalamKotaCount, isNull);
          expect(restored.uangMakan, 0);
          expect(restored.totalPengeluaran, 350000);
        }
      }
    });

    test('malformed period details fall back to complete saved totals', () {
      for (final details in <Object?>[
        null,
        1,
        '',
        'not json',
        '{}',
        '[null]',
        '[1]',
        '[[]]',
        '[{}]',
        jsonEncode([period(1, 2).toMap(), null]),
        jsonEncode([
          period(1, 2).toMap(),
          {...period(3, 5).toMap(), 'start': '2026-02-30'},
        ]),
      ]) {
        final restored = Report.fromMap({
          ...legacyReport().toMap(),
          'trip_periods': details,
        });
        expect(restored.tripPeriods, isNull, reason: '$details');
        expect(restored.luarKotaCount, 3, reason: '$details');
        expect(restored.dalamKotaCount, 2, reason: '$details');
        expect(restored.totalPengeluaran, legacyReport().totalPengeluaran);
      }
    });
  });
}
