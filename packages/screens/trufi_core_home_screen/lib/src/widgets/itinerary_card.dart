import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:trufi_core_interfaces/trufi_core_interfaces.dart';
import 'package:trufi_core_routing/trufi_core_routing.dart' as routing;
import 'package:trufi_core_routing_ui/trufi_core_routing_ui.dart';
import 'package:trufi_core_utils/trufi_core_utils.dart';

import '../../l10n/home_screen_localizations.dart';
import 'realtime_chip.dart';
import 'segmented_route_chip.dart';

/// Card displaying a single itinerary option with modern design.
class ItineraryCard extends StatelessWidget {
  final routing.Itinerary itinerary;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onDetailsTap;
  final VoidCallback? onStartNavigation;

  /// The distinct routes serving each transit slot across the itinerary's
  /// group ([routing.ItineraryGroup.slotRoutes]). When a slot carries more
  /// than one route the chip paints one segment per option, every one in
  /// its route color; the one this itinerary rides shows at full
  /// strength, the rest slightly muted. The group's options are explored
  /// in the detail view.
  final List<List<routing.Route>>? slotRoutes;

  const ItineraryCard({
    super.key,
    required this.itinerary,
    required this.isSelected,
    required this.onTap,
    this.onDetailsTap,
    this.onStartNavigation,
    this.slotRoutes,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = HomeScreenLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
            : theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.dividerColor.withValues(alpha: 0.5),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: time range, duration, transfers, Go button
                _buildHeaderRow(context, theme, l10n),
                const SizedBox(height: 10),
                // Proportional per-leg duration bar (Redesign Oktober
                // 2026, docs/design/HANDOFF.md Abschnitt 3.2)
                _buildSegmentBar(context),
                const SizedBox(height: 8),
                // "in N Min ab X" + Echtzeit-Chips je Transit-Abschnitt
                _buildRealtimeRow(context, theme, l10n),
                if (_tightTransferWarning() != null) ...[
                  const SizedBox(height: 8),
                  _buildTransferWarningRow(theme),
                ],
                const SizedBox(height: 8),
                // Bottom row: Distance, walking, and details button
                _buildFooterRow(theme, l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderRow(
    BuildContext context,
    ThemeData theme,
    HomeScreenLocalizations l10n,
  ) {
    final transfers = itinerary.numberOfTransfers;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Zeit-/Dauer-Zusammenfassung (Redesign Oktober 2026, docs/design/
        // HANDOFF.md Abschnitt 3.2: "HH:MM – HH:MM" + Dauer + Umstiege in
        // einer Zeile statt der bisherigen getrennten Dauer-Pille).
        Expanded(
          // FittedBox: 12-hour locales ("8:00 AM → 9:00 AM") made this
          // row overflow on ordinary phone widths — scale down instead.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Time range. Hidden when `routingTimeOverride` is set on
                // the app config — under that mode the routing request
                // uses a fixed time-of-day, so the resulting
                // `startTime`/`endTime` are not the user's real
                // wall-clock and would mislead.
                if (context.watch<AppConfiguration?>()?.routingTimeOverride ==
                    null) ...[
                  Text(
                    '${formatClockTime(context, itinerary.startTime)} – '
                    '${formatClockTime(context, itinerary.endTime)}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  _formatDuration(itinerary.duration, l10n),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (transfers > 0) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.sync_alt_rounded,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  Text(
                    ' $transfers',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Go button or selection indicator. fahrplaner.de fork patch
        // (04.10.2026, Nutzer-Feedback: "auch die anderen Karten direkt
        // antippbar/startbar machen") - vorher war der Los-Button an
        // `isSelected` gekoppelt, obwohl `onStartNavigation` bereits pro
        // Karte an die JEWEILIGE Itinerary gebunden ist (siehe
        // itinerary_list.dart) - nicht nur die hervorgehobene, objektiv
        // beste Verbindung (sortByGeneralizedCost, siehe
        // otp_28_routing_provider.dart) war also technisch sofort
        // startbar, die anderen brauchten den Umweg über die
        // Detailansicht. Der Los-Button erscheint jetzt auf jeder Karte
        // mit einem `onStartNavigation`-Callback; die Hervorhebung
        // (Rahmen/Hintergrund oben) bleibt die alleinige visuelle
        // Markierung der Empfehlung.
        if (onStartNavigation != null)
          FilledButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              onStartNavigation!();
            },
            icon: const Icon(Icons.navigation_rounded, size: 16),
            label: Text(l10n.buttonGo),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else if (isSelected)
          Icon(
            Icons.check_circle_rounded,
            color: theme.colorScheme.primary,
            size: 24,
          ),
      ],
    );
  }

  /// Proportionaler Balken, ein Segment je Bein (Redesign Oktober 2026,
  /// docs/design/HANDOFF.md Abschnitt 3.2: "Breite = Dauer, Farbe/Form =
  /// Linie, Lücke = Wartezeit") - ersetzt die bisherige, horizontal
  /// scrollbare Chip-Reihe (`_LegChip` bleibt dieselbe Zelle, jetzt per
  /// `Expanded`/`flex` proportional statt intrinsisch breit, siehe dessen
  /// eigene Änderung). Wartezeit-Luecken (Umstiegspuffer) werden nur
  /// eingefuegt, wenn zwischen zwei Beinen tatsaechlich eine Zeitluecke
  /// liegt (`next.startTime > leg.endTime`) - unabhaengig vom Beintyp,
  /// in der Praxis meist nur zwischen zwei Transit-Beinen relevant, da
  /// Fusswege i. d. R. nahtlos in den naechsten Abschnitt uebergehen.
  Widget _buildSegmentBar(BuildContext context) {
    final theme = Theme.of(context);
    final legs = itinerary.legs;
    final chips = _chipsWithSlotRoutes(legs);
    final children = <Widget>[];

    for (var i = 0; i < legs.length; i++) {
      if (i > 0) children.add(const SizedBox(width: 3));
      final isWalkOrBike =
          legs[i].transportMode == routing.TransportMode.walk ||
          legs[i].transportMode == routing.TransportMode.bicycle;
      children.add(
        // Fusswege/Räder bekommen bewusst eine FESTE statt proportionale
        // Breite (02.10.2026-Stil-Fix nach echtem Test-Fund,
        // itinerary_card_three_buses_test.dart): eine Verbindung mit
        // mehreren kurzen Fusswegen liess per `Expanded`/`flex` manchen
        // Segmenten nur wenige Pixel - zu wenig fuer Icon+Text, RenderFlex
        // overflow. Proportionale Breite bleibt den Transit-Beinen
        // vorbehalten, bei denen die Dauer tatsaechlich den Vergleich
        // tragen soll.
        isWalkOrBike
            ? SizedBox(width: 28, height: 28, child: chips[i])
            : Expanded(
                flex: legs[i].duration.inSeconds.clamp(1, 1 << 30),
                child: chips[i],
              ),
      );
      if (i < legs.length - 1) {
        final gap = legs[i + 1].startTime.difference(legs[i].endTime);
        if (gap > Duration.zero) {
          children.add(const SizedBox(width: 3));
          children.add(
            Expanded(
              flex: gap.inSeconds.clamp(1, 1 << 30),
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          );
        }
      }
    }

    return SizedBox(height: 28, child: Row(children: children));
  }

  /// One chip per leg, feeding each transit chip the distinct routes its
  /// group offers for that slot. Walk/bike legs pass through.
  List<Widget> _chipsWithSlotRoutes(List<routing.Leg> legs) {
    var transitSlot = 0;
    return legs
        .map((leg) {
          final slots = slotRoutes;
          final routes =
              leg.transitLeg && slots != null && transitSlot < slots.length
              ? slots[transitSlot++]
              : null;
          return _LegChip(leg: leg, slotRoutes: routes);
        })
        .toList(growable: false);
  }

  /// "in N Min ab X" (bzw. "Leihrad bis Y · Z km" wenn das erste Bein
  /// selbst schon eine Fahrt ist, nicht nur ein kurzer Fussweg zur
  /// Haltestelle) + ein `RealtimeChip` je Transit-Bein (Abschnitt 3.2).
  /// Bewusst deutsche Festtexte ohne l10n-Anbindung, analog zu Patch 23
  /// (`realtime_chip.dart`) - vermeidet, die l10n-Oberflaeche fuer dieses
  /// bereits umfangreiche Redesign zusaetzlich zu vergroessern.
  Widget _buildRealtimeRow(
    BuildContext context,
    ThemeData theme,
    HomeScreenLocalizations l10n,
  ) {
    final leadingLabel = _leadingDepartureLabel(l10n);
    final transitChips = itinerary.legs
        .where((leg) => leg.transitLeg)
        .map(
          (leg) => RealtimeChip.fromDelay(
            leg.arrivalDelay,
            cancelled: leg.realtimeState == routing.RealtimeState.canceled,
            prefix: leg.shortName ?? leg.route?.shortName,
          ),
        )
        .toList(growable: false);

    // `Wrap` statt `Row`/`Expanded` (02.10.2026-Stil-Fix nach echtem
    // Test-Fund): eine Verbindung mit 3+ Transit-Beinen (z. B. zwei
    // Umstiege) kann mehr Chips erzeugen, als in eine Zeile auf
    // Telefonbreite passen - `Wrap` laesst sie dann in eine zweite Zeile
    // rutschen statt zu ueberlaufen.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        Text(
          leadingLabel,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        ...transitChips,
      ],
    );
  }

  String _leadingDepartureLabel(HomeScreenLocalizations l10n, {DateTime? now}) {
    final firstLeg = itinerary.legs.first;
    if (!firstLeg.transitLeg &&
        firstLeg.transportMode != routing.TransportMode.walk) {
      final modeLabel = firstLeg.transportMode == routing.TransportMode.bicycle
          ? 'Leihrad'
          : 'Fahrt';
      final toName = firstLeg.toPlace?.name ?? '';
      return '$modeLabel bis $toName · '
          '${_formatDistance(firstLeg.distance.toInt(), l10n)}';
    }
    final firstTransit = itinerary.legs.firstWhere(
      (leg) => leg.transitLeg,
      orElse: () => firstLeg,
    );
    if (!firstTransit.transitLeg) return 'Nur zu Fuß';
    final minutes = firstTransit.startTime
        .difference(now ?? DateTime.now())
        .inMinutes;
    final stopName = firstTransit.fromPlace?.name ?? '';
    return minutes > 0 ? 'in $minutes Min ab $stopName' : 'ab $stopName';
  }

  /// "Umstieg knapp" (Abschnitt 3.2/3.4 Formel: `nextLeg.start - (leg.end
  /// + delay)`, Schwelle 5 Min) - bewusst eine eigene, kleine Kopie der
  /// Formel statt eines Imports aus der App (das Hauptprojekt-Repo kann
  /// der Fork nicht importieren, siehe Patch 23) - hier liegen ohnehin
  /// nur zwei `routing.Leg`-Felder zugrunde, keine echte Logikduplizierung
  /// wert eines eigenen Pakets. Liefert das erste gefundene knappe
  /// Transit-zu-Transit-Umstieg, nicht alle.
  ({String stopName, int bufferMinutes})? _tightTransferWarning() {
    final legs = itinerary.legs;
    for (var i = 0; i < legs.length - 1; i++) {
      final leg = legs[i];
      final next = legs[i + 1];
      if (!leg.transitLeg || !next.transitLeg) continue;
      final buffer = next.startTime.difference(
        leg.endTime.add(leg.arrivalDelay ?? Duration.zero),
      );
      if (buffer < const Duration(minutes: 5)) {
        return (
          stopName: leg.toPlace?.name ?? next.fromPlace?.name ?? '',
          bufferMinutes: buffer.inMinutes < 0 ? 0 : buffer.inMinutes,
        );
      }
    }
    return null;
  }

  Widget _buildTransferWarningRow(ThemeData theme) {
    final warning = _tightTransferWarning()!;
    const color = Color(0xFF9A4A00); // --late, siehe fahrplaner_theme.dart
    return Container(
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Umstieg ${warning.stopName} wird knapp '
              '(${warning.bufferMinutes} Min)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterRow(ThemeData theme, HomeScreenLocalizations l10n) {
    final walkingLegs = itinerary.legs.where(
      (leg) => leg.transportMode == routing.TransportMode.walk,
    );
    final totalWalkingMeters = walkingLegs.fold<int>(
      0,
      (sum, leg) => sum + leg.distance.toInt(),
    );

    return Row(
      children: [
        // fahrplaner.de fork patch (07.10.2026, siehe FAHRPLANER_PATCHES
        // .md): "fällt aus" ist dringlicher als "hat Verspätung" und
        // verdrängt daher den Verspätungs-Badge, statt daneben zu stehen -
        // beide gleichzeitig anzuzeigen wäre verwirrend (eine ausgefallene
        // Fahrt hat ohnehin meist keine sinnvolle Verspätungsangabe mehr).
        if (itinerary.hasCanceledLeg) ...[
          _CancellationBadge(theme: theme, l10n: l10n),
          const SizedBox(width: 8),
        ] else if (itinerary.overallArrivalDelay != null) ...[
          RealtimeChip.fromDelay(itinerary.overallArrivalDelay),
          const SizedBox(width: 8),
        ],
        // Distance
        _InfoChip(
          icon: Icons.straighten_rounded,
          label: _formatDistance(itinerary.distance, l10n),
          theme: theme,
        ),
        const SizedBox(width: 8),
        // Walking distance
        if (totalWalkingMeters > 0) ...[
          _InfoChip(
            icon: Icons.directions_walk_rounded,
            label: _formatDistance(totalWalkingMeters, l10n),
            theme: theme,
          ),
          const SizedBox(width: 8),
        ],
        const Spacer(),
        // Details button
        if (onDetailsTap != null)
          TextButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              onDetailsTap!();
            },
            icon: const Icon(Icons.info_outline_rounded, size: 18),
            label: Text(l10n.buttonDetails),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    );
  }

  String _formatDuration(Duration duration, HomeScreenLocalizations l10n) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return l10n.durationHoursMinutes(hours, minutes);
    }
    return l10n.durationMinutes(minutes);
  }

  String _formatDistance(int meters, HomeScreenLocalizations l10n) {
    if (meters < 1000) {
      return l10n.distanceMeters(meters);
    }
    final km = (meters / 1000).toStringAsFixed(1);
    return l10n.distanceKilometers(km);
  }
}

/// Chip showing transport leg information
class _LegChip extends StatelessWidget {
  final routing.Leg leg;

  /// Distinct routes the itinerary's group offers for this slot; when it
  /// carries more than one, the chip paints one segment per option, all
  /// in their route colors; the ridden one shows at full strength.
  final List<routing.Route>? slotRoutes;

  const _LegChip({required this.leg, this.slotRoutes});

  @override
  Widget build(BuildContext context) {
    final isWalk = leg.transportMode == routing.TransportMode.walk;
    final isBike = leg.transportMode == routing.TransportMode.bicycle;

    if (isWalk || isBike) {
      // Redesign Oktober 2026 (docs/design/HANDOFF.md Abschnitt 3.2):
      // `width: double.infinity`/`height: 28` + eigener Hintergrund, damit
      // dieses Chip als EIN Segment im proportionalen Balken (siehe
      // ItineraryCard._buildSegmentBar) die ihm per `Expanded`/`flex`
      // zugewiesene Breite ausfuellt, statt wie bisher nur intrinsisch
      // (fuer die alte, horizontal scrollbare Chip-Reihe) breit zu sein.
      // Nur das Icon, keine Minutenzahl mehr (02.10.2026-Stil-Fix nach
      // echtem Test-Fund): dieses Segment bekommt jetzt eine FESTE,
      // kleine Breite (28px, siehe ItineraryCard._buildSegmentBar) statt
      // proportional zur Dauer - fuer Icon+Text war das zu wenig Platz.
      return Container(
        width: double.infinity,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          isWalk
              ? Icons.directions_walk_rounded
              : Icons.directions_bike_rounded,
          size: 16,
          color: Colors.grey[600],
        ),
      );
    }

    // Transit leg. With interchangeable routes in the slot (#737), every
    // option paints its own segment, meeting on a slanted "/" seam, each
    // keeping its route color; the ridden one shows at full strength.
    final options = (slotRoutes != null && slotRoutes!.length > 1)
        ? slotRoutes!
        : null;

    if (options != null) {
      // Slanted "/" seams (Sam 2026-08-12: "la separación con /, no algo
      // vertical") — one shared chip, one segment per option in its own
      // color. Same widget the detail's switcher uses.
      // Same reading as the detail's switcher: every option keeps its
      // color and only the CHOSEN one rides it at full strength (Sam
      // 2026-08-13: no border) — the leg belongs to the itinerary the
      // card wears, so its name marks the choice.
      return SizedBox(
        width: double.infinity,
        height: 28,
        child: SegmentedRouteChip(
          dimBackdrop: Color.alphaBlend(
            Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            Theme.of(context).colorScheme.surface,
          ),
          segments: [
            for (final (i, route) in options.indexed)
              RouteSegmentSpec(
                label: route.shortName ?? '',
                color: _routeOwnColor(route, leg.transportMode),
                icon: i == 0 ? _getModeIcon(leg.transportMode) : null,
                dimmed: (route.shortName ?? '') != leg.displayName,
                // Unnamed feeds can't tell the ridden option apart ('' ==
                // '' matches EVERY slot): no name, no selected
                // announcement.
                selected:
                    (route.shortName ?? '').isNotEmpty &&
                    route.shortName == leg.displayName,
              ),
          ],
        ),
      );
    }

    final color = _getRouteColor(leg);
    final textColor = SegmentedRouteChip.bestContrastOn(color);
    final routeName = leg.shortName ?? leg.route?.shortName ?? '';
    final realtime = context.watch<RealtimeVehiclesProvider?>();
    // Form nach Verkehrsmittel (Redesign Oktober 2026, docs/design/
    // HANDOFF.md Abschnitt 3.2, ".ln.rail"/".ln.tram" in Verbindungen.dc
    // .html) - dieselbe grobe Zuordnung wie `lineBadgeShapeFor()` im
    // Hauptprojekt (app/lib/design/fahrplaner_theme.dart), hier als
    // eigene, kleine Kopie statt eines Imports (siehe Patch 23).
    final borderRadius = switch (leg.transportMode) {
      routing.TransportMode.rail ||
      routing.TransportMode.subway => BorderRadius.circular(999),
      routing.TransportMode.tram => BorderRadius.circular(3),
      _ => BorderRadius.circular(8),
    };

    return Container(
      width: double.infinity,
      height: 28,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: borderRadius),
      // FittedBox: eine Verbindung mit vielen kurzen Transit-Beinen (z. B.
      // mehrere Umstiege) kann einem Segment proportional zur Dauer nur
      // wenig Breite zuteilen - Inhalt schrumpft dann, statt zu
      // ueberlaufen (02.10.2026-Stil-Fix nach echtem Test-Fund).
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_getModeIcon(leg.transportMode), size: 16, color: textColor),
            if (routeName.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                routeName,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
            if (realtime != null) ...[
              const SizedBox(width: 6),
              LiveBusBadge.whenLive(
                provider: realtime,
                leg: leg,
                color: textColor,
                size: 10,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _routeOwnColor(routing.Route route, routing.TransportMode mode) {
    final colorStr = route.color ?? '';
    // Empty guard: 'FF' alone parses to a transparent blue and would make
    // the mode-color fallback unreachable.
    final parsed = colorStr.isNotEmpty
        ? int.tryParse('FF$colorStr', radix: 16)
        : null;
    if (parsed != null) return Color(parsed);
    return _getModeColor(mode);
  }

  Color _getRouteColor(routing.Leg leg) {
    final colorStr = leg.routeColor;
    final parsed = int.tryParse('FF$colorStr', radix: 16);
    if (parsed != null) return Color(parsed);
    return _getModeColor(leg.transportMode);
  }

  Color _getModeColor(routing.TransportMode mode) {
    switch (mode) {
      case routing.TransportMode.bus:
        return const Color(0xFF1976D2);
      case routing.TransportMode.rail:
      case routing.TransportMode.subway:
        return const Color(0xFFE65100);
      case routing.TransportMode.tram:
        return const Color(0xFFC62828);
      case routing.TransportMode.ferry:
        return const Color(0xFF00838F);
      default:
        return Colors.grey;
    }
  }

  IconData _getModeIcon(routing.TransportMode mode) {
    switch (mode) {
      case routing.TransportMode.bus:
        return Icons.directions_bus_rounded;
      case routing.TransportMode.rail:
        return Icons.train_rounded;
      case routing.TransportMode.subway:
        return Icons.subway_rounded;
      case routing.TransportMode.tram:
        return Icons.tram_rounded;
      case routing.TransportMode.ferry:
        return Icons.directions_boat_rounded;
      case routing.TransportMode.walk:
        return Icons.directions_walk_rounded;
      case routing.TransportMode.bicycle:
        return Icons.directions_bike_rounded;
      default:
        return Icons.directions_rounded;
    }
  }
}

/// Real-time cancellation indicator (fahrplaner.de fork patch, 07.10.2026,
/// siehe FAHRPLANER_PATCHES.md). Bewusst ein eigenes Icon/Farbe statt nur
/// eine Textvariante von [_DelayBadge] - "fällt aus" ist kategorisch
/// anders als "hat Verspätung", nicht nur eine extremere Verspätung.
class _CancellationBadge extends StatelessWidget {
  final ThemeData theme;
  final HomeScreenLocalizations l10n;

  const _CancellationBadge({required this.theme, required this.l10n});

  @override
  Widget build(BuildContext context) {
    const color = Color(
      0xFFC62828,
    ); // red - dasselbe Rot wie die starke Delay-Stufe
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cancel_rounded, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          l10n.tripCanceled,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Small info chip for footer
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final ThemeData theme;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
