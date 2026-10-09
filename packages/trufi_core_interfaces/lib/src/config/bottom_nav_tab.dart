import 'package:flutter/widgets.dart';

/// Configuration for one destination of the bottom `NavigationBar` shell.
///
/// When [AppConfiguration.bottomNavTabs] is set, [AppRouter] builds a
/// `StatefulShellRoute` with one branch per tab instead of the classic
/// drawer-based `ShellRoute` — each tab keeps its own navigation stack
/// (back-stack, scroll position) while switching tabs.
///
/// The destination's label and app-bar title are taken from the root
/// screen's own `getLocalizedTitle(context)` (the first entry of
/// [screenIds]) rather than duplicated here.
class BottomNavTab {
  /// Icon shown while this tab is inactive.
  final IconData icon;

  /// Icon shown while this tab is active. Falls back to [icon] if null.
  final IconData? activeIcon;

  /// Ids of the registered `TrufiScreen`s that belong to this tab's
  /// navigation branch, in the order they should be registered as routes.
  ///
  /// The FIRST entry is the branch's root route (what's shown when the
  /// tab is first selected); the rest are only reachable by pushing from
  /// within the branch (e.g. a detail screen opened from the tab's root).
  final List<String> screenIds;

  const BottomNavTab({
    required this.icon,
    this.activeIcon,
    required this.screenIds,
  });
}
