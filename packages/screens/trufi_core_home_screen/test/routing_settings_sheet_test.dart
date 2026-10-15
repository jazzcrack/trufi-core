// fahrplaner.de fork patch (siehe FAHRPLANER_PATCHES.md, Nutzer-Wunsch
// 12.10.2026): GBFS-Sharing-Schnellfilter zieht vom Home-Screen in das
// "Optionen"-Sheet um, das Sheet zeigt zusaetzlich den aktuellen
// Zeitpunkt der Fahrt als Kontextzeile. Dieser Test pumpt RoutingSettings
// Sheet direkt (nicht den vollen HomeScreen) - braucht dafuer nur
// RoutePlannerCubit + RoutingEngineManager, kein MapEngineManager.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:trufi_core_home_screen/trufi_core_home_screen.dart';
import 'package:trufi_core_interfaces/trufi_core_interfaces.dart'
    show TrufiLocation;
import 'package:trufi_core_routing/trufi_core_routing.dart' as routing;
import 'package:trufi_core_search_locations/trufi_core_search_locations.dart'
    show SearchLocationsLocalizations;

class _FakeRepository implements HomeScreenRepository {
  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<void> saveFromPlace(TrufiLocation? data) async {}
  @override
  Future<TrufiLocation?> getFromPlace() async => null;
  @override
  Future<void> saveToPlace(TrufiLocation? data) async {}
  @override
  Future<TrufiLocation?> getToPlace() async => null;
  @override
  Future<void> savePlan(routing.Plan? data) async {}
  @override
  Future<routing.Plan?> getPlan() async => null;
  @override
  Future<void> saveSelectedItinerary(routing.Itinerary? data) async {}
  @override
  Future<routing.Itinerary?> getSelectedItinerary() async => null;
  @override
  Future<void> clear() async {}
}

class _FakePlanService implements RequestPlanService {
  @override
  Future<routing.Plan> fetchPlan({
    required TrufiLocation from,
    required TrufiLocation to,
    String? locale,
    required DateTime dateTime,
    bool arriveBy = false,
    String? pageCursor,
    int? numItineraries,
  }) async => const routing.Plan(itineraries: []);
}

/// [withQuickFilterChips] steuert, ob der Fake-Provider einen
/// Sharing-Schnellfilter anbietet - testet damit beide Faelle
/// (Abschnitt sichtbar vs. ausgeblendet).
class _FakeRoutingProvider extends routing.IRoutingProvider {
  _FakeRoutingProvider({this.withQuickFilterChips = true});

  final bool withQuickFilterChips;

  @override
  String get id => 'fake';
  @override
  String get name => 'Fake Provider';
  @override
  String get description => 'Test double';
  @override
  bool get supportsTransitRoutes => true;
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
  Widget? buildPreferencesUI(BuildContext context) =>
      const Text('Fake-Praeferenzen');

  @override
  Widget? buildQuickFilterChips(
    BuildContext context, {
    VoidCallback? onChanged,
  }) => withQuickFilterChips ? const Text('Fake-Sharing-Filter') : null;
}

Future<RoutePlannerCubit> _cubit() async {
  final cubit = RoutePlannerCubit(
    repository: _FakeRepository(),
    requestService: _FakePlanService(),
  );
  await cubit.setFromPlace(
    const TrufiLocation(description: 'A', latitude: 53.0, longitude: 8.8),
  );
  await cubit.setToPlace(
    const TrufiLocation(description: 'B', latitude: 53.1, longitude: 8.6),
  );
  return cubit;
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required RoutePlannerCubit cubit,
  required routing.IRoutingProvider engine,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        BlocProvider<RoutePlannerCubit>.value(value: cubit),
        ChangeNotifierProvider<routing.RoutingEngineManager>(
          create: (_) => routing.RoutingEngineManager(engines: [engine]),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: [
          ...HomeScreenLocalizations.localizationsDelegates,
          SearchLocationsLocalizations.delegate,
          routing.RoutingLocalizations.delegate,
        ],
        supportedLocales: HomeScreenLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: const Scaffold(body: RoutingSettingsSheet()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('zeigt KEINE Zeitpunkt-Zeile mehr - der Zeitpunkt gehoert zum '
      'Planungsformular, nicht zu den Optionen (T047)', (tester) async {
    final cubit = await _cubit();
    addTearDown(cubit.close);

    await _pumpSheet(tester, cubit: cubit, engine: _FakeRoutingProvider());

    expect(find.text('Zeitpunkt der Fahrt'), findsNothing);
    expect(find.text('Jetzt losfahren'), findsNothing);
  });

  testWidgets(
    'zeigt den Sharing-Schnellfilter-Abschnitt, wenn der Provider einen '
    'anbietet (echter Nutzer-Wunsch: zog vom Home-Screen hierher um)',
    (tester) async {
      final cubit = await _cubit();
      addTearDown(cubit.close);

      await _pumpSheet(
        tester,
        cubit: cubit,
        engine: _FakeRoutingProvider(withQuickFilterChips: true),
      );

      expect(find.text('Sharing'), findsOneWidget);
      expect(find.text('Fake-Sharing-Filter'), findsOneWidget);
    },
  );

  testWidgets(
    'blendet den Sharing-Abschnitt komplett aus, wenn der Provider keinen '
    'Schnellfilter anbietet',
    (tester) async {
      final cubit = await _cubit();
      addTearDown(cubit.close);

      await _pumpSheet(
        tester,
        cubit: cubit,
        engine: _FakeRoutingProvider(withQuickFilterChips: false),
      );

      expect(find.text('Sharing'), findsNothing);
    },
  );
}
