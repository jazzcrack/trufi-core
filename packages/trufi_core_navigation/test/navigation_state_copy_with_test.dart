import 'package:flutter_test/flutter_test.dart';
import 'package:trufi_core_navigation/trufi_core_navigation.dart';

/// fahrplaner.de fork patch (05.10.2026, siehe FAHRPLANER_PATCHES.md):
/// Regressionstest fuer einen beim Schreiben eines Navigations-Szenario-
/// Tests entdeckten Bug - `copyWith(distanceFromRoute: null)` kam nie an,
/// da `null ?? this.distanceFromRoute` unveraendert den alten Wert
/// zurueckgibt (klassischer copyWith-Nullable-Bug). Betraf konkret
/// `NavigationCubit._checkOffRoute()`s "zurueck auf der Route"-Zweig.
void main() {
  test(
    'copyWith(clearDistanceFromRoute: true) setzt distanceFromRoute auf null',
    () {
      const withDistance = NavigationState(
        isOffRoute: true,
        distanceFromRoute: 350.0,
      );

      final cleared = withDistance.copyWith(
        isOffRoute: false,
        clearDistanceFromRoute: true,
      );

      expect(cleared.isOffRoute, isFalse);
      expect(cleared.distanceFromRoute, isNull);
    },
  );

  test(
    'copyWith ohne clearDistanceFromRoute laesst distanceFromRoute unveraendert',
    () {
      const withDistance = NavigationState(distanceFromRoute: 120.0);

      final unchanged = withDistance.copyWith(isGpsWeak: true);

      expect(unchanged.distanceFromRoute, 120.0);
    },
  );

  test(
    'copyWith(distanceFromRoute: x) setzt weiterhin einen neuen Wert',
    () {
      const state = NavigationState();

      final updated = state.copyWith(
        isOffRoute: true,
        distanceFromRoute: 275.5,
      );

      expect(updated.distanceFromRoute, 275.5);
    },
  );

  test('clearError() setzt distanceFromRoute tatsaechlich zurueck', () {
    const withError = NavigationState(
      status: NavigationStatus.error,
      errorType: NavigationError.trackingStartFailed,
      isOffRoute: true,
      distanceFromRoute: 500.0,
    );

    final cleared = withError.clearError();

    expect(cleared.distanceFromRoute, isNull);
    expect(cleared.isOffRoute, isFalse);
  });
}
