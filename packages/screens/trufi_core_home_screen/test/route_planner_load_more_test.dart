import 'package:flutter_test/flutter_test.dart';
import 'package:trufi_core_home_screen/trufi_core_home_screen.dart';
import 'package:trufi_core_interfaces/trufi_core_interfaces.dart';
import 'package:trufi_core_routing/trufi_core_routing.dart' as routing;

/// fahrplaner.de fork patch (04.10.2026, Kapitel 3.27, see
/// FAHRPLANER_PATCHES.md): real TestFlight bug. `fetchPlan()` sorts every
/// individual response by OTP's generalized cost, not by time
/// (otp_28_routing_provider.dart's `sortByGeneralizedCost`, #849/#847 — a
/// deliberate, correct choice for a single search's "best option first"
/// ranking). `loadMoreItineraries()` merged a second, independently
/// cost-sorted page into the existing list via plain concatenation, which
/// destroyed chronological order across the combined list (reported live:
/// 03:04 → 05:06 → 03:20 → 07:45 → 11:18). This file pins two fixes:
/// 1. the merged list is re-sorted by `startTime` after pagination.
/// 2. `loadMoreItineraries()` requests more than the initial search's
///    5-itinerary default, so "load more" doesn't always add the same
///    small batch (the other half of the same bug report).
routing.Itinerary _itinerary(int startMinute) => routing.Itinerary(
  legs: const [],
  startTime: DateTime(2026, 10, 4, 8, startMinute),
  endTime: DateTime(2026, 10, 4, 9, startMinute),
  walkTime: const Duration(minutes: 5),
  duration: const Duration(hours: 1),
  walkDistance: 400,
);

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

/// Records every `fetchPlan` call's `pageCursor`/`numItineraries`, and
/// returns [initialPlan] for the first (non-paginated) call, [laterPlan]
/// for every subsequent (cursor-based) call — mirroring how a real OTP
/// server answers the initial search vs. a "load more" request.
class _RecordingPlanService implements RequestPlanService {
  _RecordingPlanService({required this.initialPlan, required this.laterPlan});

  final routing.Plan initialPlan;
  final routing.Plan laterPlan;
  final List<String?> pageCursors = [];
  final List<int?> numItinerariesCalls = [];

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
    pageCursors.add(pageCursor);
    numItinerariesCalls.add(numItineraries);
    return pageCursor == null ? initialPlan : laterPlan;
  }
}

void main() {
  group('loadMoreItineraries (Kapitel 3.27)', () {
    test(
      'merges a later page into chronological order even though each page '
      'is independently cost-sorted',
      () async {
        // Cost order, not time order — matches sortByGeneralizedCost's
        // real output for a single search.
        final initialPlan = routing.Plan(
          itineraries: [_itinerary(4), _itinerary(0), _itinerary(2)],
          nextPageCursor: 'cursor-later',
        );
        final laterPlan = routing.Plan(
          itineraries: [_itinerary(45), _itinerary(20), _itinerary(50)],
        );
        final service = _RecordingPlanService(
          initialPlan: initialPlan,
          laterPlan: laterPlan,
        );
        final cubit = RoutePlannerCubit(
          repository: _FakeRepository(),
          requestService: service,
        );
        await cubit.setFromPlace(
          const TrufiLocation(description: 'A', latitude: -17.465, longitude: -66.14),
        );
        await cubit.setToPlace(
          const TrufiLocation(description: 'B', latitude: -17.355, longitude: -66.19),
        );
        await cubit.fetchPlan();
        expect(
          cubit.state.plan!.itineraries!.map((i) => i.startTime.minute),
          [4, 0, 2],
          reason: 'the initial search keeps its cost order untouched',
        );

        await cubit.loadMoreItineraries(earlier: false);

        expect(
          cubit.state.plan!.itineraries!.map((i) => i.startTime.minute),
          [0, 2, 4, 20, 45, 50],
          reason:
              'after merging a second page, the combined list must read '
              'chronologically — no large back-and-forth time gaps.',
        );
        await cubit.close();
      },
    );

    test(
      '"load more" requests more itineraries than the initial search '
      'default, so it does not always add the same small batch',
      () async {
        final initialPlan = routing.Plan(
          itineraries: [_itinerary(0)],
          nextPageCursor: 'cursor-later',
        );
        final laterPlan = routing.Plan(itineraries: [_itinerary(30)]);
        final service = _RecordingPlanService(
          initialPlan: initialPlan,
          laterPlan: laterPlan,
        );
        final cubit = RoutePlannerCubit(
          repository: _FakeRepository(),
          requestService: service,
        );
        await cubit.setFromPlace(
          const TrufiLocation(description: 'A', latitude: -17.465, longitude: -66.14),
        );
        await cubit.setToPlace(
          const TrufiLocation(description: 'B', latitude: -17.355, longitude: -66.19),
        );
        await cubit.fetchPlan();
        await cubit.loadMoreItineraries(earlier: false);

        expect(
          service.numItinerariesCalls,
          [null, loadMoreItinerariesPageSize],
          reason:
              'the initial search keeps the provider default; "load more" '
              'must explicitly ask for a larger page.',
        );
        await cubit.close();
      },
    );
  });
}
