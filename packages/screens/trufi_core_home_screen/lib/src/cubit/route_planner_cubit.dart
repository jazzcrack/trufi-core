import 'package:async/async.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:trufi_core_interfaces/trufi_core_interfaces.dart';
import 'package:trufi_core_routing/trufi_core_routing.dart' as routing;

import '../models/route_planner_state.dart';
import '../repository/home_screen_repository.dart';
import '../repository/home_screen_repository_impl.dart';
import '../services/request_plan_service.dart';

/// Error key emitted when no routes are found (UI resolves to localized string).
const String noRoutesErrorKey = 'no_routes_found';

/// Error key emitted when origin and destination are within
/// [minPlanningDistanceMeters] of each other.
const String tooCloseErrorKey = 'origin_destination_too_close';

/// Error key emitted when fetchPlan() fails for a network/connectivity
/// reason (no internet, DNS failure, server unreachable, timeout) rather
/// than a routing-logic reason. fahrplaner.de fork patch (see
/// FAHRPLANER_PATCHES.md) - before this, any such failure fell through to
/// the raw `e.toString()` (e.g. "Otp28Exception: Network error:
/// ClientException with SocketException: Connection failed (OS Error: No
/// route to host, errno = 65) ..."), shown verbatim to the user.
const String networkErrorKey = 'network_error';

/// fahrplaner.de fork patch 70: the routing server answered with an error or
/// not at all (5xx, refused, timeout) - unlike [networkErrorKey] (device
/// offline) the rider can do nothing but retry shortly.
const String serverErrorKey = 'server_error';

/// fahrplaner.de fork patch 70: Fehlerart für die Anzeige - [serverErrorKey],
/// [networkErrorKey] oder null (Rohtext anzeigen).
String? routingErrorKey(Object error) {
  if (_isServerError(error)) return serverErrorKey;
  if (_isNetworkError(error)) return networkErrorKey;
  return null;
}

bool _isServerError(Object error) {
  final text = error.toString().toLowerCase();
  return RegExp(r'http (5\d\d)|statuscode: 5\d\d|\b50[234]\b').hasMatch(text) ||
      text.contains('bad gateway') ||
      text.contains('service unavailable') ||
      text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('zeitüberschreitung') ||
      text.contains('timeoutexception');
}

/// Stabile Identitaet einer Verbindung ueber Seiten/Neuladen hinweg
/// (fahrplaner.de fork patch 59, T043): Abfahrtszeit + Linien/Trips je
/// Bein. Fuer das Entfernen von Dubletten beim Zusammenfuehren und als
/// Widget-Schluessel der Karten (vorher Listenposition - nach dem
/// Voranstellen frueherer Verbindungen blendeten dadurch ALLE Karten neu
/// ein).
String itineraryIdentityKey(routing.Itinerary itinerary) => [
  itinerary.startTime.millisecondsSinceEpoch,
  for (final leg in itinerary.legs)
    leg.tripId ?? '${leg.mode}:${leg.startTime.millisecondsSinceEpoch}',
].join('|');

/// Number of itineraries requested per [RoutePlannerCubit.loadMoreItineraries]
/// call. fahrplaner.de fork patch (04.10.2026, Kapitel 3.27, see
/// FAHRPLANER_PATCHES.md): fetchPlan() defaults to 5 itineraries (sized for
/// the initial "best option first" search); without overriding it here,
/// every "earlier/later connections" tap would silently add only 5 more,
/// which read as a hard cap. Deliberately larger than the initial-search
/// default, not applied to it.
const int loadMoreItinerariesPageSize = 10;

/// Wie viele aufeinanderfolgende OTP-Seiten ein einzelnes "Mehr laden"
/// hoechstens abruft, um leere Zeitfenster zu ueberspringen (Patch 60, T059).
const int loadMoreMaxEmptyPages = 4;

/// Best-effort classification of a routing-provider exception as a
/// network/connectivity failure vs. anything else (bad request, server-side
/// routing error, etc.), which keep surfacing as `e.toString()` - this is
/// deliberately a substring match across provider exception types (OTP
/// 1.5/2.4/2.8, the offline planner) rather than a shared exception
/// hierarchy, since none currently exists to catch more precisely.
bool _isNetworkError(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('socketexception') ||
      text.contains('network error') ||
      text.contains('connection failed') ||
      text.contains('connection refused') ||
      text.contains('no route to host') ||
      text.contains('failed host lookup') ||
      text.contains('timeoutexception') ||
      text.contains('httpexception');
}

