// fahrplaner.de fork patch (10.10.2026, echter Nutzer-Fund: "Ganze Fahrt"
// zeigt waehrend der aktiven Navigation nirgends, wo man gerade ist).
// Harness-Muster (host()) 1:1 aus itinerary_detail_redesign_test.dart
// uebernommen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:trufi_core_home_screen/trufi_core_home_screen.dart';
import 'package:trufi_core_interfaces/trufi_core_interfaces.dart';
import 'package:trufi_core_routing/trufi_core_routing.dart' as routing;

Widget host(Widget child) => Provider<AppConfiguration?>.value(
  value: AppConfiguration(appName: 'Test', screens: const []),
  child: MaterialApp(
    localizationsDelegates: HomeScreenLocalizations.localizationsDelegates,
    supportedLocales: HomeScreenLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

routing.Leg _transitLeg({
  required String shortName,
  required DateTime start,
  required DateTime end,
  List<routing.Place>? intermediatePlaces,
}) => routing.Leg(
  mode: 'BUS',
  startTime: start,
  endTime: end,
  duration: end.difference(start),
  distance: 3000,
  transitLeg: true,
  shortName: shortName,
  route: routing.Route(gtfsId: '1:$shortName', shortName: shortName),
  fromPlace: routing.Place(name: 'Start', lat: 0, lon: 0),
  toPlace: routing.Place(name: 'Ende', lat: 0, lon: 0, arrivalTime: end),
  intermediatePlaces: intermediatePlaces,
);

void main() {
  final start = DateTime(2026, 10, 9, 8);
  final itinerary = routing.Itinerary(
    legs: [
      _transitLeg(
        shortName: 'RS2',
        start: start,
        end: start.add(const Duration(minutes: 20)),
        intermediatePlaces: [
          routing.Place(
            name: 'Zwischenhalt A',
            lat: 0,
            lon: 0,
            arrivalTime: start.add(const Duration(minutes: 5)),
          ),
        ],
      ),
      _transitLeg(
        shortName: 'Tram 6',
        start: start.add(const Duration(minutes: 25)),
        end: start.add(const Duration(minutes: 35)),
      ),
    ],
    startTime: start,
    endTime: start.add(const Duration(minutes: 35)),
    walkTime: Duration.zero,
    duration: const Duration(minutes: 35),
    walkDistance: 0,
  );

  group('ItineraryDetailContent.currentLegIndex', () {
    testWidgets(
      'ohne currentLegIndex: kein "Jetzt hier"-Hinweis (Planungsphase unveraendert)',
      (tester) async {
        await tester.pumpWidget(
          host(ItineraryDetailContent(itinerary: itinerary)),
        );
        expect(find.text('Jetzt hier'), findsNothing);
      },
    );

    testWidgets('mit currentLegIndex: markiert genau das passende Bein', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(ItineraryDetailContent(itinerary: itinerary, currentLegIndex: 0)),
      );
      expect(find.text('Jetzt hier'), findsOneWidget);
    });

    testWidgets(
      'aktuelles Bein zeigt seine Zwischenhalte automatisch aufgeklappt',
      (tester) async {
        await tester.pumpWidget(
          host(
            ItineraryDetailContent(itinerary: itinerary, currentLegIndex: 0),
          ),
        );
        // Kein Tap auf den Ausklapp-Umschalter noetig - der Zwischenhalt ist
        // sofort sichtbar.
        expect(find.text('Zwischenhalt A'), findsOneWidget);
      },
    );
  });
}
