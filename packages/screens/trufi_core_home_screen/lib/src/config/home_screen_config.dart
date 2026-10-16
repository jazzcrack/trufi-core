import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show AttributionButtonPosition;
import 'package:trufi_core_maps/trufi_core_maps.dart';
import 'package:trufi_core_poi_layers/trufi_core_poi_layers.dart';
import 'package:trufi_core_search_locations/trufi_core_search_locations.dart';

import '../models/route_planner_state.dart';

/// Alternate rendering for the wide-screen (`isWideScreen`, >=600px) side
/// panel in `home_screen.dart`. Returned by [HomeScreenConfig.sidePanelStyle]
/// from the live [BuildContext], so a host can react to e.g. a landscape/
/// portrait distinction that this Fork package doesn't know about, without
/// importing app-level layout code.
///
/// Every field defaults to the value that reproduces the screen's existing,
/// unstyled behaviour - constructing `WideSidePanelStyle()` with no
/// arguments changes nothing.
///
/// fahrplaner.de fork patch (see FAHRPLANER_PATCHES.md, Patch 42).
class WideSidePanelStyle {
  /// Panel on the right instead of the built-in left.
  final bool onRight;

  /// When true, the panel floats over the map (margin on all sides, rounded
  /// corners, map rendered full-width/unshifted underneath) instead of the
  /// built-in flush, full-height split that shifts the map over to make
  /// room. Needed because a floating panel only ever covers PART of the
  /// map, so the rider's own location needs an explicit camera offset (see
  /// [HomeScreenConfig.cameraTargetAdjuster]) instead of just not being
  /// hidden under a panel the map was already resized to avoid.
  final bool floating;

  /// Margin around the panel when [floating] is true. Ignored otherwise.
  final EdgeInsets floatingMargin;

  /// Overrides the built-in 340/380/420 width breakpoints with a fixed
  /// width. `null` (the default) keeps the breakpoint function.
  final double? fixedWidth;

  /// Also show [HomeScreenConfig.mapOverlayBuilder] on wide screens (it's
  /// otherwise always suppressed there, since it was built for the narrow
  /// screen's floating top-left status pill, which had no wide-screen
  /// equivalent position until now).
  final bool showMapOverlay;

  /// Move the floating map controls (my-location, map-type) from their
  /// built-in top-right position to bottom-left - for when [onRight] puts
  /// the panel where the controls would otherwise be.
  final bool mapControlsBottomLeft;

  const WideSidePanelStyle({
    this.onRight = false,
    this.floating = false,
    this.floatingMargin = EdgeInsets.zero,
    this.fixedWidth,
    this.showMapOverlay = false,
    this.mapControlsBottomLeft = false,
  });
}

/// Configuration for the Home Screen module.
///
/// Routing configuration is provided via RoutingEngineManager in the app's
/// providers, similar to how MapEngineManager works. This allows for consistent
/// engine selection in Settings.
class HomeScreenConfig {
  /// Zoom level when choosing a location
  final double chooseLocationZoom;

  /// Search service for location search (defaults to Photon)
  final SearchLocationService? searchService;

  /// List of saved places to show in search (Home, Work, etc.)
  /// Only used if SavedPlacesCubit is not available in context.
  final List<SearchLocation> myPlaces;

  /// App name to show in shared route text
  final String? appName;

  /// Deep link scheme for route sharing (e.g., 'trufiapp').
  /// When set, shared routes will include a deep link URL.
  final String? deepLinkScheme;

  /// Base URL for web-based route sharing (e.g., 'https://maps.trujillo.trufi.dev').
  /// When set, shared routes use a web URL instead of the deep link scheme,
  /// making shared links openable from any platform/browser.
  final String? shareBaseUrl;

  /// Optional custom map layers to display on the home screen map.
  final List<TrufiLayer> Function(TrufiMapController controller)?
  customMapLayers;

  /// Optional POI layers manager for displaying points of interest on the map.
  final POILayersManager? poiLayersManager;

  /// Optional extra section appended under the built-in sections in the map
  /// settings bottom sheet. Use this for deploy-specific overlays beyond POIs
  /// and live vehicles.
  ///
  /// Note: live vehicle support is wired automatically via the currently-active
  /// [IRoutingProvider.realtimeVehiclesProvider] — no config needed here.
  final Widget? extraMapLayerSettings;

  /// Initial state of the live-vehicles map layer on a fresh install.
  ///
  /// Defaults to `false` (the user opts in from the map settings sheet).
  /// Deploys whose realtime feed is a headline feature (e.g. an operator
  /// pilot) can start with the layer on; once the user touches the toggle,
  /// their choice is persisted and this value no longer applies.
  final bool liveVehiclesInitiallyEnabled;

  /// Whether to show the floating map-style picker button on the map.
  /// Defaults to true.
  ///
  /// fahrplaner.de fork patch (see FAHRPLANER_PATCHES.md): a host app that
  /// couples map style to system/app dark mode (so the picker's choice is
  /// silently overridden on every rebuild) can set this to false instead of
  /// presenting a control that doesn't actually work.
  final bool showMapTypeButton;

  /// Optional content shown below the search bar on the EMPTY home screen
  /// (no origin/destination chosen yet, no plan loaded) - e.g. quick
  /// shortcuts, an offline-readiness pill, or a nearby-stop preview.
  /// Hidden as soon as the rider picks a place, since the departure-time/
  /// filter chips take over that space then.
  ///
  /// fahrplaner.de fork patch (see FAHRPLANER_PATCHES.md, Patch 28) -
  /// additive hook, `null` (the default) changes nothing.
  final Widget Function(BuildContext context)? belowSearchBuilder;