/// Below this distance (meters), planning is short-circuited and the user is
/// shown a "too close" message instead of a degenerate routing-engine result.
const double minPlanningDistanceMeters = 100;

/// Cubit for managing route planning state.
///
/// If [repository] is not provided, uses [HomeScreenRepositoryImpl] by default.
class RoutePlannerCubit extends Cubit<RoutePlannerState> {
  final HomeScreenRepository _repository;
  final RequestPlanService _requestService;

  /// Optional fixed time-of-day used in place of `DateTime.now()` for
  /// routing requests. Threaded down from `AppConfiguration` (see
  /// `routingTimeOverride`). When non-null, every plan request is
  /// resolved against today at this time.
  final TimeOfDay? _routingTimeOverride;

  /// BCP-47 tag of the app's current language, forwarded to the routing
  /// provider so server-produced texts (alerts, street names in
  /// instructions) come back in the rider's language instead of the
  /// server's default (#945). Kept fresh by the home screen on every
  /// dependency change — a Cubit has no BuildContext of its own.
  String? _locale;

  /// Updates the language forwarded with every plan request.
  void updateLocale(String? languageTag) => _locale = languageTag;

  /// Optional GTFS-backed lookup used to enrich [routing.Leg.serviceHours]
  /// after the provider has parsed a plan. OTP REST/GraphQL doesn't
  /// expose calendar+frequencies in a directly usable shape, so this
  /// side-channel lets OTP-backed legs show the same operating-hours
  /// indicator as the local Trufi planner.
  final routing.ServiceHoursLookup? _serviceHoursLookup;

  CancelableOperation<routing.Plan>? _currentFetchOperation;

  RoutePlannerCubit({
    HomeScreenRepository? repository,
    required RequestPlanService requestService,
    TimeOfDay? routingTimeOverride,
    routing.ServiceHoursLookup? serviceHoursLookup,
  }) : _repository = repository ?? HomeScreenRepositoryImpl(),
       _requestService = requestService,
       _routingTimeOverride = routingTimeOverride,
       _serviceHoursLookup = serviceHoursLookup,
       super(const RoutePlannerState());

  /// Returns [plan] with each transit leg's `serviceHours` populated
  /// when the lookup has a record for the leg's route id. Legs that
  /// already have `serviceHours` (e.g. produced by the local Trufi
  /// planner) are left untouched.
  routing.Plan _enrichServiceHours(routing.Plan plan) {
    final lookup = _serviceHoursLookup;
    if (lookup == null) return plan;
    final itineraries = plan.itineraries;
    if (itineraries == null) return plan;
    return plan.copyWith(
      itineraries: itineraries.map((it) {
        final newLegs = it.legs.map((leg) {
          if (leg.serviceHours != null) return leg;
          final routeId = leg.route?.gtfsId;
          if (routeId == null || routeId.isEmpty) return leg;
          final sh = lookup.serviceHoursForRouteId(routeId);
          return sh != null ? leg.copyWith(serviceHours: sh) : leg;
        }).toList();
        return it.copyWith(legs: newLegs);
      }).toList(),
    );
  }

  /// Returns [plan] shaped for the itinerary list (#737). Rides with more
  /// than two vehicles are dropped ([routing.filterMaxTransitLegs],
  /// fail-open) — note that this rewrites `plan.itineraries`, and the
  /// FILTERED list is what gets persisted and what share/deep-link indices
  /// point at. The survivors are then grouped by main bus into
  /// [routing.Plan.groupedItineraries], which never re-ranks and is NOT
  /// serialized — which is why this must also run when restoring a saved
  /// plan.
  routing.Plan _groupPlanItineraries(routing.Plan plan) {
    final itineraries = plan.itineraries;
    if (itineraries == null || itineraries.isEmpty) return plan;
    final capped = routing.filterMaxTransitLegs(itineraries);
    return plan.copyWith(
      itineraries: capped,
      groupedItineraries: routing.groupItineraries(capped),
    );
  }

