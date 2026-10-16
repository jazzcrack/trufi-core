// fahrplaner.de fork patch 62 (16.10.2026): optionale Hausnummer zu einem
// Strassen-Treffer als eigener Vollbild-Dialog - nach dem App-Entwurf des
// Nutzers (Hochformat: Eingabe mit Strassen-Chip, Kartenvorschau, "Ohne
// Hausnummer", passende Hausnummern, Uebernehmen-Knopf; Querformat: Eingabe
// + Uebernehmen in einer Zeile, Nummern-Chips darunter, Kartenvorschau nur
// bei geschlossener Tastatur). Ersetzt das fruehere Bottom-Sheet aus
// Patch 46.
//
// Bewusst deutsche Festtexte ohne l10n-Anbindung (wie Patch 23/25/57).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:trufi_core_maps/trufi_core_maps.dart';

import '../models/search_location.dart';
import '../services/search_location_service.dart';

/// Eine echte, bekannte Hausnummer einer Strasse.
class HouseNumberSuggestion {
  final String number;
  final double latitude;
  final double longitude;

  const HouseNumberSuggestion({
    required this.number,
    required this.latitude,
    required this.longitude,
  });
}

/// Liefert zu einer Strasse die zur Eingabe [prefix] passenden Hausnummern
/// (leer = noch nichts getippt). Austauschbar: ohne Quelle zeigt der Dialog
/// keine Vorschlagsliste, die Eingabe wird dann beim Uebernehmen ueber den
/// Suchdienst aufgeloest (Schritt 2 des Plans: eigene Photon-Instanz).
abstract class HouseNumberSuggestionSource {
  Future<List<HouseNumberSuggestion>> suggest(
    SearchLocation street,
    String prefix,
  );
}

/// Ergebnis des Dialogs.
sealed class HouseNumberResult {
  const HouseNumberResult();
}

/// Eine konkrete Adresse. [approximate] = die Nummer ist in den
/// Kartendaten nicht verzeichnet, die Position ist geschaetzt (zwischen
/// bekannten Nachbarnummern) bzw. die Strassenmitte - vom Nutzer
/// ausdruecklich so bestaetigt ("Trotzdem uebernehmen").
class HouseNumberLocated extends HouseNumberResult {
  final SearchLocation location;
  final bool approximate;
  const HouseNumberLocated(this.location, {this.approximate = false});
}

/// Bewusst ohne Hausnummer - die Strasse selbst (Strassenmitte) ist das Ziel.
class HouseNumberWithoutNumber extends HouseNumberResult {
  final SearchLocation street;
  const HouseNumberWithoutNumber(this.street);
}

/// Oeffnet den Dialog als Vollbild-Seite.
Future<HouseNumberResult?> showHouseNumberScreen(
  BuildContext context, {
  required SearchLocation street,
  required SearchLocationService searchService,
  HouseNumberSuggestionSource? suggestionSource,
}) {
  return Navigator.of(context).push<HouseNumberResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => HouseNumberScreen(
        street: street,
        searchService: searchService,
        suggestionSource: suggestionSource,
      ),
    ),
  );
}

/// "Oststraße 12" aus Strassenname und Nummer.
String houseNumberLabel(SearchLocation street, String number) =>
    '${street.displayName} $number';

String _normalizeName(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '');

/// Freitext-Anfrage fuer "Strasse Nummer" (fahrplaner.de fork patch 63,
/// echter Nutzer-Fund): die Adresszeile eines Strassen-Treffers enthaelt die
/// Strasse selbst ("Am Neuen Hafen, Mitte, Bremerhaven, ...") - Patch 62
/// haengte sie unveraendert an, die Strasse stand doppelt in der Anfrage und
/// Nominatim fand NIE eine Hausnummer (live geprueft: 0 Treffer, ohne die
/// Doppelung "Am Neuen Hafen 5" sofort).
String houseNumberQuery(SearchLocation street, String number) {
  final streetKey = _normalizeName(street.displayName);
  final rest = (street.address ?? '')
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty && _normalizeName(part) != streetKey)
      .toList();
  final head = '${street.displayName} $number';
  return rest.isEmpty ? head : '$head, ${rest.join(', ')}';
}

