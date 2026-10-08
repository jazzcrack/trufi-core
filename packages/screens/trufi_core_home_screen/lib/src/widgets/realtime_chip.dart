// fahrplaner.de fork patch (siehe FAHRPLANER_PATCHES.md) - Redesign Oktober
// 2026, "Echtzeit-Status" (docs/design/HANDOFF.md Abschnitt 1 im
// Hauptprojekt). Diese Datei ist eine BEWUSSTE, MANUELLE Kopie von
// RealtimeStatus/realtimeStatusFor/FpStatusColors/RealtimeChip aus
// app/lib/design/fahrplaner_theme.dart (Hauptprojekt-Repo, nicht Teil
// dieses Forks) - der Fork kann diese App-Datei nicht importieren (eigenes
// Package, eigenes Repo), ein Import ueber Paketgrenzen hinweg ist hier
// nicht moeglich.
//
// !!! WICHTIG: Diese Kopie MUSS manuell synchron zur Originaldatei
// gehalten werden !!! Aendert sich die Schwellenwert-Logik, die Labels,
// oder die Farben in app/lib/design/fahrplaner_theme.dart, muss dieselbe
// Aenderung HIER von Hand nachgezogen werden - es gibt keinen
// automatisierten Abgleich zwischen beiden Kopien. Bewusst UNVERAENDERT
// als deutsche Festtexte uebernommen (keine l10n-Anbindung an dieses
// Pakets de/en/es-Lokalisierung) - genau das haelt beide Kopien
// diff-vergleichbar, eine Relokalisierung wuerde das erschweren. Englische/
// spanische Nutzer sehen bei diesem einen Chip deshalb vorerst deutschen
// Text - bekannte, akzeptierte Abweichung, siehe FAHRPLANER_PATCHES.md.
//
// Wichtigste inhaltliche Aenderung gegenueber dem alten _DelayBadge: "keine
// Echtzeitdaten" ist ein EIGENER Zustand (RealtimeStatus.scheduleOnly) und
// wird nie mehr als "puenktlich"/gruen dargestellt (arrivalDelay == null
// zeigte bisher faelschlich "puenktlich").
import 'package:flutter/material.dart';

// ============ Status-Farben als ThemeExtension ============
//
// Nur die fuer RealtimeChip benoetigten Farbwerte uebernommen (aufgeloeste
// Hex-Werte aus FpPalette, nicht FpPalette selbst - das Original hat dort
// weitere, hier ungenutzte Token wie Markenfarbe/Oberflaechenfarben).

@immutable
class FpStatusColors extends ThemeExtension<FpStatusColors> {
  final Color liveFg;
  final Color liveBg;
  final Color lateFg;
  final Color lateBg;
  final Color badFg;
  final Color badBg;
  final Color planFg;
  final Color planBorder;

  const FpStatusColors({
    required this.liveFg,
    required this.liveBg,
    required this.lateFg,
    required this.lateBg,
    required this.badFg,
    required this.badBg,
    required this.planFg,
    required this.planBorder,
  });

  static const light = FpStatusColors(
    liveFg: Color(0xFF0B6458), // FpPalette.brandText
    liveBg: Color(0xFFD9EEE9), // FpPalette.brandSoft
    lateFg: Color(0xFF9A4A00), // FpPalette.late
    lateBg: Color(0xFFFDEBD8), // FpPalette.lateBg
    badFg: Color(0xFFB3261E), // FpPalette.bad
    badBg: Color(0xFFFBE3E1), // FpPalette.badBg
    planFg: Color(0xFF46564F), // FpPalette.ink2
    planBorder: Color(0xFFD3DDD9), // FpPalette.line
  );

  static const dark = FpStatusColors(
    liveFg: Color(0xFF74D9C5), // FpPalette.brandTextDark
    liveBg: Color(0xFF133A33), // FpPalette.brandSoftDark
    lateFg: Color(0xFFFFB36B), // FpPalette.lateDark
    lateBg: Color(0xFF3A2614), // FpPalette.lateBgDark
    badFg: Color(0xFFFF8A80), // FpPalette.badDark
    badBg: Color(0xFF3D1A18), // FpPalette.badBgDark
    planFg: Color(0xFFB3C3BD), // FpPalette.ink2Dark
    planBorder: Color(0xFF2A3B36), // FpPalette.lineDark
  );

  static FpStatusColors of(BuildContext context) =>
      Theme.of(context).extension<FpStatusColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  FpStatusColors copyWith({
    Color? liveFg,
    Color? liveBg,
    Color? lateFg,
    Color? lateBg,
    Color? badFg,
    Color? badBg,
    Color? planFg,
    Color? planBorder,
  }) {
    return FpStatusColors(
      liveFg: liveFg ?? this.liveFg,
      liveBg: liveBg ?? this.liveBg,
      lateFg: lateFg ?? this.lateFg,
      lateBg: lateBg ?? this.lateBg,
      badFg: badFg ?? this.badFg,
      badBg: badBg ?? this.badBg,
      planFg: planFg ?? this.planFg,
      planBorder: planBorder ?? this.planBorder,
    );
  }

