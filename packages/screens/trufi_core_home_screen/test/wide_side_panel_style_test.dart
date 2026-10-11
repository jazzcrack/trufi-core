import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show AttributionButtonPosition;
import 'package:trufi_core_home_screen/trufi_core_home_screen.dart';
import 'package:trufi_core_interfaces/trufi_core_interfaces.dart'
    show TrufiLocation;
import 'package:trufi_core_maps/trufi_core_maps.dart';
import 'package:trufi_core_routing/trufi_core_routing.dart' as routing;
import 'package:trufi_core_search_locations/trufi_core_search_locations.dart'
    show SearchLocationBar, SearchLocationsLocalizations;

/// fahrplaner.de fork patch (Patch 42, see FAHRPLANER_PATCHES.md) -
/// HomeScreenConfig.sidePanelStyle/cameraTargetAdjuster. Drives the real
/// [HomeScreen] over a fake map engine (same pattern as
/// restored_plan_map_test.dart) instead of the native MapLibre widget,
/// which crashes in this test environment.
const _defaultCenter = LatLng(53.0793, 8.8017);

class _NeverFetchPlanService implements RequestPlanService {
  @override
  Future<routing.Plan> fetchPlan({
    required TrufiLocation from,
    required TrufiLocation to,
    String? locale,
    required DateTime dateTime,
    bool arriveBy = false,
    String? pageCursor,
    int? numItineraries,
  }) {
    throw UnimplementedError('not expected on the empty planning screen');
  }
}

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
  }) {
    calls.camera = camera;
    return _FakeMap(controller: controller, initialCamera: initialCamera);
  }
}

class _FakeMap extends StatefulWidget {
  const _FakeMap({required this.controller, required this.initialCamera});
  final TrufiMapController? controller;
  final TrufiCameraPosition initialCamera;

  @override
  State<_FakeMap> createState() => _FakeMapState();
}

class _FakeMapState extends State<_FakeMap> implements TrufiMapDelegate {
  late TrufiCameraPosition _camera = widget.initialCamera;

  @override
  void initState() {
    super.initState();
    widget.controller?.attach(this);
  }

  @override
  void dispose() {
    widget.controller?.detach(this);
    super.dispose();
  }

  @override
  TrufiCameraPosition get cameraPosition => _camera;
  @override
  void moveCamera(TrufiCameraPosition position) => _camera = position;
  @override
  void fitBounds(
    LatLngBounds bounds, {
    EdgeInsets padding = EdgeInsets.zero,
    double minZoom = 2.0,
    double maxZoom = 20.0,
  }) {}
  @override
  List<TrufiMarker> pickMarkersAt(
    LatLng tap, {
    double hitboxPx = 24.0,
    int? perLayerLimit,
    int? globalLimit,
  }) => const [];

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

/// A landscape-phone-sized logical viewport (devicePixelRatio 1.0 keeps
/// logical == physical, so `constraints.maxWidth` in the LayoutBuilder is
/// exactly 844 - comfortably over the 600px isWideScreen threshold).
Future<_MapCalls> _pumpHome(
  WidgetTester tester, {
  required HomeScreenConfig config,
}) async {
  tester.view.physicalSize = const Size(844, 390);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final calls = _MapCalls();
  final manager = MapEngineManager(
    engines: [_FakeEngine(calls)],
    defaultCenter: _defaultCenter,
  );
  final cubit = RoutePlannerCubit(
    repository: _FakeRepository(),
    requestService: _NeverFetchPlanService(),
  );
  addTearDown(cubit.close);

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
        home: HomeScreen(onMenuPressed: () {}, config: config),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return calls;
}

void _mockGeolocatorWithFix(LatLng fix) {
  final position = <String, dynamic>{
    'latitude': fix.latitude,
    'longitude': fix.longitude,
    'timestamp': DateTime(2026, 10, 12, 12).millisecondsSinceEpoch,
    'accuracy': 5.0,
    'altitude': 0.0,
    'altitude_accuracy': 0.0,
    'heading': 0.0,
    'heading_accuracy': 0.0,
    'speed': 0.0,
    'speed_accuracy': 0.0,
    'is_mocked': true,
  };
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('flutter.baseflow.com/geolocator'),
    (call) async {
      switch (call.method) {
        case 'isLocationServiceEnabled':
          return true;
        case 'checkPermission':
        case 'requestPermission':
          return 3; // LocationPermission.always
        case 'getLastKnownPosition':
        case 'getCurrentPosition':
          return position;
        case 'getLocationAccuracy':
          return 0;
      }
      return null;
    },
  );
  const updates = EventChannel('flutter.baseflow.com/geolocator_updates');
  messenger.setMockStreamHandler(
    updates,
    MockStreamHandler.inline(
      onListen: (args, events) => events.success(position),
      onCancel: (args) {},
    ),
  );
  addTearDown(() => messenger.setMockStreamHandler(updates, null));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
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