  /// fahrplaner.de fork patch 62: Quelle fuer "passende Hausnummern" im
  /// Hausnummer-Dialog (spaeter eigene Photon-Instanz). null = keine
  /// Vorschlagsliste, die Eingabe wird ueber den Suchdienst aufgeloest.
  final HouseNumberSuggestionSource? houseNumberSuggestionSource;

  /// Optional content positioned top-left ON THE MAP itself - for a status
  /// pill (e.g. "offline ready"/"no network"), shown ABOVE everything else
  /// so it survives even when the search sheet covers most of the screen.
  /// Unlike [belowSearchBuilder] this is NOT limited to the empty-search
  /// state - it stays visible the whole time the rider is on this screen,
  /// matching the always-visible "my location" map button beside it.
  ///
  /// fahrplaner.de fork patch (see FAHRPLANER_PATCHES.md, Patch 33) -
  /// additive hook, `null` (the default) changes nothing.
  final Widget Function(BuildContext context)? mapOverlayBuilder;

  /// Optional, COMPLETE replacement of the screen's own map+results
  /// rendering - for hosts that want a fundamentally different results
  /// layout (e.g. a list+detail split with no map at all) instead of the
  /// built-in map+bottom-sheet (narrow)/map+side-panel (wide) rendering.
  ///
  /// Called with the current [RoutePlannerState] only while there ARE
  /// results to show (`state.plan != null || state.isLoading ||
  /// state.hasError`) - never while the search itself is still empty, so
  /// a host that only wants to override the RESULTS phase doesn't also
  /// have to reimplement the empty/search state. Returning `null` for a
  /// given state (e.g. the host only wants to override on wide screens)
  /// falls back to the screen's own rendering for that build.
  ///
  /// fahrplaner.de fork patch (see FAHRPLANER_PATCHES.md, Patch 41) -
  /// additive hook, `null` (the default) changes nothing.
  final Widget? Function(BuildContext context, RoutePlannerState state)?
  resultsBuilder;

  /// Optional alternate rendering for the wide-screen (>=600px) side panel,
  /// evaluated from the live [BuildContext] (so it can react to things this
  /// Fork package doesn't know about, e.g. a landscape/portrait
  /// distinction). Returning `null` (the default) keeps the screen's
  /// existing left-flush, full-height, breakpoint-width panel unchanged.
  ///
  /// fahrplaner.de fork patch (see FAHRPLANER_PATCHES.md, Patch 42) -
  /// additive hook, `null` (the default) changes nothing.
  final WideSidePanelStyle? Function(BuildContext context)? sidePanelStyle;

  /// Optional adjustment applied to the camera target whenever this screen
  /// centers the map on the rider's own location (the "my location" button,
  /// [chooseLocationZoom] applies separately). Lets a host shift the target
  /// so it lands in the visible map area when [sidePanelStyle] floats a
  /// panel over part of the map - this screen has no notion of a panel
  /// "covering" part of the map on its own, so it cannot compute that shift
  /// itself. Returning the input [LatLng] unchanged (or passing `null`, the
  /// default) keeps the screen's existing, unshifted centering.
  ///
  /// fahrplaner.de fork patch (see FAHRPLANER_PATCHES.md, Patch 42) -
  /// additive hook, `null` (the default) changes nothing.
  final LatLng Function(BuildContext context, LatLng target, double zoom)?
  cameraTargetAdjuster;

  /// Position of the native map attribution control, evaluated from the
  /// live [BuildContext] like [sidePanelStyle]/[cameraTargetAdjuster] so a
  /// host can move it out from under its own overlaid UI (e.g. a floating
  /// side panel). Passed straight through to
  /// [ITrufiMapEngine.buildMap]'s `attributionButtonPosition` - this
  /// screen otherwise never sets it, unlike the equivalent parameter on
  /// a navigation map. Returning `null` (the default) keeps the engine's
  /// own default position.
  ///
  /// fahrplaner.de fork patch (see FAHRPLANER_PATCHES.md) - additive
  /// hook, `null` (the default) changes nothing.
  final AttributionButtonPosition? Function(BuildContext context)?
  attributionButtonPosition;

  /// Margin for the native map attribution control. See
  /// [attributionButtonPosition] for the full contract.
  ///
  /// fahrplaner.de fork patch (see FAHRPLANER_PATCHES.md) - additive
  /// hook, `null` (the default) changes nothing.
  final Offset? Function(BuildContext context)? attributionButtonMargin;

  const HomeScreenConfig({
    this.chooseLocationZoom = 16.0,
    this.searchService,
    this.myPlaces = const [],
    this.appName,
    this.deepLinkScheme,
    this.shareBaseUrl,
    this.customMapLayers,
    this.poiLayersManager,
    this.extraMapLayerSettings,
    this.liveVehiclesInitiallyEnabled = false,
    this.showMapTypeButton = true,
    this.belowSearchBuilder,
    this.houseNumberSuggestionSource,
    this.mapOverlayBuilder,
    this.resultsBuilder,
    this.sidePanelStyle,
    this.cameraTargetAdjuster,
    this.attributionButtonPosition,
    this.attributionButtonMargin,
  });
}