  /// Initialize and load saved state.
  Future<void> initialize() async {
    await _repository.initialize();

    final fromPlace = await _repository.getFromPlace();
    final toPlace = await _repository.getToPlace();
    final plan = await _repository.getPlan();
    var selectedItinerary = await _repository.getSelectedItinerary();

    final shapedPlan = plan != null ? _groupPlanItineraries(plan) : null;
    // A plan saved by an older version may carry a selection the vehicle
    // cap has since dropped — the map would draw a ride the list no
    // longer shows. Fall back to the best remaining row.
    final itineraries = shapedPlan?.itineraries;
    if (itineraries != null &&
        selectedItinerary != null &&
        !itineraries.contains(selectedItinerary)) {
      selectedItinerary = itineraries.isNotEmpty ? itineraries.first : null;
    }

    emit(
      state.copyWith(
        fromPlace: fromPlace,
        toPlace: toPlace,
        plan: shapedPlan,
        selectedItinerary: selectedItinerary,
      ),
    );
  }

  /// Set the origin location.
  Future<void> setFromPlace(TrufiLocation fromPlace) async {
    await _repository.saveFromPlace(fromPlace);
    emit(state.copyWith(fromPlace: fromPlace));
  }

  /// Set the destination location.
  Future<void> setToPlace(TrufiLocation toPlace) async {
    await _repository.saveToPlace(toPlace);
    emit(state.copyWith(toPlace: toPlace));
  }

  /// Reset the origin location.
  Future<void> resetFromPlace() async {
    await _repository.saveFromPlace(null);
    emit(state.copyWithNullable(fromPlace: const Optional(null)));
  }

  /// Reset the destination location.
  Future<void> resetToPlace() async {
    await _repository.saveToPlace(null);
    emit(state.copyWithNullable(toPlace: const Optional(null)));
  }

  /// Clear the current plan and selected itinerary.
  Future<void> clearPlan() async {
    await _cancelCurrentFetch();
    await _repository.savePlan(null);
    await _repository.saveSelectedItinerary(null);
    emit(
      state.copyWithNullable(
        plan: const Optional(null),
        selectedItinerary: const Optional(null),
        error: const Optional(null),
      ),
    );
  }

  /// Swap origin and destination.
  Future<void> swapLocations() async {
    final newFromPlace = state.toPlace;
    final newToPlace = state.fromPlace;

    await _repository.saveFromPlace(newFromPlace);
    await _repository.saveToPlace(newToPlace);

    emit(state.copyWith(fromPlace: newFromPlace, toPlace: newToPlace));
  }

  /// Reset all state.
  Future<void> reset() async {
    await _cancelCurrentFetch();
    await _repository.clear();
    emit(const RoutePlannerState());
  }

  /// Set the time mode (leave now, depart at, arrive by).
  void setTimeMode(TimeMode mode) {
    emit(state.copyWith(timeMode: mode));
  }

  /// Set the departure/arrival date and time.
  void setDateTime(DateTime? dateTime) {
    emit(state.copyWithNullable(dateTime: Optional(dateTime)));
  }

  /// "Weniger Umstiege"-Chip (Redesign Oktober 2026, docs/design/
  /// HANDOFF.md Abschnitt 3.2): reine Anzeige-Praeferenz, kein Replan -
  /// `ItineraryList` liest [RoutePlannerState.preferFewerTransfers] und
  /// sortiert die bereits geladenen Itineraries/Gruppen entsprechend um.
  void toggleSortPreference() {
    emit(state.copyWith(preferFewerTransfers: !state.preferFewerTransfers));
  }

