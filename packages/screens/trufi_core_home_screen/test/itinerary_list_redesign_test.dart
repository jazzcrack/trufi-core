// fahrplaner.de fork patch (Redesign Oktober 2026, docs/design/HANDOFF.md
// Abschnitt 3.2, Hauptprojekt-Kapitel siehe architektur-konzept.md): Tests
// fuer die zwei verbliebenen Elemente dieses Abschnitts (Sortier-Umschalter
// "Weniger Umstiege" und der einmalige "Fahrplan heißt..."-Hinweis).
// Harness-Muster (Fake-Repository/-PlanService, host()) 1:1 aus
// route_planner_grouping_test.dart uebernommen.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trufi_core_home_screen/trufi_core_home_screen.dart';
import 'package:trufi_core_interfaces/trufi_core_interfaces.dart';
import 'package:trufi_core_routing/trufi_core_routing.dart' as routing;

class _FakeRepository implements HomeScreenRepository {
  routing.Plan? storedPlan;
  routing.Itinerary? storedSelected;
  TrufiLocation? from;
  TrufiLocation? to;

  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<void> saveFromPlace(TrufiLocation? data) async => from = data;
  @override
  Future<TrufiLocation?> getFromPlace() async => from;
  @override
  Future<void> saveToPlace(TrufiLocation? data) async => to = data;
  @override
  Future<TrufiLocation?> getToPlace() async => to;
  @override
  Future<void> savePlan(routing.Plan? data) async => storedPlan = data;
  @override
  Future<routing.Plan?> getPlan() async => storedPlan;
  @override
  Future<void> saveSelectedItinerary(routing.Itinerary? data) async =>
      storedSelected = data;
  @override
  Future<routing.Itinerary?> getSelectedItinerary() async => storedSelected;
  @override
  Future<void> clear() async {}
}

class _FakePlanService implements RequestPlanService {
  _FakePlanService(this.plan);
  final routing.Plan plan;

  @override
  Future<routing.Plan> fetchPlan({
    required TrufiLocation from,
    required TrufiLocation to,
    String? locale,
    required DateTime dateTime,
    bool arriveBy = false,
    String? pageCursor,
    int? numItineraries,
  }) async => plan;
}

routing.Leg _bus(String route, {required Duration duration}) => routing.Leg(
  mode: 'BUS',
  startTime: DateTime(2026, 8, 12, 8),
  endTime: DateTime(2026, 8, 12, 8).add(duration),
  duration: duration,
  distance: 5000,
  transitLeg: true,
  route: routing.Route(gtfsId: route, shortName: route),
  shortName: route,
);

/// Zwei Verbindungen, bei denen die SCHNELLERE mehr Umstiege hat als die
/// LANGSAMERE - nur so laesst sich beobachten, dass "Weniger Umstiege"
/// tatsaechlich umsortiert (ein Sortieren nach Dauer allein wuerde
/// zufaellig dieselbe Reihenfolge ergeben).
routing.Itinerary _fast = routing.Itinerary(
  legs: [
    _bus('18', duration: const Duration(minutes: 10)),
    _bus('19', duration: const Duration(minutes: 10)),
  ],
  startTime: DateTime(2026, 8, 12, 8),
  endTime: DateTime(2026, 8, 12, 8, 20),
  walkTime: Duration.zero,
  duration: const Duration(minutes: 20),
  walkDistance: 0,
);
routing.Itinerary _slowDirect = routing.Itinerary(
  legs: [_bus('100', duration: const Duration(minutes: 35))],
  startTime: DateTime(2026, 8, 12, 8, 5),
  endTime: DateTime(2026, 8, 12, 8, 40),
  walkTime: Duration.zero,
  duration: const Duration(minutes: 35),
  walkDistance: 0,
);

Future<RoutePlannerCubit> _cubitWithPlan(
  List<routing.Itinerary> itineraries,
) async {
  final cubit = RoutePlannerCubit(
    repository: _FakeRepository(),
    requestService: _FakePlanService(routing.Plan(itineraries: itineraries)),
  );
  await cubit.setFromPlace(
    const TrufiLocation(description: 'A', latitude: -17.465, longitude: -66.14),
  );
  await cubit.setToPlace(
    const TrufiLocation(description: 'B', latitude: -17.355, longitude: -66.19),
  );
  await cubit.fetchPlan();
  return cubit;
}

Widget host(RoutePlannerCubit cubit) => MaterialApp(
  localizationsDelegates: HomeScreenLocalizations.localizationsDelegates,
  supportedLocales: HomeScreenLocalizations.supportedLocales,
  home: Scaffold(
    body: BlocProvider.value(value: cubit, child: const ItineraryList()),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('"Weniger Umstiege" (RoutePlannerCubit.toggleSortPreference)', () {
    testWidgets(
      'nach dem Umschalten steht die Verbindung mit weniger Umstiegen oben, '
      'auch wenn sie langsamer ist',
      (tester) async {
        final cubit = await _cubitWithPlan([_fast, _slowDirect]);
        await tester.pumpWidget(host(cubit));
        await tester.pumpAndSettle();

        // Vorher (Standard-Sortierung durch die Fake-Plan-Reihenfolge):
        // die schnellere, aber umstiegsreichere Verbindung steht oben.
        expect(
          tester.getTopLeft(find.text('18')).dy <
              tester.getTopLeft(find.text('100')).dy,
          isTrue,
        );

        cubit.toggleSortPreference();
        await tester.pumpAndSettle();

        expect(cubit.state.preferFewerTransfers, isTrue);
        // Danach: die direkte (umstiegsfreie) Verbindung steht oben.
        expect(
          tester.getTopLeft(find.text('100')).dy <
              tester.getTopLeft(find.text('18')).dy,
          isTrue,
        );
        await cubit.close();
      },
    );
  });

  group('"Fahrplan heißt..."-Hinweis', () {
    testWidgets('wird beim ersten Mal angezeigt und bleibt nach Wegklicken '
        'dauerhaft verborgen', (tester) async {
      final cubit = await _cubitWithPlan([_fast]);
      await tester.pumpWidget(host(cubit));
      await tester.pumpAndSettle();

      expect(find.textContaining('heißt'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();

      expect(find.textContaining('heißt'), findsNothing);
      await cubit.close();

      // Fresh ItineraryList/Cubit (wie nach einem App-Neustart) - die
      // SharedPreferences-Persistenz muss den Hinweis weiterhin
      // verborgen halten.
      final secondCubit = await _cubitWithPlan([_fast]);
      await tester.pumpWidget(host(secondCubit));
      await tester.pumpAndSettle();

      expect(find.textContaining('heißt'), findsNothing);
      await secondCubit.close();
    });
  });
}