/// Anfragen in absteigender Genauigkeit (fahrplaner.de fork patch 64,
/// Nutzer-Fund "Schleusenstrasse 22 nicht gefunden"): Nominatim verlangt,
/// dass JEDER Teil der Freitext-Anfrage passt - weicht z. B. der Stadtteil
/// der Strasse von dem des Hauses ab, findet die volle Anfrage nichts,
/// "Strasse Nummer, Stadt" aber schon. Erst die volle Adresszeile, dann je
/// ein einzelner Teil daraus, zuletzt nur "Strasse Nummer". Ohne Dubletten,
/// hoechstens [maxQueries].
List<String> houseNumberQueries(
  SearchLocation street,
  String number, {
  int maxQueries = 4,
}) {
  final streetKey = _normalizeName(street.displayName);
  final rest = (street.address ?? '')
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty && _normalizeName(part) != streetKey)
      .toList();
  final head = '${street.displayName} $number';
  // Laender-/Bundeslandnamen allein grenzen kaum ein - Stadt/Stadtteil
  // zuerst: in "Mitte, Bremerhaven, Bremen, Deutschland" sind die ersten
  // beiden die nuetzlichen.
  final queries = <String>{
    houseNumberQuery(street, number),
    for (final part in rest.take(2)) '$head, $part',
    head,
  };
  return queries.take(maxQueries).toList();
}

/// Ist [result] wirklich "Strasse Nummer"? Ein Suchdienst liefert bei
/// unbekannter Nummer gern die Strasse selbst oder ein anderes Haus -
/// das darf nicht als Treffer gelten.
bool isHouseNumberMatch(
  SearchLocation result,
  SearchLocation street,
  String number,
) {
  // Auch ein Geschaeft/Buero AN dieser Adresse zaehlt (live: unter
  // "Schleusenstrasse 22" ist neben dem Haus ein Buero erfasst) - nur
  // Strassen und Haltestellen nicht.
  if (result.locationType == SearchLocationType.street ||
      result.locationType == SearchLocationType.stop) {
    return false;
  }
  final wanted = _normalizeName(houseNumberLabel(street, number));
  final candidates = [result.displayName, result.address ?? ''];
  return candidates.any((text) {
    final first = _normalizeName(text.split(',').first);
    return first == wanted;
  });
}

/// Geschaetzte Position einer in den Kartendaten fehlenden Hausnummer:
/// linear zwischen den naechsten bekannten Nummern DERSELBEN Strassenseite
/// (gleiche Paritaet), sonst die naechste bekannte, sonst null.
({double latitude, double longitude})? estimateHouseNumberPosition(
  String number,
  List<HouseNumberSuggestion> known,
) {
  final target = int.tryParse(RegExp(r'^\d+').stringMatch(number) ?? '');
  if (target == null) return null;
  final numbered = [
    for (final k in known)
      if (int.tryParse(RegExp(r'^\d+').stringMatch(k.number) ?? '')
          case final n?)
        (n: n, s: k),
  ];
  final sameSide = numbered.where((e) => e.n.isEven == target.isEven).toList();
  final pool = sameSide.isNotEmpty ? sameSide : numbered;
  if (pool.isEmpty) return null;
  final lower = pool.where((e) => e.n < target).toList()
    ..sort((a, b) => b.n.compareTo(a.n));
  final higher = pool.where((e) => e.n > target).toList()
    ..sort((a, b) => a.n.compareTo(b.n));
  if (lower.isNotEmpty && higher.isNotEmpty) {
    final a = lower.first, b = higher.first;
    final t = (target - a.n) / (b.n - a.n);
    return (
      latitude: a.s.latitude + (b.s.latitude - a.s.latitude) * t,
      longitude: a.s.longitude + (b.s.longitude - a.s.longitude) * t,
    );
  }
  final nearest = (lower.isNotEmpty ? lower : higher).first.s;
  return (latitude: nearest.latitude, longitude: nearest.longitude);
}

class HouseNumberScreen extends StatefulWidget {
  final SearchLocation street;
  final SearchLocationService searchService;
  final HouseNumberSuggestionSource? suggestionSource;

  const HouseNumberScreen({
    super.key,
    required this.street,
    required this.searchService,
    this.suggestionSource,
  });

  @override
  State<HouseNumberScreen> createState() => _HouseNumberScreenState();
}

