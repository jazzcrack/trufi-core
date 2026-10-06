import 'package:flutter_test/flutter_test.dart';
import 'package:trufi_core_routing/trufi_core_routing.dart';

/// fahrplaner.de fork patch (06.10.2026, siehe FAHRPLANER_PATCHES.md):
/// Leg.tripId geparst aus OTP's `trip.gtfsId` - Voraussetzung dafuer, eine
/// per IRoutingProvider.fetchLiveStopDelays() abgefragte, nach Trip-ID
/// geschluesselte Verspaetungs-Map waehrend einer aktiven Navigation der
/// richtigen Fahrt zuzuordnen (siehe trufi_core_navigation,
/// NavigationCubit.refreshCurrentLegDelay()).
void main() {
  group('Otp28ResponseParser tripId parsing', () {
    Map<String, dynamic> legJson({String? tripGtfsId}) => {
      'mode': 'BUS',
      'startTime': 1700000000000,
      'endTime': 1700000600000,
      'duration': 600,
      'distance': 1000.0,
      'transitLeg': true,
      if (tripGtfsId != null) 'trip': {'gtfsId': tripGtfsId},
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

    test('parses trip.gtfsId into Leg.tripId', () {
      final plan = Otp28ResponseParser.parsePlan(
        planJson([legJson(tripGtfsId: 'vbn:12345')]),
      );
      expect(plan.itineraries!.first.legs.first.tripId, 'vbn:12345');
    });

    test('is null when the leg has no trip (e.g. a walking leg)', () {
      final plan = Otp28ResponseParser.parsePlan(planJson([legJson()]));
      expect(plan.itineraries!.first.legs.first.tripId, isNull);
    });

    test('Leg.toJson()/fromJson() round-trips tripId', () {
      final plan = Otp28ResponseParser.parsePlan(
        planJson([legJson(tripGtfsId: 'vbn:99')]),
      );
      final leg = plan.itineraries!.first.legs.first;

      final roundTripped = Leg.fromJson(leg.toJson());

      expect(roundTripped.tripId, 'vbn:99');
    });
  });
}
