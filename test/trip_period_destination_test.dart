import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bus_crew/models/report.dart';

void main() {
  const legacyPeriodMap = {
    'start': '2026-09-01',
    'end': '2026-09-03',
    'type': 'luar_kota',
  };

  TripPeriod period({String origin = '', String destination = ''}) => TripPeriod(
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 3),
        type: TripType.luarKota,
        origin: origin,
        destination: destination,
      );

  test('origin and destination default to empty without changing the legacy map',
      () {
    final original = period();
    expect(original.origin, isEmpty);
    expect(original.destination, isEmpty);
    expect(original.toMap(), legacyPeriodMap);
    expect(original.days, 3);
  });

  for (final field in ['origin', 'destination']) {
    test('missing, null and empty stored $field load as empty', () {
      final otherField = field == 'origin' ? 'destination' : 'origin';
      final stored = {...legacyPeriodMap, otherField: 'Malang'};
      for (final map in <Map<String, dynamic>>[
        stored,
        {...stored, field: null},
        {...stored, field: ''},
      ]) {
        final restored = TripPeriod.fromMap(map);
        expect(field == 'origin' ? restored.origin : restored.destination,
            isEmpty);
        expect(restored.toMap(), stored);
      }
    });

    test('non-text stored $field follows malformed-period handling', () {
      for (final value in <Object>[1, false, <String>[], <String, String>{}]) {
        final malformed = {...legacyPeriodMap, field: value};
        expect(() => TripPeriod.fromMap(malformed), throwsFormatException);
        final restored = Report.fromMap({
          'trip_periods': jsonEncode([malformed]),
          'luar_kota_count': 3,
          'dalam_kota_count': 0,
        });
        expect(restored.tripPeriods, isNull);
        expect(restored.luarKotaCount, 3);
        expect(restored.dalamKotaCount, 0);
      }
    });
  }

  test('origin and destination round-trip independently for both trip types', () {
    const values = ['', '  ', 'Surabaya', 'Batu / Café "A"\nMalang'];
    for (final type in [TripType.luarKota, TripType.dalamKota]) {
      for (final origin in values) {
        for (final destination in values) {
          final original = TripPeriod(
            start: DateTime(2026, 9, 1, 23),
            end: DateTime(2026, 9, 3, 8),
            type: type,
            origin: origin,
            destination: destination,
          );
          final restored = TripPeriod.fromMap(
              jsonDecode(jsonEncode(original.toMap())) as Map<String, dynamic>);
          expect(restored.origin, origin);
          expect(restored.destination, destination);
          expect(restored.toMap(), original.toMap());
          expect(restored.start, DateTime(2026, 9, 1));
          expect(restored.end, DateTime(2026, 9, 3));
          expect(restored.days, 3);
          expect(restored.type, type);
          expect(original.toMap(), {
            ...legacyPeriodMap,
            'type': type.value,
            if (origin.isNotEmpty) 'origin': origin,
            if (destination.isNotEmpty) 'destination': destination,
          });
        }
      }
    }
  });

  test('report JSON preserves each route and loads destination-only periods', () {
    final original = Report.fromMap({}).copyWith(tripPeriods: [
      period(origin: 'Surabaya', destination: 'Malang'),
      TripPeriod(
        start: DateTime(2026, 9, 5),
        end: DateTime(2026, 9, 5),
        type: TripType.dalamKota,
        origin: 'Sidoarjo',
        destination: 'Surabaya',
      ),
      TripPeriod.fromMap({
        ...legacyPeriodMap,
        'start': '2026-09-07',
        'end': '2026-09-07',
        'destination': 'Kediri',
      }),
    ]);
    final stored = original.toMap();
    final restored = Report.fromMap(stored);
    expect(restored.tripPeriods!.map((period) => period.origin),
        ['Surabaya', 'Sidoarjo', '']);
    expect(restored.tripPeriods!.map((period) => period.destination),
        ['Malang', 'Surabaya', 'Kediri']);
    expect(restored.toMap(), stored);
    expect(restored.luarKotaCount, 4);
    expect(restored.dalamKotaCount, 1);
    expect(restored.mealDays, 5);
    expect(restored.uangMakan, 250000);
    expect(TripPeriod.validateNoOverlap(restored.tripPeriods!), isNull);
  });

  test('report copying preserves origin and destination', () {
    final original = Report.fromMap({}).copyWith(
        tripPeriods: [period(origin: 'Surabaya', destination: 'Malang')]);
    for (final copied in [
      original.copyWith(catatan: 'Edited'),
      original.copyWith(id: 7),
      original.copyWith(tripPeriods: List.of(original.tripPeriods!)),
    ]) {
      expect(copied.tripPeriods!.single.origin, 'Surabaya');
      expect(copied.tripPeriods!.single.destination, 'Malang');
      expect(copied.toMap()['trip_periods'], original.toMap()['trip_periods']);
      final restored = Report.fromMap(copied.toMap());
      expect(restored.tripPeriods!.single.origin, 'Surabaya');
      expect(restored.tripPeriods!.single.destination, 'Malang');
    }
  });

  test('different routes do not make overlapping periods valid', () {
    expect(
      TripPeriod.validateNoOverlap([
        period(origin: 'Surabaya', destination: 'Malang'),
        period(origin: 'Sidoarjo', destination: 'Surabaya'),
      ]),
      'Periode bertumpuk.',
    );
  });
}
