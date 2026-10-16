// fahrplaner.de fork patch 62: Vollbild-Dialog "Hausnummer".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufi_core_search_locations/trufi_core_search_locations.dart';

const _street = SearchLocation(
  id: 'way:1',
  displayName: 'Oststraße',
  address: 'Bremerhaven-Fischereihafen',
  latitude: 53.52,
  longitude: 8.58,
  locationType: SearchLocationType.street,
);

class _FakeSource implements HouseNumberSuggestionSource {
  final List<HouseNumberSuggestion> all;
  _FakeSource(this.all);

  @override
  Future<List<HouseNumberSuggestion>> suggest(
    SearchLocation street,
    String prefix,
  ) async => all.where((s) => s.number.startsWith(prefix)).toList();
}

class _FakeSearch implements SearchLocationService {
  String? lastQuery;

  @override
  Future<List<SearchLocation>> search(String query) async {
    lastQuery = query;
    return const [];
  }

  @override
  Future<SearchLocation?> reverse(double latitude, double longitude) async =>
      null;

  @override
  void dispose() {}
}

Future<HouseNumberResult?> _open(
  WidgetTester tester, {
  SearchLocationService? search,
  HouseNumberSuggestionSource? source,
}) async {
  HouseNumberResult? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showHouseNumberScreen(
              context,
              street: _street,
              searchService: search ?? _FakeSearch(),
              suggestionSource: source,
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

/// Hochformat-Telefon (die Standard-Testflaeche 800x600 ist Querformat).
void _portrait(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  final source = _FakeSource(const [
    HouseNumberSuggestion(number: '1', latitude: 53.521, longitude: 8.581),
    HouseNumberSuggestion(number: '12', latitude: 53.522, longitude: 8.582),
    HouseNumberSuggestion(number: '12a', latitude: 53.523, longitude: 8.583),
    HouseNumberSuggestion(number: '14', latitude: 53.524, longitude: 8.584),
  ]);

  testWidgets('"Ohne Hausnummer" liefert die Straße selbst', (tester) async {
    _portrait(tester);
    HouseNumberResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async => result = await showHouseNumberScreen(
              context,
              street: _street,
              searchService: _FakeSearch(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ohne Hausnummer'));
    await tester.pumpAndSettle();

    expect(result, isA<HouseNumberWithoutNumber>());
  });

  testWidgets('passende Hausnummern filtern beim Tippen; Auswahl wird mit '
      'echter Koordinate übernommen', (tester) async {
    _portrait(tester);
    HouseNumberResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async => result = await showHouseNumberScreen(
              context,
              street: _street,
              searchService: _FakeSearch(),
              suggestionSource: source,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('14'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '12');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('PASSENDE HAUSNUMMERN'), findsOneWidget);
    expect(find.text('12a'), findsOneWidget);
    expect(find.text('14'), findsNothing);

    await tester.tap(find.text('Oststraße 12 übernehmen'));
    await tester.pumpAndSettle();

    expect(result, isA<HouseNumberLocated>());
    final located = (result! as HouseNumberLocated).location;
    expect(located.displayName, 'Oststraße 12');
    expect(located.latitude, 53.522);
    expect(located.locationType, SearchLocationType.address);
  });

  testWidgets('unbekannte Nummer: Suche ohne Treffer -> NotFound', (
    tester,
  ) async {
    _portrait(tester);
    final search = _FakeSearch();
    HouseNumberResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async => result = await showHouseNumberScreen(
              context,
              street: _street,
              searchService: search,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '99');
    await tester.pump();
    await tester.tap(find.text('Oststraße 99 übernehmen'));
    await tester.pumpAndSettle();

    expect(search.lastQuery, 'Oststraße 99, Bremerhaven-Fischereihafen');
    expect(result, isA<HouseNumberNotFound>());
    expect((result! as HouseNumberNotFound).number, '99');
  });

  testWidgets('Querformat: Übernehmen in der Eingabezeile, "Ohne Nr." als '
      'erster Chip', (tester) async {
    tester.view.physicalSize = const Size(2532, 1170);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await _open(tester, source: source);

    expect(find.text('Übernehmen'), findsOneWidget);
    expect(find.text('Ohne Nr.'), findsOneWidget);
    expect(find.text('Ohne Hausnummer'), findsNothing);
  });
}
