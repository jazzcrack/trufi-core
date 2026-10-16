import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:trufi_core_interfaces/trufi_core_interfaces.dart'
    hide ITrufiMapEngine;
import 'package:trufi_core_routing/trufi_core_routing.dart' as routing;
import 'package:trufi_core_search_locations/trufi_core_search_locations.dart'
    show isStreetLocationType, streetLengthFromLocationType;
import 'package:trufi_core_utils/trufi_core_utils.dart';

import '../cubit/route_planner_cubit.dart';
import '../models/route_planner_state.dart';
import '../../l10n/home_screen_localizations.dart';
import 'itinerary_card.dart';
import 'itinerary_detail_screen.dart';

/// "Weniger Umstiege"-Chip (Redesign Oktober 2026, docs/design/HANDOFF.md
/// Abschnitt 3.2): sortiert nach Umstiegszahl, dann Dauer, dann
/// Abfahrtszeit - dieselbe Kaskade wie `rankAlternatives()` im
/// Hauptprojekt-Repo (`alternative_routes.dart`), hier als eigene, kleine
/// Kopie statt eines Imports (der Fork kann das Hauptprojekt nicht
/// importieren, siehe Patch 23). Rein eine Anzeige-Umsortierung der
/// bereits geladenen Antwort, kein erneuter Server-Aufruf.
List<routing.Itinerary>? _rankedByFewerTransfers(
  List<routing.Itinerary>? itineraries,
) {
  if (itineraries == null) return null;
  final ranked = List<routing.Itinerary>.of(itineraries);
  ranked.sort((a, b) {
    final transfers = a.numberOfTransfers.compareTo(b.numberOfTransfers);
    if (transfers != 0) return transfers;
    final duration = a.duration.compareTo(b.duration);
    if (duration != 0) return duration;
    return a.startTime.compareTo(b.startTime);
  });
  return ranked;
}

/// Gleiche Kaskade wie [_rankedByFewerTransfers], angewendet auf die
/// REPRAESENTATIVEN Itineraries der Gruppen (#737) statt auf einzelne
/// Itineraries - die Gruppen selbst (ihre `alternatives`) bleiben
/// unangetastet, nur ihre Reihenfolge in der Liste aendert sich.
List<routing.ItineraryGroup>? _groupsRankedByFewerTransfers(
  List<routing.ItineraryGroup>? groups,
) {
  if (groups == null) return null;
  final ranked = List<routing.ItineraryGroup>.of(groups);
  ranked.sort((a, b) {
    final transfers = a.representative.numberOfTransfers.compareTo(
      b.representative.numberOfTransfers,
    );
    if (transfers != 0) return transfers;
    final duration = a.representative.duration.compareTo(
      b.representative.duration,
    );
    if (duration != 0) return duration;
    return a.representative.startTime.compareTo(b.representative.startTime);
  });
  return ranked;
}

/// Index des Beins, in dem [now] faellt - fahrplaner.de fork patch (siehe
/// FAHRPLANER_PATCHES.md, Nutzer-Fund "Ganze Fahrt zeigt Fahrplan statt
/// Live"). Kleine Eigenkopie von itinerary_live_refresh.dart's
/// currentLegIndexAt() im Hauptprojekt-Repo (der Fork kann das
/// Hauptprojekt nicht importieren, siehe Patch 23) - haelt dieselbe
/// Zeitfenster-Logik: waehrend einer Umstiegs-Luecke zeigt es bereits das
/// NAECHSTE Bein als "aktuell", `null` vor dem ersten bzw. nach dem
/// letzten Bein oder bei leerer Liste.
int? _currentLegIndexAt(List<routing.Leg> legs, DateTime now) {
  if (legs.isEmpty) return null;
  if (now.isBefore(legs.first.startTime)) return null;
  if (!now.isBefore(legs.last.endTime)) return null;
  for (var i = 0; i < legs.length; i++) {
    if (now.isBefore(legs[i].endTime)) return i;
  }
  return null;
}