  @override
  FpStatusColors lerp(ThemeExtension<FpStatusColors>? other, double t) {
    if (other is! FpStatusColors) return this;
    return FpStatusColors(
      liveFg: Color.lerp(liveFg, other.liveFg, t)!,
      liveBg: Color.lerp(liveBg, other.liveBg, t)!,
      lateFg: Color.lerp(lateFg, other.lateFg, t)!,
      lateBg: Color.lerp(lateBg, other.lateBg, t)!,
      badFg: Color.lerp(badFg, other.badFg, t)!,
      badBg: Color.lerp(badBg, other.badBg, t)!,
      planFg: Color.lerp(planFg, other.planFg, t)!,
      planBorder: Color.lerp(planBorder, other.planBorder, t)!,
    );
  }
}

// ============ Echtzeit-Status ============

enum RealtimeStatus {
  /// Echtzeit vorhanden, Abweichung <= 60 s.
  onTime,

  /// Echtzeit vorhanden, > 60 s spaeter.
  late,

  /// Fahrt faellt aus.
  cancelled,

  /// KEINE Echtzeitdaten - nur Soll-Fahrplan. Nie als "puenktlich" zeigen.
  scheduleOnly,
}

/// Einzige Stelle fuer die Schwellenwerte. [delay] == null bedeutet
/// "keine Echtzeit", NICHT "puenktlich".
RealtimeStatus realtimeStatusFor(Duration? delay, {bool cancelled = false}) {
  if (cancelled) return RealtimeStatus.cancelled;
  if (delay == null) return RealtimeStatus.scheduleOnly;
  return delay.inSeconds <= 60 ? RealtimeStatus.onTime : RealtimeStatus.late;
}

/// Minuten-Text fuer eine Verspaetung, aufgerundet wie bisher.
String delayMinutesLabel(Duration delay) =>
    '+${(delay.inSeconds / 60).ceil()} Min';

/// Status-Kennzeichen "Live · puenktlich" / "Live · +3 Min" / "Ausfall" /
/// "Fahrplan". [prefix] z. B. eine Liniennummer ("RS2"), [showLiveWord]
/// schaltet das vorangestellte "Live · " ein (Abfahrtstafel, Detail).
class RealtimeChip extends StatelessWidget {
  final RealtimeStatus status;
  final Duration? delay;
  final String? prefix;
  final bool showLiveWord;

  const RealtimeChip({
    super.key,
    required this.status,
    this.delay,
    this.prefix,
    this.showLiveWord = false,
  });

  factory RealtimeChip.fromDelay(
    Duration? delay, {
    Key? key,
    bool cancelled = false,
    String? prefix,
    bool showLiveWord = false,
  }) {
    return RealtimeChip(
      key: key,
      status: realtimeStatusFor(delay, cancelled: cancelled),
      delay: delay,
      prefix: prefix,
      showLiveWord: showLiveWord,
    );
  }

  String get _label {
    final live = showLiveWord ? 'Live · ' : '';
    final p = prefix != null ? '$prefix ' : '';
    switch (status) {
      case RealtimeStatus.onTime:
        return '$p${live}pünktlich';
      case RealtimeStatus.late:
        return '$p$live${delay != null ? delayMinutesLabel(delay!) : 'verspätet'}';
      case RealtimeStatus.cancelled:
        return '${p}Ausfall';
      case RealtimeStatus.scheduleOnly:
        return '${p}Fahrplan';
    }
  }

  String get _semantics {
    switch (status) {
      case RealtimeStatus.onTime:
        return 'Live-Daten: pünktlich';
      case RealtimeStatus.late:
        final min = delay != null ? (delay!.inSeconds / 60).ceil() : null;
        return min != null
            ? 'Live-Daten: $min Minuten verspätet'
            : 'Live-Daten: verspätet';
      case RealtimeStatus.cancelled:
        return 'Fahrt fällt aus';
      case RealtimeStatus.scheduleOnly:
        return 'Keine Live-Daten, nur Fahrplan';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FpStatusColors.of(context);
    final (Color fg, Color? bg, IconData? icon) = switch (status) {
      RealtimeStatus.onTime => (c.liveFg, c.liveBg, Icons.sensors_rounded),
      RealtimeStatus.late => (c.lateFg, c.lateBg, Icons.sensors_rounded),
      RealtimeStatus.cancelled => (c.badFg, c.badBg, null),
      RealtimeStatus.scheduleOnly => (c.planFg, null, Icons.schedule_rounded),
    };

    return Semantics(
      label: _semantics,
      excludeSemantics: true,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: bg == null
              ? Border.all(color: c.planBorder, width: 1.5)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 4),
            ],
            Text(
              _label,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
