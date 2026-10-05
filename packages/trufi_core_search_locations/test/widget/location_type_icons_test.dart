import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufi_core_search_locations/trufi_core_search_locations.dart';

/// fahrplaner.de fork patch (05.10.2026, siehe FAHRPLANER_PATCHES.md):
/// die Suchergebnis-Liste zeigt jetzt ein zum SearchLocationType passendes
/// Icon statt immer eines generischen Pins, wenn ein Suchdienst locationType
/// befuellt hat.
class _FakeSearchService implements SearchLocationService {
  final List<SearchLocation> results;
  const _FakeSearchService(this.results);

  @override
  Future<List<SearchLocation>> search(String query) async => results;
  @override
  Future<SearchLocation?> reverse(double latitude, double longitude) async =>
      null;
  @override
  void dispose() {}
}

void main() {
  const stop = SearchLocation(
    id: '1',
    displayName: 'Bremen Hauptbahnhof',
    latitude: 53.0,
    longitude: 8.8,
    locationType: SearchLocationType.stop,
  );
  const poi = SearchLocation(
    id: '2',
    displayName: 'Café Sand',
    latitude: 53.1,
    longitude: 8.9,
    locationType: SearchLocationType.poi,
  );
  const street = SearchLocation(
    id: '3',
    displayName: 'Sögestraße',
    latitude: 53.07,
    longitude: 8.8,
    locationType: SearchLocationType.street,
  );
  const unknown = SearchLocation(
    id: '4',
    displayName: 'Irgendwo',
    latitude: 53.0,
    longitude: 8.8,
  );

  testWidgets(
    'Haltestelle/POI/Straße/unbekannt zeigen unterschiedliche Icons',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates:
              SearchLocationsLocalizations.localizationsDelegates,
          supportedLocales: SearchLocationsLocalizations.supportedLocales,
          home: LocationSearchScreen(
            isOrigin: true,
            searchService: const _FakeSearchService([
              stop,
              poi,
              street,
              unknown,
            ]),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).first, 'x');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.directions_bus_rounded), findsOneWidget);
      expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
      expect(find.byIcon(Icons.add_road_rounded), findsOneWidget);
      // "unknown" faellt auf das bisherige generische Pin-Icon zurueck.
      expect(find.byIcon(Icons.place_rounded), findsOneWidget);
    },
  );
}
