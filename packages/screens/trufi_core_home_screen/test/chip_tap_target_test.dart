// fahrplaner.de fork patch (see FAHRPLANER_PATCHES.md) - _DepartureTimeChip
// and _FewerTransfersChip grew their vertical padding 8->12 so the
// tappable area meets docs/design/QUERFORMAT.md Grundregel 5's 44px
// minimum (found during the Querformat Q8 gap review). Measures the
// actual rendered size instead of just trusting the padding math, same
// fake-map-engine approach as wide_side_panel_style_test.dart (Patch 42).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show AttributionButtonPosition;
import 'package:provider/provider.dart';
import 'package:trufi_core_home_screen/trufi_core_home_screen.dart';
import 'package:trufi_core_interfaces/trufi_core_interfaces.dart'
    show TrufiLocation;
import 'package:trufi_core_maps/trufi_core_maps.dart';
import 'package:trufi_core_routing/trufi_core_routing.dart' as routing;
import 'package:trufi_core_search_locations/trufi_core_search_locations.dart'
    show SearchLocationsLocalizations;

const _defaultCenter = LatLng(53.0793, 8.8017);

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

routing.Itinerary _oneLegItinerary() {
  final start = DateTime(2026, 10, 12, 8);
  return routing.Itinerary(
    legs: [
      routing.Leg(
        mode: 'BUS',
        shortName: '22',
        startTime: start,
        endTime: start.add(const Duration(minutes: 20)),
        duration: const Duration(minutes: 20),
        distance: 3000,
        transitLeg: true,
        decodedPoints: const [],
      ),
    ],
    startTime: start,
    endTime: start.add(const Duration(minutes: 20)),
    duration: const Duration(minutes: 20),
    walkDistance: 0,
    walkTime: Duration.zero,
  );
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
  }) async => routing.Plan(itineraries: [_oneLegItinerary()]);
}

class _MapCalls {
  TrufiCameraPosition? camera;
}

class _FakeEngine extends ITrufiMapEngine {
  _FakeEngine(this.calls);
  final _MapCalls calls;

  @override
  String get id => 'fake';
  @override
  String get name => 'Fake';
  @override
  String get description => 'Fake map';

  @override
  Widget buildMap({
    TrufiMapController? controller,
    required TrufiCameraPosition initialCamera,
    TrufiCameraPosition? camera,
    ValueChanged<TrufiCameraPosition>? onCameraChanged,
    void Function(LatLng)? onMapClick,
    void Function(LatLng)? onMapLongClick,
    List<TrufiLayer> layers = const [],
    List<WidgetMarker> widgetMarkers = const [],
    Offset? attributionButtonMargin,
    AttributionButtonPosition? attributionButtonPosition,
    bool attributionButtonEnabled = true,
  }) {
    calls.camera = camera;
    return const SizedBox.expand();
  }
}

Future<void> _pumpHomeWithPlan(
  WidgetTester tester, {
  bool withPlan = true,
  HomeScreenConfig config = const HomeScreenConfig(),
}) async {
  final manager = MapEngineManager(
    engines: [_FakeEngine(_MapCalls())],
    defaultCenter: _defaultCenter,
  );
  final cubit = RoutePlannerCubit(
    repository: _FakeRepository(),
    requestService: _FakePlanService(),
  );
  addTearDown(cubit.close);
  if (withPlan) {
    await cubit.setFromPlace(
      const TrufiLocation(description: 'A', latitude: 53.0, longitude: 8.8),
    );
    await cubit.setToPlace(
      const TrufiLocation(description: 'B', latitude: 53.1, longitude: 8.6),
    );
    await cubit.fetchPlan();
  }

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<MapEngineManager>.value(value: manager),
        BlocProvider<RoutePlannerCubit>.value(value: cubit),
      ],
      child: MaterialApp(
        localizationsDelegates: [
          ...HomeScreenLocalizations.localizationsDelegates,
          MapsLocalizations.delegate,
          SearchLocationsLocalizations.delegate,
          routing.RoutingLocalizations.delegate,
        ],
        supportedLocales: HomeScreenLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: HomeScreen(onMenuPressed: () {}, config: config),
      ),
    ),
  );
  // Not pumpAndSettle(): something in the full HomeScreen tree never
  // settles in this test environment (unclear which animation/timer -
  // same kind of issue home_quick_start_test.dart documents for a
  // different reason). A few bounded frames are enough for the chips
  // to render.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

