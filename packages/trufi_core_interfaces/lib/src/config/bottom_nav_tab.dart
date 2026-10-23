import 'package:flutter/widgets.dart';

/// Configuration for one destination of the bottom `NavigationBar` shell.
///
/// When [AppConfiguration.bottomNavTabs] is set, [AppRouter] builds a
/// `StatefulShellRoute` with one branch per tab instead of the classic
/// drawer-based `ShellRoute` — each tab keeps its own navigation stack
/// (back-stack, scroll position) while switching tabs.
///
/// The destination's label and app-bar title default to the root screen's
/// own `getLocalizedTitle(context)` (the first entry of [screenIds]) —
/// override with [labelBuilder] when the tab needs different wording than
/// that screen's own title (e.g. a title written for a drawer menu entry,
/// not a short bottom-tab label).
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

  /// Overrides the destination's label. `null` (the default) falls back to
  /// the root screen's own `getLocalizedTitle(context)`.
  final String Function(BuildContext context)? labelBuilder;

  const BottomNavTab({
    required this.icon,
    this.activeIcon,
    required this.screenIds,
    this.labelBuilder,
  });
}

/// fahrplaner.de fork patch (Patch 74, see FAHRPLANER_PATCHES.md): what
/// [AppConfiguration.bottomNavShellBuilder] receives to draw the tab shell
/// itself (bottom bar, side rail, anything above the bar) instead of the
/// default Material `NavigationBar`/`NavigationRail`.
class BottomNavShellData {
  /// The active branch's content (go_router's navigation shell).
  final Widget body;

  /// Index of the active tab in [tabs].
  final int currentIndex;

  /// Switches to tab [index]; selecting the active tab again pops it back
  /// to its root (same behaviour as the default shell).
  final void Function(int index) onSelect;

  final List<BottomNavTab> tabs;

  /// Resolved label per tab (same order as [tabs]).
  final List<String> labels;

  const BottomNavShellData({
    required this.body,
    required this.currentIndex,
    required this.onSelect,
    required this.tabs,
    required this.labels,
  });
}

typedef BottomNavShellBuilder =
    Widget Function(BuildContext context, BottomNavShellData data);