  group('WideSidePanelStyle (Patch 42, Querformat Q6)', () {
    testWidgets(
      'default style (null) keeps the panel flush left at breakpoint width',
      (tester) async {
        await _pumpHome(tester, config: const HomeScreenConfig());

        final barLeft = tester.getTopLeft(find.byType(SearchLocationBar)).dx;
        expect(barLeft, lessThan(20), reason: 'flush left, no margin');
      },
    );

    testWidgets('floating onRight style moves the panel to the right edge '
        'at the fixed width, with margin', (tester) async {
      await _pumpHome(
        tester,
        config: HomeScreenConfig(
          sidePanelStyle: (context) => const WideSidePanelStyle(
            onRight: true,
            floating: true,
            floatingMargin: EdgeInsets.all(12),
            fixedWidth: 356,
            showMapOverlay: true,
            mapControlsBottomLeft: true,
          ),
        ),
      );

      final barTopLeft = tester.getTopLeft(find.byType(SearchLocationBar));
      // Panel right edge sits 12px from the 844px-wide screen's right edge,
      // panel is 356px wide -> its content starts around 844-12-356=476.
      expect(barTopLeft.dx, greaterThan(400));
      expect(barTopLeft.dy, greaterThan(5), reason: 'floating margin on top');
    });

    testWidgets(
      'mapOverlayBuilder is suppressed on wide screens by default, shown '
      'when showMapOverlay is true',
      (tester) async {
        final config = HomeScreenConfig(
          mapOverlayBuilder: (context) => const Text('OFFLINE_PILL'),
          sidePanelStyle: (context) =>
              const WideSidePanelStyle(showMapOverlay: true),
        );
        await _pumpHome(tester, config: config);
        expect(find.text('OFFLINE_PILL'), findsOneWidget);

        await _pumpHome(
          tester,
          config: HomeScreenConfig(
            mapOverlayBuilder: (context) => const Text('OFFLINE_PILL'),
          ),
        );
        expect(find.text('OFFLINE_PILL'), findsNothing);
      },
    );

    testWidgets(
      'cameraTargetAdjuster shifts the "my location" camera target east',
      (tester) async {
        const fix = LatLng(53.0833, 8.8139);
        _mockGeolocatorWithFix(fix);

        await _pumpHome(
          tester,
          config: HomeScreenConfig(
            sidePanelStyle: (context) => const WideSidePanelStyle(
              onRight: true,
              floating: true,
              fixedWidth: 356,
            ),
            cameraTargetAdjuster: (context, target, zoom) =>
                LatLng(target.latitude, target.longitude + 0.01),
          ),
        );

        // Permission already granted + a fix available: tracking auto-starts
        // before this point, so the icon is already the filled variant (see
        // restored_plan_map_test.dart's "already tracking" comment).
        final myLocation = find.byIcon(Icons.my_location_rounded);
        expect(myLocation, findsOneWidget);
        await tester.tap(myLocation);
        await tester.pumpAndSettle();

        // A programmatic move (_moveCameraTracked) goes straight to the map
        // controller, not through a rebuild - so it shows up on the fake
        // map's own state, not on the last `camera:` handed to buildMap().
        final map = tester.state(find.byType(_FakeMap)) as _FakeMapState;
        expect(map.cameraPosition.target.latitude, fix.latitude);
        expect(
          map.cameraPosition.target.longitude,
          closeTo(fix.longitude + 0.01, 1e-9),
          reason: 'cameraTargetAdjuster must be applied to the raw GPS fix',
        );
      },
    );
  });
}
