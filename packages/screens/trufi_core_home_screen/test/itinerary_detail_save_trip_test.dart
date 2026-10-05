import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:trufi_core_home_screen/trufi_core_home_screen.dart';
import 'package:trufi_core_interfaces/trufi_core_interfaces.dart';
import 'package:trufi_core_routing/trufi_core_routing.dart' as routing;

/// fahrplaner.de fork patch (05.10.2026, siehe FAHRPLANER_PATCHES.md):
/// "Fahrt merken" auf der Itinerary-Detailansicht - neuer additiver
/// onSaveTrip-Callback auf ItineraryDetailContent/ItineraryDetailScreen,
/// analog zum bereits vorhandenen onShare. Pint: Button nur sichtbar, wenn
/// der Callback gesetzt ist, und ruft ihn beim Antippen auf.
void main() {
  final itinerary = routing.Itinerary(
    legs: [
      routing.Leg(
        mode: 'BUS',
        startTime: DateTime(2026, 10, 5, 15),
        endTime: DateTime(2026, 10, 5, 15, 30),
        duration: const Duration(minutes: 30),
        distance: 5000,
        transitLeg: true,
        route: routing.Route(gtfsId: '1:123', shortName: '123'),
        shortName: '123',
      ),
    ],
    startTime: DateTime(2026, 10, 5, 15),
    endTime: DateTime(2026, 10, 5, 15, 30),
    walkTime: Duration.zero,
    duration: const Duration(minutes: 30),
    walkDistance: 0,
  );

  Widget host(Widget child) => Provider<AppConfiguration?>.value(
    value: AppConfiguration(appName: 'Test', screens: const []),
    child: MaterialApp(
      localizationsDelegates: HomeScreenLocalizations.localizationsDelegates,
      supportedLocales: HomeScreenLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  testWidgets(
    'ItineraryDetailContent: Button sichtbar und ruft onSaveTrip auf, '
    'wenn gesetzt',
    (tester) async {
      var saved = false;
      await tester.pumpWidget(
        host(
          ItineraryDetailContent(
            itinerary: itinerary,
            onSaveTrip: () => saved = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
      expect(saved, isTrue);
    },
  );

  testWidgets(
    'ItineraryDetailContent: Button ausgeblendet ohne onSaveTrip',
    (tester) async {
      await tester.pumpWidget(
        host(ItineraryDetailContent(itinerary: itinerary)),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bookmark_add_outlined), findsNothing);
    },
  );

  testWidgets(
    'ItineraryDetailScreen: Button sichtbar und ruft onSaveTrip auf, '
    'wenn gesetzt',
    (tester) async {
      var saved = false;
      await tester.pumpWidget(
        host(
          ItineraryDetailScreen(
            itinerary: itinerary,
            onSaveTrip: () => saved = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
      expect(saved, isTrue);
    },
  );
}
