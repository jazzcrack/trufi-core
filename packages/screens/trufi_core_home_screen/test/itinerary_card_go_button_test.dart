import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufi_core_home_screen/trufi_core_home_screen.dart';
import 'package:trufi_core_routing/trufi_core_routing.dart' as routing;

/// fahrplaner.de fork patch (04.10.2026, Nutzer-Feedback: "auch die anderen
/// Karten direkt antippbar/startbar machen"): der Los-Button war an
/// `isSelected` gekoppelt, obwohl `onStartNavigation` schon zuvor pro Karte
/// an die jeweilige Itinerary gebunden wurde (itinerary_list.dart) - nur die
/// hervorgehobene, per sortByGeneralizedCost objektiv beste Verbindung war
/// also wirklich mit einem Tipp startbar, alle anderen brauchten den Umweg
/// über die Detailansicht. Pint das neue Verhalten: der Los-Button
/// erscheint jetzt unabhängig von `isSelected`, sobald ein
/// `onStartNavigation`-Callback übergeben wird.
void main() {
  final itinerary = routing.Itinerary(
    legs: [
      routing.Leg(
        mode: 'BUS',
        startTime: DateTime(2026, 10, 4, 11, 18),
        endTime: DateTime(2026, 10, 4, 12, 31),
        duration: const Duration(minutes: 72),
        distance: 66100,
        transitLeg: true,
        route: routing.Route(gtfsId: '1:506', shortName: '506'),
        shortName: '506',
      ),
    ],
    startTime: DateTime(2026, 10, 4, 11, 18),
    endTime: DateTime(2026, 10, 4, 12, 31),
    walkTime: Duration.zero,
    duration: const Duration(minutes: 72),
    walkDistance: 345,
  );

  Widget host(Widget child) => MaterialApp(
    localizationsDelegates: HomeScreenLocalizations.localizationsDelegates,
    supportedLocales: HomeScreenLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  testWidgets(
    'eine NICHT hervorgehobene Karte zeigt trotzdem einen Los-Button, '
    'wenn onStartNavigation übergeben wird',
    (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        host(
          ItineraryCard(
            itinerary: itinerary,
            isSelected: false,
            onTap: () {},
            onStartNavigation: () => tapped = true,
          ),
        ),
      );

      expect(find.byIcon(Icons.navigation_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.navigation_rounded));
      expect(tapped, isTrue);
    },
  );

  testWidgets(
    'eine hervorgehobene Karte ohne onStartNavigation zeigt weiterhin nur '
    'das Auswahl-Häkchen, keinen Los-Button',
    (tester) async {
      await tester.pumpWidget(
        host(
          ItineraryCard(itinerary: itinerary, isSelected: true, onTap: () {}),
        ),
      );

      expect(find.byIcon(Icons.navigation_rounded), findsNothing);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    },
  );
}
