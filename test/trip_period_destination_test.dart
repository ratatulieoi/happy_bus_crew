import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bus_crew/models/report.dart';

void main() {
  const legacyPeriodMap = {
    'start': '2026-09-01',
    'end': '2026-09-03',
    'type': 'luar_kota',
  };

  TripPeriod period({String destination = ''}) => TripPeriod(
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 3),
        type: TripType.luarKota,
        destination: destination,
      );

  test('destination defaults to empty without changing the legacy map', () {
    final original = TripPeriod(
      start: DateTime(2026, 9, 1),
      end: DateTime(2026, 9, 3),
      type: TripType.luarKota,
    );
    expect(original.destination, isEmpty);
    expect(original.toMap(), legacyPeriodMap);
    expect(original.days, 3);
  });

  test('missing, null and empty stored destinations load as empty', () {
    for (final map in <Map<String, dynamic>>[
      legacyPeriodMap,
      {...legacyPeriodMap, 'destination': null},
      {...legacyPeriodMap, 'destination': ''},
    ]) {
      final restored = TripPeriod.fromMap(map);
      expect(restored.destination, isEmpty);
      expect(restored.toMap(), legacyPeriodMap);
    }
  });

  test('destination round-trips unchanged for both trip types', () {
    for (final type in [TripType.luarKota, TripType.dalamKota]) {
      for (final destination in [
        '',
        '  ',
        'Surabaya',
        'Batu / Café "A"\nMalang'
      ]) {
        final original = TripPeriod(
          start: DateTime(2026, 9, 1, 23),
          end: DateTime(2026, 9, 3, 8),
          type: type,
          destination: destination,
        );
        final restored = TripPeriod.fromMap(
            jsonDecode(jsonEncode(original.toMap())) as Map<String, dynamic>);
        expect(restored.destination, destination);
        expect(restored.toMap(), original.toMap());
        expect(restored.start, DateTime(2026, 9, 1));
        expect(restored.end, DateTime(2026, 9, 3));
        expect(restored.days, 3);
        expect(restored.type, type);
        if (destination.isNotEmpty) {
          expect(original.toMap()['destination'], destination);
        }
      }
    }
  });

  test('non-text stored destinations follow malformed-period handling', () {
    for (final destination in <Object>[
      1,
      false,
      <String>[],
      <String, String>{}
    ]) {
      final malformed = {...legacyPeriodMap, 'destination': destination};
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

  test('report JSON preserves each destination and loads legacy periods', () {
    final original = Report.fromMap({}).copyWith(tripPeriods: [
      period(destination: 'Malang'),
      TripPeriod(
        start: DateTime(2026, 9, 5),
        end: DateTime(2026, 9, 5),
        type: TripType.dalamKota,
        destination: 'Surabaya',
      ),
      TripPeriod.fromMap(
          {...legacyPeriodMap, 'start': '2026-09-07', 'end': '2026-09-07'}),
    ]);
    final stored = original.toMap();
    final restored = Report.fromMap(stored);
    expect(restored.tripPeriods!.map((period) => period.destination),
        ['Malang', 'Surabaya', '']);
    expect(restored.toMap(), stored);
    expect(restored.luarKotaCount, 4);
    expect(restored.dalamKotaCount, 1);
    expect(restored.mealDays, 5);
    expect(restored.uangMakan, 250000);
    expect(TripPeriod.validateNoOverlap(restored.tripPeriods!), isNull);
  });

  test('report copying preserves destination when keeping or copying periods',
      () {
    final original = Report.fromMap({})
        .copyWith(tripPeriods: [period(destination: 'Malang')]);
    for (final copied in [
      original.copyWith(catatan: 'Edited'),
      original.copyWith(id: 7),
      original.copyWith(tripPeriods: List.of(original.tripPeriods!)),
    ]) {
      expect(copied.tripPeriods!.single.destination, 'Malang');
      expect(copied.toMap()['trip_periods'], original.toMap()['trip_periods']);
      final restored = Report.fromMap(copied.toMap());
      expect(restored.tripPeriods!.single.destination, 'Malang');
    }
  });

  test('different destinations do not make overlapping periods valid', () {
    expect(
      TripPeriod.validateNoOverlap([
        period(destination: 'Malang'),
        period(destination: 'Surabaya'),
      ]),
      'Periode bertumpuk.',
    );
  });
}
