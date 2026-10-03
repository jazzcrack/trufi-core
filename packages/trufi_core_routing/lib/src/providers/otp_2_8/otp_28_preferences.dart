import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/routing_localizations.dart';

/// Simplified walk speed levels for UI.
enum WalkSpeedLevel {
  slow,
  normal,
  fast;

  double get speedValue {
    switch (this) {
      case WalkSpeedLevel.slow:
        return 0.8;
      case WalkSpeedLevel.normal:
        return 1.33;
      case WalkSpeedLevel.fast:
        return 1.8;
    }
  }

  double get reluctanceValue {
    switch (this) {
      case WalkSpeedLevel.slow:
        return 3.5;
      case WalkSpeedLevel.normal:
        return 2.0;
      case WalkSpeedLevel.fast:
        return 1.5;
    }
  }
}

/// Transport modes for routing configuration.
enum RoutingMode {
  walk,
  transit,
  bicycle,
  car;

  String get otpName {
    switch (this) {
      case RoutingMode.walk:
        return 'WALK';
      case RoutingMode.transit:
        return 'TRANSIT';
      case RoutingMode.bicycle:
        return 'BICYCLE';
      case RoutingMode.car:
        return 'CAR';
    }
  }
}

/// A GBFS/shared-mobility vehicle type OTP's `qualifier: RENT` mechanism
/// can request (fahrplaner.de fork patch, Kapitel 3.23). A subset of
/// OTP's `Mode` enum that supports `RENT` via the legacy `plan` query
/// this fork uses - not OTP's full modern `FormFactor` enum.
enum RentalFormFactor {
  bicycle,
  scooter;

  String get otpMode {
    switch (this) {
      case RentalFormFactor.bicycle:
        return 'BICYCLE';
      case RentalFormFactor.scooter:
        return 'SCOOTER';
    }
  }
}

/// Builds the `transportModes` GraphQL variable from the user's base
/// modes plus any rental form factors they've opted into. Pure, no
/// side effects - when [rentalFormFactors] is empty (the only state
/// reachable before this patch, and still the default after it), this
/// produces byte-for-byte the same list the old inline
/// `.map((m) => {'mode': m.otpName})` produced.
List<Map<String, String>> buildTransportModesVariable({
  required Set<RoutingMode> baseModes,
  required Set<RentalFormFactor> rentalFormFactors,
}) {
  return [
    for (final mode in baseModes) {'mode': mode.otpName},
    for (final formFactor in rentalFormFactors)
      {'mode': formFactor.otpMode, 'qualifier': 'RENT'},
  ];
}

/// Internal preferences state for OTP 2.8 provider.
///
/// Handles its own persistence with SharedPreferences.
class Otp28PreferencesState extends ChangeNotifier {
  static const _key = 'routing_prefs_otp28';

  bool _wheelchair = false;
  double _walkSpeed = 1.33;
  double? _maxWalkDistance = 800;
  double _walkReluctance = 2.0;
  double _bikeSpeed = 5.0;
  Set<RoutingMode> _transportModes = const {
    RoutingMode.transit,
    RoutingMode.walk,
  };
  // fahrplaner.de fork patch (Kapitel 3.23): independent from
  // _transportModes on purpose - a RENT-qualified mode means something
  // different from a base mode and is requested alongside, not instead
  // of, the base modes above. Default empty: sharing stays opt-in, no
  // search mixes in GBFS results until the user actively picks one.
  Set<RentalFormFactor> _rentalFormFactors = const {};
  bool _initialized = false;

  bool get wheelchair => _wheelchair;
  double get walkSpeed => _walkSpeed;
  double? get maxWalkDistance => _maxWalkDistance;
  double get walkReluctance => _walkReluctance;
  double get bikeSpeed => _bikeSpeed;
  Set<RoutingMode> get transportModes => _transportModes;
  Set<RentalFormFactor> get rentalFormFactors => _rentalFormFactors;

