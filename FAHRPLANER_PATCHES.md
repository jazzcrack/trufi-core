# Fahrplaner-Fork: Patches & Sync-Strategie

Dieser Fork existiert ausschließlich, um Trufi-Core-Lücken zu
schließen, für die es keinen Konfigurationspunkt gibt (siehe
`architektur-konzept.md` im Hauptprojekt
[jazzcrack/-PNV-Fahrplan-App](https://github.com/jazzcrack/-PNV-Fahrplan-App),
Kapitel 3.13/14/18–3.45 für die vollständige Herleitung jedes einzelnen
Patches). Keine anderen Änderungen gegenüber Upstream. Stand:
dreiundzwanzig Patches (zuletzt aktualisiert 08.10.2026, Kapitel 3.44/3.45).

## Branch-Struktur

- **`fahrplaner-patches`** – der einzige Branch, den die App tatsächlich
  nutzt (`app/pubspec.yaml` zeigt per Git-Dependency hierher). Erstellt
  als Abzweigung vom upstream-Tag `v5.27.0`, enthält nur die unten
  gelisteten additiven Commits.
- **`main`** – bleibt 1:1 Spiegel von `trufi-association/trufi-core`s
  `main`, wird nie direkt verändert. Dient nur als Referenz für
  `git rebase`.

## Die dreiundzwanzig Patches

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
| 13 | "Mehr laden": chronologische Sortierung + größere Seite | `trufi_core_home_screen` | niedrig (additiver Parameter + lokaler Sort) |
| 14 | Onboarding: Kartenstil-Auswahl ausblendbar | `trufi_core_settings` | niedrig (additiver Optional-Parameter) |
| 15 | Attribution-Button: echte Eckenwahl statt nur Marge (+ Compile-Fix) | `trufi_core_maps`, `trufi_core_transport_list` | niedrig (additiver Optional-Parameter + nachgezogener Testfix) |
| 16 | Los-Button auf jeder Verbindungskarte, nicht nur der hervorgehobenen | `trufi_core_home_screen` | niedrig (Bedingung gelockert, kein neuer Zustand) |
| 17 | "Fahrt merken"-Callback auf der Itinerary-Detailansicht | `trufi_core_home_screen` | niedrig (additiver Optional-Callback) |
| 18 | `SearchLocationType`: optisch unterscheidbare Trefferliste | `trufi_core_search_locations` | niedrig (additives Enum-Feld + zwei neue Icon-Zuordnungen) |
| 19 | `NavigationState.copyWith`: `distanceFromRoute`-Nullable-Bug behoben | `trufi_core_navigation` | niedrig (additiver Sentinel-Parameter, kein aktueller UI-Konsument betroffen) |
| 20 | `Leg.tripId` + `NavigationStop.gtfsStopId` + `refreshCurrentLegDelay()` | `trufi_core_routing`, `trufi_core_navigation` | niedrig (additive Felder + neue Methode, keine bestehende Signatur geändert) |
| 21 | iOS: Standort-Tracking laeuft auch bei gesperrtem Bildschirm weiter | `trufi_core_utils` | niedrig (iOS-Zweig in einer privaten Hilfsmethode, Android/Web unverändert) |
| 22 | Ausfall-Erkennung: `Itinerary.hasCanceledLeg` + `NavigationLeg.isCanceled` | `trufi_core_routing`, `trufi_core_navigation`, `trufi_core_home_screen` | niedrig (additiver Getter/Feld + neues Badge, keine bestehende Signatur geändert) |
| 23 | Redesign Phase A Teil 2: `_DelayBadge` durch `RealtimeChip` ersetzt | `trufi_core_home_screen` | niedrig (1:1-Ersatz eines privaten Widgets, keine Signaturaenderung an `ItineraryCard`) |

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

### 13. "Mehr laden": chronologische Sortierung + größere Seite

Zwei Teile desselben TestFlight-Reports ("immer maximal 5
Verbindungen ... mit großen zeitlichen Lücken"):

- **Unsortierte Reihenfolge:** `fetchPlan()` sortiert jede Antwort per
  `sortByGeneralizedCost()` nach OTPs Generalized Cost statt nach Zeit
  (`otp_28_routing_provider.dart`, begründet mit #849/#847 - für eine
  einzelne Suche gewollt: "beste Option zuerst"). `loadMoreItineraries()`
  (`route_planner_cubit.dart`) mergte eine zweite, unabhängig
  kostensortierte Seite per simpler Listenkonkatenation - die
  chronologische Reihenfolge der kombinierten Liste ging dabei verloren
  (live gemeldet: 03:04 → 05:06 → 03:20 → 07:45 → 11:18). Fix: nach dem
  Merge wird explizit nach `Itinerary.startTime` sortiert - nur in
  diesem Pagination-Pfad, die Kostensortierung der Erstsuche bleibt
  unverändert (`groupItineraries()` behält die eingehende Reihenfolge
  bei, siehe dessen eigener Doc-Kommentar - der Fix muss also vor der
  Gruppierung greifen, tut er, da `loadMoreItineraries()` erst mergt+
  sortiert und danach `_groupPlanItineraries()` aufruft).
- **Immer nur 5:** `fetchPlan()`s `numItineraries`-Parameter (Default 5,
  für die Erstsuche gedacht) wurde von `RequestPlanService` nie
  durchgereicht - jeder Aufruf (Erstsuche UND "mehr laden") fiel auf
  denselben Wert zurück. Jetzt additiv durch `RequestPlanService` →
  `RoutingEngineRequestPlanService` gezogen; `loadMoreItineraries()`
  fordert explizit `loadMoreItinerariesPageSize` (10) an, die Erstsuche
  bleibt unverändert bei 5.
- Drei Test-Fakes (`implements RequestPlanService`) mussten den neuen
  Parameter ergänzen (gleiches Dart-Override-Muster wie Patch 2/10).
- Neue Unit-Tests (`route_planner_load_more_test.dart`): simulieren
  zwei unabhängig kostensortierte Seiten und prüfen, dass die gemergte
  Liste chronologisch ist; prüfen, dass `numItineraries` nur bei "mehr
  laden" gesetzt wird, nicht bei der Erstsuche.
- Bewusst NICHT verändert: die bestehende Integration-Test-Datei
  `itinerary_pagination_test.dart` (App-Repo) - die prüft bereits
  bewusst den Request-Flow, nicht die Kartenanzahl (siehe deren eigener
  Kommentar), bleibt also gültig.

### 14. Onboarding: Kartenstil-Auswahl ausblendbar

Nutzer-Feedback (04.10.2026): Im Onboarding-Dialog (`OnboardingSheet`)
fragt `_OnboardingMapSection` eine Kartenstil-Auswahl (Hell/Dunkel) ab,
die seit der Dark-Mode-Kopplung des Kartenstils (`_mapDarkModeSync` in
`main.dart`, überschreibt den Stil bei jedem Rebuild anhand der
effektiven Helligkeit) rein kosmetisch wirkungslos ist - dieselbe
Begründung, aus der die Einstellungen-Karte bereits per Patch 6
(`SettingsTrufiScreen.showMapSettings`) und der schwebende
Kartentyp-Button bereits app-seitig ausgeblendet sind. Die
Onboarding-Sektion wurde dabei übersehen.

`OnboardingSheet` bekommt einen neuen, additiven `showMapSection`-
Parameter (Default `true`, Upstream-Verhalten unverändert) - exakt
dasselbe additive Muster wie Patch 6s `showMapSettings`. Guard um
`_OnboardingMapSection` in `_buildContent()`, keine Pagination-/Index-
Logik betroffen (der Dialog ist eine einzelne scrollbare Spalte, keine
Multi-Page-Sequenz mit Zählern/Punkten).

Kein eigener Test: `trufi_core_settings` hatte bisher keine
Test-Infrastruktur (kein `test/`-Verzeichnis), ein neues Harness nur für
diesen einen additiven Boolean-Guard wäre unverhältnismäßig - analog zu
Patch 6, der aus demselben Grund ebenfalls ohne dedizierten Test blieb.

### 15. Attribution-Button: echte Eckenwahl statt nur Marge (+ Compile-Fix)

Echter Nutzer-Fund (04.10.2026): Patch 10 (Kapitel 3.21) verschob das
native Attribution-Steuerelement per `attributionButtonMargin` nur
INNERHALB seiner Standard-Ecke (unten rechts). Eine Margin-Schätzung
(`Offset(8, 220)`, nie am Gerät gemessen) sollte es über ein
raumfüllendes Navigations-Panel heben - blieb am echten Gerät aber
weiterhin verdeckt (App-seitig jetzt auf eine andere Ecke umgestellt,
siehe Hauptprojekt-Kapitel 3.32).

- Neuer additiver Parameter `attributionButtonPosition`
  (`AttributionButtonPosition?`, Default `null` = unveränderte
  Standard-Ecke) auf `ITrufiMapEngine.buildMap()` - nativ in
  `maplibre_gl` bereits als `MapLibreMap.attributionButtonPosition`
  vorhanden (iOS: `MLNMapView.attributionButtonPosition`, Android:
  `Gravity`-Mapping), bisher nur nie durchgereicht.
- Durchgereicht durch `MapLibreEngine`/`OfflineMapLibreEngine`/
  `TrufiMap` bis zur eigentlichen `MapLibreMap(...)`-Konstruktion,
  gleiches additive Muster wie Patch 10.
- Alle Implementierungen/Fakes von `ITrufiMapEngine.buildMap()`
  mussten den neuen Parameter ergänzen (Dart-Override-Regel, siehe
  Patch 2/10): `FlutterMapEngine` (Beispiel-App),
  `FakeEngine`/`_FakeEngine` in drei verschiedenen Testdateien.
- **Nebenbei gefunden und behoben:** `transport_detail_copy_test.dart`
  (`trufi_core_transport_list`) fehlte bereits beim zehnten Fork-Patch
  der damals neue `attributionButtonMargin`-Parameter - ein echter
  Compile-Fehler (`invalid_override`), der seitdem unbemerkt blieb
  (per `git stash` bestätigt: bestand bereits vor diesem Patch 15).
  Dessen komplette Testsuite (`trufi_core_transport_list`, 29 Tests)
  lief seit Kapitel 3.21 vermutlich nie mehr grün durch - jetzt
  behoben und verifiziert.

### 16. Los-Button auf jeder Verbindungskarte, nicht nur der hervorgehobenen

Nutzer-Rückfrage (04.10.2026): „Macht es Sinn, dass eine Fahrt hervorgehoben
ist?" - beantwortet (Hauptprojekt-Kapitel 3.33): ja, die Hervorhebung
markiert die per `sortByGeneralizedCost` objektiv beste Verbindung (z. B.
gleiche Ankunftszeit bei deutlich weniger Fußweg). Dabei aber entdeckt:
der Los-Button war an `isSelected` gekoppelt, obwohl `onStartNavigation`
in `itinerary_list.dart` schon vorher pro Karte an die JEWEILIGE
Itinerary gebunden wird (`onStartNavigation: () => widget
.onStartNavigation!(context, face/itinerary, ...)`, nicht nur an die
ausgewählte). Nicht hervorgehobene Karten waren damit technisch bereits
sofort startbar, zeigten aber keinen Button dafür - der einzige Weg war
der Umweg über die Detailansicht. Auf Nutzer-Wunsch behoben.

- `itinerary_card.dart`: Bedingung von `if (isSelected &&
  onStartNavigation != null)` auf `if (onStartNavigation != null)`
  gelockert - kein neuer Zustand, keine neue Schnittstelle, nur eine
  Anzeigebedingung. Die Hervorhebung (Rahmen/Hintergrund) bleibt die
  alleinige visuelle Markierung der Empfehlung.
- Zwei neue Widget-Tests (`itinerary_card_go_button_test.dart`): eine
  nicht hervorgehobene Karte zeigt trotzdem einen funktionierenden
  Los-Button; eine hervorgehobene Karte OHNE `onStartNavigation`-
  Callback zeigt weiterhin nur das Auswahl-Häkchen (Regressionsschutz
  für den verbleibenden Zweig).

### 17. "Fahrt merken"-Callback auf der Itinerary-Detailansicht

Echter Nutzer-Wunsch, wiederholt genannt (05.10.2026, Hauptprojekt
Kapitel 3.36): konkrete Fahrten speichern (Linien + Abfahrtszeit), nicht
nur Start/Ziel-Paare. Der eigentliche Speicher-Mechanismus lebt in der
App (`SavedTripsManager`, app-eigene Persistenz) - dieser Patch liefert
nur den fehlenden Haken dafür im Fork.

- Neuer additiver `onSaveTrip`-Callback auf `ItineraryDetailContent`/
  `ItineraryDetailScreen` (`void Function(routing.Itinerary)?`,
  kontextlos - dieselben Widgets haben ohnehin einen eigenen
  `BuildContext`), durchgereicht über `ItineraryList` bis zu
  `HomeScreenConfig`/`HomeScreenTrufiScreen` - anders als `onShare`
  (bleibt komplett fork-intern, ruft `ShareRouteService` selbst auf)
  MUSS dieser Callback die Host-App erreichen.
- **Nachgebessert (derselbe Tag):** Auf `HomeScreenTrufiScreen`/
  `HomeScreen` selbst ist die Signatur `void Function(BuildContext,
  routing.Itinerary)?`, analog zu `onRouteTap` - die App baut ihre
  `screens:`-Liste ohne eigenen `BuildContext`, ein reiner
  `VoidCallback`-Stil haette sich dort nicht sinnvoll anschliessen
  lassen (z. B. keine SnackBar-Bestaetigung ohne Context). Erst beim
  echten Verdrahtungsversuch in `main.dart` aufgefallen - `home_screen
  .dart` faengt seinen eigenen `context` ab und reicht ihn durch, die
  Leaf-Ebene (`ItineraryDetailContent`/`-Screen`, `ItineraryList`)
  blieb unveraendert kontextlos.
- Zeigt einen Bookmark-Button neben dem bestehenden Share-Button, auf
  derselben Detailansicht (eindeutig, welche Itinerary - gleicher Grund
  wie bei `onShare`).
- Drei neue Widget-Tests (`itinerary_detail_save_trip_test.dart`):
  Button sichtbar + ruft Callback auf, wenn gesetzt; Button ausgeblendet
  ohne Callback - für beide Widgets (`ItineraryDetailContent` und
  `ItineraryDetailScreen`).

### 18. `SearchLocationType`: optisch unterscheidbare Trefferliste

Echter Nutzer-Wunsch (05.10.2026, Hauptprojekt Kapitel 3.37): "wäre es
schön wenn bei Suchergebnissen auf optisch klar zwischen den
unterschiedlichen Ortsarten unterschieden würde (z.B. Haltestelle, POI,
Straße)". Teil eines größeren Suchverbesserungs-Pakets (siehe Kapitel
3.37 im Hauptprojekt) - dieser Patch liefert nur den Baustein, der im
Fork leben muss: das Datenmodell und die Icon-Zuordnung.

- Neues additives Enum `SearchLocationType` (`stop`/`poi`/`street`/
  `address`) + neues optionales Feld `SearchLocation.locationType` -
  Dienste, die es (noch) nicht befüllen, verhalten sich unverändert
  (`null` = generisches Pin-Icon wie zuvor).
- `PhotonSearchService._parseFeature()` befüllt es jetzt aus Photons
  eigenem `osm_key`/`osm_value`-Paar (ein neuer privater
  `_locationTypeFromOsmTag()`-Mapper, bewusst grob statt die volle
  OSM-Tag-Vielfalt abzubilden).
- `location_search_screen.dart`: das Trefferlisten-Icon zeigt jetzt
  `directions_bus_rounded`/`storefront_rounded`/`add_road_rounded`/
  `place_rounded` je nach `locationType`, statt wie bisher immer nur
  Pin oder Verzweigungs-Icon.
- Die App-seitige Befüllung für Nominatim (`PatchedNominatimSearchService`,
  liest Nominatims `class`/`type`/`addresstype`-Felder) lebt bewusst
  NICHT in diesem Fork, sondern direkt in der App (kein Upstream-Code
  betroffen) - siehe Kapitel 3.37.
- Neue Tests: `test/unit/photon_search_service_test.dart` (6 neue Fälle
  für `locationType`), `test/widget/location_type_icons_test.dart` (neu,
  prüft alle vier unterscheidbaren Icons in einer echten Trefferliste).

### 19. `NavigationState.copyWith`: `distanceFromRoute`-Nullable-Bug behoben

Gefunden beim Schreiben eines Navigations-Szenario-Tests im Hauptprojekt
(05.10.2026, Kapitel 3.38) - kein von einem echten Nutzer gemeldeter Bug,
sondern eine durch den neuen automatisierten Test aufgedeckte, bis dahin
folgenlose Dateninkonsistenz (aktuell liest keine App-UI
`distanceFromRoute`).

- `copyWith(distanceFromRoute: null)` kam nie an: `null ?? this
  .distanceFromRoute` liefert unverändert den alten Wert zurück -
  klassischer copyWith-Nullable-Bug. Betraf konkret
  `NavigationCubit._checkOffRoute()`s "zurück auf der Route"-Zweig
  (`isOffRoute` sprang korrekt auf `false`, `distanceFromRoute` blieb
  aber auf dem letzten Abweichungswert stehen) sowie die bis dahin
  nirgends aufgerufene `NavigationState.clearError()`.
- Neuer additiver `clearDistanceFromRoute`-Parameter (Default `false`)
  auf `copyWith` statt des unwirksamen `null`-Arguments, an beiden
  Aufrufstellen nachgezogen.
- Neue Tests: `test/navigation_state_copy_with_test.dart` (4 neue Fälle,
  inkl. Regressionstest für genau dieses Verhalten).

### 20. `Leg.tripId` + `NavigationStop.gtfsStopId` + `refreshCurrentLegDelay()`

Echter Nutzer-Fund (06.10.2026, Hauptprojekt Kapitel 3.39, waehrend
einer tatsaechlichen Fahrt gemeldet): "Bus hat gerade 4 Minuten
Verspaetung ... wird in meiner App nicht angezeigt". Ursache:
`arrivalDelay` wird nur EINMALIG bei `ItineraryConverter
.toNavigationRoute()` gesetzt (beim Start der Navigation), niemals
danach vom Cubit aktualisiert - eine erst waehrend der Fahrt
entstehende oder wachsende Verspaetung blieb dadurch fuer die gesamte
Fahrtdauer unsichtbar (Live Activity UND das Abschnitt-Detail-Sheet
lesen denselben statischen Wert). Zusaetzliches Problem: den fuer
einen Live-Refresh noetigen GTFS-Trip-/Halt-IDs fehlten komplett -
`trip.gtfsId` wurde in der Query zwar schon angefragt, aber nirgends
in ein Modellfeld uebernommen.

- `trufi_core_routing`: neues additives `Leg.tripId` (`String?`),
  geparst aus OTP's `trip.gtfsId` (Feld war schon Teil der Query,
  wurde nur nie gelesen). Inkl. `toJson()`/`fromJson()`/`copyWith()`.
