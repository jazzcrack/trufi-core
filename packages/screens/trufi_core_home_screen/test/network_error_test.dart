import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trufi_core_home_screen/trufi_core_home_screen.dart';
import 'package:trufi_core_interfaces/trufi_core_interfaces.dart';
import 'package:trufi_core_routing/trufi_core_routing.dart' as routing;

/// fahrplaner.de fork patch (see FAHRPLANER_PATCHES.md): a connectivity
/// failure should map to the generic [networkErrorKey], not leak the raw
/// exception text (e.g. "Otp28Exception: Network error: ClientException
/// with SocketException: Connection failed (OS Error: No route to host,
/// errno = 65) ...") into the UI verbatim - exactly what a real TestFlight
/// tester saw and reported (02.10.2026).
class _ThrowingPlanService implements RequestPlanService {
  _ThrowingPlanService(this.error);
  final Object error;

  @override
  Future<routing.Plan> fetchPlan({
    required TrufiLocation from,
    required TrufiLocation to,
    String? locale,
    required DateTime dateTime,
    bool arriveBy = false,
    String? pageCursor,
  }) async {
    throw error;
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

Future<RoutePlannerCubit> _cubitThatThrows(Object error) async {
  final cubit = RoutePlannerCubit(
    repository: _FakeRepository(),
    requestService: _ThrowingPlanService(error),
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
  group('RoutePlannerCubit network error classification', () {
    test('a SocketException-flavoured failure maps to networkErrorKey', () async {
      final cubit = await _cubitThatThrows(
        const SocketException('Connection failed (OS Error: No route to host, errno = 65)'),
      );
      expect(cubit.state.error, networkErrorKey);
    });

    test('an exception whose message mentions "Network error" maps to networkErrorKey', () async {
      // Mirrors Otp28Exception's own message shape without depending on
      // that class directly (it lives in trufi_core_routing's providers,
      // not part of the public API surface this test should reach for).
      final cubit = await _cubitThatThrows(
        Exception('Network error: ClientException with SocketException: Connection failed'),
      );
      expect(cubit.state.error, networkErrorKey);
    });

    test('a non-network failure still surfaces its own message, unchanged', () async {
      final cubit = await _cubitThatThrows(Exception('GraphQL error: Unknown argument "foo"'));
      expect(cubit.state.error, isNot(networkErrorKey));
      expect(cubit.state.error, contains('Unknown argument'));
    });
  });
}
