import 'package:flutter_test/flutter_test.dart';
import 'package:trufi_core_routing/trufi_core_routing.dart';

/// fahrplaner.de fork patch (07.10.2026, siehe FAHRPLANER_PATCHES.md):
/// Itinerary.hasCanceledLeg - "fällt aus" ist etwas anderes als "hat
/// Verspätung" und braucht eine eigene Prüfung statt sich auf
/// overallArrivalDelay zu verlassen.
void main() {
  group('Itinerary.hasCanceledLeg', () {
    Leg legWith({required String mode, RealtimeState? realtimeState}) => Leg(
      mode: mode,
      startTime: DateTime(2026, 1, 1, 10),
      endTime: DateTime(2026, 1, 1, 10, 10),
      duration: const Duration(minutes: 10),
      distance: 1000,
      transitLeg: mode != 'WALK',
      realtimeState: realtimeState,
    );

    Itinerary itineraryWith(List<Leg> legs) => Itinerary(
      legs: legs,
      startTime: DateTime(2026, 1, 1, 10),
      endTime: DateTime(2026, 1, 1, 10, 10),
      duration: const Duration(minutes: 10),
      walkDistance: 0,
      walkTime: Duration.zero,
    );

    test('is false when no leg carries a canceled state', () {
      final itinerary = itineraryWith([
        legWith(mode: 'WALK'),
        legWith(mode: 'BUS', realtimeState: RealtimeState.updated),
      ]);

      expect(itinerary.hasCanceledLeg, isFalse);
    });

    test('is true when any leg is canceled', () {
      final itinerary = itineraryWith([
        legWith(mode: 'WALK'),
        legWith(mode: 'BUS', realtimeState: RealtimeState.canceled),
        legWith(mode: 'WALK'),
      ]);

      expect(itinerary.hasCanceledLeg, isTrue);
    });

    test('is false when realtimeState is null (no real-time data)', () {
      final itinerary = itineraryWith([legWith(mode: 'BUS')]);

      expect(itinerary.hasCanceledLeg, isFalse);
    });
  });
}
