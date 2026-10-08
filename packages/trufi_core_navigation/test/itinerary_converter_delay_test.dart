import 'package:flutter_test/flutter_test.dart';
import 'package:trufi_core_navigation/trufi_core_navigation.dart';
import 'package:trufi_core_routing/trufi_core_routing.dart' as routing;

/// fahrplaner.de fork patch (see FAHRPLANER_PATCHES.md): the Verspätungsanzeige
/// (Kapitel 3.18) only reached the route-results list at first - a real
/// tester explicitly noted it was missing during active navigation
/// (02.10.2026). ItineraryConverter.toNavigationRoute() must carry
/// routing.Leg.arrivalDelay over into NavigationLeg.arrivalDelay for the
/// navigation map's leg-detail sheet to show it.
void main() {
  test(
    'toNavigationRoute carries arrivalDelay from routing.Leg to NavigationLeg',
    () {
      final leg = routing.Leg(
        mode: 'BUS',
        startTime: DateTime(2026, 1, 1, 10),
        endTime: DateTime(2026, 1, 1, 10, 10),
        duration: const Duration(minutes: 10),
        distance: 2000,
        transitLeg: true,
        decodedPoints: const [],
        arrivalDelay: const Duration(minutes: 4),
      );
      final itinerary = routing.Itinerary(
        legs: [leg],
        startTime: DateTime(2026, 1, 1, 10),
        endTime: DateTime(2026, 1, 1, 10, 10),
        duration: const Duration(minutes: 10),
        walkDistance: 0,
        walkTime: Duration.zero,
      );

      final route = ItineraryConverter.toNavigationRoute(itinerary);

      expect(route.legs, hasLength(1));
      expect(route.legs.first.arrivalDelay, const Duration(minutes: 4));
    },
  );

  test(
    'toNavigationRoute carries tripId and stop gtfsIds over (06.10.2026)',
    () {
      final fromPlace = routing.Place(
        name: 'Start',
        lat: 53.0,
        lon: 8.8,
        stopId: 'vbn:stop-1',
      );
      final toPlace = routing.Place(
        name: 'Ziel',
        lat: 53.1,
        lon: 8.9,
        stopId: 'vbn:stop-2',
      );
      final leg = routing.Leg(
        mode: 'BUS',
        startTime: DateTime(2026, 1, 1, 10),
        endTime: DateTime(2026, 1, 1, 10, 10),
        duration: const Duration(minutes: 10),
        distance: 2000,
        transitLeg: true,
        decodedPoints: const [],
        fromPlace: fromPlace,
        toPlace: toPlace,
        tripId: 'vbn:trip-42',
      );
      final itinerary = routing.Itinerary(
        legs: [leg],
        startTime: DateTime(2026, 1, 1, 10),
        endTime: DateTime(2026, 1, 1, 10, 10),
        duration: const Duration(minutes: 10),
        walkDistance: 0,
        walkTime: Duration.zero,
      );

      final route = ItineraryConverter.toNavigationRoute(itinerary);

      expect(route.legs.first.tripId, 'vbn:trip-42');
      expect(route.stops.first.gtfsStopId, 'vbn:stop-1');
      expect(route.stops.last.gtfsStopId, 'vbn:stop-2');
    },
  );

  test(
    'toNavigationRoute carries realtimeState/isCanceled over (07.10.2026)',
    () {
      final canceledLeg = routing.Leg(
        mode: 'BUS',
        startTime: DateTime(2026, 1, 1, 10),
        endTime: DateTime(2026, 1, 1, 10, 10),
        duration: const Duration(minutes: 10),
        distance: 2000,
        transitLeg: true,
        decodedPoints: const [],
        realtimeState: routing.RealtimeState.canceled,
      );
      final scheduledLeg = routing.Leg(
        mode: 'WALK',
        startTime: DateTime(2026, 1, 1, 10, 10),
        endTime: DateTime(2026, 1, 1, 10, 15),
        duration: const Duration(minutes: 5),
        distance: 300,
        transitLeg: false,
        decodedPoints: const [],
        realtimeState: routing.RealtimeState.scheduled,
      );
      final itinerary = routing.Itinerary(
        legs: [canceledLeg, scheduledLeg],
        startTime: DateTime(2026, 1, 1, 10),
        endTime: DateTime(2026, 1, 1, 10, 15),
        duration: const Duration(minutes: 15),
        walkDistance: 300,
        walkTime: const Duration(minutes: 5),
      );

      final route = ItineraryConverter.toNavigationRoute(itinerary);

      expect(route.legs[0].realtimeState, routing.RealtimeState.canceled);
      expect(route.legs[0].isCanceled, isTrue);
      expect(route.legs[1].realtimeState, routing.RealtimeState.scheduled);
      expect(route.legs[1].isCanceled, isFalse);
    },
  );

  test(
    'toNavigationRoute leaves arrivalDelay null when the routing leg has none',
    () {
      final leg = routing.Leg(
        mode: 'WALK',
        startTime: DateTime(2026, 1, 1, 10),
        endTime: DateTime(2026, 1, 1, 10, 5),
        duration: const Duration(minutes: 5),
        distance: 400,
        transitLeg: false,
        decodedPoints: const [],
      );
      final itinerary = routing.Itinerary(
        legs: [leg],
        startTime: DateTime(2026, 1, 1, 10),
        endTime: DateTime(2026, 1, 1, 10, 5),
        duration: const Duration(minutes: 5),
        walkDistance: 400,
        walkTime: const Duration(minutes: 5),
      );

      final route = ItineraryConverter.toNavigationRoute(itinerary);

      expect(route.legs.first.arrivalDelay, isNull);
    },
  );
}