/// List of itinerary options with inline detail view.
/// When an itinerary is tapped, shows details inline replacing the list.
class ItineraryList extends StatefulWidget {
  final void Function(routing.Itinerary itinerary)? onItineraryDetails;
  // fahrplaner.de fork patch (see FAHRPLANER_PATCHES.md, Patch 27):
  // `wakeAtDestination` added as an optional named param (additive -
  // every existing caller keeps working unchanged) so the detail
  // screen's "Vor dem Aussteigen wecken" switch can reach the host app's
  // navigation start.
  final void Function(
    BuildContext context,
    routing.Itinerary itinerary,
    LocationService locationService, {
    bool wakeAtDestination,
  })?
  onStartNavigation;
  final LocationService? locationService;

  /// Callback when a transit route badge is tapped.
  /// Provides the route code to allow navigation to route details.
  final void Function(String routeCode)? onRouteTap;

  /// When true, the list will shrink to fit content and disable its own scrolling.
  /// Use this when the list is inside a parent scrollable (e.g., bottom sheet).
  /// When false (default), the list will scroll independently.
  final bool shrinkWrap;

  /// When true, automatically shows details for the selected itinerary on first load.
  /// Used when opening from a deep link URL with a specific route.
  final bool showDetailOnLoad;

  /// Callback when detail view state changes (shown/hidden).
  final void Function(bool isShowingDetail)? onDetailStateChanged;

  /// fahrplaner.de fork patch (see FAHRPLANER_PATCHES.md): called when the
  /// rider taps "share" on an itinerary's OWN detail view - unlike a
  /// list-wide share button, this is unambiguous about which itinerary is
  /// being shared. Pass null to not show a share action at all.
  final void Function(routing.Itinerary itinerary)? onShare;

  /// fahrplaner.de fork patch (05.10.2026, siehe FAHRPLANER_PATCHES.md):
  /// "Fahrt merken" auf der Detailansicht einer Itinerary - gleiches
  /// unambiguous-welche-Itinerary-Muster wie [onShare], muss aber die
  /// App selbst erreichen (Speichern ist App-spezifisch).
  final void Function(routing.Itinerary itinerary)? onSaveTrip;

  /// fahrplaner.de fork patch 62: Hinweis "Start/Ziel ist die
  /// Strassenmitte" ueber den Verbindungen mit "+ Hausnummer ergaenzen".
  /// null = kein Hinweis.
  final void Function({required bool isOrigin})? onAddHouseNumber;

  const ItineraryList({
    super.key,
    this.onItineraryDetails,
    this.onStartNavigation,
    this.locationService,
    this.onRouteTap,
    this.shrinkWrap = false,
    this.showDetailOnLoad = false,
    this.onDetailStateChanged,
    this.onShare,
    this.onAddHouseNumber,
    this.onSaveTrip,
  });

  @override
  State<ItineraryList> createState() => _ItineraryListState();
}

class _ItineraryListState extends State<ItineraryList> {
  routing.Itinerary? _detailItinerary;

  /// Weggeklickter Strassenmitte-Hinweis - gilt nur fuer genau dieses
  /// Start/Ziel-Paar, bei einer neuen Suche erscheint er wieder.
  String? _dismissedStreetHintKey;
  bool _hasAutoShownDetail = false;

  /// fahrplaner.de fork patch (siehe FAHRPLANER_PATCHES.md, Nutzer-Fund
  /// "Ganze Fahrt zeigt Fahrplan statt Live"): pollt Verspaetungen fuer die
  /// gerade offene Detailansicht nach, solange sie sichtbar ist - siehe
  /// [_showDetails]/[_hideDetails]/[_refreshDetailItineraryDelays].
  Timer? _delayRefreshTimer;

  // "Fahrplan heißt..."-Hinweis (Redesign Oktober 2026, docs/design/
  // HANDOFF.md Abschnitt 3.2): einmalig erklären, danach dauerhaft
  // wegklickbar. `null` waehrend des (sehr kurzen) asynchronen Ladens
  // haelt den Hinweis zunaechst verborgen statt kurz einzublenden und
  // sofort wieder zu verschwinden, falls er schon dismissed war.
  static const _scheduleBannerStorageKey = 'fp_schedule_banner_dismissed';
  final StorageService _scheduleBannerStorage = SharedPreferencesStorage();
  bool? _scheduleBannerDismissed;

  @override
  void initState() {
    super.initState();
    _loadScheduleBannerDismissed();
  }

  Future<void> _loadScheduleBannerDismissed() async {
    await _scheduleBannerStorage.initialize();
    final dismissed =
        await _scheduleBannerStorage.readBool(_scheduleBannerStorageKey) ??
        false;
    if (mounted) setState(() => _scheduleBannerDismissed = dismissed);
  }

