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

/// Eine konkrete Adresse wurde gefunden.
class HouseNumberLocated extends HouseNumberResult {
  final SearchLocation location;
  const HouseNumberLocated(this.location);
}

/// Bewusst ohne Hausnummer - die Strasse selbst (Strassenmitte) ist das Ziel.
class HouseNumberWithoutNumber extends HouseNumberResult {
  final SearchLocation street;
  const HouseNumberWithoutNumber(this.street);
}

/// Die eingegebene Nummer ist in den Kartendaten nicht bekannt - der
/// Aufrufer entscheidet (z. B. Punkt auf der Karte setzen lassen).
class HouseNumberNotFound extends HouseNumberResult {
  final String number;
  const HouseNumberNotFound(this.number);
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
    setState(() {});
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
    // Keine bekannte Nummer ausgewaehlt: wie bisher (Patch 46) EINE
    // verfeinerte Freitext-Anfrage "Strasse Nummer, Ort".
    setState(() => _resolving = true);
    SearchLocation? precise;
    try {
      final locality = widget.street.address;
      final query = locality != null && locality.isNotEmpty
          ? '${widget.street.displayName} $number, $locality'
          : '${widget.street.displayName} $number';
      final results = await widget.searchService.search(query);
      precise = results
          .where((r) => r.locationType == SearchLocationType.address)
          .firstOrNull;
    } catch (_) {
      precise = null;
    }
    if (!mounted) return;
    setState(() => _resolving = false);
    Navigator.of(context).pop(
      precise != null
          ? HouseNumberLocated(precise)
          : HouseNumberNotFound(number),
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
              _WithoutNumberRow(onTap: _withoutNumber),
              ..._buildSuggestionsSection(context),
            ],
          ),
        ),
        if (_number.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _SubmitButton(
              label: '${houseNumberLabel(widget.street, _number)} übernehmen',
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
                label: 'Übernehmen',
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
