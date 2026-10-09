import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:trufi_core_interfaces/trufi_core_interfaces.dart';
import 'package:trufi_core_utils/trufi_core_utils.dart'
    show PackageInfoPlatform;
import 'package:url_launcher/url_launcher.dart';

import '../l10n/core_localizations.dart';

/// Application router using GoRouter with dynamic screen support
class AppRouter {
  final List<TrufiScreen> screens;
  final List<SocialMediaLink> socialMediaLinks;
  final GlobalKey<NavigatorState> rootNavigatorKey;
  final GlobalKey<NavigatorState> shellNavigatorKey;
  final String appName;
  final String? appTagline;
  final Widget? drawerFooterExtra;
  final Widget? logo;

  /// Optional bottom `NavigationBar` tabs. See
  /// [AppConfiguration.bottomNavTabs] for the full contract.
  final List<BottomNavTab>? bottomNavTabs;

  /// Initial route to navigate to (for web deep linking)
  final String? initialRoute;

  GoRouter? _router;

  AppRouter({
    required this.screens,
    this.socialMediaLinks = const [],
    this.initialRoute,
    this.appName = 'Trufi App',
    this.appTagline,
    this.drawerFooterExtra,
    this.logo,
    this.bottomNavTabs,
    GlobalKey<NavigatorState>? rootNavigatorKey,
    GlobalKey<NavigatorState>? shellNavigatorKey,
  }) : rootNavigatorKey = rootNavigatorKey ?? GlobalKey<NavigatorState>(),
       shellNavigatorKey = shellNavigatorKey ?? GlobalKey<NavigatorState>();

  /// Get or create the router
  GoRouter get router {
    _router ??= _createRouter();
    return _router!;
  }

  /// Converts one screen (and its sub-routes) into a [GoRoute]. Shared by
  /// both the classic drawer shell and the per-tab branches below.
  GoRoute _screenToRoute(TrufiScreen s) {
    final subRoutes = s.subRoutes
        .map(
          (sub) => GoRoute(
            path: sub.path,
            builder: (context, state) {
              // Merge path parameters and query parameters
              final params = <String, String>{
                ...state.pathParameters,
                ...state.uri.queryParameters,
              };
              return sub.builder(context, params);
            },
          ),
        )
        .toList();

    return GoRoute(
      path: s.path,
      name: s.id,
      builder: (context, state) => s.builder(context),
      routes: subRoutes,
    );
  }

  /// The `/route` deep-link handler: parses a shared route from the query
  /// parameters (if any) and always redirects to the app's root.
  GoRoute _sharedRouteDeepLinkRoute() {
    return GoRoute(
      path: '/route',
      name: 'shared_route',
      redirect: (context, state) {
        // Parse and store the shared route
        if (state.uri.queryParameters.isNotEmpty) {
          final route = SharedRoute.fromUri(state.uri);
          if (route != null) {
            final notifier = Provider.of<SharedRouteNotifier>(
              context,
              listen: false,
            );
            notifier.setPendingRoute(route);
          }
        }
        // Always redirect to home
        return '/';
      },
    );
  }

  GoRouter _createRouter() {
    // Enable URL updates for imperative navigation (push/pop) on web
    // Without this, push() won't update the browser URL (GoRouter 8.0+ behavior)
    GoRouter.optionURLReflectsImperativeAPIs = true;

    final tabs = bottomNavTabs;
    return GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: initialRoute ?? '/',
      routes: tabs != null && tabs.isNotEmpty
          ? _buildBottomNavRoutes(tabs)
          : _buildDrawerShellRoutes(),
      errorBuilder: (context, state) => ErrorScreen(error: state.error),
    );
  }

  /// Classic single-shell, drawer-based navigation (unchanged behavior).
  List<RouteBase> _buildDrawerShellRoutes() {
    final routes = screens.map(_screenToRoute).toList();

    // Add the /route deep link handler to the routes list. The fallback
    // home is keyed on the screen-derived routes: the deep-link handler
    // below is always present, so `allRoutes` itself is never empty and
    // '/' would otherwise 404 in a screen-less app.
    final allRoutes = [
      if (routes.isEmpty) _defaultHomeRoute(),
      ...routes,
      _sharedRouteDeepLinkRoute(),
    ];

    return [
      ShellRoute(
        navigatorKey: shellNavigatorKey,
        builder: (context, state, child) {
          return AppShell(
            currentPath: state.uri.path,
            screens: screens,
            socialMediaLinks: socialMediaLinks,
            appName: appName,
            appTagline: appTagline,
            drawerFooterExtra: drawerFooterExtra,
            logo: logo,
            child: child,
          );
        },
        routes: allRoutes,
      ),
    ];
  }

  /// Bottom-`NavigationBar` navigation: one [StatefulShellBranch] per tab,
  /// each holding the [GoRoute]s for its [BottomNavTab.screenIds] in order.
  /// No drawer is built in this mode — every screen must be reachable
  /// through exactly one tab.
  List<RouteBase> _buildBottomNavRoutes(List<BottomNavTab> tabs) {
    GoRoute routeForId(String id) =>
        _screenToRoute(screens.firstWhere((s) => s.id == id));

    final branches = tabs
        .map(
          (tab) => StatefulShellBranch(
            routes: tab.screenIds.map(routeForId).toList(),
          ),
        )
        .toList();

    return [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShellWithBottomNav(
            navigationShell: navigationShell,
            tabs: tabs,
            screens: screens,
          );
        },
        branches: branches,
      ),
      _sharedRouteDeepLinkRoute(),
    ];
  }

  /// Default home route if no screens registered
  GoRoute _defaultHomeRoute() {
    return GoRoute(
      path: '/',
      name: 'home',
      builder: (context, state) => Center(
        child: Text(CoreLocalizations.of(context).errorNoScreensRegistered),
      ),
    );
  }

  /// Rebuild router when screens change
  void rebuild() {
    _router?.refresh();
  }
}