  /// Fetch route plan.
  Future<void> fetchPlan({int? selectedItineraryIndex}) async {
    if (state.fromPlace == null || state.toPlace == null) return;

    if (state.fromPlace!.latLng.distanceTo(state.toPlace!.latLng) <
        minPlanningDistanceMeters) {
      await _cancelCurrentFetch();
      emit(
        state.copyWithNullable(
          isLoading: false,
          plan: const Optional(null),
          selectedItinerary: const Optional(null),
          error: Optional(tooCloseErrorKey),
        ),
      );
      return;
    }

    await _cancelCurrentFetch();

    emit(
      state.copyWithNullable(
        isLoading: true,
        plan: const Optional(null),
        selectedItinerary: const Optional(null),
        error: const Optional(null),
      ),
    );

    // Compute dateTime and arriveBy from time settings.
    //
    // Two modes:
    //
    // - `routingTimeOverride` set → resolve every request against
    //   today @ override-time, ignoring `state.timeMode/dateTime`.
    //   The picker UI is hidden in this mode, so the user can't
    //   even reach the other branch.
    //
    // - Override not set → honour the user's choice from the
    //   departure-time chip: `leaveNow` uses `DateTime.now()`,
    //   `departAt`/`arriveBy` use the time the user picked
    //   (`state.dateTime`), with `arriveBy` flipping the flag.
    final DateTime now = DateTime.now();
    final DateTime effectiveDateTime;
    final bool arriveBy;

    final override = _routingTimeOverride;
    if (override != null) {
      effectiveDateTime = DateTime(
        now.year,
        now.month,
        now.day,
        override.hour,
        override.minute,
      );
      arriveBy = false;
    } else {
      switch (state.timeMode) {
        case TimeMode.leaveNow:
          effectiveDateTime = now;
          arriveBy = false;
        case TimeMode.departAt:
          effectiveDateTime = state.dateTime ?? now;
          arriveBy = false;
        case TimeMode.arriveBy:
          effectiveDateTime = state.dateTime ?? now;
          arriveBy = true;
      }
    }

    try {
      _currentFetchOperation = CancelableOperation.fromFuture(
        _requestService.fetchPlan(
          from: state.fromPlace!,
          to: state.toPlace!,
          locale: _locale,
          dateTime: effectiveDateTime,
          arriveBy: arriveBy,
        ),
      );

      final rawPlan = await _currentFetchOperation?.valueOrCancellation();

      if (rawPlan == null) {
        // Operation was cancelled
        return;
      }

      if (!rawPlan.hasItineraries) {
        emit(state.copyWith(isLoading: false, error: noRoutesErrorKey));
        return;
      }

      // Enrich legs with operating hours from the bundled GTFS so OTP
      // 1.5/2.8 plans show the indicator just like the local planner.
      final plan = _groupPlanItineraries(_enrichServiceHours(rawPlan));

      final index = selectedItineraryIndex ?? 0;
      final selectedItinerary =
          plan.itineraries![index < plan.itineraries!.length ? index : 0];

      await _repository.savePlan(plan);
      await _repository.saveSelectedItinerary(selectedItinerary);

      emit(
        state.copyWith(
          plan: plan,
          selectedItinerary: selectedItinerary,
          isLoading: false,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          error: routingErrorKey(e) ?? e.toString(),
        ),
      );
    }
  }

