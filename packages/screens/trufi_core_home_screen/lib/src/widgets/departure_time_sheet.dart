import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:trufi_core_base_widgets/trufi_core_base_widgets.dart';

import '../../l10n/home_screen_localizations.dart';
import '../cubit/route_planner_cubit.dart';
import '../models/route_planner_state.dart';

/// fahrplaner.de fork patch (siehe FAHRPLANER_PATCHES.md, Nutzer-Wunsch:
/// "Optionen" soll auch den Zeitpunkt der Fahrt als Kontext zeigen statt nur
/// Routing-Praeferenzen): aus home_screen.dart herausgeloest, damit sowohl
/// [DepartureTimeChip] (schneller Zugriff direkt auf dem Home-Screen,
/// unveraendertes Verhalten) als auch die neue Zeit-Kontextzeile im
/// "Optionen"-Sheet ([RoutingSettingsSheet] in routing_settings_sheet.dart)
/// denselben Dialog oeffnen (showDepartureTimeSheet()) und dieselbe
/// Label-Formatierung (timeModeIcon()/timeModeLabel()) nutzen, statt zwei
/// leicht abweichende Kopien zu pflegen.
IconData timeModeIcon(TimeMode mode) {
  switch (mode) {
    case TimeMode.leaveNow:
      return Icons.access_time_rounded;
    case TimeMode.departAt:
      return Icons.departure_board_rounded;
    case TimeMode.arriveBy:
      return Icons.schedule_rounded;
  }
}

String timeModeLabel(
  TimeMode mode,
  DateTime? dateTime,
  HomeScreenLocalizations l10n,
) {
  switch (mode) {
    case TimeMode.leaveNow:
      return l10n.leaveNow;
    case TimeMode.departAt:
      if (dateTime != null) {
        return l10n.departAtTime(_formatDateTime(dateTime, l10n));
      }
      return l10n.departAt;
    case TimeMode.arriveBy:
      if (dateTime != null) {
        return l10n.arriveByTime(_formatDateTime(dateTime, l10n));
      }
      return l10n.arriveBy;
  }
}

String _formatDateTime(DateTime dt, HomeScreenLocalizations l10n) {
  final now = DateTime.now();
  final isToday =
      dt.year == now.year && dt.month == now.month && dt.day == now.day;
  final isTomorrow =
      dt.year == now.year && dt.month == now.month && dt.day == now.day + 1;

  final time =
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  if (isToday) {
    return time;
  } else if (isTomorrow) {
    return l10n.tomorrowWithTime(time);
  } else {
    return '${dt.day}/${dt.month} $time';
  }
}

/// Oeffnet den Zeitpunkt-Dialog - oeffentlich, damit sowohl [DepartureTimeChip]
/// als auch die Zeit-Kontextzeile im "Optionen"-Sheet denselben Dialog
/// teilen, statt die Sheet-Oeffnungs-Logik zu verdoppeln.
void showDepartureTimeSheet(
  BuildContext context, {
  required TimeMode currentMode,
  required DateTime? currentDateTime,
  required VoidCallback onTimeChanged,
}) {
  HapticFeedback.selectionClick();
  showTrufiModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _DepartureTimeSheet(
      initialMode: currentMode,
      initialDateTime: currentDateTime,
      onTimeChanged: onTimeChanged,
      cubit: context.read<RoutePlannerCubit>(),
    ),
  );
}

/// Schneller Zugriff auf den Zeitpunkt direkt auf dem Home-Screen
/// ("Jetzt losfahren"-Chip, docs/design/HANDOFF.md Abschnitt 3.1) -
/// unveraendertes Verhalten/Aussehen, bleibt als eigener Knopf neben
/// "Optionen" bestehen (Nutzerentscheidung 12.10.2026: kein vollstaendiges
/// Zusammenlegen in einen einzigen Dialog).
class DepartureTimeChip extends StatelessWidget {
  final VoidCallback onTimeChanged;