/// Main app shell with navigation drawer
class AppShell extends StatelessWidget {
  final Widget child;
  final String currentPath;
  final List<TrufiScreen> screens;
  final List<SocialMediaLink> socialMediaLinks;
  final String appName;
  final String? appTagline;
  final Widget? drawerFooterExtra;
  final Widget? logo;

  const AppShell({
    super.key,
    required this.child,
    required this.currentPath,
    required this.screens,
    this.socialMediaLinks = const [],
    this.appName = 'Trufi App',
    this.appTagline,
    this.drawerFooterExtra,
    this.logo,
  });

  /// First screen matching [test], the first screen otherwise, or null
  /// when the app has no screens at all (the fallback-home case).
  TrufiScreen? _findScreen(bool Function(TrufiScreen) test) {
    for (final s in screens) {
      if (test(s)) return s;
    }
    return screens.isEmpty ? null : screens.first;
  }

  @override
  Widget build(BuildContext context) {
    // Verificar si la pantalla actual tiene su propio AppBar
    final currentScreen = _findScreen((s) => s.path == currentPath);
    final hasOwnAppBar = currentScreen?.hasOwnAppBar ?? false;

    return Scaffold(
      appBar: hasOwnAppBar
          ? null // La pantalla maneja su propio AppBar
          : AppBar(
              title: Text(_getTitle(context)),
              elevation: 2,
              actions: [
                // Placeholder para acciones adicionales si se necesitan
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: CoreLocalizations.of(context).navAbout,
                  onPressed: () {
                    final aboutScreen = _findScreen((s) => s.id == 'about');
                    if (aboutScreen != null) {
                      _navigateToSection(context, aboutScreen.path);
                    }
                  },
                ),
              ],
            ),
      drawer: AppDrawer(
        currentPath: currentPath,
        screens: screens,
        socialMediaLinks: socialMediaLinks,
        appName: appName,
        appTagline: appTagline,
        footerExtra: drawerFooterExtra,
        logo: logo,
      ),
      body: child,
    );
  }

  String _getTitle(BuildContext context) {
    for (final screen in screens) {
      if (screen.path == currentPath) {
        return screen.getLocalizedTitle(context);
      }
    }
    return appName;
  }
}

/// Shell for bottom-`NavigationBar` navigation (see
/// [AppConfiguration.bottomNavTabs]). No drawer — each [BottomNavTab]'s
/// label/title comes from its root screen's own `getLocalizedTitle`.
class AppShellWithBottomNav extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  final List<BottomNavTab> tabs;
  final List<TrufiScreen> screens;

  const AppShellWithBottomNav({
    super.key,
    required this.navigationShell,
    required this.tabs,
    required this.screens,
  });

  TrufiScreen _rootScreen(BottomNavTab tab) =>
      screens.firstWhere((s) => s.id == tab.screenIds.first);

  String _label(BuildContext context, BottomNavTab tab) =>
      tab.labelBuilder?.call(context) ??
      _rootScreen(tab).getLocalizedTitle(context);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: [
          for (final tab in tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.activeIcon ?? tab.icon),
              label: _label(context, tab),
            ),
        ],
      ),
    );
  }
}

/// Modern navigation drawer with Material 3 design
class AppDrawer extends StatelessWidget {
  final String currentPath;
  final List<TrufiScreen> screens;
  final List<SocialMediaLink> socialMediaLinks;
  final String appName;
  final String? appTagline;
  final Widget? footerExtra;
  final Widget? logo;

