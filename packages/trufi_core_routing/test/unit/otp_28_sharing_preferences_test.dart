// fahrplaner.de fork patch (Kapitel 3.23): unit tests for the GBFS
// sharing quick-filter mechanism - buildTransportModesVariable() (pure
// mapping) and Otp28PreferencesState's rentalFormFactors persistence.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trufi_core_routing/src/providers/otp_2_8/otp_28_preferences.dart';

void main() {
  group('buildTransportModesVariable', () {
    test('matches the old base-modes-only mapping when rentalFormFactors is empty', () {
      final result = buildTransportModesVariable(
        baseModes: {RoutingMode.transit, RoutingMode.walk},
        rentalFormFactors: const {},
      );

      expect(result, unorderedEquals([
        {'mode': 'TRANSIT'},
        {'mode': 'WALK'},
      ]));
    });

    test('adds a RENT-qualified entry per selected rental form factor', () {
      final result = buildTransportModesVariable(
        baseModes: {RoutingMode.walk},
        rentalFormFactors: {RentalFormFactor.bicycle},
      );

      expect(result, unorderedEquals([
        {'mode': 'WALK'},
        {'mode': 'BICYCLE', 'qualifier': 'RENT'},
      ]));
    });

    test('supports multiple rental form factors at once', () {
      final result = buildTransportModesVariable(
        baseModes: {RoutingMode.walk},
        rentalFormFactors: {RentalFormFactor.bicycle, RentalFormFactor.scooter},
      );

      expect(result, unorderedEquals([
        {'mode': 'WALK'},
        {'mode': 'BICYCLE', 'qualifier': 'RENT'},
        {'mode': 'SCOOTER', 'qualifier': 'RENT'},
      ]));
    });

    test('empty base modes with a rental form factor still emits the rental entry', () {
      final result = buildTransportModesVariable(
        baseModes: const {},
        rentalFormFactors: {RentalFormFactor.scooter},
      );

      expect(result, [
        {'mode': 'SCOOTER', 'qualifier': 'RENT'},
      ]);
    });
  });

  group('RentalFormFactor.otpMode', () {
    test('maps to the correct OTP Mode string', () {
      expect(RentalFormFactor.bicycle.otpMode, 'BICYCLE');
      expect(RentalFormFactor.scooter.otpMode, 'SCOOTER');
    });
  });

  group('Otp28PreferencesState.rentalFormFactors', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to empty (opt-in only, no change for existing behavior)', () async {
      final state = Otp28PreferencesState();
      await state.initialize();

      expect(state.rentalFormFactors, isEmpty);
    });

    test('setRentalFormFactors persists and round-trips through a fresh initialize()', () async {
      final state = Otp28PreferencesState();
      await state.initialize();

      state.setRentalFormFactors({RentalFormFactor.bicycle});

      final reloaded = Otp28PreferencesState();
      await reloaded.initialize();

      expect(reloaded.rentalFormFactors, {RentalFormFactor.bicycle});
    });

    test('toggleRentalFormFactor adds then removes', () async {
      final state = Otp28PreferencesState();
      await state.initialize();

      state.toggleRentalFormFactor(RentalFormFactor.scooter);
      expect(state.rentalFormFactors, {RentalFormFactor.scooter});

      state.toggleRentalFormFactor(RentalFormFactor.scooter);
      expect(state.rentalFormFactors, isEmpty);
    });

    test('reset() clears rentalFormFactors along with the other preferences', () async {
      final state = Otp28PreferencesState();
      await state.initialize();
      state.setRentalFormFactors({RentalFormFactor.bicycle});

      state.reset();

      expect(state.rentalFormFactors, isEmpty);
    });

    test('a persisted blob from before this patch (no rentalFormFactors key) loads as empty', () async {
      SharedPreferences.setMockInitialValues({
        'routing_prefs_otp28': jsonEncode({
          'wheelchair': false,
          'walkSpeed': 1.33,
          'maxWalkDistance': 800,
          'walkReluctance': 2.0,
          'bikeSpeed': 5.0,
          'transportModes': ['transit', 'walk'],
        }),
      });

      final state = Otp28PreferencesState();
      await state.initialize();

      expect(state.rentalFormFactors, isEmpty);
      expect(state.transportModes, {RoutingMode.transit, RoutingMode.walk});
    });

    test('ignores unrecognized rentalFormFactors entries instead of crashing', () async {
      SharedPreferences.setMockInitialValues({
        'routing_prefs_otp28': jsonEncode({
          'transportModes': ['transit', 'walk'],
          'rentalFormFactors': ['bicycle', 'someFutureFormFactor'],
        }),
      });

      final state = Otp28PreferencesState();
      await state.initialize();

      expect(state.rentalFormFactors, {RentalFormFactor.bicycle});
    });
  });
}
