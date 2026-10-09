import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:trufi_core_interfaces/trufi_core_interfaces.dart';
import 'package:trufi_core_ui/src/l10n/core_localizations.dart';
import 'package:trufi_core_ui/src/router/app_router.dart';

/// `AppConfiguration.bottomNavTabs` replaces the classic drawer shell with
/// a `StatefulShellRoute`: one independent navigation branch per tab, no
/// drawer at all. See architektur-konzept.md Kapitel 3.55/3.56 for why.
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

  AppRouter twoTabRouter() {
    // Die erste Branch-Wurzel braucht Pfad "/" - AppRouter() ohne
    // initialRoute (wie im echten main.dart, siehe trufi_app.dart) geht
    // sonst ins Leere (ErrorScreen statt NavigationBar).
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
    );
  }

  testWidgets('renders a NavigationBar with one destination per tab, no '
      'drawer', (tester) async {
    await tester.pumpWidget(appWithTabs(twoTabRouter()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(2));
    expect(find.text('Planen'), findsOneWidget);
    expect(find.text('Gemerkt'), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
    expect(find.text('Planen-Inhalt'), findsOneWidget);
  });

  testWidgets('tapping a destination switches to that branch\'s root', (
    tester,
  ) async {
    await tester.pumpWidget(appWithTabs(twoTabRouter()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gemerkt'));
    await tester.pumpAndSettle();

    expect(find.text('Gemerkt-Inhalt'), findsOneWidget);
    expect(find.text('Planen-Inhalt'), findsNothing);
  });

  testWidgets('a second screen in the same branch is reachable by pushing, '
      'without leaving the tab bar', (tester) async {
    // Zwei Tabs, weil Flutters eigenes NavigationBar-Widget mindestens
    // zwei Destinations verlangt (destinations.length >= 2) - der zweite
    // Tab ("b") ist hier nur ein Fuellwert, der eigentliche Testfall
    // (Push innerhalb EINES Branches) betrifft nur Tab "a".
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
    );
    await tester.pumpWidget(appWithTabs(router));
    await tester.pumpAndSettle();

    router.router.push('/a-detail');
    await tester.pumpAndSettle();

    expect(find.text('Detail'), findsOneWidget);
    // The bottom nav bar stays visible — pushing within a branch doesn't
    // leave the StatefulShellRoute's IndexedStack.
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('the /route deep link still redirects into the first branch', (
    tester,
  ) async {
    final router = twoTabRouter();
    await tester.pumpWidget(appWithTabs(router));
    await tester.pumpAndSettle();

    router.router.go('/route');
    await tester.pumpAndSettle();

    expect(find.text('Planen-Inhalt'), findsOneWidget);
  });
}
