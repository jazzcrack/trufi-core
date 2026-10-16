// fahrplaner.de fork patch 59 (16.10.2026, T043, Nutzer-Fund): "Frühere/
// spätere Verbindungen" luden die ganze Liste neu und sprangen an den
// Anfang. Ursache: loadMoreItineraries() setzte isLoading - ItineraryList
// ersetzt dann die komplette Liste durch die Lade-Animation. Dieser Test
// haelt fest: kein isLoading beim Nachladen, Liste bleibt stehen, Scroll-
// position bleibt, Dubletten werden beim Zusammenfuehren entfernt.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trufi_core_home_screen/trufi_core_home_screen.dart';
import 'package:trufi_core_interfaces/trufi_core_interfaces.dart';
import 'package:trufi_core_routing/trufi_core_routing.dart' as routing;

class _FakeRepository implements HomeScreenRepository {
  routing.Plan? storedPlan;
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
  Future<void> savePlan(routing.Plan? data) async => storedPlan = data;
  @override
  Future<routing.Plan?> getPlan() async => storedPlan;
  @override
  Future<void> saveSelectedItinerary(routing.Itinerary? data) async {}
  @override
  Future<routing.Itinerary?> getSelectedItinerary() async => null;
  @override
  Future<void> clear() async {}
}

/// Erste Anfrage sofort, jede Nachlade-Anfrage erst, wenn der Test
/// [completeLater] aufruft - so ist der Zustand WAEHREND des Ladens pruefbar.
class _GatedPlanService implements RequestPlanService {
  _GatedPlanService({required this.initialPlan, required this.laterPlan});

  final routing.Plan initialPlan;
  final routing.Plan laterPlan;
  Completer<routing.Plan>? _pending;

  void completeLater() => _pending!.complete(laterPlan);

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
    if (pageCursor == null) return Future.value(initialPlan);
    _pending = Completer<routing.Plan>();
    return _pending!.future;
  }
}

/// Liefert fuer jeden Nachlade-Aufruf die naechste Seite aus [pages]
/// (Patch 60, T059: leere Zeitfenster).
class _SequencePlanService implements RequestPlanService {
  _SequencePlanService({required this.initialPlan, required this.pages});

  final routing.Plan initialPlan;
  final List<routing.Plan> pages;
  int pageCalls = 0;

  @override
  Future<routing.Plan> fetchPlan({
    required TrufiLocation from,
    required TrufiLocation to,
    String? locale,
    required DateTime dateTime,
    bool arriveBy = false,
    String? pageCursor,
    int? numItineraries,
  }) async {
    if (pageCursor == null) return initialPlan;
    return pages[pageCalls++];
  }
}

routing.Itinerary _itinerary(int minute) {
  // In der Zukunft: der Cubit filtert bereits abgefahrene Verbindungen.
  final base = DateTime.now().add(const Duration(days: 1));
  final start = DateTime(
    base.year,
    base.month,
    base.day,
    8,
  ).add(Duration(minutes: minute));
  return routing.Itinerary(
    legs: [
      routing.Leg(
        mode: 'BUS',
        tripId: '1:trip-$minute',
        startTime: start,
        endTime: start.add(const Duration(minutes: 20)),
        duration: const Duration(minutes: 20),
        distance: 5000,
        transitLeg: true,
        shortName: 'L$minute',
        route: routing.Route(gtfsId: '1:L$minute', shortName: 'L$minute'),
      ),
    ],
    startTime: start,
    endTime: start.add(const Duration(minutes: 20)),
    walkTime: Duration.zero,
    duration: const Duration(minutes: 20),
    walkDistance: 0,
  );
}