  WalkSpeedLevel get walkSpeedLevel {
    if (_walkSpeed <= 0.9) return WalkSpeedLevel.slow;
    if (_walkSpeed <= 1.5) return WalkSpeedLevel.normal;
    return WalkSpeedLevel.fast;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    final sp = await SharedPreferences.getInstance();
    final json = sp.getString(_key);
    if (json != null) {
      try {
        final map = jsonDecode(json) as Map<String, dynamic>;
        _wheelchair = map['wheelchair'] as bool? ?? false;
        _walkSpeed = (map['walkSpeed'] as num?)?.toDouble() ?? 1.33;
        _maxWalkDistance = (map['maxWalkDistance'] as num?)?.toDouble() ?? 800;
        _walkReluctance = (map['walkReluctance'] as num?)?.toDouble() ?? 2.0;
        _bikeSpeed = (map['bikeSpeed'] as num?)?.toDouble() ?? 5.0;
        _transportModes =
            (map['transportModes'] as List<dynamic>?)
                ?.map(
                  (e) => RoutingMode.values.firstWhere(
                    (m) => m.name == e,
                    orElse: () => RoutingMode.transit,
                  ),
                )
                .toSet() ??
            const {RoutingMode.transit, RoutingMode.walk};
        // Missing key (every blob persisted before this patch) -> empty
        // set, i.e. unchanged behavior for existing users. Unrecognized
        // entries are skipped rather than forced to a fallback value -
        // unlike _transportModes there is no sensible "always include
        // this" default here.
        _rentalFormFactors =
            (map['rentalFormFactors'] as List<dynamic>?)
                ?.map((e) {
                  for (final formFactor in RentalFormFactor.values) {
                    if (formFactor.name == e) return formFactor;
                  }
                  return null;
                })
                .whereType<RentalFormFactor>()
                .toSet() ??
            const {};
      } catch (_) {}
    }
    _initialized = true;
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _key,
      jsonEncode({
        'wheelchair': _wheelchair,
        'walkSpeed': _walkSpeed,
        'maxWalkDistance': _maxWalkDistance,
        'walkReluctance': _walkReluctance,
        'bikeSpeed': _bikeSpeed,
        'transportModes': _transportModes.map((m) => m.name).toList(),
        'rentalFormFactors': _rentalFormFactors.map((f) => f.name).toList(),
      }),
    );
  }

  void setWheelchair(bool value) {
    if (_wheelchair == value) return;
    _wheelchair = value;
    if (value) {
      _walkSpeed = 0.8;
      _walkReluctance = 3.0;
      _maxWalkDistance ??= 400;
    }
    _save();
    notifyListeners();
  }

  void setWalkSpeedLevel(WalkSpeedLevel level) {
    if (walkSpeedLevel == level) return;
    _walkSpeed = level.speedValue;
    _walkReluctance = level.reluctanceValue;
    _save();
    notifyListeners();
  }

  void setMaxWalkDistance(double? distance) {
    if (_maxWalkDistance == distance) return;
    _maxWalkDistance = distance;
    _save();
    notifyListeners();
  }

  void setTransportModes(Set<RoutingMode> modes) {
    if (_transportModes == modes) return;
    _transportModes = Set.unmodifiable(modes);
    _save();
    notifyListeners();
  }

  void toggleTransportMode(RoutingMode mode) {
    final modes = Set<RoutingMode>.from(_transportModes);
    if (modes.contains(mode)) {
      if (modes.length > 1) modes.remove(mode);
    } else {
      modes.add(mode);
    }
    setTransportModes(modes);
  }

  void setRentalFormFactors(Set<RentalFormFactor> formFactors) {
    if (_rentalFormFactors == formFactors) return;
    _rentalFormFactors = Set.unmodifiable(formFactors);
    _save();
    notifyListeners();
  }

  void toggleRentalFormFactor(RentalFormFactor formFactor) {
    final formFactors = Set<RentalFormFactor>.from(_rentalFormFactors);
    if (!formFactors.remove(formFactor)) {
      formFactors.add(formFactor);
    }
    setRentalFormFactors(formFactors);
  }

  void reset() {
    _wheelchair = false;
    _walkSpeed = 1.33;
    _maxWalkDistance = 800;
    _walkReluctance = 2.0;
    _bikeSpeed = 5.0;
    _transportModes = const {RoutingMode.transit, RoutingMode.walk};
    _rentalFormFactors = const {};
    _save();
    notifyListeners();
  }
}

