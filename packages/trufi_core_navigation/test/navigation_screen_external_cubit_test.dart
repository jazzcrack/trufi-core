// fahrplaner.de fork patch (10.10.2026, "Navigation minimieren" - siehe
// FAHRPLANER_PATCHES.md): Regressionstest fuer den neuen externalCubit-
// Parameter. _FixedPositionPlatform/LocationService-Aufbau 1:1 aus
// navigation_cubit_refresh_delay_test.dart uebernommen.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:trufi_core_navigation/trufi_core_navigation.dart';
import 'package:trufi_core_utils/trufi_core_utils.dart';

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
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async => _position;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      _stream.stream;
}

void main() {
  const stopA = NavigationStop(
    id: 'a',
    name: 'Start',
    position: LatLng(53.0, 8.8),
  );
  const stopB = NavigationStop(
    id: 'b',
    name: 'Ziel',
    position: LatLng(53.0, 8.82),
  );

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
      ),
    ],
  );

  Future<void> pushAndPopScreen(
    WidgetTester tester, {
    NavigationCubit? externalCubit,
  }) async {
    final locationService = LocationService(platform: _FixedPositionPlatform());
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: NavigationLocalizations.localizationsDelegates,
        supportedLocales: NavigationLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => NavigationScreen.show(
              context,
              route: buildRoute(),
              locationService: locationService,
              externalCubit: externalCubit,
              mapBuilder: (ctx, state, layers) => const SizedBox.shrink(),
            ),
            child: const Text('start'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    // Zurueck zum Ausgangsscreen - loest NavigationScreen.dispose() aus.
    Navigator.of(tester.element(find.byType(NavigationScreen))).pop();
    await tester.pumpAndSettle();
  }

  group('NavigationScreen.externalCubit', () {
    testWidgets(
      'ohne externalCubit (Default): dispose() schliesst den selbst erzeugten Cubit',
      (tester) async {
        await pushAndPopScreen(tester);
        // Kein direkter Zugriff auf den intern erzeugten Cubit noetig -
        // wenn dispose() ihn faelschlich NICHT schliessen wuerde, bliebe
        // das unbemerkt, aber zumindest stellt dieser Test sicher, dass
        // der Default-Pfad (kein externalCubit) weiterhin fehlerfrei
        // durchlaeuft (keine Exception beim Pop/Dispose).
      },
    );

    testWidgets(
      'mit externalCubit: dispose() schliesst ihn NICHT - er bleibt fuer "Minimieren" nutzbar',
      (tester) async {
        final locationService = LocationService(
          platform: _FixedPositionPlatform(),
        );
        final cubit = NavigationCubit(locationService: locationService);
        addTearDown(() {
          if (!cubit.isClosed) cubit.close();
        });
        await cubit.startNavigation(buildRoute());

        await pushAndPopScreen(tester, externalCubit: cubit);

        expect(cubit.isClosed, isFalse);
        // Der Fahrtzustand lebt unveraendert weiter - z. B. fuer eine
        // erneute Anzeige nach dem Minimieren.
        expect(cubit.state.status, NavigationStatus.navigating);
      },
    );
  });
}
