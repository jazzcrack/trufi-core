import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufi_core_search_locations/trufi_core_search_locations.dart';

/// "+ Hausnummer" (fahrplaner.de fork patch, siehe FAHRPLANER_PATCHES.md,
/// Nutzer-Fund: Hausnummer-Eingabe nach einem Straßen-Suchtreffer ist
/// mühsam). Harness-Muster 1:1 aus location_search_screen_drilldown_test.dart
/// übernommen.
class _FakeService implements SearchLocationService {
  static const street = SearchLocation(
    id: 'street:1',
    displayName: 'Schleusenstraße',
    address: 'Bremerhaven',
    latitude: 53.55,
    longitude: 8.58,
    locationType: SearchLocationType.street,
  );
  static const poi = SearchLocation(
    id: 'poi:1',
    displayName: 'Café Nord',
    latitude: 53.56,
    longitude: 8.59,
    locationType: SearchLocationType.poi,
  );

  @override
  Future<List<SearchLocation>> search(String query) async => [street, poi];

  @override
  Future<SearchLocation?> reverse(double latitude, double longitude) async =>
      null;

  @override
  void dispose() {}
}

void main() {
  SearchLocation? picked;
  SearchLocation? houseNumberRequestedFor;

  Future<void> pumpAndSearch(
    WidgetTester tester, {
    Future<SearchLocation?> Function(SearchLocation)? onAddHouseNumber,
  }) async {
    picked = null;
    houseNumberRequestedFor = null;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates:
            SearchLocationsLocalizations.localizationsDelegates,
        supportedLocales: SearchLocationsLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              picked = await Navigator.push<SearchLocation>(
                context,
                MaterialPageRoute(
                  builder: (_) => LocationSearchScreen(
                    isOrigin: true,
                    searchService: _FakeService(),
                    onYourLocation: () async => null,
                    onChooseOnMap: () async => null,
                    onAddHouseNumber: onAddHouseNumber == null
                        ? null
                        : (street) {
                            houseNumberRequestedFor = street;
                            return onAddHouseNumber(street);
                          },
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'schleusen');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'ein Straßentreffer bekommt die "+ Hausnummer"-Aktion, ein POI-Treffer '
    'nicht',
    (tester) async {
      await pumpAndSearch(tester, onAddHouseNumber: (_) async => null);

      expect(find.byTooltip('Hausnummer hinzufügen'), findsOneWidget);
    },
  );

  testWidgets('ohne onAddHouseNumber-Callback erscheint keine Aktion', (
    tester,
  ) async {
    await pumpAndSearch(tester);

    expect(find.byTooltip('Hausnummer hinzufügen'), findsNothing);
  });

  testWidgets(
    'Tippen auf die Aktion ruft den Callback mit genau diesem Straßentreffer '
    'auf',
    (tester) async {
      await pumpAndSearch(tester, onAddHouseNumber: (_) async => null);

      await tester.tap(find.byTooltip('Hausnummer hinzufügen'));
      await tester.pumpAndSettle();

      expect(houseNumberRequestedFor?.id, 'street:1');
    },
  );

  testWidgets(
    'liefert der Callback ein Ergebnis, schließt der Suchscreen damit',
    (tester) async {
      const precise = SearchLocation(
        id: 'address:1',
        displayName: 'Schleusenstraße 39',
        address: 'Bremerhaven',
        latitude: 53.5501,
        longitude: 8.5802,
        locationType: SearchLocationType.address,
      );
      await pumpAndSearch(tester, onAddHouseNumber: (_) async => precise);

      await tester.tap(find.byTooltip('Hausnummer hinzufügen'));
      await tester.pumpAndSettle();

      expect(picked?.id, 'address:1');
    },
  );

  testWidgets(
    'liefert der Callback null (z. B. abgebrochen), bleibt die Ergebnisliste '
    'offen',
    (tester) async {
      await pumpAndSearch(tester, onAddHouseNumber: (_) async => null);

      await tester.tap(find.byTooltip('Hausnummer hinzufügen'));
      await tester.pumpAndSettle();

      expect(picked, isNull);
      expect(find.text('Schleusenstraße'), findsOneWidget);
    },
  );
}
