// fahrplaner.de fork patch (siehe FAHRPLANER_PATCHES.md, Nutzer-Fund "Ganze
// Fahrt zeigt Fahrplan statt Live"): Test fuer den periodischen
// Verspaetungs-Refresh der inline-Detailansicht direkt nach der
// Verbindungssuche (vor Fahrtstart). Harness-Muster (Fake-Repository/
// -PlanService, host()) 1:1 aus itinerary_list_redesign_test.dart
// uebernommen, ergaenzt um einen gefakten IRoutingProvider/
// RoutingEngineManager (siehe itinerary_live_refresh_test.dart im
// Hauptprojekt-Repo fuer dasselbe Fake-Muster).
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
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

class _FakeRoutingProvider extends routing.IRoutingProvider {
  _FakeRoutingProvider(this._delaysByStop);

  final Map<String, Map<String, Duration>> _delaysByStop;

  @override
  String get id => 'fake';
  @override
  String get name => 'Fake';
  @override
  String get description => 'Test double';
  @override
  bool get supportsTransitRoutes => false;
  @override
  bool get requiresInternet => true;

  @override
  Future<routing.Plan> fetchPlan({
    required routing.RoutingLocation from,
    required routing.RoutingLocation to,
    int numItineraries = 5,
    String? locale,
    required DateTime dateTime,
    bool arriveBy = false,
    String? pageCursor,
  }) async => const routing.Plan(itineraries: []);

  @override
  Future<List<routing.TransitRoute>> fetchTransitRoutes() async => [];

  @override
  Future<routing.TransitRoute?> fetchTransitRouteById(String id) async => null;

  @override
  Future<Map<String, Duration>?> fetchLiveStopDelays(String stopId) async =>
      _delaysByStop[stopId];
}

routing.Leg _bus(
  String route, {
  required Duration duration,
  required String tripId,
  required String fromStopId,
}) => routing.Leg(
  mode: 'BUS',
  startTime: DateTime(2026, 8, 12, 8),
  endTime: DateTime(2026, 8, 12, 8).add(duration),
  duration: duration,
  distance: 5000,
  transitLeg: true,
  route: routing.Route(gtfsId: route, shortName: route),
  shortName: route,
  tripId: tripId,
  fromPlace: routing.Place(name: 'Start', lat: 0, lon: 0, stopId: fromStopId),
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

Widget host(RoutePlannerCubit cubit, routing.RoutingEngineManager manager) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: manager),
        BlocProvider.value(value: cubit),
      ],
      child: MaterialApp(
        localizationsDelegates: HomeScreenLocalizations.localizationsDelegates,
        supportedLocales: HomeScreenLocalizations.supportedLocales,
        home: const Scaffold(body: ItineraryList()),
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'aktualisiert die Echtzeit-Anzeige der offenen Detailansicht nach dem '
    'ersten Takt, ohne dass die Ansicht erneut geoeffnet wird',
    (tester) async {
      final itinerary = routing.Itinerary(
        legs: [
          _bus(
            '18',
            duration: const Duration(minutes: 10),
            tripId: 'trip-1',
            fromStopId: 'stop-1',
          ),
        ],
        startTime: DateTime(2026, 8, 12, 8),
        endTime: DateTime(2026, 8, 12, 8, 10),
        walkTime: Duration.zero,
        duration: const Duration(minutes: 10),
        walkDistance: 0,
      );
      final cubit = await _cubitWithPlan([itinerary]);
      final manager = routing.RoutingEngineManager(
        engines: [
          _FakeRoutingProvider({
            'stop-1': {'trip-1': const Duration(minutes: 4)},
          }),
        ],
      );

      await tester.pumpWidget(host(cubit, manager));
      await tester.pumpAndSettle();

      // Vor dem Oeffnen: Liste zeigt die Verbindung ohne Live-Daten.
      await tester.tap(find.byType(ItineraryCard));
      await tester.pumpAndSettle();

      // Direkt nach dem Oeffnen: noch keine Verspaetung (Schnappschuss).
      expect(find.textContaining('Fahrplan'), findsWidgets);
      expect(find.textContaining('+4 Min'), findsNothing);

      // Ein Takt (45s) vergeht - der periodische Refresh fragt nach.
      await tester.pump(const Duration(seconds: 45));
      await tester.pumpAndSettle();

      expect(find.textContaining('+4 Min'), findsWidgets);

      await cubit.close();
    },
  );
}
