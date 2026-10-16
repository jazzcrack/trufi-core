// fahrplaner.de fork patch 61 (16.10.2026, T055): Leg.tripPatternId muss
// `pattern.code` sein - das ist der Schluessel, den fetchTransitRouteById()
// per `pattern(id: $id)` auf dem OTP-Server findet. Werte unten sind ECHTE
// Antworten des Produktiv-Servers (Linie 509, Bremerhaven, 16.10.2026):
//   pattern(id: "UGF0dGVybjoxOjMyODgwOjA6MDg") -> null
//   pattern(id: "1:32880:0:08")                -> Treffer
// Der fruehere Test (Patch 13) nutzte erfundene Werte und hielt deshalb das
// Gegenteil fest - genau die Ursache fuer "Linie nicht gefunden".
import 'package:flutter_test/flutter_test.dart';
import 'package:trufi_core_routing/trufi_core_routing.dart';

const _realId = 'UGF0dGVybjoxOjMyODgwOjA6MDg';
const _realCode = '1:32880:0:08';

Map<String, dynamic> _planWithPattern({String? id, String? code}) {
  return {
    'plan': {
      'itineraries': [
        {
          'legs': [
            {
              'mode': 'BUS',
              'transitLeg': true,
              'trip': {
                'pattern': {'id': ?id, 'code': ?code},
              },
            },
          ],
        },
      ],
    },
  };
}

void main() {
  group('Otp28ResponseParser leg.tripPatternId', () {
    test('wird aus pattern.code befuellt (der Lookup-Schluessel)', () {
      final plan = Otp28ResponseParser.parsePlan(
        _planWithPattern(id: _realId, code: _realCode),
      );

      expect(plan.itineraries!.single.legs.single.tripPatternId, _realCode);
    });

    test('faellt auf pattern.id zurueck, wenn kein code geliefert wird', () {
      final plan = Otp28ResponseParser.parsePlan(_planWithPattern(id: _realId));

      expect(plan.itineraries!.single.legs.single.tripPatternId, _realId);
    });

    test('null ohne pattern', () {
      final plan = Otp28ResponseParser.parsePlan(_planWithPattern());

      expect(plan.itineraries!.single.legs.single.tripPatternId, isNull);
    });
  });

  group('patternLookupKey (alte Relay-IDs aus gemerkten Fahrten)', () {
    test('Relay-ID wird zum Code', () {
      expect(patternLookupKey(_realId), _realCode);
    });

    test('ein Code bleibt unveraendert', () {
      expect(patternLookupKey(_realCode), _realCode);
    });

    test('Unlesbares bleibt unveraendert', () {
      expect(patternLookupKey('kein-base64!'), 'kein-base64!');
    });
  });
}