  void _dismissScheduleBanner() {
    setState(() => _scheduleBannerDismissed = true);
    _scheduleBannerStorage.writeBool(_scheduleBannerStorageKey, true);
  }

  void _showDetails(routing.Itinerary itinerary) {
    HapticFeedback.selectionClick();
    setState(() {
      _detailItinerary = itinerary;
    });
    widget.onDetailStateChanged?.call(true);
    _syncDelayRefreshTimer();
  }

  void _hideDetails() {
    HapticFeedback.lightImpact();
    setState(() {
      _detailItinerary = null;
    });
    widget.onDetailStateChanged?.call(false);
    _syncDelayRefreshTimer();
  }

  /// Startet/stoppt den Verspaetungs-Refresh je danach, ob gerade eine
  /// Detailansicht offen ist - derselbe An/Aus-Mechanismus wie
  /// navigation_map.dart._syncDelayRefreshTimer() im Hauptprojekt-Repo.
  void _syncDelayRefreshTimer() {
    if (_detailItinerary == null) {
      _delayRefreshTimer?.cancel();
      _delayRefreshTimer = null;
      return;
    }
    if (_delayRefreshTimer != null) return;
    // fahrplaner.de fork patch (siehe FAHRPLANER_PATCHES.md, echter
    // Nutzer-Fund 12.10.2026): `Timer.periodic` feuert NIE sofort, erst
    // nach den vollen 45s - ein kurzer Blick auf die Detailansicht sah
    // deshalb nie eine Live-Verspaetung, nur den Schnappschuss vom Oeffnen.
    _refreshDetailItineraryDelays();
    _delayRefreshTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => _refreshDetailItineraryDelays(),
    );
  }

  /// Fragt IRoutingProvider.fetchLiveStopDelays() fuer jede eindeutige
  /// Einstiegshaltestelle der Transit-Beine der offenen Detailansicht ab
  /// und schreibt neue Verspaetungen zurueck. Fehlt eine Trip-ID in einer
  /// Antwort (kein GTFS-RT-Update fuer diesen Takt), bleibt der zuletzt
  /// bekannte Wert bewusst unveraendert statt faelschlich zurueckgesetzt
  /// zu werden.
  Future<void> _refreshDetailItineraryDelays() async {
    final current = _detailItinerary;
    if (current == null) return;

    final stopIds = <String>{
      for (final leg in current.transitLegs)
        if (leg.fromPlace?.stopId != null) leg.fromPlace!.stopId!,
    };
    if (stopIds.isEmpty) return;

    // fahrplaner.de fork patch (FAHRPLANER_PATCHES.md, Patch 47): die
    // sofortige erste Abfrage in _showDetails() (statt erst nach dem
    // ersten 45s-Takt) deckte auf, dass dieser Pfad bisher davon ausging,
    // dass ein RoutingEngineManager IMMER im Kontext vorhanden ist - eine
    // optionale Anreicherung sollte das nie erzwingen (gleiches Prinzip
    // wie der try/catch je Haltestelle unten).
    routing.IRoutingProvider routingProvider;
    try {
      routingProvider = context
          .read<routing.RoutingEngineManager>()
          .currentEngine;
    } catch (_) {
      return;
    }
    final delaysByStop = <String, Map<String, Duration>>{};
    for (final stopId in stopIds) {
      try {
        final delays = await routingProvider.fetchLiveStopDelays(stopId);
        if (delays != null) delaysByStop[stopId] = delays;
      } catch (_) {
        // Einzelner Halt fehlgeschlagen - andere Halte trotzdem abfragen,
        // zuletzt bekannte Werte fuer diesen Halt bleiben erhalten.
      }
    }
    if (delaysByStop.isEmpty || !mounted) return;

    final updatedLegs = current.legs.map((leg) {
      final stopId = leg.fromPlace?.stopId;
      final tripId = leg.tripId;
      if (stopId == null || tripId == null) return leg;
      // Echter Nutzer-Fund (14.10.2026): fetchLiveStopDelays() liefert laut
      // eigenem Doku-Kommentar feed-praefix-gestrippte Trip-IDs zurueck
      // (z. B. "449964075"), waehrend leg.tripId aus der Planungsantwort
      // feed-qualifiziert bleibt (z. B. "1:449964075") - ohne Stripping
      // fand dieser Lookup NIE eine Uebereinstimmung, selbst nachdem die
      // Stop-ID-Normalisierung (Patch 51) die eigentliche Abfrage schon
      // repariert hatte.
      final newDelay = delaysByStop[stopId]?[stripGtfsFeedPrefix(tripId)];
      if (newDelay == null) return leg;
      return leg.copyWith(arrivalDelay: newDelay);
    }).toList();

    // Nur neu rendern, wenn die Detailansicht fuer GENAU diese Itinerary
    // noch offen ist - zwischen Start der Abfrage und ihrer Antwort kann
    // der Rider bereits eine andere Itinerary geoeffnet oder die
    // Detailansicht wieder verlassen haben.
    if (_detailItinerary != current) return;
    setState(() {
      _detailItinerary = current.copyWith(legs: updatedLegs);
    });
  }

  @override
  void dispose() {
    _delayRefreshTimer?.cancel();
    super.dispose();
  }

  /// Erste Listenzeile: Strassenmitte-Hinweis (Patch 62) + bisheriger
  /// "Fahrplan heisst..."-Hinweis.
  Widget _topBanners(RoutePlannerState state, HomeScreenLocalizations l10n) {
    final from = state.fromPlace;
    final to = state.toPlace;
    final key =
        '${from?.description}|${from?.type}>${to?.description}|${to?.type}';
    final showStreetHint =
        widget.onAddHouseNumber != null &&
        _dismissedStreetHintKey != key &&
        (isStreetLocationType(from?.type) || isStreetLocationType(to?.type));
    if (!showStreetHint) return _EstimatedTimesBanner(l10n: l10n);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StreetPrecisionBanner(
          from: from,
          to: to,
          onAddHouseNumber: widget.onAddHouseNumber!,
          onDismiss: () => setState(() => _dismissedStreetHintKey = key),
        ),
        _EstimatedTimesBanner(l10n: l10n),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RoutePlannerCubit, RoutePlannerState>(
      listener: (context, state) {
        // Clear stale local state when a new search starts or plan changes
        if (state.isLoading || state.plan == null) {
          if (_detailItinerary != null) {
            setState(() {
              _detailItinerary = null;
            });
            widget.onDetailStateChanged?.call(false);
          }
        }
      },
      builder: (context, state) {
        final l10n = HomeScreenLocalizations.of(context);
        final cubit = context.read<RoutePlannerCubit>();
        final theme = Theme.of(context);

        if (state.isLoading) {
          return _buildShimmerLoading(theme);
        }

        if (state.hasError) {
          return _buildErrorState(context, state, l10n, theme);
        }

        final itineraries = state.preferFewerTransfers
            ? _rankedByFewerTransfers(state.plan?.itineraries)
            : state.plan?.itineraries;
        if (itineraries == null || itineraries.isEmpty) {
          if (!state.isPlacesDefined) {
            return _buildEmptyState(
              context,
              icon: Icons.route_rounded,
              message: l10n.selectLocations,
              theme: theme,
            );
          }
          return _buildEmptyState(
            context,
            icon: Icons.search_off_rounded,
            message: l10n.noRoutesFound,
            theme: theme,
          );
        }

        // Auto-show detail on first load if requested (e.g., from URL)
        if (widget.showDetailOnLoad &&
            !_hasAutoShownDetail &&
            state.selectedItinerary != null) {
          _hasAutoShownDetail = true;
          // Use post-frame callback to avoid setState during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _detailItinerary = state.selectedItinerary;
              });
              widget.onDetailStateChanged?.call(true);
            }
          });
        }

        // Show detail view only if the itinerary is still in the current plan
        if (_detailItinerary != null) {
          if (itineraries.contains(_detailItinerary)) {
            return _buildDetailView(context, _detailItinerary!);
          }
          // Stale detail from a previous search — clear it
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _detailItinerary != null) {
              setState(() {
                _detailItinerary = null;
              });
              widget.onDetailStateChanged?.call(false);
            }
          });
        }

        // Use grouped itineraries if available, otherwise fall back to regular list
        final groupedItineraries = state.preferFewerTransfers
            ? _groupsRankedByFewerTransfers(state.plan?.groupedItineraries)
            : state.plan?.groupedItineraries;
        if (groupedItineraries != null && groupedItineraries.isNotEmpty) {
          return _withScheduleBanner(
            _buildGroupedListView(context, groupedItineraries, state, cubit),
          );
        }

        // Fallback to non-grouped list view
        return _withScheduleBanner(
          _buildListView(context, itineraries, state, cubit),
        );
      },
    );
  }

  /// "Fahrplan heißt..."-Hinweis oberhalb der Liste, solange noch nicht
  /// dismissed (Abschnitt 3.2). `null` (noch am Laden) oder `true`
  /// (bereits dismissed) zeigen nichts zusaetzlich - [list] bleibt
  /// unveraendert. `Expanded` nur, wenn [list] selbst nicht `shrinkWrap`
  /// ist (sonst steckt dieser Baum oft schon in einer aeusseren
  /// Scrollansicht mit unbegrenzter Hoehe - `Expanded` wuerde dort einen
  /// RenderFlex-Fehler werfen).
  Widget _withScheduleBanner(Widget list) {
    if (_scheduleBannerDismissed != false) return list;
    final banner = _ScheduleExplainerBanner(onDismiss: _dismissScheduleBanner);
    return Column(
      mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: widget.shrinkWrap
          ? [banner, list]
          : [banner, Expanded(child: list)],
    );
  }

  Widget _buildDetailView(BuildContext context, routing.Itinerary itinerary) {
    final cubit = context.read<RoutePlannerCubit>();
    // The itinerary's group (#737): its members feed the detail's option
    // switcher so the rider can flip between interchangeable connections.
    final group = cubit.state.plan?.groupedItineraries
        ?.where((g) => g.alternatives.contains(itinerary))
        .firstOrNull;

    return ItineraryDetailContent(
      itinerary: itinerary,
      shrinkWrap: widget.shrinkWrap,
      onBack: _hideDetails,
      onRouteTap: widget.onRouteTap,
      alternatives: group?.alternatives,
      onSelectAlternative: (alternative) {
        cubit.selectItinerary(alternative);
        _showDetails(alternative);
      },
      // Patch 27: der Wert kommt jetzt aus dem Aufruf selbst (die
      // Detailansicht uebergibt ihren eigenen Wecken-Schalter-Zustand),
      // nicht aus einem hier gehaltenen Feld.
      onStartNavigation:
          widget.onStartNavigation != null && widget.locationService != null
          ? (wakeAtDestination) => widget.onStartNavigation!(
              context,
              itinerary,
              widget.locationService!,
              wakeAtDestination: wakeAtDestination,
            )
          : null,
      onShare: widget.onShare != null ? () => widget.onShare!(itinerary) : null,
      onSaveTrip: widget.onSaveTrip != null
          ? () => widget.onSaveTrip!(itinerary)
          : null,
      // fahrplaner.de fork patch (siehe FAHRPLANER_PATCHES.md, Nutzer-Fund
      // "Ganze Fahrt zeigt Fahrplan statt Live"): markiert bereits in
      // dieser Vor-Fahrt-Vorschau, auf welchem Bein man laut Fahrplan
      // "jetzt" waere - reine Fahrplanzeit-Interpolation, kein GPS (siehe
      // _currentLegIndexAt oben).
      currentLegIndex: _currentLegIndexAt(itinerary.legs, DateTime.now()),
    );
  }

  Widget _buildGroupedListView(
    BuildContext context,
    List<routing.ItineraryGroup> groups,
    RoutePlannerState state,
    RoutePlannerCubit cubit,
  ) {
    final l10n = HomeScreenLocalizations.of(context);

    // fahrplaner.de fork patch (see FAHRPLANER_PATCHES.md): fixed slots for
    // "load earlier"/"load later connections" right after the banner and
    // after the last group - rendered as SizedBox.shrink() when the
    // corresponding cursor isn't available, so the index math stays simple
    // regardless of whether either button is actually visible.
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      itemCount: groups.length + 3,
      itemBuilder: (context, index) {
        if (index == 0) return _topBanners(state, l10n);
        if (index == 1) {
          return _LoadMoreButton(
            cursor: state.plan?.previousPageCursor,
            earlier: true,
            isLoading: state.isLoadingEarlier,
            isBusy: state.isLoadingMore,
            foundNothing: state.earlierFoundNothing,
            onTap: () => cubit.loadMoreItineraries(earlier: true),
          );
        }
        if (index == groups.length + 2) {
          return _LoadMoreButton(
            cursor: state.plan?.nextPageCursor,
            earlier: false,
            isLoading: state.isLoadingLater,
            isBusy: state.isLoadingMore,
            foundNothing: state.laterFoundNothing,
            onTap: () => cubit.loadMoreItineraries(earlier: false),
          );
        }
        final groupIndex = index - 2;
        final group = groups[groupIndex];
        final containsSelection = group.alternatives.contains(
          state.selectedItinerary,
        );
        // The card wears the group's currently chosen option (#737): after
        // picking an alternative in the detail switcher, its times/legs are
        // what the row shows — and what Go navigates.
        final face = containsSelection
            ? state.selectedItinerary!
            : group.representative;

        return TweenAnimationBuilder<double>(
          // Schluessel nach Verbindung statt Position (Patch 59, T043):
          // sonst blendeten nach dem Voranstellen frueherer Verbindungen
          // alle Karten neu ein.
          key: ValueKey('group-${itineraryIdentityKey(group.representative)}'),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 200 + (groupIndex.clamp(0, 6) * 50)),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 20 * (1 - value)),
              child: Opacity(opacity: value, child: child),
            );
          },
          child: Column(
            children: [
              ItineraryCard(
                itinerary: face,
                isSelected: containsSelection,
                slotRoutes: group.slotRoutes,
                // fahrplaner.de fork patch (see FAHRPLANER_PATCHES.md):
                // viewing details no longer also mutates/persists the
                // selection - tapping a card to preview it should not
                // silently change which itinerary stays highlighted/shared
                // once the rider goes back to the list. Choosing an
                // itinerary to act on (start navigation, pick an
                // alternative) remains an explicit action elsewhere.
                onTap: () {
                  if (widget.onItineraryDetails != null) {
                    widget.onItineraryDetails!(face);
                  } else {
                    _showDetails(face);
                  }
                },
                onDetailsTap: null,
                onStartNavigation:
                    widget.onStartNavigation != null &&
                        widget.locationService != null
                    ? () => widget.onStartNavigation!(
                        context,
                        face,
                        widget.locationService!,
                      )
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildListView(
    BuildContext context,
    List<routing.Itinerary> itineraries,
    RoutePlannerState state,
    RoutePlannerCubit cubit,
  ) {
    final l10n = HomeScreenLocalizations.of(context);
    // fahrplaner.de fork patch (see FAHRPLANER_PATCHES.md): same fixed
    // earlier/later slots as _buildGroupedListView above.
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      itemCount: itineraries.length + 3,
      itemBuilder: (context, index) {
        if (index == 0) return _topBanners(state, l10n);
        if (index == 1) {
          return _LoadMoreButton(
            cursor: state.plan?.previousPageCursor,
            earlier: true,
            isLoading: state.isLoadingEarlier,
            isBusy: state.isLoadingMore,
            foundNothing: state.earlierFoundNothing,
            onTap: () => cubit.loadMoreItineraries(earlier: true),
          );
        }
        if (index == itineraries.length + 2) {
          return _LoadMoreButton(
            cursor: state.plan?.nextPageCursor,
            earlier: false,
            isLoading: state.isLoadingLater,
            isBusy: state.isLoadingMore,
            foundNothing: state.laterFoundNothing,
            onTap: () => cubit.loadMoreItineraries(earlier: false),
          );
        }
        final itemIndex = index - 2;
        final itinerary = itineraries[itemIndex];
        final isSelected = itinerary == state.selectedItinerary;

        return TweenAnimationBuilder<double>(
          key: ValueKey('itinerary-${itineraryIdentityKey(itinerary)}'),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 200 + (itemIndex.clamp(0, 6) * 50)),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 20 * (1 - value)),
              child: Opacity(opacity: value, child: child),
            );
          },
          child: ItineraryCard(
            itinerary: itinerary,
            isSelected: isSelected,
            // fahrplaner.de fork patch - see the grouped list's onTap above
            // for the rationale (viewing details must not silently change
            // the persisted selection).
            onTap: () {
              // Show details inline or use custom callback
              if (widget.onItineraryDetails != null) {
                widget.onItineraryDetails!(itinerary);
              } else {
                _showDetails(itinerary);
              }
            },
            onDetailsTap: null,
            onStartNavigation:
                widget.onStartNavigation != null &&
                    widget.locationService != null
                ? () => widget.onStartNavigation!(
                    context,
                    itinerary,
                    widget.locationService!,
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildShimmerLoading(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      itemCount: 3,
      itemBuilder: (context, index) {
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 300 + (index * 100)),
          curve: Curves.easeOut,
          builder: (context, value, child) {
            return Opacity(opacity: value * 0.7, child: child);
          },
          child: _ShimmerCard(theme: theme, delay: index * 200),
        );
      },
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    RoutePlannerState state,
    HomeScreenLocalizations l10n,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.error_outline_rounded,
              size: 32,
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            state.error == noRoutesErrorKey
                ? l10n.noRoutesFound
                : state.error == networkErrorKey
                ? l10n.networkErrorMessage
                : (state.error ?? l10n.errorNoRoutes),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () {
              context.read<RoutePlannerCubit>().fetchPlan();
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.refresh_rounded, size: 18),
                const SizedBox(width: 8),
                Text(l10n.buttonTryAgain),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String message,
    required ThemeData theme,
  }) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 32,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shimmer loading card placeholder
class _ShimmerCard extends StatefulWidget {
  final ThemeData theme;
  final int delay;

  const _ShimmerCard({required this.theme, this.delay = 0});

  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) {
        _controller.repeat();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.theme.colorScheme.surfaceContainerHighest;
    final highlightColor = widget.theme.colorScheme.surface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.theme.dividerColor.withValues(alpha: 0.3),
              ),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [baseColor, highlightColor, baseColor],
                stops: [
                  (_animation.value - 0.3).clamp(0.0, 1.0),
                  _animation.value.clamp(0.0, 1.0),
                  (_animation.value + 0.3).clamp(0.0, 1.0),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    _shimmerBox(width: 70, height: 28, radius: 20),
                    const SizedBox(width: 12),
                    _shimmerBox(width: 50, height: 20),
                    const SizedBox(width: 8),
                    _shimmerBox(width: 16, height: 16),
                    const SizedBox(width: 8),
                    _shimmerBox(width: 50, height: 20),
                  ],
                ),
                const SizedBox(height: 10),
                // Transport summary row
                _shimmerBox(width: double.infinity, height: 40, radius: 12),
                const SizedBox(height: 8),
                // Footer row
                Row(
                  children: [
                    _shimmerBox(width: 60, height: 16),
                    const SizedBox(width: 8),
                    _shimmerBox(width: 60, height: 16),
                    const Spacer(),
                    _shimmerBox(width: 70, height: 28, radius: 14),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _shimmerBox({
    required double height,
    double? width,
    double radius = 8,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: widget.theme.colorScheme.surfaceContainerHigh.withValues(
          alpha: 0.5,
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Banner shown above route results to indicate times are estimated.
/// "Fahrplan heißt..."-Hinweis (Redesign Oktober 2026, docs/design/
/// HANDOFF.md Abschnitt 3.2, Referenz `Verbindungen.dc.html`): einmalig
/// erklaert, was der "Fahrplan"-Status eines `RealtimeChip` bedeutet
/// (siehe FpStatusColors/RealtimeStatus.scheduleOnly im Hauptprojekt) -
/// bewusst deutscher Festtext ohne l10n-Anbindung, analog zu Patch 23/25.
class _ScheduleExplainerBanner extends StatelessWidget {
  final VoidCallback onDismiss;

  const _ScheduleExplainerBanner({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text.rich(
                TextSpan(
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  children: [
                    TextSpan(
                      text: 'Fahrplan',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const TextSpan(
                      text:
                          ' heißt: Für diesen Abschnitt gibt es keine '
                          'Live-Daten. Wir zeigen das offen, statt '
                          'Pünktlichkeit vorzutäuschen.',
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: onDismiss,
            tooltip: 'Verstanden',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _EstimatedTimesBanner extends StatelessWidget {
  final HomeScreenLocalizations l10n;

  const _EstimatedTimesBanner({required this.l10n});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.estimatedTimesDisclaimer,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Load earlier/later connections" button (fahrplaner.de fork patch, see
/// FAHRPLANER_PATCHES.md). Collapses to nothing when [cursor] is null - no
/// cursor means either the current provider doesn't support paging (e.g.
/// the offline GTFS planner) or OTP's search window is already exhausted
/// in that direction, and there is no useful action to offer either way.
/// "Ziel ist die Strassenmitte"-Hinweis (fahrplaner.de fork patch 62,
/// App-Entwurf), fuer Start und/oder Ziel (Nutzerentscheidung).
class _StreetPrecisionBanner extends StatelessWidget {
  final TrufiLocation? from;
  final TrufiLocation? to;
  final void Function({required bool isOrigin}) onAddHouseNumber;
  final VoidCallback onDismiss;

  const _StreetPrecisionBanner({
    required this.from,
    required this.to,
    required this.onAddHouseNumber,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fromStreet = isStreetLocationType(from?.type);
    final toStreet = isStreetLocationType(to?.type);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    final strong = muted?.copyWith(
      color: colorScheme.onSurface,
      fontWeight: FontWeight.w800,
    );

    String length(TrufiLocation? place) {
      final meters = streetLengthFromLocationType(place?.type);
      return meters == null || meters < 50
          ? ''
          : ' (Straße ca. $meters m lang)';
    }

    final TextSpan text;
    if (fromStreet && toStreet) {
      text = TextSpan(
        style: muted,
        children: [
          const TextSpan(text: 'Start und Ziel sind die '),
          TextSpan(text: 'Straßenmitte', style: strong),
          const TextSpan(text: '. Mit Hausnummern werden die Fußwege genauer.'),
        ],
      );
    } else {
      final place = toStreet ? to : from;
      text = TextSpan(
        style: muted,
        children: [
          TextSpan(text: toStreet ? 'Ziel ist die ' : 'Start ist die '),
          TextSpan(text: 'Straßenmitte', style: strong),
          TextSpan(
            text:
                '${length(place)}. Mit Hausnummer wird der '
                '${toStreet ? 'letzte' : 'erste'} Fußweg genauer.',
          ),
        ],
      );
    }

    Widget addButton(String label, bool isOrigin) => Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.selectionClick();
          onAddHouseNumber(isOrigin: isOrigin);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 20, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outlineVariant, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.add_road_rounded, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(text),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (fromStreet && toStreet) ...[
                        addButton('Hausnummer Start', true),
                        addButton('Hausnummer Ziel', false),
                      ] else
                        addButton('Hausnummer ergänzen', fromStreet),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Hinweis ausblenden',
              icon: const Icon(Icons.close_rounded),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadMoreButton extends StatelessWidget {
  final String? cursor;
  final bool earlier;

  /// Laedt gerade DIESE Richtung (Ladekreis statt Pfeil, Patch 59).
  final bool isLoading;

  /// Irgendein Nachladen laeuft - beide Knoepfe gesperrt.
  final bool isBusy;

  /// Letztes Nachladen in dieser Richtung fand nichts (Patch 60, T059).
  final bool foundNothing;
  final VoidCallback onTap;

  const _LoadMoreButton({
    required this.cursor,
    required this.earlier,
    required this.isLoading,
    required this.isBusy,
    required this.onTap,
    this.foundNothing = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // fahrplaner.de fork patch 60 (T059): sichtbare Rueckmeldung, wenn auch
    // nach dem Ueberspringen leerer Zeitfenster nichts kam - vorher tat der
    // Knopf scheinbar nichts. Bewusst deutsche Festtexte (Patch-23-Muster).
    final hint = foundNothing
        ? Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              cursor == null
                  ? (earlier
                        ? 'Keine früheren Verbindungen gefunden.'
                        : 'Keine späteren Verbindungen gefunden.')
                  : (earlier
                        ? 'In diesem Zeitraum keine früheren Verbindungen - '
                              'erneut tippen sucht weiter zurück.'
                        : 'In diesem Zeitraum keine späteren Verbindungen - '
                              'erneut tippen sucht weiter.'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        : null;
    if (cursor == null) {
      return hint == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: hint,
            );
    }
    final l10n = HomeScreenLocalizations.of(context);
    final label = earlier
        ? l10n.loadEarlierConnections
        : l10n.loadLaterConnections;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: TextButton.icon(
              onPressed: isBusy ? null : onTap,
              icon: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      earlier
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                    ),
              label: Text(label),
            ),
          ),
          ?hint,
        ],
      ),
    );
  }
}
