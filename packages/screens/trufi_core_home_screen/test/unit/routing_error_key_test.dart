import 'package:flutter_test/flutter_test.dart';
import 'package:trufi_core_home_screen/src/cubit/route_planner_cubit.dart';

/// fahrplaner.de fork patch 70: Server gestört vs. Gerät offline.
void main() {
  test('Serverfehler', () {
    expect(
      routingErrorKey(Exception('MotisException: HTTP 502 bei /api/v6/plan')),
      serverErrorKey,
    );
    expect(
      routingErrorKey(Exception('Zeitüberschreitung bei /api/v6/plan')),
      serverErrorKey,
    );
    expect(
      routingErrorKey(
        Exception('Network error: SocketException: Connection refused'),
      ),
      serverErrorKey,
    );
    expect(
      routingErrorKey(
        Exception('Otp28Exception: Network error: HttpException: Bad Gateway'),
      ),
      serverErrorKey,
    );
  });

  test('Gerät offline', () {
    expect(
      routingErrorKey(
        Exception('SocketException: Failed host lookup: motis.example'),
      ),
      networkErrorKey,
    );
    expect(
      routingErrorKey(
        Exception('Netzwerkfehler: SocketException: Network is unreachable'),
      ),
      networkErrorKey,
    );
  });

  test('sonstige Fehler bleiben Rohtext', () {
    expect(routingErrorKey(Exception('GraphQL error: foo')), isNull);
  });
}
