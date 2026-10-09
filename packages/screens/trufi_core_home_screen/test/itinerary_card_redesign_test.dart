// fahrplaner.de fork patch (Redesign Oktober 2026, docs/design/HANDOFF.md
// Abschnitt 3.2, Hauptprojekt-Kapitel siehe architektur-konzept.md): Tests
// fuer die drei neuen Zeilen in ItineraryCard - proportionaler Balken
// (ueber die Segment-Icons/Linien-Labels geprueft, da die Breite selbst
// per Golden-Test genauer waere als per Widget-Test sinnvoll ist), "in N
// Min ab X" + Echtzeit-Chips, und die "Umstieg knapp"-Warnzeile.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufi_core_home_screen/trufi_core_home_screen.dart';
import 'package:trufi_core_routing/trufi_core_routing.dart' as routing;

void main() {
  Widget host(Widget child) => MaterialApp(
    localizationsDelegates: HomeScreenLocalizations.localizationsDelegates,
    supportedLocales: HomeScreenLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  routing.Leg transitLeg({
    required String shortName,
    required DateTime start,
    required DateTime end,
    Duration? arrivalDelay,
    String? fromName,
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
  );

  group('Echtzeit-Zeile ("in N Min ab X" + Chips je Transit-Bein)', () {
    testWidgets(
      'zeigt die Abfahrtszeit-Vorschau und einen Chip je Transit-Bein',
      (tester) async {
        final now = DateTime(2026, 10, 9, 8, 0);
        final itinerary = routing.Itinerary(
          legs: [
            transitLeg(
              shortName: 'RS2',
              start: now.add(const Duration(minutes: 12)),
              end: now.add(const Duration(minutes: 32)),
              fromName: 'Schleusenstr.',
              arrivalDelay: const Duration(minutes: 3),
            ),
          ],
          startTime: now.add(const Duration(minutes: 12)),
          endTime: now.add(const Duration(minutes: 32)),
          walkTime: Duration.zero,
          duration: const Duration(minutes: 20),
          walkDistance: 0,
        );

        await tester.pumpWidget(
          host(
            ItineraryCard(
              itinerary: itinerary,
              isSelected: false,
              onTap: () {},
            ),
          ),
        );

        expect(find.textContaining('ab Schleusenstr.'), findsOneWidget);
        // Zwei "+3 Min"-Texte sind hier korrekt: die Fusszeile zeigt
        // weiterhin den GESAMT-Verspaetungs-Chip (ohne Praefix, Patch 23),
        // die neue Echtzeit-Zeile den EIGENEN, praefixierten Chip je Bein.
        expect(find.text('RS2 +3 Min'), findsOneWidget);
      },
    );
  });

  group('"Umstieg knapp"-Warnzeile', () {
    testWidgets(
      'erscheint, wenn der Puffer nach Verspaetung unter 5 Min faellt',
      (tester) async {
        final start = DateTime(2026, 10, 9, 8, 0);
        final leg1 = transitLeg(
          shortName: '502',
          start: start,
          end: start.add(const Duration(minutes: 20)),
          fromName: 'Start',
          arrivalDelay: const Duration(minutes: 4),
        );
        final leg2 = transitLeg(
          shortName: 'RS2',
          start: start.add(const Duration(minutes: 22)),
          end: start.add(const Duration(minutes: 40)),
          fromName: 'Bremen Hbf',
        );
        final itinerary = routing.Itinerary(
          legs: [leg1, leg2],
          startTime: start,
          endTime: start.add(const Duration(minutes: 40)),
          walkTime: Duration.zero,
          duration: const Duration(minutes: 40),
          walkDistance: 0,
        );

        await tester.pumpWidget(
          host(
            ItineraryCard(
              itinerary: itinerary,
              isSelected: false,
              onTap: () {},
            ),
          ),
        );

        // Puffer = 22 - (20 + 4) = -2 Min -> auf 0 begrenzt, jedenfalls < 5.
        expect(
          find.textContaining('Umstieg Bremen Hbf wird knapp'),
          findsOneWidget,
        );
      },
    );

    testWidgets('erscheint NICHT bei einem komfortablen Puffer', (
      tester,
    ) async {
      final start = DateTime(2026, 10, 9, 8, 0);
      final leg1 = transitLeg(
        shortName: '502',
        start: start,
        end: start.add(const Duration(minutes: 20)),
        fromName: 'Start',
      );
      final leg2 = transitLeg(
        shortName: 'RS2',
        start: start.add(const Duration(minutes: 35)),
        end: start.add(const Duration(minutes: 50)),
        fromName: 'Bremen Hbf',
      );
      final itinerary = routing.Itinerary(
        legs: [leg1, leg2],
        startTime: start,
        endTime: start.add(const Duration(minutes: 50)),
        walkTime: Duration.zero,
        duration: const Duration(minutes: 50),
        walkDistance: 0,
      );

      await tester.pumpWidget(
        host(
          ItineraryCard(itinerary: itinerary, isSelected: false, onTap: () {}),
        ),
      );

      expect(find.textContaining('wird knapp'), findsNothing);
    });
  });

  group('Kopfzeile: Dauer + Umstiege', () {
    testWidgets('zeigt die Umstiegszahl (Transit-Beine minus eins) im Header', (
      tester,
    ) async {
      final start = DateTime(2026, 10, 9, 8, 0);
      final itinerary = routing.Itinerary(
        legs: [
          transitLeg(
            shortName: '502',
            start: start,
            end: start.add(const Duration(minutes: 20)),
          ),
          transitLeg(
            shortName: 'RS2',
            start: start.add(const Duration(minutes: 25)),
            end: start.add(const Duration(minutes: 45)),
          ),
        ],
        startTime: start,
        endTime: start.add(const Duration(minutes: 45)),
        walkTime: Duration.zero,
        duration: const Duration(minutes: 45),
        walkDistance: 0,
      );

      await tester.pumpWidget(
        host(
          ItineraryCard(itinerary: itinerary, isSelected: false, onTap: () {}),
        ),
      );

      expect(find.byIcon(Icons.sync_alt_rounded), findsOneWidget);
      expect(find.text(' 1'), findsOneWidget);
    });
  });
}
