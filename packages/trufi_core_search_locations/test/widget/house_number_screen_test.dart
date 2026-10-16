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
  final List<String> queries = [];

  /// Antwortet nur auf genau diese Anfrage (sonst leer) - wie Nominatim,
  /// das bei einem unpassenden Adressteil nichts findet.
  final Map<String, List<SearchLocation>> answers;
  _FakeSearch([this.answers = const {}]);

  String? get lastQuery => queries.isEmpty ? null : queries.last;

  @override
  Future<List<SearchLocation>> search(String query) async {
    queries.add(query);
    return answers[query] ?? const [];
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

  testWidgets('unbekannte Nummer: Dialog bleibt offen, erklaert, "Trotzdem '
      'übernehmen" liefert die Strassenmitte als ungefaehr', (tester) async {
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

    // Anfragen ohne doppelte Strasse (Patch 63), mehrere Varianten (64)
    expect(search.queries, [
      'Oststraße 99, Bremerhaven-Fischereihafen',
      'Oststraße 99',
    ]);
    expect(result, isNull, reason: 'Dialog bleibt offen');
    expect(find.textContaining('nicht verzeichnet'), findsOneWidget);

    await tester.tap(find.text('Trotzdem übernehmen'));
    await tester.pumpAndSettle();

    expect(result, isA<HouseNumberLocated>());
    final located = result! as HouseNumberLocated;
    expect(located.approximate, isTrue);
    expect(located.location.displayName, 'Oststraße 99');
    expect(located.location.latitude, _street.latitude);
    expect(located.location.locationType, SearchLocationType.street);
  });

  group('Patch 63 Hilfsfunktionen', () {
    const street = SearchLocation(
      id: 'w',
      displayName: 'Am Neuen Hafen',
      address: 'Am Neuen Hafen, Mitte, Bremerhaven, Bremen, Deutschland',
      latitude: 53.55,
      longitude: 8.57,
      locationType: SearchLocationType.street,
    );

    test('Anfrage ohne doppelte Strasse (live: sonst 0 Treffer)', () {
      expect(
        houseNumberQuery(street, '5'),
        'Am Neuen Hafen 5, Mitte, Bremerhaven, Bremen, Deutschland',
      );
    });

    test('nur echter Treffer zaehlt - nicht die Strasse, nicht ein '
        'anderes Haus', () {
      SearchLocation hit(String name, String address, SearchLocationType t) =>
          SearchLocation(
            id: name,
            displayName: name,
            address: address,
            latitude: 0,
            longitude: 0,
            locationType: t,
          );
      expect(
        isHouseNumberMatch(
          hit(
            'Am Neuen Hafen',
            'Am Neuen Hafen 5, Mitte, Bremerhaven',
            SearchLocationType.address,
          ),
          street,
          '5',
        ),
        isTrue,
      );
      expect(
        isHouseNumberMatch(
          hit(
            'Am Neuen Hafen',
            'Am Neuen Hafen, Mitte, Bremerhaven',
            SearchLocationType.street,
          ),
          street,
          '22',
        ),
        isFalse,
      );
      expect(
        isHouseNumberMatch(
          hit(
            'Am Neuen Hafen',
            'Am Neuen Hafen 5, Mitte',
            SearchLocationType.address,
          ),
          street,
          '55',
        ),
        isFalse,
      );
    });

    test('Schaetzung zwischen Nachbarn derselben Strassenseite', () {
      const known = [
        HouseNumberSuggestion(number: '20', latitude: 1.0, longitude: 1.0),
        HouseNumberSuggestion(number: '21', latitude: 9.0, longitude: 9.0),
        HouseNumberSuggestion(number: '24', latitude: 3.0, longitude: 3.0),
      ];
      final estimate = estimateHouseNumberPosition('22', known)!;
      expect(estimate.latitude, closeTo(2.0, 1e-9)); // Mitte 20..24
      expect(estimateHouseNumberPosition('30', known)!.latitude, 3.0);
      expect(estimateHouseNumberPosition('22', const []), isNull);
      expect(estimateHouseNumberPosition('a', known), isNull);
    });
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

  testWidgets('Schleusenstrasse 22: volle Anfrage leer, "Strasse Nr, Stadt" '
      'findet ein Buero an der Adresse -> uebernommen (Patch 64)', (
    tester,
  ) async {
    _portrait(tester);
    const street = SearchLocation(
      id: 'way:9',
      displayName: 'Schleusenstraße',
      address: 'Schleusenstraße, Lehe, Bremerhaven, Bremen, Deutschland',
      latitude: 53.549,
      longitude: 8.583,
      locationType: SearchLocationType.street,
    );
    final search = _FakeSearch({
      'Schleusenstraße 22, Bremerhaven': [
        const SearchLocation(
          id: 'node:1',
          displayName: 'Logotomie',
          address:
              'Schleusenstraße 22, Mitte, Bremerhaven, Bremen, Deutschland',
          latitude: 53.5493,
          longitude: 8.5834,
          locationType: SearchLocationType.poi,
        ),
      ],
    });
    HouseNumberResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async => result = await showHouseNumberScreen(
              context,
              street: street,
              searchService: search,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '22');
    await tester.pump();
    await tester.tap(find.text('Schleusenstraße 22 übernehmen'));
    await tester.pumpAndSettle();

    expect(search.queries, [
      'Schleusenstraße 22, Lehe, Bremerhaven, Bremen, Deutschland',
      'Schleusenstraße 22, Lehe',
      'Schleusenstraße 22, Bremerhaven',
    ]);
    final located = result! as HouseNumberLocated;
    expect(located.approximate, isFalse);
    expect(located.location.displayName, 'Schleusenstraße 22');
    expect(located.location.latitude, 53.5493);
  });
}