/// Complete preferences UI for OTP 2.8 provider.
class Otp28Preferences extends StatelessWidget {
  final Otp28PreferencesState state;
  final bool showWheelchair;
  final bool showBicycle;

  const Otp28Preferences({super.key, required this.state, this.showWheelchair = true, this.showBicycle = true});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showWheelchair) ...[
              _AccessibilitySection(state: state),
              const SizedBox(height: 24),
            ],
            _WalkSpeedSection(state: state),
            const SizedBox(height: 24),
            _TransportModesSection(state: state, showBicycle: showBicycle),
          ],
        );
      },
    );
  }
}

// --- Accessibility ---

class _AccessibilitySection extends StatelessWidget {
  final Otp28PreferencesState state;
  const _AccessibilitySection({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return _SettingsCard(
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Row(
          children: [
            Icon(
              Icons.accessible_rounded,
              color: state.wheelchair
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(RoutingLocalizations.of(context).prefsWheelchairAccessible)),
          ],
        ),
        subtitle: Text(
          state.wheelchair
              ? RoutingLocalizations.of(context).prefsWheelchairOn
              : RoutingLocalizations.of(context).prefsWheelchairOff,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        value: state.wheelchair,
        onChanged: (value) {
          HapticFeedback.selectionClick();
          state.setWheelchair(value);
        },
      ),
    );
  }
}

// --- Walk Speed ---

class _WalkSpeedSection extends StatelessWidget {
  final Otp28PreferencesState state;
  const _WalkSpeedSection({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.directions_walk_rounded,
              color: colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              RoutingLocalizations.of(context).prefsWalkingSpeed,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: WalkSpeedLevel.values.map((level) {
            final isSelected = state.walkSpeedLevel == level;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: level != WalkSpeedLevel.fast ? 8 : 0,
                ),
                child: _SpeedChip(
                  label: _speedLabel(context, level),
                  icon: _speedIcon(level),
                  isSelected: isSelected,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    state.setWalkSpeedLevel(level);
                  },
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  static String _speedLabel(BuildContext context, WalkSpeedLevel level) {
    final l10n = RoutingLocalizations.of(context);
    switch (level) {
      case WalkSpeedLevel.slow:
        return l10n.prefsSpeedSlow;
      case WalkSpeedLevel.normal:
        return l10n.prefsSpeedNormal;
      case WalkSpeedLevel.fast:
        return l10n.prefsSpeedFast;
    }
  }

  static IconData _speedIcon(WalkSpeedLevel level) {
    switch (level) {
      case WalkSpeedLevel.slow:
        return Icons.elderly_rounded;
      case WalkSpeedLevel.normal:
        return Icons.directions_walk_rounded;
      case WalkSpeedLevel.fast:
        return Icons.directions_run_rounded;
    }
  }
}

class _SpeedChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _SpeedChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.5)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Sharing quick filter (fahrplaner.de fork patch, Kapitel 3.23) ---

/// Compact, always-visible GBFS sharing quick-filter chip row. Rendered
/// inline on the search screen via
/// [IRoutingProvider.buildQuickFilterChips] - deliberately NOT nested
/// inside the full [Otp28Preferences] settings sheet, so this stays
/// discoverable rather than buried next to wheelchair/walk-speed
/// settings. [availableRentalFormFactors] controls which presets are
/// offered at all (e.g. only bicycle today, since nextbike Bremen is
/// the only live-tested GBFS feed - see architektur-konzept.md Kapitel
/// 3.23); an empty set renders nothing.
class SharingQuickFilterChips extends StatelessWidget {
  final Otp28PreferencesState state;
  final Set<RentalFormFactor> availableRentalFormFactors;

  /// Called right after a tap changes [state]'s rental form factors -
  /// unlike the full preferences sheet, a quick-filter chip takes effect
  /// immediately, so the caller (typically re-fetching the plan) needs
  /// to know when that happened.
  final VoidCallback? onChanged;

  const SharingQuickFilterChips({
    super.key,
    required this.state,
    required this.availableRentalFormFactors,
    this.onChanged,
  });

  static IconData _iconFor(RentalFormFactor formFactor) {
    switch (formFactor) {
      case RentalFormFactor.bicycle:
        return Icons.directions_bike_rounded;
      case RentalFormFactor.scooter:
        return Icons.electric_scooter_rounded;
    }
  }

  static String _labelFor(RoutingLocalizations l10n, RentalFormFactor formFactor) {
    switch (formFactor) {
      case RentalFormFactor.bicycle:
        return l10n.sharingFilterRentalBicycle;
      case RentalFormFactor.scooter:
        return l10n.sharingFilterRentalScooter;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (availableRentalFormFactors.isEmpty) return const SizedBox.shrink();
    final l10n = RoutingLocalizations.of(context);

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        bool isOnlyPreset(RentalFormFactor formFactor) =>
            state.rentalFormFactors.length == 1 &&
            state.rentalFormFactors.single == formFactor;

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final formFactor in availableRentalFormFactors)
              _TransportModeChip(
                icon: _iconFor(formFactor),
                label: _labelFor(l10n, formFactor),
                isSelected: isOnlyPreset(formFactor),
                onTap: () {
                  HapticFeedback.selectionClick();
                  state.setRentalFormFactors(
                    isOnlyPreset(formFactor) ? const {} : {formFactor},
                  );
                  onChanged?.call();
                },
              ),
            _TransportModeChip(
              icon: Icons.block_rounded,
              label: l10n.sharingFilterNone,
              isSelected: state.rentalFormFactors.isEmpty,
              onTap: () {
                HapticFeedback.selectionClick();
                state.setRentalFormFactors(const {});
                onChanged?.call();
              },
            ),
          ],
        );
      },
    );
  }
}

