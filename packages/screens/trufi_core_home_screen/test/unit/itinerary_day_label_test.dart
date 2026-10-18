import 'package:flutter_test/flutter_test.dart';
import 'package:trufi_core_home_screen/src/widgets/itinerary_list.dart';

/// fahrplaner.de fork patch 67: Tageszeile, sobald eine Verbindung auf einen
/// anderen Tag fällt (Sonntagabend: "18:26" direkt über "06:27").
void main() {
  final now = DateTime(2026, 10, 18, 16, 35); // Sonntag

  test('erste Verbindung heute: keine Zeile', () {
    expect(
      itineraryDayLabel(DateTime(2026, 10, 18, 17, 25), null, now: now),
      isNull,
    );
  });

  test('Tageswechsel: Morgen mit Wochentag und Datum', () {
    expect(
      itineraryDayLabel(
        DateTime(2026, 10, 19, 6, 27),
        DateTime(2026, 10, 18, 18, 26),
        now: now,
      ),
      'Morgen, Mo. 19.10.',
    );
    expect(
      itineraryDayLabel(
        DateTime(2026, 10, 19, 7, 27),
        DateTime(2026, 10, 19, 6, 27),
        now: now,
      ),
      isNull,
    );
  });

  test('frühere Verbindungen vom Vortag, erster Eintrag nicht heute', () {
    expect(
      itineraryDayLabel(DateTime(2026, 10, 17, 17, 27), null, now: now),
      'Gestern, Sa. 17.10.',
    );
    expect(
      itineraryDayLabel(
        DateTime(2026, 10, 18, 9, 44),
        DateTime(2026, 10, 17, 18, 28),
        now: now,
      ),
      'Heute, So. 18.10.',
    );
    expect(
      itineraryDayLabel(
        DateTime(2026, 10, 21, 8),
        DateTime(2026, 10, 20, 8),
        now: now,
      ),
      'Mi. 21.10.',
    );
  });
}
