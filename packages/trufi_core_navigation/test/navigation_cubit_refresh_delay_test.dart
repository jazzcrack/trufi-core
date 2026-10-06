import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:trufi_core_navigation/trufi_core_navigation.dart';
import 'package:trufi_core_utils/trufi_core_utils.dart';

/// Minimale, nur fuer diesen Test gebrauchte GeolocatorPlatform-Fake -
/// liefert eine feste Position, genug damit startNavigation() erfolgreich
/// durchlaeuft (kein simuliertes Bewegen noetig, siehe
/// refreshCurrentLegDelay(), das unabhaengig von GPS-Updates arbeitet).
class _FixedPositionPlatform extends GeolocatorPlatform {
  final _stream = StreamController<Position>.broadcast();

  Position get _position => Position(
    latitude: 53.0,
    longitude: 8.8,
    timestamp: DateTime.now(),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async =>
      _position;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      _stream.stream;
}

/// fahrplaner.de fork patch (06.10.2026, siehe FAHRPLANER_PATCHES.md):
/// Regressionstest fuer den echten Nutzer-Fund "Sperrbildschirm zeigt
/// weiterhin puenktlich, obwohl der Bus inzwischen Verspaetung hat" -
/// arrivalDelay wird sonst nur einmalig von ItineraryConverter
/// .toNavigationRoute() gesetzt, nie vom Cubit selbst aktualisiert.
void main() {
  const stopA = NavigationStop(id: 'a', name: 'Start', position: LatLng(53.0, 8.8));
  const stopB = NavigationStop(id: 'b', name: 'Ziel', position: LatLng(53.0, 8.82));

  NavigationRoute buildRoute() => NavigationRoute(
    id: 'route-1',
    code: '506',
    name: 'Buslinie 506',
    geometry: [stopA.position, stopB.position],
    stops: const [stopA, stopB],
    legs: [
      NavigationLeg(
        id: 'leg-1',
        points: [stopA.position, stopB.position],
        isTransit: true,
        tripId: 'vbn:123',
      ),
    ],
  );

  test('setzt eine neue Verspaetung auf dem aktuellen Abschnitt', () async {
    final locationService = LocationService(platform: _FixedPositionPlatform());
    final cubit = NavigationCubit(locationService: locationService);
    addTearDown(cubit.close);

    await cubit.startNavigation(buildRoute());
    expect(cubit.state.currentLeg?.arrivalDelay, isNull);

    cubit.refreshCurrentLegDelay(const Duration(minutes: 4));

    expect(cubit.state.currentLeg?.arrivalDelay, const Duration(minutes: 4));
    // Andere Felder des Leg bleiben unveraendert.
    expect(cubit.state.currentLeg?.tripId, 'vbn:123');
    expect(cubit.state.currentLeg?.isTransit, isTrue);
  });

  test('kann eine Verspaetung auch wieder auf null zuruecksetzen', () async {
    final locationService = LocationService(platform: _FixedPositionPlatform());
    final cubit = NavigationCubit(locationService: locationService);
    addTearDown(cubit.close);

    await cubit.startNavigation(buildRoute());
    cubit.refreshCurrentLegDelay(const Duration(minutes: 4));
    expect(cubit.state.currentLeg?.arrivalDelay, const Duration(minutes: 4));

    cubit.refreshCurrentLegDelay(null);

    expect(cubit.state.currentLeg?.arrivalDelay, isNull);
  });

  test('ist ein No-Op ohne aktive Route', () async {
    final locationService = LocationService(platform: _FixedPositionPlatform());
    final cubit = NavigationCubit(locationService: locationService);
    addTearDown(cubit.close);

    expect(() => cubit.refreshCurrentLegDelay(const Duration(minutes: 1)),
        returnsNormally);
    expect(cubit.state.route, isNull);
  });
}
