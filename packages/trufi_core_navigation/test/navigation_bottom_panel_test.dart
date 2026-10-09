// fahrplaner.de fork patch (see FAHRPLANER_PATCHES.md, Patch 24):
// NavigationBottomPanel's new, purely additive `actionsBuilder`/`compact`
// parameters. Covers only the new branching - the pre-existing default
// single-button behaviour was already unverified by any test in this
// package before this patch and is left as-is (out of scope here).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trufi_core_navigation/trufi_core_navigation.dart';
import 'package:trufi_core_navigation/src/presentation/widgets/navigation_bottom_panel.dart';
import 'package:trufi_core_navigation/src/presentation/widgets/navigation_instruction_card.dart';

Future<void> pump(
  WidgetTester tester, {
  required NavigationState state,
  Widget Function(BuildContext, VoidCallback)? actionsBuilder,
  bool compact = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: NavigationLocalizations.localizationsDelegates,
      supportedLocales: NavigationLocalizations.supportedLocales,
      home: Scaffold(
        body: NavigationBottomPanel(
          state: state,
          onExitNavigation: () {},
          actionsBuilder: actionsBuilder,
          compact: compact,
        ),
      ),
    ),
  );
}

void main() {
  const stateWithInstruction = NavigationState(
    status: NavigationStatus.navigating,
    currentInstruction: NavigationInstruction(
      type: InstructionType.walkStraight,
    ),
  );

  group('actionsBuilder', () {
    testWidgets('null (Default) zeigt weiterhin den einzelnen Beenden-Knopf', (
      tester,
    ) async {
      await pump(tester, state: stateWithInstruction);

      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets(
      'gesetzt ersetzt den Beenden-Knopf durch eigenen Inhalt und bekommt eine funktionierende onExitNavigation',
      (tester) async {
        await pump(
          tester,
          state: stateWithInstruction,
          actionsBuilder: (context, onExitNavigation) => TextButton(
            onPressed: onExitNavigation,
            child: const Text('Eigene Aktionen'),
          ),
        );

        expect(find.byIcon(Icons.close_rounded), findsNothing);
        expect(find.text('Eigene Aktionen'), findsOneWidget);

        await tester.tap(find.text('Eigene Aktionen'));
        await tester.pumpAndSettle();

        // onExitNavigation() zeigt denselben Bestaetigungsdialog wie der
        // Standard-Knopf (nicht den rohen onExitNavigation-Callback direkt).
        expect(find.byType(AlertDialog), findsOneWidget);
      },
    );
  });

  group('compact', () {
    testWidgets(
      'false (Default) zeigt weiterhin die NavigationInstructionCard',
      (tester) async {
        await pump(tester, state: stateWithInstruction);

        expect(find.byType(NavigationInstructionCard), findsOneWidget);
      },
    );

    testWidgets('true blendet die NavigationInstructionCard komplett aus', (
      tester,
    ) async {
      await pump(tester, state: stateWithInstruction, compact: true);

      expect(find.byType(NavigationInstructionCard), findsNothing);
    });

    testWidgets(
      'true zeigt weiterhin den Beenden-Knopf (nur die Karte entfaellt)',
      (tester) async {
        await pump(tester, state: stateWithInstruction, compact: true);

        expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      },
    );
  });
}
