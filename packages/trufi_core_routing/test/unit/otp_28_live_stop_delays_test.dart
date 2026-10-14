// fahrplaner.de fork patch (see FAHRPLANER_PATCHES.md): unit tests for
// parseLiveStopDelays(), the pure JSON->delay-map conversion used by
// Otp28RoutingProvider.fetchLiveStopDelays().
import 'package:flutter_test/flutter_test.dart';
import 'package:trufi_core_routing/trufi_core_routing.dart';

void main() {
  group('parseLiveStopDelays', () {
    test('includes only entries with realtime data', () {
      final json = [
        {
          'realtime': true,
          'departureDelay': 120,
          'trip': {'gtfsId': 'gtfsde:trip-1'},
        },
        {
          'realtime': false,
          'departureDelay': 0,
          'trip': {'gtfsId': 'gtfsde:trip-2'},
        },
      ];

      final result = parseLiveStopDelays(json);

      expect(result.keys, ['trip-1']);
      expect(result['trip-1'], const Duration(seconds: 120));
    });

    test('strips the feed prefix from the trip id', () {
      final json = [
        {
          'realtime': true,
          'departureDelay': 60,
          'trip': {'gtfsId': 'gtfsde:abc123'},
        },
      ];

      final result = parseLiveStopDelays(json);

      expect(result.keys, ['abc123']);
    });

    test('supports negative delays (ahead of schedule)', () {
      final json = [
        {
          'realtime': true,
          'departureDelay': -90,
          'trip': {'gtfsId': 'gtfsde:trip-1'},
        },
      ];

      final result = parseLiveStopDelays(json);

      expect(result['trip-1'], const Duration(seconds: -90));
    });

    test('skips entries with missing delay or trip id', () {
      final json = [
        {
          'realtime': true,
          'departureDelay': null,
          'trip': {'gtfsId': 'gtfsde:trip-1'},
        },
        {'realtime': true, 'departureDelay': 30, 'trip': null},
      ];

      expect(parseLiveStopDelays(json), isEmpty);
    });

    test('empty input liefert eine leere Map', () {
      expect(parseLiveStopDelays(const []), isEmpty);
    });
  });

  group('stripKnownFeedPrefix', () {
    test('entfernt das exakte Feed-Praefix von einer rohen OTP-Stop-ID', () {
      expect(stripKnownFeedPrefix('2:92253', '2'), '92253');
    });

    test('laesst eine rohe ID ohne Feed-Praefix unveraendert', () {
      expect(stripKnownFeedPrefix('92253', '2'), '92253');
    });

    test(
      'echter Regressions-Fund (14.10.2026): zerschneidet eine DHID-Stop-ID '
      '("de:03405:99839", MEHRERE Doppelpunkte als Teil der ID selbst) NICHT '
      '- stripGtfsFeedPrefix haette hier faelschlich "03405:99839" geliefert',
      () {
        expect(stripKnownFeedPrefix('de:03405:99839', '2'), 'de:03405:99839');
      },
    );

    test('entfernt nur ein wirklich fuehrendes Feed-Praefix, auch bei einer '
        'DHID-Stop-ID (z. B. wenn OTP sie selbst feed-qualifiziert hat)', () {
      expect(stripKnownFeedPrefix('2:de:03405:99839', '2'), 'de:03405:99839');
    });
  });
}
