// fahrplaner.de fork patch (04.10.2026, Kapitel 3.26): Regressionstest fuer
// einen echten Upstream-Bug. Leg.tripPatternId wurde aus `pattern.code`
// statt `pattern.id` befuellt - fetchTransitRouteById() fragt anschliessend
// `pattern(id: $id)` ab, was mit `code` IMMER fehlschlaegt ("Linie nicht
// gefunden" beim Antippen einer Linienbadge in einer Verbindung, siehe
// FAHRPLANER_PATCHES.md). `code` ist bei OTP ein menschenlesbares Kuerzel,
// keine gueltige Lookup-ID.
import 'package:flutter_test/flutter_test.dart';
import 'package:trufi_core_routing/trufi_core_routing.dart';

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
    test('wird aus pattern.id befuellt, nicht pattern.code', () {
      final plan = Otp28ResponseParser.parsePlan(
        _planWithPattern(id: 'RS1:1:01', code: 'RS1'),
      );

      expect(plan.itineraries!.single.legs.single.tripPatternId, 'RS1:1:01');
    });

    test('ist null, wenn pattern.id fehlt - auch wenn code vorhanden ist', () {
      final plan = Otp28ResponseParser.parsePlan(
        _planWithPattern(code: 'RS1'),
      );

      expect(plan.itineraries!.single.legs.single.tripPatternId, isNull);
    });
  });
}
