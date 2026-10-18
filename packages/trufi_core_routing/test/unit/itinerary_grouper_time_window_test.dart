// fahrplaner.de fork patch 65: dieselbe Linie zu einer anderen Zeit ist in
// Fahrplan-Netzen eine eigene Verbindung, keine Gruppen-Option.
import 'package:flutter_test/flutter_test.dart';
import 'package:trufi_core_routing/trufi_core_routing.dart';

Place _stop(String id, double lat, double lon) => Place(name: id, lat: lat, lon: lon, stopId: id);

Leg _ride(String line, String mode, DateTime start, Place from, Place to) => Leg(
  mode: mode,
  startTime: start,
  endTime: start.add(const Duration(minutes: 30)),
  duration: const Duration(minutes: 30),
  distance: 5000,
  transitLeg: true,
  route: Route(gtfsId: '1:$line', shortName: line),
  shortName: line,
  fromPlace: from,
  toPlace: to,
);

Itinerary _it(List<Leg> legs) => Itinerary(
  legs: legs,
  startTime: legs.first.startTime,
  endTime: legs.last.endTime,
  walkTime: Duration.zero,
  duration: legs.last.endTime.difference(legs.first.startTime),
  walkDistance: 0,
);

void main() {
  final a = _stop('a', 53.54, 8.58), hub = _stop('hub', 53.53, 8.60), z = _stop('z', 53.08, 8.81);
  final eight = DateTime(2026, 10, 19, 8, 7), nine = DateTime(2026, 10, 19, 9, 7);
  final at8 = _it([_ride('508', 'BUS', eight, a, hub), _ride('RS2', 'RAIL', eight.add(const Duration(minutes: 35)), hub, z)]);
  final at9 = _it([_ride('508', 'BUS', nine, a, hub), _ride('RS2', 'RAIL', nine.add(const Duration(minutes: 35)), hub, z)]);
  final at8re9 = _it([_ride('508', 'BUS', eight, a, hub), _ride('RE9', 'RAIL', eight.add(const Duration(minutes: 45)), hub, z)]);

  test('gleiche Linie, andere Stunde: zwei Gruppen', () {
    final groups = groupItineraries([at8, at9]);
    expect(groups, hasLength(2));
  });

  test('gleiche Hauptfahrt, andere Anschluesse: eine Gruppe mit Optionen', () {
    final groups = groupItineraries([at8, at8re9, at9]);
    expect(groups, hasLength(2));
    expect(groups.first.alternatives, containsAll([at8, at8re9]));
  });

  test('ohne Zeitfenster (Upstream-Verhalten) eine Gruppe', () {
    expect(groupItineraries([at8, at9], sameDepartureWindow: null), hasLength(1));
  });
}
