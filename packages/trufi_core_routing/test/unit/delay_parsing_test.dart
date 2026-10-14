import 'package:flutter_test/flutter_test.dart';
import 'package:trufi_core_routing/trufi_core_routing.dart';

/// fahrplaner.de fork patch (see FAHRPLANER_PATCHES.md): Leg.departureDelay/
/// arrivalDelay parsed from OTP's `start.estimated.delay`/
/// `end.estimated.delay`, and Itinerary.overallArrivalDelay walking back
/// from the last leg that actually carries real-time data.
void main() {
  group('Otp28ResponseParser delay parsing', () {
    Map<String, dynamic> legJson({
      Map<String, dynamic>? start,
      Map<String, dynamic>? end,
    }) => {
      'mode': 'BUS',
      'startTime': 1700000000000,
      'endTime': 1700000600000,
      'duration': 600,
      'distance': 1000.0,
      'transitLeg': true,
      if (start != null) 'start': start,
      if (end != null) 'end': end,
    };

    Map<String, dynamic> planJson(List<Map<String, dynamic>> legs) => {
      'plan': {
        'from': {'name': 'A', 'lat': 0.0, 'lon': 0.0},
        'to': {'name': 'B', 'lat': 0.0, 'lon': 0.0},
        'itineraries': [
          {
            'startTime': 1700000000000,
            'endTime': 1700000600000,
            'duration': 600,
            'legs': legs,
          },
        ],
      },
    };

    test('parses a positive delay (late) in seconds', () {
      final plan = Otp28ResponseParser.parsePlan(
        planJson([
          legJson(
            start: {
              'scheduledTime': '2026-01-01T10:00:00Z',
              'estimated': {'delay': 320},
            },
            end: {
              'scheduledTime': '2026-01-01T10:10:00Z',
              'estimated': {'delay': 400},
            },
          ),
        ]),
      );
      final leg = plan.itineraries!.first.legs.first;
      expect(leg.departureDelay, const Duration(seconds: 320));
      expect(leg.arrivalDelay, const Duration(seconds: 400));
    });

    test('parses a negative delay (early)', () {
      final plan = Otp28ResponseParser.parsePlan(
        planJson([
          legJson(
            end: {
              'scheduledTime': '2026-01-01T10:10:00Z',
              'estimated': {'delay': -45},
            },
          ),
        ]),
      );
      expect(
        plan.itineraries!.first.legs.first.arrivalDelay,
        const Duration(seconds: -45),
      );
    });

    test('is null when there is no real-time data (estimated missing)', () {
      final plan = Otp28ResponseParser.parsePlan(
        planJson([
          legJson(end: {'scheduledTime': '2026-01-01T10:10:00Z'}),
        ]),
      );
      expect(plan.itineraries!.first.legs.first.arrivalDelay, isNull);
    });

    test('is null when start/end are absent entirely (older/offline data)', () {
      final plan = Otp28ResponseParser.parsePlan(planJson([legJson()]));
      expect(plan.itineraries!.first.legs.first.arrivalDelay, isNull);
      expect(plan.itineraries!.first.legs.first.departureDelay, isNull);
    });

    group('echter Nutzer-Fund (14.10.2026): estimated.delay als ISO-8601-'
        'Duration-String statt Zahl', () {
      // Live gegen den echten OTP-Server verifiziert: "estimated": {"delay":
      // "PT1M5S"} statt der von diesem Code bis dahin angenommenen Zahl
      // "estimated": {"delay": 65} - die alte `is! num`-Pruefung griff
      // deshalb IMMER, jede Planung/laufende Fahrt bekam dauerhaft `null`
      // zurueck, obwohl derselbe Server (bestaetigt per `arrivalDelay: 129`
      // im selben Response) tatsaechlich Echtzeitdaten hatte. Die
      // bisherigen Tests oben nutzten nur Zahlen als Fixture - genau das
      // verdeckte den Fehler.
      test('parses minutes+seconds ("PT1M5S")', () {
        final plan = Otp28ResponseParser.parsePlan(
          planJson([
            legJson(
              end: {
                'scheduledTime': '2026-01-01T10:10:00Z',
                'estimated': {'delay': 'PT1M5S'},
              },
            ),
          ]),
        );
        expect(
          plan.itineraries!.first.legs.first.arrivalDelay,
          const Duration(minutes: 1, seconds: 5),
        );
      });

      test('parses a zero duration ("PT0S") as no delay', () {
        final plan = Otp28ResponseParser.parsePlan(
          planJson([
            legJson(
              end: {
                'scheduledTime': '2026-01-01T10:10:00Z',
                'estimated': {'delay': 'PT0S'},
              },
            ),
          ]),
        );
        expect(plan.itineraries!.first.legs.first.arrivalDelay, Duration.zero);
      });

      test('parses hours+minutes+seconds ("PT1H2M3S")', () {
        final plan = Otp28ResponseParser.parsePlan(
          planJson([
            legJson(
              end: {
                'scheduledTime': '2026-01-01T10:10:00Z',
                'estimated': {'delay': 'PT1H2M3S'},
              },
            ),
          ]),
        );
        expect(
          plan.itineraries!.first.legs.first.arrivalDelay,
          const Duration(hours: 1, minutes: 2, seconds: 3),
        );
      });

      test('parses a negative duration ("-PT45S") as early', () {
        final plan = Otp28ResponseParser.parsePlan(
          planJson([
            legJson(
              end: {
                'scheduledTime': '2026-01-01T10:10:00Z',
                'estimated': {'delay': '-PT45S'},
              },
            ),
          ]),
        );
        expect(
          plan.itineraries!.first.legs.first.arrivalDelay,
          const Duration(seconds: -45),
        );
      });

      test('is null for an unparsable string', () {
        final plan = Otp28ResponseParser.parsePlan(
          planJson([
            legJson(
              end: {
                'scheduledTime': '2026-01-01T10:10:00Z',
                'estimated': {'delay': 'not-a-duration'},
              },
            ),
          ]),
        );
        expect(plan.itineraries!.first.legs.first.arrivalDelay, isNull);
      });
    });
  });

  group('Itinerary.overallArrivalDelay', () {
    Leg leg({Duration? arrivalDelay}) => Leg(
      mode: 'BUS',
      startTime: DateTime(2026),
      endTime: DateTime(2026),
      duration: const Duration(minutes: 10),
      distance: 1000,
      transitLeg: true,
      arrivalDelay: arrivalDelay,
    );

    test('takes the last leg\'s delay when it has real-time data', () {
      final itinerary = Itinerary(
        legs: [
          leg(arrivalDelay: const Duration(seconds: 120)),
          leg(arrivalDelay: const Duration(seconds: 400)),
        ],
        startTime: DateTime(2026),
        endTime: DateTime(2026),
        duration: const Duration(minutes: 20),
        walkDistance: 0,
        walkTime: Duration.zero,
      );
      expect(itinerary.overallArrivalDelay, const Duration(seconds: 400));
    });

    test(
      'falls back to an earlier leg when the last leg has no real-time data (e.g. trailing walk)',
      () {
        final itinerary = Itinerary(
          legs: [
            leg(arrivalDelay: const Duration(seconds: 180)),
            leg(), // trailing walk leg, no GTFS-RT data
          ],
          startTime: DateTime(2026),
          endTime: DateTime(2026),
          duration: const Duration(minutes: 20),
          walkDistance: 0,
          walkTime: Duration.zero,
        );
        expect(itinerary.overallArrivalDelay, const Duration(seconds: 180));
      },
    );

    test('is null when no leg has real-time data', () {
      final itinerary = Itinerary(
        legs: [leg(), leg()],
        startTime: DateTime(2026),
        endTime: DateTime(2026),
        duration: const Duration(minutes: 20),
        walkDistance: 0,
        walkTime: Duration.zero,
      );
      expect(itinerary.overallArrivalDelay, isNull);
    });
  });
}