class _HouseNumberScreenState extends State<HouseNumberScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<HouseNumberSuggestion> _suggestions = const [];
  bool _loadingSuggestions = false;
  bool _resolving = false;
  int _requestSerial = 0;

  /// Die zuletzt gesuchte, in den Kartendaten NICHT gefundene Nummer -
  /// der Dialog bleibt dann offen und erklaert das (Patch 63).
  String? _notFoundNumber;

  bool get _confirmingApproximate =>
      _notFoundNumber != null && _notFoundNumber == _number;

  String get _number => _controller.text.trim();

  HouseNumberSuggestion? get _exactSuggestion {
    final needle = _number.toLowerCase();
    if (needle.isEmpty) return null;
    for (final s in _suggestions) {
      if (s.number.toLowerCase() == needle) return s;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadSuggestions('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    setState(() {
      if (_notFoundNumber != _number) _notFoundNumber = null;
    });
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => _loadSuggestions(_number),
    );
  }

  Future<void> _loadSuggestions(String prefix) async {
    final source = widget.suggestionSource;
    if (source == null) return;
    final serial = ++_requestSerial;
    setState(() => _loadingSuggestions = true);
    List<HouseNumberSuggestion> result;
    try {
      result = await source.suggest(widget.street, prefix);
    } catch (_) {
      result = const [];
    }
    if (!mounted || serial != _requestSerial) return;
    setState(() {
      _suggestions = result;
      _loadingSuggestions = false;
    });
  }

  void _pickSuggestion(HouseNumberSuggestion suggestion) {
    HapticFeedback.selectionClick();
    _controller.value = TextEditingValue(
      text: suggestion.number,
      selection: TextSelection.collapsed(offset: suggestion.number.length),
    );
    setState(() {});
  }

  void _withoutNumber() {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(HouseNumberWithoutNumber(widget.street));
  }

  Future<void> _submit() async {
    final number = _number;
    if (number.isEmpty) {
      _withoutNumber();
      return;
    }
    HapticFeedback.lightImpact();
    final exact = _exactSuggestion;
    if (exact != null) {
      Navigator.of(context).pop(
        HouseNumberLocated(
          SearchLocation(
            id: 'house:${widget.street.id}:$number',
            displayName: houseNumberLabel(widget.street, exact.number),
            address: widget.street.address,
            latitude: exact.latitude,
            longitude: exact.longitude,
            locationType: SearchLocationType.address,
          ),
        ),
      );
      return;
    }
    if (_confirmingApproximate) {
      await _submitApproximate(number);
      return;
    }
    // Keine bekannte Nummer ausgewaehlt: EINE verfeinerte Freitext-Anfrage
    // (Patch 63: ohne die doppelte Strasse), Treffer nur bei echter
    // Uebereinstimmung von Strasse UND Nummer.
    setState(() => _resolving = true);
    SearchLocation? precise;
    for (final query in houseNumberQueries(widget.street, number)) {
      try {
        final results = await widget.searchService.search(query);
        precise = results
            .where((r) => isHouseNumberMatch(r, widget.street, number))
            .firstOrNull;
      } catch (_) {
        precise = null;
      }
      if (precise != null || !mounted) break;
    }
    if (!mounted) return;
    if (precise != null) {
      setState(() => _resolving = false);
      Navigator.of(context).pop(
        HouseNumberLocated(
          SearchLocation(
            id: precise.id,
            displayName: houseNumberLabel(widget.street, number),
            address: widget.street.address,
            latitude: precise.latitude,
            longitude: precise.longitude,
            locationType: SearchLocationType.address,
          ),
        ),
      );
      return;
    }
    // Nicht verzeichnet: NICHT mehr in den Kartenwaehler (Nutzer-Fund:
    // "mit dem Setzen der Hausnummer sollte alles klar sein"), sondern
    // offen bleiben und erklaeren - "Trotzdem uebernehmen" bestaetigt.
    setState(() {
      _resolving = false;
      _notFoundNumber = number;
    });
  }

  Future<void> _submitApproximate(String number) async {
    setState(() => _resolving = true);
    List<HouseNumberSuggestion> known = _suggestions;
    final source = widget.suggestionSource;
    if (source != null) {
      try {
        known = await source.suggest(widget.street, '');
      } catch (_) {}
    }
    if (!mounted) return;
    final estimate = estimateHouseNumberPosition(number, known);
    setState(() => _resolving = false);
    Navigator.of(context).pop(
      HouseNumberLocated(
        SearchLocation(
          id: 'house:${widget.street.id}:$number',
          displayName: houseNumberLabel(widget.street, number),
          address: widget.street.address,
          latitude: estimate?.latitude ?? widget.street.latitude,
          longitude: estimate?.longitude ?? widget.street.longitude,
          // Ohne Schaetzung ist die Position die Strassenmitte - dann
          // bleibt es fuer Planer und Hinweis eine "Strasse".
          locationType: estimate == null
              ? SearchLocationType.street
              : SearchLocationType.address,
          extentMeters: estimate == null ? widget.street.extentMeters : null,
        ),
        approximate: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final landscape = media.size.width > media.size.height;
    final keyboardOpen = media.viewInsets.bottom > 0;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: landscape
            ? _buildLandscape(context, keyboardOpen)
            : _buildPortrait(context),
      ),
    );
  }

  // --- Hochformat ---------------------------------------------------------

  Widget _buildPortrait(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              _BackButton(onTap: () => Navigator.of(context).pop()),
              const SizedBox(width: 12),
              Expanded(child: _buildInputField(context, compactChip: true)),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              _MapPreview(
                street: widget.street,
                number: _number,
                point: _previewPoint,
                height: 150,
              ),
              const SizedBox(height: 12),
              if (_confirmingApproximate) ...[
                _NotFoundNotice(
                  number: _notFoundNumber!,
                  canEstimate: widget.suggestionSource != null,
                ),
                const SizedBox(height: 12),
              ],
              _WithoutNumberRow(onTap: _withoutNumber),
              ..._buildSuggestionsSection(context),
            ],
          ),
        ),
        if (_number.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _SubmitButton(
              label: _confirmingApproximate
                  ? 'Trotzdem übernehmen'
                  : '${houseNumberLabel(widget.street, _number)} übernehmen',
              loading: _resolving,
              onTap: _submit,
              expand: true,
            ),
          ),
      ],
    );
  }

  // --- Querformat ---------------------------------------------------------

  Widget _buildLandscape(BuildContext context, bool keyboardOpen) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _BackButton(onTap: () => Navigator.of(context).pop()),
              const SizedBox(width: 12),
              Expanded(child: _buildInputField(context, compactChip: false)),
              const SizedBox(width: 12),
              _SubmitButton(
                label: _confirmingApproximate
                    ? 'Trotzdem übernehmen'
                    : 'Übernehmen',
                loading: _resolving,
                onTap: _submit,
                expand: false,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _NumberChip(
                  label: 'Ohne Nr.',
                  selected: false,
                  onTap: _withoutNumber,
                ),
                for (final s in _suggestions) ...[
                  const SizedBox(width: 8),
                  _NumberChip(
                    label: s.number,
                    selected: _exactSuggestion == s,
                    onTap: () => _pickSuggestion(s),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_confirmingApproximate) ...[
            _NotFoundNotice(
              number: _notFoundNumber!,
              canEstimate: widget.suggestionSource != null,
            ),
            const SizedBox(height: 10),
          ],
          if (keyboardOpen)
            Text(
              'Kartenvorschau entfällt quer – sie erscheint, sobald die '
              'Tastatur geschlossen ist.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _MapPreview(
                  street: widget.street,
                  number: _number,
                  point: _previewPoint,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- gemeinsame Bausteine ----------------------------------------------

  latlng.LatLng get _previewPoint {
    final exact = _exactSuggestion;
    return exact != null
        ? latlng.LatLng(exact.latitude, exact.longitude)
        : latlng.LatLng(widget.street.latitude, widget.street.longitude);
  }

  Widget _buildInputField(BuildContext context, {required bool compactChip}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final locality = widget.street.address;
    final shortLocality = locality == null || locality.isEmpty
        ? null
        : compactChip
        ? locality.split(RegExp(r'[,·]')).first.trim()
        : locality;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary, width: 2),
      ),
      child: Row(
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: widget.street.displayName,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          if (shortLocality != null)
                            TextSpan(text: ' · $shortLocality'),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // × = zurueck zur Suche (andere Strasse waehlen).
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: colorScheme.onPrimaryContainer,
                        semanticLabel: 'Andere Straße wählen',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              // Text mit Ziffernreihe statt reiner Zifferntastatur:
              // Hausnummern wie "12a" brauchen Buchstaben.
              keyboardType: TextInputType.visiblePassword,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onChanged: _onChanged,
              onSubmitted: (_) => _submit(),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              decoration: const InputDecoration(
                hintText: 'Nr.',
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSuggestionsSection(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.suggestionSource == null) return const [];
    final hasInput = _number.isNotEmpty;
    return [
      const SizedBox(height: 20),
      Text(
        hasInput ? 'PASSENDE HAUSNUMMERN' : 'HAUSNUMMERN',
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 10),
      if (_loadingSuggestions && _suggestions.isEmpty)
        const Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        )
      else if (_suggestions.isEmpty)
        Text(
          hasInput
              ? 'Keine passende Hausnummer in den Kartendaten – die Eingabe '
                    'wird beim Übernehmen gesucht.'
              : 'Für diese Straße sind keine Hausnummern in den Kartendaten '
                    'erfasst. Du kannst trotzdem eine eingeben.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        )
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _suggestions)
              _NumberChip(
                label: s.number,
                selected: _exactSuggestion == s,
                onTap: () => _pickSuggestion(s),
              ),
          ],
        ),
    ];
  }
}