  const AppDrawer({
    super.key,
    required this.currentPath,
    required this.screens,
    this.socialMediaLinks = const [],
    this.appName = 'Trufi App',
    this.appTagline,
    this.footerExtra,
    this.logo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Drawer(
      backgroundColor: colorScheme.surface,
      child: Column(
        children: [
          // Modern header with layered design
          _DrawerHeader(
            theme: theme,
            appName: appName,
            appTagline: appTagline,
            logo: logo,
          ),

          const SizedBox(height: 8),

          // Menu items with Material 3 styling
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _buildMenuItems(context, theme),
            ),
          ),

          // Modern footer
          _DrawerFooter(
            theme: theme,
            socialMediaLinks: socialMediaLinks,
            extra: footerExtra,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMenuItems(BuildContext context, ThemeData theme) {
    final widgets = <Widget>[];

    // Collect screens with menu items
    final menuScreens = screens.where((s) => s.menuItem != null).toList();

    // Sort by order
    menuScreens.sort((a, b) => a.menuItem!.order.compareTo(b.menuItem!.order));

    for (int i = 0; i < menuScreens.length; i++) {
      final screen = menuScreens[i];
      final item = screen.menuItem!;

      if (item.showDividerBefore) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: theme.colorScheme.outlineVariant),
          ),
        );
      }

      widgets.add(
        _DrawerMenuItem(
          icon: item.icon,
          title: screen.getLocalizedTitle(context),
          isSelected: currentPath == screen.path,
          onTap: () {
            Scaffold.of(context).closeDrawer();
            _navigateToSection(context, screen.path);
          },
        ),
      );
    }

    return widgets;
  }
}

/// Navigates to a top-level section, keeping `/` at the bottom of the stack
/// so the system back button always returns to home.
void _navigateToSection(BuildContext context, String path) {
  final router = GoRouter.of(context);
  final currentPath = router.routeInformationProvider.value.uri.path;

  if (currentPath == path) return;

  if (currentPath == '/') {
    router.push(path);
    return;
  }

  if (router.canPop()) {
    router.pushReplacement(path);
    return;
  }

  // Deep-linked into a section; reset stack to [/, path].
  router.go('/');
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) router.push(path);
  });
}

/// Modern drawer header with layered design
class _DrawerHeader extends StatelessWidget {
  final ThemeData theme;
  final String appName;
  final String? appTagline;
  final Widget? logo;

  const _DrawerHeader({
    required this.theme,
    required this.appName,
    this.appTagline,
    this.logo,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo/Avatar with modern styling
              logo != null
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 56),
                      child: logo!,
                    )
                  : Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.directions_bus_rounded,
                        size: 32,
                        color: colorScheme.onPrimary,
                      ),
                    ),
              const SizedBox(height: 16),
              // App name
              Text(
                appName,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              // Tagline
              if (appTagline != null)
                Text(
                  appTagline!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Material 3 styled drawer menu item
class _DrawerMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool isSelected;

  const _DrawerMenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? colorScheme.secondaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: isSelected
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: isSelected
                          ? colorScheme.onSecondaryContainer
                          : colorScheme.onSurfaceVariant,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
                // Selection indicator
                if (isSelected)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Modern drawer footer with version and optional actions
class _DrawerFooter extends StatelessWidget {
  final ThemeData theme;
  final List<SocialMediaLink> socialMediaLinks;
  final Widget? extra;

  const _DrawerFooter({
    required this.theme,
    this.socialMediaLinks = const [],
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        children: [
          if (extra != null) ...[extra!, const SizedBox(height: 12)],
          // Version info
          FutureBuilder<String>(
            future: PackageInfoPlatform.version(),
            builder: (context, snapshot) {
              final version = snapshot.data ?? '';
              if (version.isEmpty) return const SizedBox.shrink();
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'v$version',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.6,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          if (socialMediaLinks.isNotEmpty) ...[
            const SizedBox(height: 12),
            // Social media icons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < socialMediaLinks.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _SocialIconButton(
                    icon: socialMediaLinks[i].icon,
                    url: socialMediaLinks[i].url,
                    label: socialMediaLinks[i].label,
                    colorScheme: colorScheme,
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 12),
          // Powered by text
          Text(
            CoreLocalizations.of(context).poweredByTrufi,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// Social media icon button for the drawer footer
class _SocialIconButton extends StatelessWidget {
  final Widget icon;
  final String url;
  final String? label;
  final ColorScheme colorScheme;

  const _SocialIconButton({
    required this.icon,
    required this.url,
    this.label,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: icon,
      iconSize: 20,
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      onPressed: () => launchUrl(Uri.parse(url)),
      tooltip: label ?? url,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
    );
  }
}

/// Error screen for unknown routes
class ErrorScreen extends StatelessWidget {
  final Exception? error;

  const ErrorScreen({super.key, this.error});

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.titleError)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(l10n.errorPageNotFound, style: TextStyle(fontSize: 24)),
            const SizedBox(height: 8),
            if (error != null)
              Text(
                error.toString(),
                style: const TextStyle(color: Colors.grey),
              ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/'),
              child: Text(l10n.actionGoHome),
            ),
          ],
        ),
      ),
    );
  }
}
