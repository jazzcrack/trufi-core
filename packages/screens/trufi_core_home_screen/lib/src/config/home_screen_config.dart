import 'package:flutter/widgets.dart';
import 'package:trufi_core_maps/trufi_core_maps.dart';
import 'package:trufi_core_poi_layers/trufi_core_poi_layers.dart';
import 'package:trufi_core_search_locations/trufi_core_search_locations.dart';

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
  });
}
