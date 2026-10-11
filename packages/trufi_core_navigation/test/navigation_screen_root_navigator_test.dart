// fahrplaner.de fork patch (Patch 43, see FAHRPLANER_PATCHES.md):
// NavigationScreen.show() now pushes on the app's ROOT Navigator instead of
// the nearest one. A host using a nested Navigator below some persistent
// chrome (e.g. AppConfiguration.bottomNavTabs' bottom NavigationBar/
// NavigationRail) would otherwise get a NavigationScreen confined to that
// nested Navigator's own box - which is only the body slot ABOVE the bottom
// bar/left of the rail, never the full screen. This test builds a minimal
// stand-in for that shape (an outer Scaffold with a persistent bottom bar
// around an inner, separate Navigator - the same relationship go_router's
// StatefulShellRoute has between its outer shell and a branch's nested
// Navigator) without depending on go_router itself.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:trufi_core_navigation/trufi_core_navigation.dart';
import 'package:trufi_core_utils/trufi_core_utils.dart';

const _barHeight = 80.0;

const _stopA = NavigationStop(
  id: 'a',
  name: 'Start',
  position: LatLng(53.0, 8.8),
);
const _stopB = NavigationStop(
  id: 'b',
  name: 'Ziel',
  position: LatLng(53.0, 8.82),
);

NavigationRoute _buildRoute() => NavigationRoute(
  id: 'route-1',
  code: '506',
  name: 'Buslinie 506',
  geometry: const [
    _stopA,
    _stopB,
  ].map((s) => s.position).toList(growable: false),
  stops: const [_stopA, _stopB],
  legs: [
    NavigationLeg(
      id: 'leg-1',
      points: const [_stopA, _stopB].map((s) => s.position).toList(),
      isTransit: true,
    ),
  ],
);

/// Same fake as navigation_screen_external_cubit_test.dart - a real
/// LocationService without a fixed platform hangs pumpAndSettle() on the
/// geolocator plugin channel, which doesn't exist in this test environment.
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

Widget _appWithNestedNavigator() {
  return MaterialApp(
    localizationsDelegates: NavigationLocalizations.localizationsDelegates,
    supportedLocales: NavigationLocalizations.supportedLocales,
    home: Scaffold(
      body: Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('start'),
                onPressed: () => NavigationScreen.show(
                  context,
                  route: _buildRoute(),
                  locationService: LocationService(
                    platform: _FixedPositionPlatform(),
                  ),
                  mapBuilder: (ctx, state, layers) =>
                      const SizedBox.expand(key: Key('nav-screen-map')),
                ),
                child: const Text('start'),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: const SizedBox(
        height: _barHeight,
        child: ColoredBox(color: Colors.black12),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'NavigationScreen.show() covers the full screen, not just the body '
    'slot above a persistent bottom bar in an outer shell',
    (tester) async {
      await tester.pumpWidget(_appWithNestedNavigator());
      await tester.pumpAndSettle();

      final screenSize =
          tester.view.physicalSize / tester.view.devicePixelRatio;

      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();

      final mapSize = tester.getSize(find.byKey(const Key('nav-screen-map')));
      expect(
        mapSize.height,
        screenSize.height,
        reason:
            'a push confined to the inner Navigator would be $_barHeight '
            'px shorter than the full screen (the bottom bar\'s height)',
      );
    },
  );
}