- `trufi_core_navigation`: `NavigationLeg.tripId` und
  `NavigationStop.gtfsStopId` (beide additiv), von
  `ItineraryConverter.toNavigationRoute()` aus den entsprechenden
  `routing.Leg`/`routing.Place`-Feldern befuellt.
- Neue `NavigationCubit.refreshCurrentLegDelay(Duration? arrivalDelay)`:
  reiner Daten-Setter, ersetzt gezielt nur das Leg an
  `state.currentLegIndex` (per direkter Neukonstruktion, nicht per
  `copyWith`, um keinen weiteren Nullable-Bug wie bei Patch 19 zu
  riskieren - der Parameter ist bewusst REQUIRED, nicht optional).
  Das Paket selbst fragt nichts nach - das periodische Nachfragen (per
  `IRoutingProvider.fetchLiveStopDelays()`) ist App-Ebene
  (`navigation_map.dart`, alle 60 Sekunden waehrend aktiver
  Navigation, siehe Hauptprojekt-Kommentar dort).
- Neue Tests: `test/navigation_cubit_refresh_delay_test.dart` (3 neue
  Faelle), `test/itinerary_converter_delay_test.dart` (1 neuer Fall
  fuer tripId/gtfsStopId-Weitergabe),
  `trufi_core_routing/test/unit/trip_id_parsing_test.dart` (3 neue
  Faelle inkl. JSON-Rundreise).

