import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufi_core_home_screen/src/widgets/segmented_route_chip.dart';
import 'package:trufi_core_home_screen/trufi_core_home_screen.dart';
import 'package:trufi_core_routing/trufi_core_routing.dart' as routing;

/// A three-bus itinerary (two transfers, #998) renders in the card: one
/// segment per leg — walks included — in the proportional duration bar
/// (Redesign Oktober 2026, docs/design/HANDOFF.md Abschnitt 3.2, siehe
/// ItineraryCard._buildSegmentBar), and a transfer count in the header
/// row. Pinned at phone width so a layout that gives a short leg too
/// little width would overflow and fail here (echter Test-Fund waehrend
/// dieses Redesigns: proportionale Breite allein liess kurze Fusswege
/// ueberlaufen, siehe die Fest-statt-proportional-Breite fuer Fusswege/
/// Raeder in _buildSegmentBar/_LegChip).
void main() {
  routing.Leg bus(String route, {String? from, String? to}) => routing.Leg(
    mode: 'BUS',
    startTime: DateTime(2026, 9, 11, 8),
    endTime: DateTime(2026, 9, 11, 8, 20),
    duration: const Duration(minutes: 20),
    distance: 5000,
    transitLeg: true,
    route: routing.Route(gtfsId: '1:$route', shortName: route),
    shortName: route,
    fromPlace: from == null ? null : routing.Place(name: from, lat: 0, lon: 0),
    toPlace: to == null ? null : routing.Place(name: to, lat: 0, lon: 0),
  );

  routing.Leg walk(double meters) => routing.Leg(
    mode: 'WALK',
    startTime: DateTime(2026, 9, 11, 8),
    endTime: DateTime(2026, 9, 11, 8, 2),
    duration: const Duration(minutes: 2),
    distance: meters,
    transitLeg: false,
  );

  // Ammar's chain: walk, 7, 8 m, 14, 73 m, 14, walk.
  final itinerary = routing.Itinerary(
    legs: [
      walk(25),
      bus('7'),
      walk(8),
      bus('14'),
      walk(73),
      bus('14'),
      walk(136),
    ],
    startTime: DateTime(2026, 9, 11, 8),
    endTime: DateTime(2026, 9, 11, 9, 5),
    walkTime: const Duration(minutes: 4),
    duration: const Duration(minutes: 65),
    walkDistance: 242,
    transfers: 2,
  );

  Widget host(Widget child) => MaterialApp(
    localizationsDelegates: HomeScreenLocalizations.localizationsDelegates,
    supportedLocales: HomeScreenLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  testWidgets(
    'three transit segments, four walk segments and a "2" transfer count',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2424);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(
          ItineraryCard(itinerary: itinerary, isSelected: false, onTap: () {}),
        ),
      );

      // One segment per leg: the route names appear once per transit leg.
      expect(find.text('7'), findsOneWidget);
      expect(find.text('14'), findsNWidgets(2));
      // Header: transfers = transit legs − 1.
      expect(find.byIcon(Icons.sync_alt_rounded), findsOneWidget);
      expect(find.text(' 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a grouped three-slot card feeds the third slot its options', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2424);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(
        ItineraryCard(
          itinerary: itinerary,
          isSelected: false,
          onTap: () {},
          slotRoutes: [
            [routing.Route(shortName: '7', color: '7E57C2')],
            [routing.Route(shortName: '14', color: 'E91E63')],
            [
              routing.Route(shortName: '14', color: 'E91E63'),
              routing.Route(shortName: '24', color: '4CAF50'),
            ],
          ],
        ),
      ),
    );

    // Slots 1 and 2 are plain chips ("7", "14"); slot 3 is one segmented
    // chip with both options, the ridden "14" at full strength.
    expect(find.text('7'), findsOneWidget);
    expect(find.text('14'), findsNWidgets(2));
    expect(find.text('24'), findsOneWidget);
    expect(find.byType(SegmentedRouteChip), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
