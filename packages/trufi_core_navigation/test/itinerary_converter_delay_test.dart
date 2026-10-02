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
  test('toNavigationRoute carries arrivalDelay from routing.Leg to NavigationLeg', () {
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
  });

  test('toNavigationRoute leaves arrivalDelay null when the routing leg has none', () {
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
  });
}