### 21. iOS: Standort-Tracking läuft auch bei gesperrtem Bildschirm weiter

Drei echte TestFlight-Rückmeldungen am selben Tag (06.10.2026, Hauptprojekt
Kapitel 3.40), alle auf dieselbe Ursache zurückgeführt: eingefrorener
Streckenfortschritt/nächste Haltestelle ("nur beim Wiederaufrufen des
Sperrbildschirms sollte es eine Aktualisierung geben" - tat es aber
nicht), ein verschwindender blauer GPS-Punkt, eingefrorene
Verbindungsdetails während der Fahrt.

- `LocationService.startTracking()` nutzte ein plattformneutrales
  `LocationSettings`. Im nativen `PositionStreamHandler`
  (`geolocator_apple`) kam dadurch nie ein
  `allowBackgroundLocationUpdates`-Schlüssel an -
  `NSNumber?.boolValue` bei `nil` ist in Objective-C `NO`. Trotz
  `UIBackgroundModes: location` in der `Info.plist` wurde
  GPS-Tracking beim Sperren des Bildschirms faktisch eingestellt.
- Neue private `_buildTrackingSettings()`: auf iOS jetzt
  `AppleSettings(allowBackgroundLocationUpdates: true,
  pauseLocationUpdatesAutomatically: false)` statt des generischen
  `LocationSettings`. `defaultTargetPlatform` statt `dart:io`s
  `Platform.isIOS`, damit das plattformübergreifende Paket (inkl.
  Web) kompilierbar bleibt - dieselbe Wahl wie Geolocators eigene
  `Geolocator.getCurrentPosition()`-Fassade.