Future<RoutePlannerCubit> _cubit(RequestPlanService service) async {
  final cubit = RoutePlannerCubit(
    repository: _FakeRepository(),
    requestService: service,
  );
  await cubit.setFromPlace(
    const TrufiLocation(description: 'A', latitude: 53.0, longitude: 8.8),
  );
  await cubit.setToPlace(
    const TrufiLocation(description: 'B', latitude: 53.1, longitude: 8.6),
  );
  await cubit.fetchPlan();
  return cubit;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final initialPlan = routing.Plan(
    itineraries: [for (var m = 0; m < 80; m += 10) _itinerary(m)],
    nextPageCursor: 'later',
  );

  test('Nachladen setzt nie isLoading, nur isLoadingLater', () async {
    final service = _GatedPlanService(
      initialPlan: initialPlan,
      laterPlan: routing.Plan(itineraries: [_itinerary(90)]),
    );
    final cubit = await _cubit(service);
    final states = <RoutePlannerState>[];
    final sub = cubit.stream.listen(states.add);

    final future = cubit.loadMoreItineraries(earlier: false);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.isLoadingLater, isTrue);
    service.completeLater();
    await future;
    await sub.cancel();

    expect(states.any((s) => s.isLoading), isFalse);
    expect(cubit.state.isLoadingMore, isFalse);
    expect(cubit.state.plan!.itineraries!.length, 9);
    await cubit.close();
  });

  test('ueberlappende Seiten: dieselbe Verbindung nur einmal', () async {
    final service = _GatedPlanService(
      initialPlan: initialPlan,
      laterPlan: routing.Plan(itineraries: [_itinerary(70), _itinerary(90)]),
    );
    final cubit = await _cubit(service);

    final future = cubit.loadMoreItineraries(earlier: false);
    await Future<void>.delayed(Duration.zero);
    service.completeLater();
    await future;

    final starts = cubit.state.plan!.itineraries!
        .map((i) => i.startTime)
        .toList();
    expect(starts.toSet().length, starts.length);
    expect(cubit.state.plan!.itineraries!.length, 9);
    await cubit.close();
  });

  testWidgets('Liste bleibt beim Nachladen stehen, Scrollposition bleibt', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final service = _GatedPlanService(
      initialPlan: initialPlan,
      laterPlan: routing.Plan(itineraries: [_itinerary(90), _itinerary(100)]),
    );
    final cubit = await _cubit(service);
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: HomeScreenLocalizations.localizationsDelegates,
        supportedLocales: HomeScreenLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: Scaffold(
          body: BlocProvider.value(value: cubit, child: const ItineraryList()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byType(Scrollable).first;
    final laterButton = find.byIcon(Icons.expand_more_rounded);
    await tester.scrollUntilVisible(laterButton, 300, scrollable: list);
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(list);
    final offsetBefore = scrollable.position.pixels;
    expect(offsetBefore, greaterThan(0));

    await tester.tap(laterButton);
    await tester.pump();

    // Waehrend des Ladens: Liste steht weiter da (vorher Lade-Animation).
    expect(find.byType(Scrollable), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      offsetBefore,
    );

    service.completeLater();
    await tester.pumpAndSettle();

    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      offsetBefore,
    );
    expect(cubit.state.plan!.itineraries!.length, 10);
  });

  group('leere Zeitfenster (Patch 60, T059)', () {
    test('ueberspringt leere Seiten automatisch - EIN Klick reicht', () async {
      final service = _SequencePlanService(
        initialPlan: initialPlan,
        pages: [
          routing.Plan(itineraries: const [], nextPageCursor: 'p2'),
          routing.Plan(itineraries: const [], nextPageCursor: 'p3'),
          routing.Plan(itineraries: [_itinerary(300)], nextPageCursor: 'p4'),
        ],
      );
      final cubit = await _cubit(service);

      await cubit.loadMoreItineraries(earlier: false);

      expect(service.pageCalls, 3);
      expect(cubit.state.plan!.itineraries!.length, 9);
      expect(cubit.state.laterFoundNothing, isFalse);
      expect(cubit.state.plan!.nextPageCursor, 'p4');
      await cubit.close();
    });

    test('nach der Hoechstzahl leerer Seiten: Hinweis, Cursor bleibt fuer '
        'den naechsten Versuch', () async {
      final service = _SequencePlanService(
        initialPlan: initialPlan,
        pages: [
          for (var i = 0; i < loadMoreMaxEmptyPages; i++)
            routing.Plan(itineraries: const [], nextPageCursor: 'p$i'),
        ],
      );
      final cubit = await _cubit(service);

      await cubit.loadMoreItineraries(earlier: false);

      expect(service.pageCalls, loadMoreMaxEmptyPages);
      expect(cubit.state.laterFoundNothing, isTrue);
      expect(cubit.state.plan!.nextPageCursor, isNotNull);
      await cubit.close();
    });

    testWidgets('Liste zeigt den Hinweis statt kommentarlos nichts zu tun', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final service = _SequencePlanService(
        initialPlan: routing.Plan(
          itineraries: [_itinerary(0)],
          nextPageCursor: 'later',
        ),
        pages: [routing.Plan(itineraries: const [])],
      );
      final cubit = await _cubit(service);
      addTearDown(cubit.close);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates:
              HomeScreenLocalizations.localizationsDelegates,
          supportedLocales: HomeScreenLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: const ItineraryList(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.expand_more_rounded));
      await tester.pumpAndSettle();

      expect(
        find.text('Keine späteren Verbindungen gefunden.'),
        findsOneWidget,
      );
    });
  });

  test('kein weiterer Cursor von OTP: Cursor wird wirklich geleert', () async {
    final service = _SequencePlanService(
      initialPlan: initialPlan,
      pages: [
        routing.Plan(itineraries: [_itinerary(300)]),
      ],
    );
    final cubit = await _cubit(service);

    await cubit.loadMoreItineraries(earlier: false);

    expect(cubit.state.plan!.nextPageCursor, isNull);
    await cubit.close();
  });
}