// --- Transport Modes ---

class _TransportModesSection extends StatelessWidget {
  final Otp28PreferencesState state;
  final bool showBicycle;
  const _TransportModesSection({required this.state, this.showBicycle = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.commute_rounded, color: colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              RoutingLocalizations.of(context).prefsTransportModes,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _TransportModeChip(
              icon: Icons.directions_bus_rounded,
              label: RoutingLocalizations.of(context).prefsModeTransit,
              isSelected: state.transportModes.contains(RoutingMode.transit),
              onTap: () {
                HapticFeedback.selectionClick();
                state.toggleTransportMode(RoutingMode.transit);
              },
            ),
            _TransportModeChip(
              icon: Icons.directions_walk_rounded,
              label: RoutingLocalizations.of(context).prefsModeWalk,
              isSelected: state.transportModes.contains(RoutingMode.walk),
              onTap: () {
                HapticFeedback.selectionClick();
                state.toggleTransportMode(RoutingMode.walk);
              },
            ),
            if (showBicycle)
              _TransportModeChip(
                icon: Icons.directions_bike_rounded,
                label: RoutingLocalizations.of(context).prefsModeBicycle,
                isSelected: state.transportModes.contains(RoutingMode.bicycle),
                onTap: () {
                  HapticFeedback.selectionClick();
                  state.toggleTransportMode(RoutingMode.bicycle);
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _TransportModeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TransportModeChip({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.5)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Helpers ---

class _SettingsCard extends StatelessWidget {
  final Widget child;
  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: child,
    );
  }
}