- Erfordert weiterhin nur "When In Use"-Berechtigung, keine Änderung
  an der bewussten Kapitel-11-Entscheidung gegen "Immer"-Zugriff - die
  bereits laufende Live Activity erfüllt die von iOS geforderte
  sichtbare Standortnutzung im Hintergrund.
- Erster Fork-Patch an `trufi_core_utils` (bis dahin einziges noch nie
  geforktes Paket).
- Neue Tests: zwei neue Fälle in `test/location_service_test.dart`
  (iOS nutzt `AppleSettings` mit den richtigen Flags, Android/Web
  nutzt weiterhin das generische `LocationSettings`).

### 22. Ausfall-Erkennung: `Itinerary.hasCanceledLeg` + `NavigationLeg.isCanceled`

Hauptprojekt Kapitel 3.41 (07.10.2026): korrigiert eine falsche frühere
Annahme - `routing.Leg.realtimeState` (inkl. `RealtimeState.canceled`) wird
seit Längerem vollständig von OTP geparst, es fehlte nur die Weiterleitung
bis in die Navigation/UI, nicht das Parsen selbst.

- `trufi_core_routing`: neuer `Itinerary.hasCanceledLeg`-Getter (additiv,
  analog zu `overallArrivalDelay`) - `true`, sobald irgendein Bein
  `realtimeState == RealtimeState.canceled` ist.