  /// Loads one more page of itineraries ("earlier"/"later connections",
  /// fahrplaner.de fork patch, see FAHRPLANER_PATCHES.md) using the cursor
  /// OTP already returns with every plan (previously parsed but discarded,
  /// see [routing.Plan.nextPageCursor]/[routing.Plan.previousPageCursor]).
  /// No-op if there is no current plan, no cursor in the requested
  /// direction (provider doesn't support paging, or already at the edge of
  /// the search window), or a fetch is already running.
  ///
  /// New itineraries are merged into the existing list (prepended for
  /// [earlier], appended otherwise) and run through the same
  /// enrichment/grouping/filtering pipeline as [fetchPlan] so the merged
  /// list stays consistent.
  Future<void> loadMoreItineraries({required bool earlier}) async {
    final currentPlan = state.plan;
    if (currentPlan == null || state.isLoading || state.isLoadingMore) return;
    final cursor = earlier
        ? currentPlan.previousPageCursor
        : currentPlan.nextPageCursor;
    if (cursor == null) return;
    if (state.fromPlace == null || state.toPlace == null) return;

    // T043 (Patch 59): eigener Ladezustand je Richtung statt isLoading -
    // die Liste bleibt dabei stehen, statt durch die Lade-Animation ersetzt
    // zu werden.
    emit(
      earlier
          ? state.copyWith(isLoadingEarlier: true, earlierFoundNothing: false)
          : state.copyWith(isLoadingLater: true, laterFoundNothing: false),
    );
    try {
      final existing = currentPlan.itineraries ?? [];
      // fahrplaner.de fork patch 59 (T043): Dubletten entfernen - OTP-Seiten
      // koennen sich an den Raendern des Suchfensters ueberschneiden.
      // Bereits vorhandene Eintraege gewinnen (behalten ihre Identitaet).
      final seen = {for (final it in existing) itineraryIdentityKey(it)};
      final added = <routing.Itinerary>[];
      String? nextCursor = cursor;

      // fahrplaner.de fork patch 60 (16.10.2026, T059, Nutzer-Fund): eine
      // OTP-Seite deckt nur ein Zeitfenster ab - liegt darin keine Fahrt
      // (z. B. nachts), kam eine LEERE Seite zurueck und die Liste aenderte
      // sich sichtbar nicht; erst der 3. Klick brachte eine viel spaetere
      // Verbindung. Leere Fenster werden jetzt automatisch uebersprungen
      // (hoechstens [loadMoreMaxEmptyPages] Mal), danach ein Hinweis.
      for (var page = 0; page < loadMoreMaxEmptyPages; page++) {
        final rawPlan = await _requestService.fetchPlan(
          from: state.fromPlace!,
          to: state.toPlace!,
          locale: _locale,
          dateTime: DateTime.now(),
          pageCursor: nextCursor,
          // fahrplaner.de fork patch (04.10.2026, Kapitel 3.27): ohne dies
          // faellt fetchPlan() auf den Erstsuche-Standard von 5 zurueck.
          numItineraries: loadMoreItinerariesPageSize,
        );
        final enriched = _enrichServiceHours(rawPlan);
        for (final itinerary in enriched.itineraries ?? <routing.Itinerary>[]) {
          if (seen.add(itineraryIdentityKey(itinerary))) added.add(itinerary);
        }
        nextCursor = earlier
            ? enriched.previousPageCursor
            : enriched.nextPageCursor;
        if (added.isNotEmpty || nextCursor == null) break;
      }

      // fahrplaner.de fork patch (04.10.2026, Kapitel 3.27): jede einzelne
      // Antwort ist nach OTP-Kosten sortiert - beim Zusammenfuegen deshalb
      // explizit chronologisch neu sortieren.
      final merged = [...existing, ...added]
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

      // Plan neu konstruiert statt copyWith(): copyWith kann einen Cursor
      // nicht auf null setzen ("?? this.nextPageCursor") - liefert OTP
      // keinen weiteren Cursor (Suchfenster erschoepft), blieb bisher der
      // ALTE stehen und jeder weitere Klick holte dieselbe Seite erneut
      // (Patch 60, beim Test fuer T059 gefunden).
      final mergedPlan = _groupPlanItineraries(
        routing.Plan(
          from: currentPlan.from,
          to: currentPlan.to,
          itineraries: merged,
          type: currentPlan.type,
          nextPageCursor: earlier ? currentPlan.nextPageCursor : nextCursor,
          previousPageCursor: earlier
              ? nextCursor
              : currentPlan.previousPageCursor,
        ),
      );

      await _repository.savePlan(mergedPlan);
      emit(
        state.copyWith(
          plan: mergedPlan,
          isLoadingEarlier: false,
          isLoadingLater: false,
          earlierFoundNothing: earlier && added.isEmpty,
          laterFoundNothing: !earlier && added.isEmpty,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isLoadingEarlier: false,
          isLoadingLater: false,
          error: routingErrorKey(e) ?? e.toString(),
        ),
      );
    }
  }

  /// Select an itinerary from the plan.
  Future<void> selectItinerary(routing.Itinerary itinerary) async {
    await _repository.saveSelectedItinerary(itinerary);
    emit(state.copyWith(selectedItinerary: itinerary));
  }

  Future<void> _cancelCurrentFetch() async {
    await _currentFetchOperation?.cancel();
    _currentFetchOperation = null;
  }

  @override
  Future<void> close() async {
    await _cancelCurrentFetch();
    return super.close();
  }
}
