import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/widgets.dart';
import 'package:provider/single_child_widget.dart';

import '../overlay/overlay_service.dart';
import 'bottom_nav_tab.dart';
import 'trufi_screen.dart';
import 'trufi_theme_config.dart';
import 'trufi_locale_config.dart';
import 'social_media_config.dart';

/// Steps during app initialization.
enum AppInitStep {
  /// Initial state, starting up
  starting,

  /// Initializing overlay managers
  initializingOverlays,

  /// Loading map engines
  loadingMaps,

  /// Loading routing engines
  loadingRoutes,

  /// Preparing screen modules
  preparingScreens,
}

/// Builder for custom app initialization screen.
///
/// Parameters:
/// - [currentStep]: Current initialization step (null if error)
/// - [errorMessage]: Error message if initialization failed (null if loading)
/// - [onRetry]: Callback to retry initialization after an error
///
/// Example:
/// ```dart
/// Widget myInitScreen(
///   BuildContext context,
///   AppInitStep? currentStep,
///   String? errorMessage,
///   VoidCallback onRetry,
/// ) {
///   if (errorMessage != null) {
///     return Column(
///       mainAxisAlignment: MainAxisAlignment.center,
///       children: [
///         Icon(Icons.error, color: Colors.red),
///         Text('Error: $errorMessage'),
///         ElevatedButton(onPressed: onRetry, child: Text('Retry')),
///       ],
///     );
///   }
///
///   return Column(
///     mainAxisAlignment: MainAxisAlignment.center,
///     children: [
///       CircularProgressIndicator(),
///       Text(_stepToString(currentStep)),
///     ],
///   );
/// }
/// ```
typedef AppInitScreenBuilder =
    Widget Function(
      BuildContext context,
      AppInitStep? currentStep,
      String? errorMessage,
      VoidCallback onRetry,
    );

/// Application configuration
class AppConfiguration {
  final String appName;
  final String? appTagline;
  final List<TrufiScreen> screens;
  final TrufiLocaleConfig localeConfig;
  final TrufiThemeConfig themeConfig;
  final List<SocialMediaLink> socialMediaLinks;

  /// Optional default locale override.
  /// If provided, this will be used instead of [localeConfig.defaultLocale].
  final Locale? defaultLocale;

  /// Deep link scheme for route sharing (e.g., 'trufiapp').
  /// When set, shared routes will include a deep link URL that opens the app.
  final String? deepLinkScheme;

  /// Optional overlay manager. When provided, it and all its child
  /// AppOverlayManagers are auto-registered as Providers, so consumers
  /// can use `context.watch<PrivacyConsentManager>()` etc. directly.
  final OverlayService? overlayManager;

  /// Global providers that will be available to all screens.
  ///
  /// Use this to inject shared state managers:
  /// - MapEngineManager (required)
  /// - RoutingEngineManager (required)
  /// - SearchLocationsCubit, POILayersCubit, etc.
  ///
  /// For overlay managers (privacy consent, onboarding, etc.), use the
  /// dedicated [overlayManager] field instead.
  ///
  /// Example:
  /// ```dart
  /// providers: [
  ///   ChangeNotifierProvider(
  ///     create: (_) => MapEngineManager(engines: [...]),
  ///   ),
  ///   ChangeNotifierProvider(
  ///     create: (_) => RoutingEngineManager(engines: [...]),
  ///   ),
  /// ]
  /// ```
  final List<SingleChildWidget> providers;

  /// Optional custom initialization screen builder.
  ///
  /// If provided, this will be used instead of the default initialization UI.
  /// The builder receives:
  /// - [currentStep]: Current step (null if error occurred)
  /// - [errorMessage]: Error message (null if loading normally)
  /// - [onRetry]: Callback to retry initialization
  ///
  /// If null, a beautiful default initialization screen is shown.
  final AppInitScreenBuilder? initScreenBuilder;

  /// Additional localization delegates from the app.
  ///
  /// Use this to register app-level ARB localizations (e.g., custom map names).
  final List<LocalizationsDelegate> extraLocalizationsDelegates;

  /// Optional widget displayed above the drawer footer (e.g., partner logos).
  final Widget? drawerFooterExtra;

  /// Optional logo widget (used in drawer header, etc.).
  final Widget? logo;

  /// Minimum duration the splash/init screen is shown.
  /// Defaults to Duration.zero (no minimum).
  final Duration minSplashDuration;

  /// Optional fixed time-of-day used for every transit-routing
  /// request on the current calendar day. When set, the
  /// departure-time picker is hidden and absolute `HH:mm` labels in
  /// itinerary cards/details are also hidden — the routing time is
  /// fictitious, so showing it would mislead the user.
  ///
  /// Use this for cities where service doesn't run 24h: planning at
  /// 02:00 against the real `now` returns 0 results because no
  /// service is active. Setting this to e.g.
  /// `TimeOfDay(hour: 12, minute: 0)` makes every request resolve
  /// against midday on today's date, so the user always sees
  /// representative routes regardless of when they open the app.
  ///
  /// Default: null → users see the picker, requests use
  /// `DateTime.now()`, and time labels render normally.
  final TimeOfDay? routingTimeOverride;

  /// Optional bottom `NavigationBar` tabs. When set (and non-empty),
  /// [AppRouter] replaces the classic drawer-based shell with a
  /// `StatefulShellRoute` holding one independent navigation branch per
  /// tab, and the navigation drawer is not built at all — every
  /// registered screen must then be reachable through exactly one tab's
  /// [BottomNavTab.screenIds].
  ///
  /// Default: null → the classic single-shell, drawer-based navigation
  /// (unchanged, fully backward compatible).
  final List<BottomNavTab>? bottomNavTabs;

  const AppConfiguration({
    required this.appName,
    this.appTagline,
    required this.screens,
    this.localeConfig = const TrufiLocaleConfig(),
    this.themeConfig = const TrufiThemeConfig(),
    this.socialMediaLinks = const [],
    this.deepLinkScheme,
    this.defaultLocale,
    this.overlayManager,
    this.providers = const [],
    this.initScreenBuilder,
    this.extraLocalizationsDelegates = const [],
    this.drawerFooterExtra,
    this.logo,
    this.minSplashDuration = Duration.zero,
    this.routingTimeOverride,
    this.bottomNavTabs,
  });
}