- `trufi_core_navigation`: `NavigationLeg` bekommt ein neues
  `realtimeState`-Feld + `isCanceled`-Getter (additiv), von
  `ItineraryConverter.toNavigationRoute()` aus `routing.Leg.realtimeState`
  befüllt.
- `trufi_core_home_screen`: neuer `_CancellationBadge` auf `ItineraryCard`
  - verdrängt den bestehenden `_DelayBadge`, statt daneben zu stehen (eine
    ausgefallene Fahrt hat meist keine sinnvolle Verspätungsangabe mehr).
    Neue lokalisierte Zeichenkette `tripCanceled` (de/en/es).
- Neue Tests: 3 neue Fälle in `trufi_core_routing/test/unit/cancellation_test.dart`
  (`hasCanceledLeg` true/false/null-realtimeState), 1 neuer Fall in
  `trufi_core_navigation/test/itinerary_converter_delay_test.dart`
  (`realtimeState`/`isCanceled` werden von `toNavigationRoute()`
  durchgereicht).

### 23. Redesign Phase A Teil 2: `_DelayBadge` durch `RealtimeChip` ersetzt

Hauptprojekt Kapitel 3.44/3.45 (08.10.2026), Fortsetzung von Patch 22:
`_DelayBadge` auf `ItineraryCard` war die letzte der drei ursprünglich
duplizierten Verspätungs-Anzeigen (neben `_LiveDelayLabel` in
`departures_screen.dart` und `_DelayDetailRow` in `navigation_map.dart`,
beide bereits in Phase A durch `RealtimeChip` ersetzt, siehe
`docs/design/HANDOFF.md` Abschnitt 1 im Hauptprojekt-Repo).

- Der Fork kann `app/lib/design/fahrplaner_theme.dart` (Hauptprojekt-Repo,
  eigenes Repo/Package) nicht importieren - stattdessen neue Datei
  `trufi_core_home_screen/lib/src/widgets/realtime_chip.dart`: eine
  **manuelle, bewusst unveränderte Kopie** von `RealtimeStatus`,
  `realtimeStatusFor`, `FpStatusColors` (nur die von `RealtimeChip`
  benötigten, bereits aufgelösten Farbwerte, nicht die volle `FpPalette`)
  und `RealtimeChip`. Kopfkommentar der Datei vermerkt ausdrücklich, dass
  beide Kopien manuell synchron gehalten werden müssen - es gibt keinen
  automatisierten Abgleich.
- Bewusst **nicht** an dieses Pakets de/en/es-l10n angebunden (anders als
  der bestehende Code dieses Screens) - die Kopie übernimmt dieselben
  deutschen Festtexte wie das Original, damit beide Dateien diff-
  vergleichbar bleiben. Bekannte, akzeptierte Abweichung: englische/
  spanische Nutzer sehen bei diesem einen Chip vorerst deutschen Text.
- `arrivalDelay == null` (bzw. `overallArrivalDelay == null`) zeigt jetzt
  "Fahrplan" (`RealtimeStatus.scheduleOnly`) statt wie bei `_DelayBadge`
  zuvor fälschlich "Pünktlich" - derselbe Fund wie bei `delayBucket()` in
  Phase A (Hauptprojekt, `live_activities_bridge.dart`).
- `_DelayBadge` und die davon verwendeten l10n-Schlüssel `delayOnTime`/
  `delayLateMinutes` wurden NICHT aus den `.arb`-Dateien entfernt (bewusst
  außerhalb des Scopes dieses Patches) - nur der Dart-Widget-Code ist
  jetzt tot, die Zeichenketten bleiben ungenutzt liegen.
- `_CancellationBadge` (Patch 22) bewusst UNVERÄNDERT gelassen - der
  Nutzer-Auftrag nannte explizit nur `_DelayBadge`, eine Vereinheitlichung
  mit `RealtimeChip.cancelled` ist eine spätere, eigene Entscheidung.
- Keine neuen Tests (reiner Widget-Austausch, keine neue Logik - die
  Schwellenwert-Logik selbst ist 1:1 aus dem bereits unveränderten
  Original übernommen).

### 24. `NavigationBottomPanel`/`NavigationScreen`: `actionsBuilder` + `compact`

