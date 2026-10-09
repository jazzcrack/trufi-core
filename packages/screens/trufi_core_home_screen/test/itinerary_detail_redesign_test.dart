// fahrplaner.de fork patch (Redesign Oktober 2026, docs/design/HANDOFF.md
// Abschnitt 3.3, Hauptprojekt-Kapitel siehe architektur-konzept.md): Tests
// fuer die neuen Elemente des Verbindungsdetails - Echtzeit-Zeile,
// durchgestrichene Zeit bei Verspätung, "Umstieg knapp"-Pille und den
// Wecken-Schalter + "Fahrt starten"-Leiste. Harness-Muster (host()) 1:1
// aus itinerary_detail_save_trip_test.dart uebernommen.
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
  Duration? arrivalDelay,
  String? fromName,
  String? toName,
  String? toPlatformCode,
}) => routing.Leg(
  mode: 'BUS',
  startTime: start,
  endTime: end,
  duration: end.difference(start),
  distance: 3000,
  transitLeg: true,
  shortName: shortName,
  route: routing.Route(gtfsId: '1:$shortName', shortName: shortName),
  arrivalDelay: arrivalDelay,
  fromPlace: fromName == null
      ? null
      : routing.Place(name: fromName, lat: 0, lon: 0),
  toPlace: toName == null
      ? null
      : routing.Place(
          name: toName,
          lat: 0,
          lon: 0,
          platformCode: toPlatformCode,
          arrivalTime: end,
        ),
);

