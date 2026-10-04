# Fahrplaner-Fork: Patches & Sync-Strategie

Dieser Fork existiert ausschließlich, um Trufi-Core-Lücken zu
schließen, für die es keinen Konfigurationspunkt gibt (siehe
`architektur-konzept.md` im Hauptprojekt
[jazzcrack/-PNV-Fahrplan-App](https://github.com/jazzcrack/-PNV-Fahrplan-App),
Kapitel 3.13/14/18–3.26 für die vollständige Herleitung jedes einzelnen
Patches). Keine anderen Änderungen gegenüber Upstream. Stand: zwölf
Patches (zuletzt aktualisiert 04.10.2026, Kapitel 3.26).

## Branch-Struktur

- **`fahrplaner-patches`** – der einzige Branch, den die App tatsächlich
  nutzt (`app/pubspec.yaml` zeigt per Git-Dependency hierher). Erstellt
  als Abzweigung vom upstream-Tag `v5.27.0`, enthält nur die unten
  gelisteten additiven Commits.
- **`main`** – bleibt 1:1 Spiegel von `trufi-association/trufi-core`s
  `main`, wird nie direkt verändert. Dient nur als Referenz für
  `git rebase`.

## Die zwölf Patches

| # | Thema | Pakete | Risiko |
|---|---|---|---|
| 1 | `ChooseOnMapScreen`-Standortbutton | `trufi_core_maps` | niedrig |
| 2 | "Früher/später"-Pagination | `trufi_core_routing`, `trufi_core_home_screen` | mittel |
| 3 | Verspätungsanzeige (Ergebnisliste) | `trufi_core_routing` | mittel |
| 4 | Freundliche Netzwerkfehler-Meldung | `trufi_core_home_screen` | niedrig |
| 5 | Verspätungsanzeige (aktive Navigation) | `trufi_core_navigation` | niedrig |
| 6 | Kartentyp-Auswahl ausblendbar | `trufi_core_home_screen`, `trufi_core_settings` | niedrig |
| 7 | `SharedRoute` mit nullable Ziel | `trufi_core_interfaces`, `trufi_core_home_screen` | niedrig |
| 8 | Live-Verspätungen für die Abfahrtstafel | `trufi_core_routing` | niedrig (additiver Optional-Hook) |
| 9 | Auswahl entkoppelt, Teilen auf Detailseite | `trufi_core_home_screen` | niedrig |
| 10 | Attribution-Button-Position konfigurierbar | `trufi_core_maps` | niedrig |
| 11 | GBFS-Sharing-Filter ("Nur Leihrad"/"Kein Sharing") | `trufi_core_routing`, `trufi_core_routing_ui`, `trufi_core_home_screen` | niedrig (additiver Optional-Hook) |
| 12 | `tripPatternId` aus `pattern.id` statt `pattern.code` | `trufi_core_routing` | niedrig (Bugfix, ein Feldwert) |

Patches 1–5 sind in den commit-Historien der ersten Fork-Runden
(Kapitel 3.18–3.19 im Hauptprojekt) im Detail dokumentiert, hier nur
tabellarisch zusammengefasst, um diese Datei kompakt zu halten.
Patches 6–11 (Kapitel 3.21–3.23) im Detail:

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

### 3. Verspätungsanzeige (Ergebnisliste)

`Leg.departureDelay`/`arrivalDelay` (aus OTPs `start.estimated.delay`/
`end.estimated.delay`), `Itinerary.overallArrivalDelay`-Getter,
`otp_2_8_response_parser.dart` parst beide Felder zusätzlich zum
`fromJson()`-Pfad (die aktive OTP-2.8-Provider-Implementierung baut
`Leg` direkt, nicht über `fromJson()`). Rein additiv.

### 4. Freundliche Netzwerkfehler-Meldung

`RoutePlannerCubit._isNetworkError()`-Heuristik (textbasiert, da keine
gemeinsame Exception-Hierarchie über alle Routing-Provider existiert)
mappt Verbindungsfehler auf einen neuen `networkErrorKey` statt
`e.toString()` 1:1 anzuzeigen.

### 5. Verspätungsanzeige (aktive Navigation)

`NavigationLeg.arrivalDelay`-Feld, `ItineraryConverter.toNavigationRoute()`
reicht `leg.arrivalDelay` durch. Schließt die Lücke, dass Patch 3 nur
die Ergebnisliste erreichte, nicht die aktive Navigation (eigenes,
einfacheres `NavigationLeg`-Modell).

### 6. Kartentyp-Auswahl ausblendbar

`HomeScreenConfig.showMapTypeButton` (neuer Parameter, Default `true`)
blendet den schwebenden Kartentyp-Button auf der Karte aus;
`SettingsTrufiScreen.showMapSettings` (Default `true`) blendet die
Kartenstil-Karte in den Einstellungen aus, `.extraSections` (neuer
Parameter, `List<Widget Function(BuildContext)>`, Default `[]`) lässt
eine Host-App eigene Abschnitte anhängen, ohne das interne Layout von
`_SettingsContent` zu forken. Alle drei additiv.

### 7. `SharedRoute` mit nullable Ziel

`SharedRoute.toLat`/`toLng`/`toName` sind jetzt `double?`/`String?`
statt `required`. `HomeScreenTrufiScreen._onSharedRouteChanged()` setzt
bei fehlendem Ziel nur `fromPlace` und ruft `fetchPlan()` nicht auf -
lässt eine Host-App "nur den Start übergeben, Ziel wählt der Nutzer
selbst" umsetzen. `fromUri()` (Deep-Link-Parsing) verlangt weiterhin
alle sechs Parameter - nur der programmatische `SharedRouteNotifier`-Pfad
profitiert von der Lockerung.

### 8. Live-Verspätungen für die Abfahrtstafel

`IRoutingProvider.fetchLiveStopDelays(String stopId)` ist eine neue,
NICHT-abstrakte Methode mit Default-Implementierung `=> null` (exakt
wie das bestehende `realtimeVehiclesProvider`-Muster) - kein Zwang zur
Umsetzung in den anderen drei Providern. `Otp28RoutingProvider`
überschreibt sie: neue `stoptimesWithoutPatterns`-GraphQL-Query (Schema
live gegen den echten OTP-Source auf GitHub verifiziert), liefert eine
`trip_id -> Duration`-Map (Feed-Präfix per `stripGtfsFeedPrefix`
entfernt). Neuer, optionaler `feedId`-Konstruktorparameter auf
`Otp28RoutingProvider` (Default `null` = Feature aus). Reine
Parsing-Logik (`parseLiveStopDelays()`) als eigene, testbare
Top-Level-Funktion ausgelagert.

### 9. Auswahl entkoppelt, Teilen auf Detailseite

`itinerary_list.dart`: die beiden `onTap`-Handler in der Ergebnisliste
rufen `cubit.selectItinerary()` nicht mehr auf - Details ansehen ändert
nicht mehr die dauerhaft markierte/geteilte Verbindung.
`ItineraryList.onShare`/`ItineraryDetailContent.onShare` sind neue,
optionale Callbacks; ein neuer Share-Button sitzt jetzt auf der
Detailseite der jeweiligen Verbindung. Die beiden alten, mehrdeutigen
Teilen-Buttons (Listen-Kopfzeile, Zusammenfassungs-Leiste) in
`home_screen.dart` sind entfernt, ihre Logik in eine gemeinsame
`_shareItinerary()`-Methode extrahiert.

### 10. Attribution-Button-Position konfigurierbar

`ITrufiMapEngine.buildMap()` bekommt einen neuen, additiven
`attributionButtonMargin`-Parameter (`Offset?`), durchgereicht durch
`MapLibreEngine`/`OfflineMapLibreEngine`/`TrufiMap` bis zu
`MapLibreMap.attributionButtonMargins` (dort `Point<double>`). Beide
Engine-Implementierungen sowie der Test-Fake und die Beispiel-App
mussten den Parameter ergänzen (Dart-Override-Regel, siehe Patch 2).

### 11. GBFS-Sharing-Filter ("Nur Leihrad" / "Kein Sharing")

- `TransportMode.scooter` (neuer Enum-Wert, `trufi_core_routing`) +
  `Leg.isRentedVehicle` (abgeleiteter Getter, kein neues Feld/keine
  Query-Änderung - `rentedBike == true || mode == scooter`).
- `TransportMode.scooter`-Icon (`Icons.electric_scooter_rounded`) +
  RENT-Qualifier-Eintrag in `trufi_core_routing_ui/transport_mode_ui.dart`.
- Neuer `RentalFormFactor`-Enum (`bicycle`, `scooter`) + reine Funktion
  `buildTransportModesVariable()` in `otp_28_preferences.dart`, die
  OTPs `qualifier: RENT`-Mechanismus nutzt - bei leerem
  `rentalFormFactors` (Default) byte-für-byte identisch zur alten
  `.map((m) => {'mode': m.otpName})`-Ausgabe.
- `Otp28PreferencesState` bekommt ein neues, unabhängig persistiertes
  `rentalFormFactors`-Feld (Default leer, opt-in) + `setRentalFormFactors()`/
  `toggleRentalFormFactor()`, gleiches Muster wie `transportModes`.
- `Otp28RoutingProvider`: neuer `availableRentalFormFactors`-Konstruktor-
  Parameter (Default `{RentalFormFactor.bicycle}`, additiv), minimaler
  öffentlicher Zugriff (`rentalFormFactors`-Getter + `setRentalFormFactors()`,
  nicht das ganze `_prefs`-Objekt).
- Neue additive `IRoutingProvider.buildQuickFilterChips(context, {onChanged})`-
  Methode (`routing_provider.dart`, Default `null` - gleiches Muster wie
  `buildPreferencesUI`) für eine immer sichtbare Chip-Reihe, statt im
  Routeneinstellungen-Sheet versteckt. `onChanged` wird sofort nach einem
  Chip-Tap aufgerufen (kein Apply-Button wie bei `buildPreferencesUI`),
  damit der Aufrufer die Route neu laden kann.
- `home_screen.dart` rendert die Chip-Reihe generisch neben dem
  bestehenden Abfahrtszeit-Chip, kein `is Otp28RoutingProvider`-Check.
- Nebenbei: `restored_plan_map_test.dart`s `_FakeEngine.buildMap()` fehlte
  der `attributionButtonMargin`-Parameter aus Patch 10 (dort wurden nur
  `choose_on_map_tap_test.dart` und die Beispiel-App aktualisiert, diese
  Testdatei übersehen) - beim Durcharbeiten dieses Patches aufgefallen
  und ergänzt.
- **Bewusster Scope-Cut:** keine Erweiterung auf OTPs moderne
  `rentalVehicle`/`FormFactor`-Query-Felder in dieser Runde (keine echten
  Free-Floating-/Scooter-Daten zum Testen vorhanden, da der einzige
  aktuell laufende GBFS-Feed - nextbike Bremen - ein stationsbasiertes
  Leihrad-System ist). Folgepunkt für eine spätere Runde, sobald ein
  echter Scooter-/Free-Floating-Feed existiert.

### 12. `tripPatternId` aus `pattern.id` statt `pattern.code`

Echter Upstream-Bug (Kommit `f0eb93c5`, 06.02.2026, vor unserem Fork):
`otp_2_8_response_parser.dart` befüllte `Leg.tripPatternId` aus OTPs
`pattern.code` statt `pattern.id`. `fetchTransitRouteById()` fragt
anschließend `pattern(id: $id)` ab (`otp_28_routing_provider.dart`) -
mit einem `code`-Wert statt der echten GraphQL-ID schlägt diese Abfrage
für OTP 2.8 **immer** fehl. Betrifft eine Kernfunktion: Antippen einer
Linienbadge in einer Verbindung (`itinerary_detail_screen.dart`s
`_handleRouteTap`) zeigte „Linie nicht gefunden" statt des
Liniendetails - von einem echten Nutzer per TestFlight-Feedback
gemeldet.

- `otp_2_8_queries.dart`: `pattern { code }` → `pattern { id code }`
  (additiv, `code` bleibt für evtl. andere Konsumenten erhalten).
- `otp_2_8_response_parser.dart`: `tripPatternId` liest jetzt
  `pattern.id` statt `pattern.code`.
- Blast-Radius geprüft: `tripPatternId` wird nirgends sonst gelesen
  (nur `_handleRouteTap`, reine Lookup-ID, nie angezeigt) - die
  Offline-Variante (`trufi_planner_provider.dart`) befüllt das Feld
  bereits korrekt mit einem eigenen, funktionierenden Format und ist
  von diesem Patch nicht betroffen.

Alle zwölf Patches sind per `dart analyze` (keine neuen Fehler) und den
bestehenden Testsuiten der jeweils betroffenen Pakete verifiziert
(alle grün, inkl. neuer Tests für Patches 8/10/11/12).

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