Hauptprojekt Kapitel 3.48/3.49 (09.10.2026, Redesign Phase D): die obere
Karte im `mapBuilder`-Stack (`NextStepCard`, Phase D1) übernimmt jetzt
Informationen, die bisher nur `NavigationInstructionCard` in diesem Panel
zeigte - `docs/design/HANDOFF.md` Abschnitt 3.4 schlägt dafür genau diesen
Patch als Vorschlag vor ("ein neuer Parameter `actionsBuilder` plus
`compact`-Modus, statt das Panel neu zu schreiben"), bewusst rein additiv.

- `NavigationBottomPanel`: zwei neue optionale Parameter.
  `actionsBuilder: Widget Function(BuildContext, VoidCallback
  onExitNavigation)?` ersetzt bei Angabe die bisherige einzelne
  "Beenden"-Schaltfläche durch beliebigen eigenen Inhalt (z. B. eine
  Mehr-Aktionen-Reihe) - `null` (Default) lässt das bisherige Verhalten
  unverändert. Der an den Builder übergebene `onExitNavigation`-Callback
  ist NICHT das rohe `onExitNavigation`-Feld, sondern ein Wrapper, der
  weiterhin erst `_showExitConfirmation()` zeigt - ein eigener "Beenden"-
  Knopf in einer Mehr-Aktionen-Reihe bekommt dadurch automatisch dieselbe
  Rückfrage wie der bisherige Standard-Knopf. `compact: bool = false`
  blendet bei `true` die `NavigationInstructionCard` komplett aus (die
  Beenden-/Aktionsreihe bleibt in jedem Fall sichtbar).
- `NavigationScreen`/`NavigationScreen.show()`: zwei neue, gleichnamige
  optionale Parameter (`bottomPanelActionsBuilder`,
  `compactBottomPanel = false`), 1:1 an `NavigationBottomPanel`
  durchgereicht - ohne diese zweite Änderung wären die neuen
  `NavigationBottomPanel`-Parameter von App-Code aus gar nicht erreichbar
  gewesen, da `NavigationScreen._buildBottomPanel()` das Panel bisher
  fest verdrahtet instanziiert.
- Neue Tests: `trufi_core_navigation/test/navigation_bottom_panel_test.dart`
  (5 Fälle - Default-Verhalten beider Parameter unverändert, `actionsBuilder`
  ersetzt den Knopf UND bekommt ein funktionierendes `onExitNavigation`
  inkl. Bestätigungsdialog, `compact` blendet nur die Karte aus, nicht die
  Aktionsreihe).
- Bewusst außerhalb des Scopes: die eigentliche App-seitige Nutzung (die
  volle "Ganze Fahrt / Wecken an / Merken / Beenden"-Vierer-Reihe aus
  `AktiveFahrt.dc.html`) ist NICHT Teil dieses Patches - der Hauptprojekt-
  Auftrag für diese Phase war explizit nur der additive Fork-Patch selbst.

### 25. `ItineraryCard`: proportionaler Balken, Echtzeit-Zeile, "Umstieg knapp"

Hauptprojekt Kapitel E1 (09.10.2026, Redesign, docs/design/HANDOFF.md
Abschnitt 3.2 "Verbindungen", Referenz `Verbindungen.dc.html`) - Nutzer-
Entscheidung vorab: direkt patchen statt Builder-Override (siehe
Hauptprojekt-Konversation), da die Wiederverwendung der bestehenden
Auswahl-/Daten-Logik in `ItineraryCard`/`ItineraryList` sonst in main.dart
hätte nachgebaut werden müssen.

- **Kopfzeile neu:** "HH:MM – HH:MM" (mono-grosse Schrift) + Dauer +
  Umstiegszahl (Icon+Zahl) in einer Zeile statt der bisherigen separaten
  Dauer-Pille. Der bestehende Los-Button/Auswahl-Häkchen (Patch 16)
  bleibt bewusst erhalten und steht jetzt rechts daneben - die Referenz
  zeigt keinen Los-Button auf der Karte (volle Karte ist dort EIN
  Tap-Ziel zur Detailansicht), dieses bereits vorhandene, vom Nutzer
  gewünschte Feature wird aber nicht stillschweigend entfernt.
- **Neuer `_buildSegmentBar()`:** proportionaler Balken, ein Segment je
  Bein (`Expanded`/`flex` nach `leg.duration.inSeconds`), Wartezeit-
  Lücken zwischen zwei Beinen mit echter Zeitdifferenz als duenner Balken
  dazwischen. `_LegChip` (vorher nur fuer eine horizontal scrollende
  Chip-Reihe gedacht) bekam dafür explizite Grössen (`width:
  double.infinity, height: 28`) und behält dabei die komplette bisherige
  Logik (Slot-Routen/`SegmentedRouteChip` fuer austauschbare Linien
  #737, `LiveBusBadge`, Formkodierung rail=Pille/tram=3px/sonst=8px nach
  dem gleichen Muster wie `lineBadgeShapeFor()` im Hauptprojekt) - keine
  doppelte Implementierung.
- **Echte Layout-Bugs waehrend des Redesigns gefunden, nicht nur
  theoretisch:** `itinerary_card_three_buses_test.dart` (ein
  realistischer Sieben-Bein-Fall mit zwei Umstiegen) deckte zwei
  RenderFlex-Overflows auf. Behoben: Fusswege/Räder bekommen jetzt eine
  FESTE 28px-Breite statt proportionaler `flex` (zu wenig Platz für
  Icon+Text bei vielen kurzen Beinen), die einfache Transit-Variante von
  `_LegChip` ist zusätzlich in ein `FittedBox(fit: scaleDown)` gepackt
  (Sicherheitsnetz gegen schmale Zuteilungen bei vielen Transit-Beinen),
  und die neue Echtzeit-Zeile (`_buildRealtimeRow`) nutzt `Wrap` statt
  `Row`/`Expanded`, da mehrere Umstiege mehr Chips erzeugen können, als
  in eine Zeile auf Telefonbreite passen.
- **Neue `_buildRealtimeRow()`:** "in N Min ab X" (bzw. "Leihrad bis Y ·
  Z km", wenn das erste Bein selbst schon eine Fahrt ist) + ein
  `RealtimeChip` je Transit-Bein (mit Linien-Präfix). Bewusst deutsche
  Festtexte ohne l10n-Anbindung, exakt wie Patch 23 begründet - vermeidet
  zusätzliche l10n-Oberfläche für dieses bereits umfangreiche Redesign.
- **Neue `_tightTransferWarning()`/`_buildTransferWarningRow()`:**
  "Umstieg {Haltestelle} wird knapp (N Min)", Formel `nextLeg.start -
  (leg.end + delay)` < 5 Minuten - bewusst eine eigene, winzige Kopie der
  Formel statt eines Imports aus dem Hauptprojekt-Repo (kann der Fork
  nicht importieren, siehe Patch 23); hier stecken ohnehin nur zwei
  `routing.Leg`-Felder dahinter, keine echte Logik wert eines Imports.
- **Footer bereinigt:** die alte "Umstiege"-`_InfoChip` entfernt (jetzt
  in der Kopfzeile) - Distanz/Fussweg/Ausfall-Badge/Detail-Button
  bleiben unverändert.
- Neue Tests: `test/itinerary_card_redesign_test.dart` (4 Fälle -
  Echtzeit-Zeile, "Umstieg knapp" ja/nein, Kopfzeile-Umstiegszahl).
  `test/itinerary_card_three_buses_test.dart` angepasst (Chevron-
  Erwartung entfernt, da die alte scrollende Chip-Reihe durch den
  Balken ersetzt wurde - die Kernaussage "ein Segment je Bein, kein
  Overflow" bleibt).
- Bewusst außerhalb des Scopes (E1 ist nur die Karte): die "Weniger
  Umstiege"-Sortier-Chip und der einmalige "Fahrplan heißt…"-Hinweis aus
  Abschnitt 3.2 (beide in `ItineraryList`, nicht `ItineraryCard`) -
  eigener, kleinerer Folge-Patch.

### 26. `ItineraryList`: "Weniger Umstiege"-Sortierung + "Fahrplan heißt…"-Hinweis

Hauptprojekt Kapitel E1-Rest (09.10.2026, Redesign, docs/design/HANDOFF.md
Abschnitt 3.2, Referenz `Verbindungen.dc.html`) - die beiden in Patch 25
bewusst ausgelassenen Elemente, da sie in `ItineraryList`/`home_screen.dart`
statt `ItineraryCard` liegen.

- **`RoutePlannerState.preferFewerTransfers`** (neues additives `bool`-
  Feld, Default `false`) + **`RoutePlannerCubit.toggleSortPreference()`**:
  reine Anzeige-Praeferenz, kein Replan. `ItineraryList.build()` sortiert
  bei `true` die bereits geladenen `itineraries`/`groupedItineraries`
  (bzw. deren `representative`) nach Umstiegszahl, dann Dauer, dann
  Abfahrtszeit um - dieselbe Kaskade wie `rankAlternatives()` im
  Hauptprojekt (`alternative_routes.dart`), hier als eigene, kleine Kopie
  statt eines Imports (siehe Patch 23/25).
- **Neue `_FewerTransfersChip`** in `home_screen.dart`, an beiden
  bestehenden Stellen eingehaengt, an denen schon der Abfahrtszeit-Chip
  sitzt (schmale UND breite Ansicht) - `BlocBuilder`-gestuetzter Toggle,
  derselbe Material-Pill-Stil wie `_DepartureTimeChip`. Nur sichtbar,
  wenn bereits ein Plan mit Ergebnissen vorliegt (`state.plan
  ?.hasItineraries == true`) - vorher gibt es nichts umzusortieren.
  Bewusst deutscher Festtext ohne l10n-Anbindung (Patch 23/25-Muster).
- **Neue `_ScheduleExplainerBanner`** in `itinerary_list.dart`, ueber der
  eigentlichen Liste eingehaengt (per neuem `_withScheduleBanner()`-
  Wrapper, der bei `widget.shrinkWrap` bewusst OHNE `Expanded` arbeitet -
  sonst ein RenderFlex-Fehler in der Bottom-Sheet-Einbettung, wo die
  Hoehe von aussen unbegrenzt ist). Persistenz ueber `StorageService`/
  `SharedPreferencesStorage` (dasselbe Muster wie
  `HomeScreen._liveVehiclesStorage`), Schluessel
  `fp_schedule_banner_dismissed` - einmalig angezeigt, danach dauerhaft
  verborgen.
- Neue Tests: `test/itinerary_list_redesign_test.dart` (2 Faelle - Chip
  sortiert tatsaechlich um, auch wenn die umstiegsaermere Verbindung
  LANGSAMER ist, damit ein Zufallstreffer durch reine Dauersortierung
  ausgeschlossen ist; Hinweis erscheint einmalig und bleibt nach
  Wegklicken auch nach einem simulierten Neustart verborgen).

### 27. `ItineraryDetailContent`/`-Screen`: Echtzeit, Verspätung, Umstieg, Wecken

Hauptprojekt Kapitel E2 (09.10.2026, Redesign, docs/design/HANDOFF.md
Abschnitt 3.3 "Verbindungsdetail", Referenz `Verbindung.dc.html`) - direkt
patchen statt Builder-Override (dieselbe Nutzer-Entscheidung wie Patch
25/26).

- **Neue Echtzeit-Zeile** (`_buildRealtimeSummaryRow`): "Echtzeit:" + ein
  `RealtimeChip` je Transit-Bein, identisches Muster zu `ItineraryCard`
  (Patch 25).
- **"Durchgestrichene Zeit + neue Zeit bei Verspätung"**: `_PlaceItem`
  bekommt ein neues `delay`-Feld - nur bei `delay.inSeconds > 60`
  (derselbe Schwellenwert wie `realtimeStatusFor()`) wird die Zeit als
  durchgestrichenes Soll + fette, orange Ist-Zeit gezeigt, sonst
  unveraendert wie bisher. Bewusst nur am ANKUNFTS-/Umstiegspunkt
  (`legs[i].arrivalDelay`), nicht beim Einstieg.
- **Neue `_TransferPill`** zwischen zwei Transit-Beinen: "Umstieg N Min"
  (grau) bzw. "Umstieg nur noch N Min" (orange) unter 5 Minuten Puffer -
  dieselbe Formel/Schwelle wie `transferBufferWarning` im Hauptprojekt
  (Patch 25), hier als kleine Eigenkopie. Echter Test-Fund bei 320dp-
  Breite: der Pillen-Text brauchte `Flexible`+Ellipsis statt eines
  intrinsisch breiten `Container`, sonst RenderFlex-Overflow bei langen
  Haltestellen-/Steig-Namen.
- **Neue `_StartNavigationBar`** (eigenes StatefulWidget, haelt den
  "Vor dem Aussteigen wecken"-Schalter-Zustand selbst) ersetzt den
  bisherigen kompakten Go-Button im Header durch eine volle-Breite
  "Fahrt starten"-Leiste + Schalter. `onStartNavigation` wechselt dafuer
  von `VoidCallback?` zu `void Function(bool wakeAtDestination)?` - eine
  Signaturaenderung, die additiv bis zu `HomeScreenTrufiScreen`
  durchgereicht werden musste (`ItineraryDetailContent` →
  `ItineraryList` → `HomeScreen` → `HomeScreenTrufiScreen`, jeweils ein
  neuer optionaler `{bool wakeAtDestination}`-Parameter auf einer schon
  bestehenden 3-Positionsargumente-Funktion - bleibt dadurch
  zuweisungskompatibel zu bestehenden Aufrufern, siehe Dart-
  Funktionssubtyping-Hinweis bei Patch 24).
- **Fund + Fix nebenbei:** `ItineraryDetailScreen` (die Standalone-
  Variante, von `saved_trips_screen.dart openSavedTrip()` im
  Hauptprojekt genutzt) hatte bisher eine KOMPLETT EIGENE, zu
  `ItineraryDetailContent` parallele AppBar+Zeitstrahl-Implementierung,
  in der `onStartNavigation` entgegengenommen, aber nirgends tatsaechlich
  aufgerufen wurde - ein bestehender, unbemerkter Funktionsluecke.
  Jetzt delegiert `ItineraryDetailScreen` an `ItineraryDetailContent`
  (duenner Scaffold-Wrapper) statt eine zweite Implementierung zu
  pflegen - behebt die Luecke und bringt alle neuen Redesign-Inhalte
  (Echtzeit-Zeile, Zeitstrahl, Wecken-Schalter) der Standalone-Variante
  kostenlos mit.
- Neue Tests: `test/itinerary_detail_redesign_test.dart` (8 Fälle -
  Echtzeit-Zeile, durchgestrichene Zeit ja/nein, Umstieg-Pille orange/
  grau, Wecken-Schalter aus/ein, UND ein Regressionstest, der bestaetigt,
  dass `ItineraryDetailScreen.show()`s `onStartNavigation` jetzt
  tatsaechlich aufgerufen wird).

### 28. `HomeScreenConfig.belowSearchBuilder`

Hauptprojekt Kapitel E3 (09.10.2026, Redesign, docs/design/HANDOFF.md
Abschnitt 3.1 "Start · Planen") - genau der additive Hook, den HANDOFF.md
selbst vorschlug ("ein neuer Einhängepunkt... z. B.
`HomeScreenConfig.belowSearchBuilder`, also ein kleiner, additiver
Fork-Patch statt eines Umbaus"), bereits beim Lesen des Forks in E0
bestätigt.

- Neues optionales Feld `Widget Function(BuildContext)? belowSearchBuilder`
  auf `HomeScreenConfig`. In `home_screen.dart` (beide Layouts, schmal UND
  breit) direkt unter der `SearchLocationBar` eingehängt, aber NUR auf dem
  LEEREN Home-Screen sichtbar (`state.fromPlace == null && state.toPlace
  == null`) - sobald eine Suche beginnt, übernehmen Abfahrtszeit-/Filter-
  Chips denselben Platz.
- Test: nur auf Feld-Ebene (`belowSearchBuilder` ist `null` per Default),
  analog zu `showMapTypeButton`/`extraMapLayerSettings` oben im selben
  Testfile - keiner von beiden hat einen vollen `HomeScreen`-Widget-Test
  (brauchte ein schweres Map-/Routing-Setup, siehe
  `restored_plan_map_test.dart`), der Render-Zweig selbst ist eine
  einzige, triviale Bedingung.

Alle achtundzwanzig Patches sind per `dart analyze` (keine neuen Fehler) und
den bestehenden Testsuiten der jeweils betroffenen Pakete verifiziert
(alle grün, inkl. neuer Tests für Patches 8/10/11/12/13/16/17/18/19/20/21/22/24/25/26/27).

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
