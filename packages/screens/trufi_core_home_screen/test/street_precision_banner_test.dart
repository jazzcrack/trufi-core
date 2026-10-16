// fahrplaner.de fork patch 62: "Ziel ist die Strassenmitte"-Hinweis ueber
// den Verbindungen, mit "+ Hausnummer ergaenzen".
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

routing.Itinerary _itinerary() {
  final start = DateTime.now().add(const Duration(hours: 2));
  return routing.Itinerary(
    legs: [
      routing.Leg(
        mode: 'BUS',
        startTime: start,
        endTime: start.add(const Duration(minutes: 20)),
        duration: const Duration(minutes: 20),
        distance: 5000,
        transitLeg: true,
        shortName: '505',
        route: const routing.Route(gtfsId: '1:505', shortName: '505'),
      ),
    ],
    startTime: start,
    endTime: start.add(const Duration(minutes: 20)),
    walkTime: Duration.zero,
    duration: const Duration(minutes: 20),
    walkDistance: 0,
  );
}

Future<RoutePlannerCubit> _cubit({String? toType}) async {
  final cubit = RoutePlannerCubit(
    repository: _FakeRepository(),
    requestService: _FakePlanService(routing.Plan(itineraries: [_itinerary()])),
  );
  await cubit.setFromPlace(
    const TrufiLocation(
      description: 'Mein Standort',
      latitude: 53.5,
      longitude: 8.6,
    ),
  );
  await cubit.setToPlace(
    TrufiLocation(
      description: 'Oststraße',
      latitude: 53.52,
      longitude: 8.58,
      type: toType,
    ),
  );
  await cubit.fetchPlan();
  return cubit;
}

Widget _host(
  RoutePlannerCubit cubit,
  void Function({required bool isOrigin})? onAdd,
) => MaterialApp(
  localizationsDelegates: HomeScreenLocalizations.localizationsDelegates,
  supportedLocales: HomeScreenLocalizations.supportedLocales,
  locale: const Locale('de'),
  home: Scaffold(
    body: BlocProvider.value(
      value: cubit,
      child: ItineraryList(onAddHouseNumber: onAdd),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Ziel nur Strasse: Hinweis mit Laenge, Knopf ruft Ziel auf', (
    tester,
  ) async {
    final cubit = await _cubit(toType: 'street:650');
    addTearDown(cubit.close);
    bool? calledForOrigin;

    await tester.pumpWidget(
      _host(cubit, ({required isOrigin}) => calledForOrigin = isOrigin),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Straße ca. 650 m lang'), findsOneWidget);
    await tester.tap(find.text('Hausnummer ergänzen'));
    expect(calledForOrigin, isFalse);

    await tester.tap(find.byTooltip('Hinweis ausblenden'));
    await tester.pumpAndSettle();
    expect(find.text('Hausnummer ergänzen'), findsNothing);
  });

  testWidgets('Ziel mit Hausnummer: kein Hinweis', (tester) async {
    final cubit = await _cubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(_host(cubit, ({required isOrigin}) {}));
    await tester.pumpAndSettle();

    expect(find.text('Hausnummer ergänzen'), findsNothing);
  });
}
