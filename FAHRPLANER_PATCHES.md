# Fahrplaner-Fork: Patches & Sync-Strategie

Dieser Fork existiert ausschließlich, um zwei Trufi-Core-Lücken zu
schließen, für die es keinen Konfigurationspunkt gibt (siehe
`architektur-konzept.md`, Kapitel 3.13/14 im Hauptprojekt
[jazzcrack/-PNV-Fahrplan-App](https://github.com/jazzcrack/-PNV-Fahrplan-App)
für die vollständige Herleitung). Keine anderen Änderungen gegenüber
Upstream.

## Branch-Struktur

- **`fahrplaner-patches`** – der einzige Branch, den die App tatsächlich
  nutzt (`app/pubspec.yaml` zeigt per Git-Dependency hierher). Erstellt
  als Abzweigung vom upstream-Tag `v5.27.0`, enthält nur die unten
  gelisteten additiven Commits.
- **`main`** – bleibt 1:1 Spiegel von `trufi-association/trufi-core`s
  `main`, wird nie direkt verändert. Dient nur als Referenz für
  `git rebase`.

## Die beiden Patches

### 1. `ChooseOnMapScreen`: "Zu meinem Standort springen"-Button

- Datei: `packages/trufi_core_maps/lib/src/presentation/widgets/choose_on_map_screen.dart`
- Neuer `geolocator`-Abhängigkeit in `packages/trufi_core_maps/pubspec.yaml`.
- Rein additiv: neuer State (`_locating`), neue Methode
  (`_jumpToMyLocation()`), ein neuer Button in der bestehenden Top-Leiste.
  Keine bestehende Signatur geändert.
- Risiko: niedrig, ein Datei, kein Eingriff in öffentliche Schnittstellen.

### 2. "Frühere/spätere Verbindungen"-Pagination

OTP liefert `nextPageCursor`/`previousPageCursor` bereits in der
Response, Trufi Core hat sie nie geparst oder durchgereicht. Betrifft
mehrere Schichten (additiv, keine bestehende Methode wurde entfernt oder
umbenannt):

- `trufi_core_routing`:
  - `Plan`-Modell: zwei neue Felder.
  - `otp_2_8_queries.dart`: `pageCursor`/`nextPageCursor`/
    `previousPageCursor` in beiden Queries (Standard + "simple").
  - `otp_2_8_response_parser.dart`: parst die beiden neuen Felder.
  - `IRoutingProvider.fetchPlan()` + alle vier Implementierungen
    (OTP 1.5/2.4/2.8, offline Trufi-Planner): neuer optionaler
    `pageCursor`-Parameter. Bei OTP 1.5/2.4/offline wird er akzeptiert,
    aber ignoriert (keine Pagination-API dort).
  - `RoutingEngineManager.fetchPlan()`: reicht den Parameter durch.
- `trufi_core_home_screen`:
  - `RequestPlanService` (abstrakt + `RoutingEngineRequestPlanService`):
    derselbe neue Parameter.
  - `RoutePlannerCubit`: neue Methode `loadMoreItineraries({required bool earlier})`.
  - `ItineraryList`: neue "Frühere/Spätere Verbindungen anzeigen"-Buttons
    in `_buildListView` UND `_buildGroupedListView` (Letzteres ist der in
    der echten App aktive Pfad, da `groupedItineraries` immer befüllt
    wird).
  - Neue l10n-Strings (`loadEarlierConnections`/`loadLaterConnections`)
    in `.arb`-Quelldateien UND den generierten `_localizations_*.dart` -
    **wichtig:** nur die `.arb`-Dateien ändern reicht nicht, `flutter
    pub get`/`flutter gen-l10n` überschreibt die generierten Dateien
    sonst beim nächsten Lauf wieder.
  - Drei Test-Mocks (`implements IRoutingProvider`/`RequestPlanService`)
    mussten denselben Parameter ergänzen, sonst kompiliert das Paket
    nicht mehr (Dart verlangt, dass Overrides alle Parameter der
    Interface-Methode übernehmen, auch optionale).
- Risiko: mittel – mehr Dateien, berührt eine von mehreren Implementierungen
  genutzte Schnittstelle, aber rein additiv (neuer optionaler Parameter,
  neue Modellfelder) – keine bestehenden Aufrufer brechen.

Beide Patches sind per `dart analyze` (keine neuen Fehler) und den
bestehenden Testsuiten von `trufi_core_maps`, `trufi_core_routing` und
`trufi_core_home_screen` verifiziert (alle grün, inkl. der schon
vorhandenen `choose_on_map_tap_test.dart`, die exakt den gepatchten
Screen testet).

## Sync-Strategie: wie künftige Upstream-Änderungen reinkommen

Ziel: Trufi-Core-Updates (neue Features, Bugfixes) weiter bekommen,
ohne die beiden Patches jedes Mal von Hand neu zu schreiben.

**Grundprinzip:** `fahrplaner-patches` wird nie direkt weiterentwickelt,
sondern bei jedem gewünschten Upstream-Update komplett neu auf den
neuen Tag reba­siert:

```bash
git fetch upstream --tags
git checkout fahrplaner-patches
git rebase <neuer-upstream-tag>   # z. B. v5.28.0
```

Da beide Patches rein additiv sind (neue Dateien/Felder/optionale
Parameter, keine Änderung bestehender Signaturen), sind Konflikte beim
Rebase unwahrscheinlich – im Normalfall betrifft ein Upstream-Update
andere Zeilen als die wenigen, die hier geändert wurden.

**Automatisierter Teil (GitHub Action):**
`.github/workflows/check-upstream-sync.yml` in diesem Fork läuft
wöchentlich und bei manuellem Anstoß:
1. Holt die neuesten Tags von `trufi-association/trufi-core`.
2. Vergleicht den neuesten Tag mit dem, den `fahrplaner-patches` aktuell
   als Basis hat (`git merge-base`).
3. Bei einem neueren Tag: versucht den Rebase automatisch in einem
   Wegwerf-Branch. Klappt er sauber durch, laufen `dart analyze` +
   die Testsuiten der drei betroffenen Pakete automatisch mit.
4. Nur bei **vollem Erfolg** (Rebase + Analyze + Tests grün): öffnet
   einen Pull Request `fahrplaner-patches` ← `sync/v5.28.0` mit den
   Ergebnissen im PR-Text.
5. Bei einem Konflikt oder fehlgeschlagenen Tests: **kein PR**,
   stattdessen ein GitHub Issue mit der genauen Fehlermeldung.

**Gesteuerter Teil (durch Claude/den Entwickler):** Der PR wird nie
automatisch gemerged. Stattdessen:
- Claude (oder der Entwickler) prüft den PR, liest das Upstream-Changelog
  des neuen Tags kurz gegen, merged bei Unauffälligkeit.
- Nach dem Merge: `app/pubspec.yaml`s `ref:` für `trufi_core_maps` und
  `trufi_core_routing`/`trufi_core_home_screen` auf den neuen Commit-Hash
  von `fahrplaner-patches` aktualisieren, `flutter pub get` + die
  bestehende App-Testsuite laufen lassen.
- Bei einem gemeldeten Issue (Rebase-Konflikt): Claude löst den Konflikt
  manuell, da die Patches klein genug sind, um das schnell von Hand zu
  prüfen.

Diese Kombination (Mechanik automatisch, Freigabe/Merge-Entscheidung
weiterhin bewusst getroffen) vermeidet sowohl "nie wieder upstream
aktualisiert" als auch "unbeaufsichtigt gemergter Rebase bricht etwas".