double _tapTargetHeight(WidgetTester tester, Finder textFinder) {
  final material = find.ancestor(
    of: textFinder,
    matching: find.byType(Material),
  );
  return tester.getSize(material.first).height;
}

void main() {
  // Without this, HomeScreen's own location auto-resolve hits the
  // geolocator plugin channel, which has no handler in this test
  // environment - pumpAndSettle() then never settles. Same mock as
  // wide_side_panel_style_test.dart (Patch 42).
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          (call) async => false,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          null,
        );
  });

  testWidgets(
    '_DepartureTimeChip and _FewerTransfersChip meet the 44px tap-target '
    'minimum (docs/design/QUERFORMAT.md Grundregel 5)',
    (tester) async {
      await _pumpHomeWithPlan(tester);

      final departureTimeHeight = _tapTargetHeight(
        tester,
        find.text('Jetzt losfahren'),
      );
      expect(
        departureTimeHeight,
        greaterThanOrEqualTo(44),
        reason:
            '_DepartureTimeChip tap target is only ${departureTimeHeight}px',
      );

      final fewerTransfersHeight = _tapTargetHeight(
        tester,
        find.text('Weniger Umstiege'),
      );
      expect(
        fewerTransfersHeight,
        greaterThanOrEqualTo(44),
        reason:
            '_FewerTransfersChip tap target is only ${fewerTransfersHeight}px',
      );
    },
  );

  testWidgets(
    '_RoutingOptionsButton ("Optionen") meets the 44px tap-target minimum '
    'and sits next to "Jetzt losfahren" as a labeled pill, not a bare icon '
    'inside the search bar (fahrplaner.de fork patch, 13.10.2026, '
    'Nutzer-Fund anhand des Design-Entwurfs Main.dc.html)',
    (tester) async {
      await _pumpHomeWithPlan(tester);

      final optionsHeight = _tapTargetHeight(tester, find.text('Optionen'));
      expect(
        optionsHeight,
        greaterThanOrEqualTo(44),
        reason: '_RoutingOptionsButton tap target is only ${optionsHeight}px',
      );
    },
  );

  testWidgets(
    '"Jetzt losfahren" + "Optionen" stehen direkt unter Von/Nach - auch ohne '
    'gewaehlten Ort und OBERHALB des belowSearchBuilder-Blocks (T046/T047)',
    (tester) async {
      // Hochformat, 550 breit wegen der breiten Ahem-Testschrift (im
      // 800x600-Standard laeuft dagegen das schmale
      // Querformat-Seitenpanel, wo der Umbruch gewollt ist).
      tester.view.physicalSize = const Size(1650, 3000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await _pumpHomeWithPlan(
        tester,
        withPlan: false,
        config: HomeScreenConfig(
          belowSearchBuilder: (_) => const Text('Zuhause-Kacheln'),
        ),
      );

      expect(find.text('Jetzt losfahren'), findsOneWidget);
      expect(find.text('Optionen'), findsOneWidget);
      final timeY = tester.getTopLeft(find.text('Jetzt losfahren')).dy;
      final belowY = tester.getTopLeft(find.text('Zuhause-Kacheln')).dy;
      expect(timeY, lessThan(belowY));
      // Nebeneinander in EINER Zeile (vorher dehnte ein Align den
      // Zeit-Chip auf volle Breite, "Optionen" rutschte darunter).
      expect(
        tester.getCenter(find.text('Optionen')).dy,
        moreOrLessEquals(
          tester.getCenter(find.text('Jetzt losfahren')).dy,
          epsilon: 2,
        ),
      );
    },
  );
}
