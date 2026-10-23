import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:trufi_core_interfaces/trufi_core_interfaces.dart';
import 'package:trufi_core_ui/src/l10n/core_localizations.dart';
import 'package:trufi_core_ui/src/router/app_router.dart';

/// fahrplaner.de fork patch (Patch 74, see FAHRPLANER_PATCHES.md) -
/// `AppConfiguration.bottomNavShellBuilder`. Same `_StubScreen`/harness
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
  Widget appWith(AppRouter router) => ChangeNotifierProvider(
    create: (_) => SharedRouteNotifier(),
    child: MaterialApp.router(
      locale: const Locale('en'),
      supportedLocales: CoreLocalizations.supportedLocales,
      localizationsDelegates: CoreLocalizations.localizationsDelegates,
      routerConfig: router.router,
    ),
  );

  testWidgets('shellBuilder replaces bar and rail, receives labels and '
      'switches tabs', (tester) async {
    BottomNavShellData? last;
    final router = AppRouter(
      screens: [
        _StubScreen('a', '/', 'Planen', const Text('Planen-Inhalt')),
        _StubScreen('b', '/b', 'Fahrten', const Text('Fahrten-Inhalt')),
      ],
      bottomNavTabs: const [
        BottomNavTab(icon: Icons.home, screenIds: ['a']),
        BottomNavTab(icon: Icons.bookmark, screenIds: ['b']),
      ],
      useNavigationRail: (_) => true,
      bottomNavShellBuilder: (context, data) {
        last = data;
        return Scaffold(
          body: data.body,
          bottomNavigationBar: Row(
            children: [
              for (var i = 0; i < data.labels.length; i++)
                TextButton(
                  onPressed: () => data.onSelect(i),
                  child: Text('Tab ${data.labels[i]}'),
                ),
            ],
          ),
        );
      },
    );
    await tester.pumpWidget(appWith(router));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Planen-Inhalt'), findsOneWidget);
    expect(last!.labels, ['Planen', 'Fahrten']);
    expect(last!.currentIndex, 0);

    await tester.tap(find.text('Tab Fahrten'));
    await tester.pumpAndSettle();
    expect(find.text('Fahrten-Inhalt'), findsOneWidget);
    expect(last!.currentIndex, 1);
  });
}
