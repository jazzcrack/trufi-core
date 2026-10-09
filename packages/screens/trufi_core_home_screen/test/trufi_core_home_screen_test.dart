import 'package:flutter_test/flutter_test.dart';
import 'package:trufi_core_home_screen/trufi_core_home_screen.dart';

void main() {
  group('RoutePlannerState', () {
    test('initial state has correct defaults', () {
      const state = RoutePlannerState();

      expect(state.fromPlace, isNull);
      expect(state.toPlace, isNull);
      expect(state.plan, isNull);
      expect(state.selectedItinerary, isNull);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    });

    test('isPlacesDefined returns false when no places', () {
      const state = RoutePlannerState();
      expect(state.isPlacesDefined, isFalse);
    });

    test('hasError returns true when error is set', () {
      const state = RoutePlannerState(error: 'Test error');
      expect(state.hasError, isTrue);
    });

    test('copyWith preserves values not being changed', () {
      const state = RoutePlannerState(isLoading: true, error: 'Test error');

      final newState = state.copyWith(isLoading: false);

      expect(newState.isLoading, isFalse);
      expect(newState.error, equals('Test error'));
    });

    test('copyWithNullable can set values to null', () {
      const state = RoutePlannerState(error: 'Test error');

      final newState = state.copyWithNullable(error: const Optional(null));

      expect(newState.error, isNull);
    });
  });

  group('HomeScreenConfig', () {
    test('has correct defaults', () {
      const config = HomeScreenConfig();

      expect(config.chooseLocationZoom, equals(16.0));
      expect(config.myPlaces, isEmpty);
    });

    test('can set custom values', () {
      const config = HomeScreenConfig(chooseLocationZoom: 18.0);

      expect(config.chooseLocationZoom, equals(18.0));
    });

    // Redesign Oktober 2026 (docs/design/HANDOFF.md Abschnitt 3.1,
    // Patch 28): additiver Hook, `null` per Default - der eigentliche
    // Render-Zweig (sichtbar nur auf dem leeren Home-Screen) sitzt in
    // HomeScreen, dessen volle Pumpbarkeit ein schweres Map-/Routing-
    // Setup braucht (siehe restored_plan_map_test.dart) - fuer diesen
    // additiven Konfigurationspunkt reicht wie bei showMapTypeButton/
    // extraMapLayerSettings oben die Feld-Ebene.
    test('belowSearchBuilder ist standardmaessig null', () {
      const config = HomeScreenConfig();
      expect(config.belowSearchBuilder, isNull);
    });
  });
}