/// "Nicht in den Kartendaten" (Patch 63) - ehrlich statt Kartenwaehler.
class _NotFoundNotice extends StatelessWidget {
  final String number;
  final bool canEstimate;
  const _NotFoundNotice({required this.number, required this.canEstimate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Hausnummer $number ist in den Kartendaten nicht verzeichnet. '
              '${canEstimate ? 'Beim Übernehmen wird die Position zwischen den '
                        'bekannten Nachbarnummern geschätzt.' : 'Beim Übernehmen ist das Ziel die Straßenmitte.'} '
              'Oder eine andere Nummer eingeben.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: SizedBox(
          width: 52,
          height: 56,
          child: Icon(
            Icons.chevron_left_rounded,
            size: 30,
            semanticLabel: 'Zurück',
            color: colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _WithoutNumberRow extends StatelessWidget {
  final VoidCallback onTap;
  const _WithoutNumberRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.add_road_rounded, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ohne Hausnummer',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Straßenmitte als Ziel',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumberChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NumberChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: selected ? colorScheme.primary : colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: selected
            ? BorderSide.none
            : BorderSide(color: colorScheme.outlineVariant, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 52, minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;
  final bool expand;

  const _SubmitButton({
    required this.label,
    required this.loading,
    required this.onTap,
    required this.expand,
  });

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      onPressed: loading ? null : onTap,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 56),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 10),
          loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.keyboard_return_rounded, size: 20),
        ],
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Echte Karte, nur Anzeige (Nutzerentscheidung): Strassen-/Ortsname oben,
/// Markierung mit Nummer am gewaehlten Punkt. Ohne Kartenmodul im Kontext
/// (Tests, fremde Hosts) entfaellt die Vorschau.
class _MapPreview extends StatelessWidget {
  final SearchLocation street;
  final String number;
  final latlng.LatLng point;
  final double? height;

  const _MapPreview({
    required this.street,
    required this.number,
    required this.point,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    MapEngineManager? manager;
    try {
      manager = MapEngineManager.watch(context);
    } catch (_) {
      manager = null;
    }
    if (manager == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final camera = TrufiCameraPosition(target: point, zoom: 16.5);
    final label = street.address == null || street.address!.isEmpty
        ? street.displayName
        : '${street.displayName} · ${street.address}';

    final map = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: manager.currentEngine.buildMap(
                initialCamera: camera,
                camera: camera,
                widgetMarkers: [
                  WidgetMarker(
                    id: 'house-number',
                    position: point,
                    size: const Size(64, 56),
                    alignment: Alignment.bottomCenter,
                    child: _NumberPin(number: number),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 12,
            right: 12,
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return height == null ? map : SizedBox(height: height, child: map);
  }
}

class _NumberPin extends StatelessWidget {
  final String number;
  const _NumberPin({required this.number});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (number.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              number,
              maxLines: 1,
              style: TextStyle(
                color: colorScheme.onPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: colorScheme.primary,
            shape: BoxShape.circle,
            border: Border.all(color: colorScheme.surface, width: 2),
          ),
        ),
      ],
    );
  }
}