  const DepartureTimeChip({super.key, required this.onTimeChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = HomeScreenLocalizations.of(context);

    return BlocBuilder<RoutePlannerCubit, RoutePlannerState>(
      builder: (context, state) {
        final timeMode = state.timeMode;
        final dateTime = state.dateTime;

        // fahrplaner.de fork patch (15.10.2026, T046): KEIN `Align` mehr -
        // es dehnte den Chip auf volle Breite, wodurch "Optionen" im
        // umgebenden `Wrap` immer in eine eigene Zeile rutschte. Pillen-
        // Optik wie Main.dc.html: getoente Flaeche (--sf2 =
        // surfaceContainer), voll gerundet, ohne Schatten.
        return Material(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: () => showDepartureTimeSheet(
              context,
              currentMode: timeMode,
              currentDateTime: dateTime,
              onTimeChanged: onTimeChanged,
            ),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              // fahrplaner.de fork patch (see FAHRPLANER_PATCHES.md):
              // 12 instead of 8 - the old padding left the tappable area
              // under the 44px minimum (docs/design/QUERFORMAT.md
              // Grundregel 5, found during the Querformat Q8 gap review).
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    timeModeIcon(timeMode),
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    timeModeLabel(timeMode, dateTime, l10n),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Bottom sheet for selecting departure time mode and date/time
class _DepartureTimeSheet extends StatefulWidget {
  final TimeMode initialMode;
  final DateTime? initialDateTime;
  final VoidCallback onTimeChanged;
  final RoutePlannerCubit cubit;

  const _DepartureTimeSheet({
    required this.initialMode,
    required this.initialDateTime,
    required this.onTimeChanged,
    required this.cubit,
  });

  @override
  State<_DepartureTimeSheet> createState() => _DepartureTimeSheetState();
}

class _DepartureTimeSheetState extends State<_DepartureTimeSheet> {
  late TimeMode _selectedMode;
  late DateTime _selectedDateTime;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.initialMode;
    _selectedDateTime = widget.initialDateTime ?? DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = HomeScreenLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.whenDoYouWantToTravel,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Time mode options
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _TimeModeOption(
                    icon: Icons.access_time_rounded,
                    label: l10n.leaveNow,
                    isSelected: _selectedMode == TimeMode.leaveNow,
                    onTap: () {
                      setState(() => _selectedMode = TimeMode.leaveNow);
                    },
                  ),
                  const SizedBox(height: 8),
                  _TimeModeOption(
                    icon: Icons.departure_board_rounded,
                    label: l10n.departAt.replaceAll('...', ''),
                    isSelected: _selectedMode == TimeMode.departAt,
                    onTap: () {
                      setState(() => _selectedMode = TimeMode.departAt);
                    },
                  ),
                  const SizedBox(height: 8),
                  _TimeModeOption(
                    icon: Icons.schedule_rounded,
                    label: l10n.arriveBy.replaceAll('...', ''),
                    isSelected: _selectedMode == TimeMode.arriveBy,
                    onTap: () {
                      setState(() => _selectedMode = TimeMode.arriveBy);
                    },
                  ),
                ],
              ),
            ),
            // Date/time picker (only shown when not "Leave now")
            if (_selectedMode != TimeMode.leaveNow) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: _DateTimeButton(
                        icon: Icons.calendar_today_rounded,
                        label: _formatDate(_selectedDateTime, l10n),
                        onTap: () => _selectDate(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateTimeButton(
                        icon: Icons.access_time_rounded,
                        label: _formatTime(_selectedDateTime),
                        onTap: () => _selectTime(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Apply button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _applyChanges,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(l10n.buttonApply),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt, HomeScreenLocalizations l10n) {
    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final isTomorrow =
        dt.year == now.year && dt.month == now.month && dt.day == now.day + 1;

    if (isToday) return l10n.today;
    if (isTomorrow) return l10n.tomorrow;

    final months = [
      l10n.monthJan,
      l10n.monthFeb,
      l10n.monthMar,
      l10n.monthApr,
      l10n.monthMay,
      l10n.monthJun,
      l10n.monthJul,
      l10n.monthAug,
      l10n.monthSep,
      l10n.monthOct,
      l10n.monthNov,
      l10n.monthDec,
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _selectDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDateTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _selectedDateTime.hour,
          _selectedDateTime.minute,
        );
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
    );
    if (picked != null) {
      setState(() {
        _selectedDateTime = DateTime(
          _selectedDateTime.year,
          _selectedDateTime.month,
          _selectedDateTime.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  void _applyChanges() {
    HapticFeedback.mediumImpact();
    widget.cubit.setTimeMode(_selectedMode);
    if (_selectedMode != TimeMode.leaveNow) {
      widget.cubit.setDateTime(_selectedDateTime);
    }
    Navigator.of(context).pop();
    widget.onTimeChanged();
  }
}

/// Time mode selection option
class _TimeModeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TimeModeOption({
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
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.5)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 22,
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (isSelected)
                Icon(
                  Icons.check_circle_rounded,
                  size: 22,
                  color: colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Date/time selection button
class _DateTimeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DateTimeButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
