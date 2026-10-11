import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:trufi_core_interfaces/trufi_core_interfaces.dart';
import 'package:trufi_core_ui/src/l10n/core_localizations.dart';
import 'package:trufi_core_ui/src/router/app_router.dart';

/// fahrplaner.de fork patch (Patch 43, see FAHRPLANER_PATCHES.md) -
/// `AppConfiguration.useNavigationRail`. Same `_StubScreen`/harness
/// shape as app_router_bottom_nav_test.dart (Patch 29).
class _StubScreen extends TrufiScreen {
  _StubScreen(this.id, this.path, this.title, this.body);

  @override
  final String id;
  @override
  final String path;
  final String title;
  final Widget body;

  @override
  Widget Function(BuildContext) get builder =>
      (context) => body;

  @override
  List<LocalizationsDelegate> get localizationsDelegates => const [];

  @override
  String getLocalizedTitle(BuildContext context) => title;
}

void main() {
  Widget appWithTabs(AppRouter router) {
    return ChangeNotifierProvider(
      create: (_) => SharedRouteNotifier(),
      child: MaterialApp.router(
        locale: const Locale('en'),
        supportedLocales: CoreLocalizations.supportedLocales,
        localizationsDelegates: CoreLocalizations.localizationsDelegates,
        routerConfig: router.router,
      ),
    );
  }

  AppRouter twoTabRouter({bool Function(BuildContext)? useNavigationRail}) {
    final screens = [
      _StubScreen('a', '/', 'Planen', const Text('Planen-Inhalt')),
      _StubScreen('b', '/b', 'Gemerkt', const Text('Gemerkt-Inhalt')),
    ];
    return AppRouter(
      screens: screens,
      bottomNavTabs: const [
        BottomNavTab(icon: Icons.home, screenIds: ['a']),
        BottomNavTab(icon: Icons.bookmark, screenIds: ['b']),
      ],
      useNavigationRail: useNavigationRail,
    );
  }

  testWidgets(
    'useNavigationRail unset (default): NavigationBar as before, no rail',
    (tester) async {
      await tester.pumpWidget(appWithTabs(twoTabRouter()));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    },
  );

  testWidgets(
    'useNavigationRail returning true: NavigationRail instead of the bar, '
    'one destination per tab, labels always shown',
    (tester) async {
      await tester.pumpWidget(
        appWithTabs(twoTabRouter(useNavigationRail: (context) => true)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsNothing);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.minWidth, 84);
      expect(rail.labelType, NavigationRailLabelType.all);
      expect(rail.groupAlignment, 0.0);
      expect(rail.destinations, hasLength(2));
      expect(find.text('Planen'), findsOneWidget);
      expect(find.text('Gemerkt'), findsOneWidget);
      expect(find.text('Planen-Inhalt'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping a rail destination switches to that branch\'s root - same '
    'StatefulShellRoute state as the bar',
    (tester) async {
      await tester.pumpWidget(
        appWithTabs(twoTabRouter(useNavigationRail: (context) => true)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gemerkt'));
      await tester.pumpAndSettle();

      expect(find.text('Gemerkt-Inhalt'), findsOneWidget);
      expect(find.text('Planen-Inhalt'), findsNothing);
    },
  );

  testWidgets(
    'a push within one branch keeps the rail visible, same as the bar',
    (tester) async {
      final screens = [
        _StubScreen('a', '/', 'Planen', const Text('Planen-Inhalt')),
        _StubScreen('a-detail', '/a-detail', 'Detail', const Text('Detail')),
        _StubScreen('b', '/b', 'Gemerkt', const Text('Gemerkt-Inhalt')),
      ];
      final router = AppRouter(
        screens: screens,
        bottomNavTabs: const [
          BottomNavTab(icon: Icons.home, screenIds: ['a', 'a-detail']),
          BottomNavTab(icon: Icons.bookmark, screenIds: ['b']),
        ],
        useNavigationRail: (context) => true,
      );
      await tester.pumpWidget(appWithTabs(router));
      await tester.pumpAndSettle();

      router.router.push('/a-detail');
      await tester.pumpAndSettle();

      expect(find.text('Detail'), findsOneWidget);
      expect(find.byType(NavigationRail), findsOneWidget);
    },
  );
}