void main() {
  group('Echtzeit-Zeile', () {
    testWidgets('zeigt einen Chip je Transit-Bein', (tester) async {
      final start = DateTime(2026, 10, 9, 8);
      final itinerary = routing.Itinerary(
        legs: [
          _transitLeg(
            shortName: 'RS2',
            start: start,
            end: start.add(const Duration(minutes: 20)),
            arrivalDelay: const Duration(minutes: 3),
          ),
        ],
        startTime: start,
        endTime: start.add(const Duration(minutes: 20)),
        walkTime: Duration.zero,
        duration: const Duration(minutes: 20),
        walkDistance: 0,
      );

      await tester.pumpWidget(
        host(ItineraryDetailContent(itinerary: itinerary)),
      );

      expect(find.text('Echtzeit:'), findsOneWidget);
      expect(find.textContaining('RS2'), findsWidgets);
    });
  });

  group('Durchgestrichene Zeit bei Verspätung', () {
    testWidgets('zeigt Soll (durchgestrichen) und Ist am Ankunftspunkt', (
      tester,
    ) async {
      final start = DateTime(2026, 10, 9, 8);
      final itinerary = routing.Itinerary(
        legs: [
          _transitLeg(
            shortName: 'RS2',
            start: start,
            end: start.add(const Duration(minutes: 20)),
            arrivalDelay: const Duration(minutes: 3),
            toName: 'Bremen Hbf',
          ),
        ],
        startTime: start,
        endTime: start.add(const Duration(minutes: 20)),
        walkTime: Duration.zero,
        duration: const Duration(minutes: 20),
        walkDistance: 0,
      );

      await tester.pumpWidget(
        host(ItineraryDetailContent(itinerary: itinerary)),
      );

      // Soll 8:20 (durchgestrichen) und Ist 8:23 (neue Zeit) - per
      // Teilstring statt exaktem Text, da formatClockTime() je Locale/
      // 24h-Einstellung "08:20" oder "8:20 AM" liefern kann (siehe
      // route_planner_grouping_test.dart fuer dasselbe Muster).
      final strikethrough = tester
          .widgetList<Text>(find.byType(Text))
          .where(
            (t) =>
                (t.data ?? '').contains('8:20') &&
                t.style?.decoration == TextDecoration.lineThrough,
          );
      expect(strikethrough, hasLength(1));
      expect(find.textContaining('8:23'), findsOneWidget);
    });

    testWidgets('bleibt bei kleiner/keiner Verspaetung unveraendert', (
      tester,
    ) async {
      final start = DateTime(2026, 10, 9, 8);
      final itinerary = routing.Itinerary(
        legs: [
          _transitLeg(
            shortName: 'RS2',
            start: start,
            end: start.add(const Duration(minutes: 20)),
            toName: 'Bremen Hbf',
          ),
        ],
        startTime: start,
        endTime: start.add(const Duration(minutes: 20)),
        walkTime: Duration.zero,
        duration: const Duration(minutes: 20),
        walkDistance: 0,
      );

      await tester.pumpWidget(
        host(ItineraryDetailContent(itinerary: itinerary)),
      );

      // Mehrfach erwartet: sowohl die Kopfzeile ("8:00 AM – 8:20 AM") als
      // auch der Zeitstrahl enthalten "8:20" - die eigentliche Aussage
      // dieses Tests ist, dass KEINE davon durchgestrichen ist.
      expect(find.textContaining('8:20'), findsWidgets);
      final strikethrough = tester
          .widgetList<Text>(find.byType(Text))
          .where(
            (t) =>
                (t.data ?? '').contains('8:20') &&
                t.style?.decoration == TextDecoration.lineThrough,
          );
      expect(strikethrough, isEmpty);
    });
  });

  group('"Umstieg knapp"-Pille', () {
    testWidgets('orange, wenn der Puffer unter 5 Min liegt', (tester) async {
      final start = DateTime(2026, 10, 9, 8);
      final itinerary = routing.Itinerary(
        legs: [
          _transitLeg(
            shortName: '502',
            start: start,
            end: start.add(const Duration(minutes: 20)),
            arrivalDelay: const Duration(minutes: 4),
            toName: 'Bremen Hbf',
          ),
          _transitLeg(
            shortName: 'RS2',
            start: start.add(const Duration(minutes: 22)),
            end: start.add(const Duration(minutes: 40)),
            fromName: 'Bremen Hbf',
            toPlatformCode: 'C',
          ),
        ],
        startTime: start,
        endTime: start.add(const Duration(minutes: 40)),
        walkTime: Duration.zero,
        duration: const Duration(minutes: 40),
        walkDistance: 0,
      );

      await tester.pumpWidget(
        host(ItineraryDetailContent(itinerary: itinerary)),
      );

      expect(find.textContaining('Umstieg nur noch'), findsOneWidget);
    });

    testWidgets('grau, wenn der Puffer komfortabel ist', (tester) async {
      final start = DateTime(2026, 10, 9, 8);
      final itinerary = routing.Itinerary(
        legs: [
          _transitLeg(
            shortName: '502',
            start: start,
            end: start.add(const Duration(minutes: 20)),
            toName: 'Bremen Hbf',
          ),
          _transitLeg(
            shortName: 'RS2',
            start: start.add(const Duration(minutes: 35)),
            end: start.add(const Duration(minutes: 50)),
            fromName: 'Bremen Hbf',
          ),
        ],
        startTime: start,
        endTime: start.add(const Duration(minutes: 50)),
        walkTime: Duration.zero,
        duration: const Duration(minutes: 50),
        walkDistance: 0,
      );

      await tester.pumpWidget(
        host(ItineraryDetailContent(itinerary: itinerary)),
      );

      expect(find.textContaining('Umstieg nur noch'), findsNothing);
      expect(find.textContaining('Umstieg 15 Min'), findsOneWidget);
    });
  });

  group('Wecken-Schalter + "Fahrt starten"', () {
    final itinerary = routing.Itinerary(
      legs: [
        _transitLeg(
          shortName: '123',
          start: DateTime(2026, 10, 9, 8),
          end: DateTime(2026, 10, 9, 8, 30),
          toName: 'Universität/NW1',
        ),
      ],
      startTime: DateTime(2026, 10, 9, 8),
      endTime: DateTime(2026, 10, 9, 8, 30),
      walkTime: Duration.zero,
      duration: const Duration(minutes: 30),
      walkDistance: 0,
    );

    testWidgets(
      'Standard (nicht eingeschaltet) startet mit wakeAtDestination: false',
      (tester) async {
        bool? received;
        await tester.pumpWidget(
          host(
            ItineraryDetailContent(
              itinerary: itinerary,
              onStartNavigation: (wake) => received = wake,
            ),
          ),
        );

        await tester.tap(find.text('Fahrt starten'));
        expect(received, isFalse);
      },
    );

    testWidgets('Einschalten des Schalters uebergibt wakeAtDestination: true', (
      tester,
    ) async {
      bool? received;
      await tester.pumpWidget(
        host(
          ItineraryDetailContent(
            itinerary: itinerary,
            onStartNavigation: (wake) => received = wake,
          ),
        ),
      );

      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.text('Fahrt starten'));

      expect(received, isTrue);
    });

    testWidgets(
      'ItineraryDetailScreen (Standalone) ruft onStartNavigation jetzt tatsaechlich auf',
      (tester) async {
        bool? received;
        await tester.pumpWidget(
          host(
            Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ItineraryDetailScreen.show(
                  context,
                  itinerary: itinerary,
                  onStartNavigation: (wake) => received = wake,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Fahrt starten'));

        expect(received, isFalse);
      },
    );
  });
}
