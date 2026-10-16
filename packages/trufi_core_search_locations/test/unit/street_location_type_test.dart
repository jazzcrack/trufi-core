// fahrplaner.de fork patch 62: "nur Strasse" + Laenge in TrufiLocation.type.
import 'package:flutter_test/flutter_test.dart';
import 'package:trufi_core_search_locations/trufi_core_search_locations.dart';

void main() {
  test('Laenge wird gerundet mitgespeichert und wieder gelesen', () {
    final tag = streetLocationTypeTag(649.6);
    expect(tag, 'street:650');
    expect(isStreetLocationType(tag), isTrue);
    expect(streetLengthFromLocationType(tag), 650);
  });

  test('ohne Laenge: nur "street"', () {
    expect(streetLocationTypeTag(null), 'street');
    expect(isStreetLocationType('street'), isTrue);
    expect(streetLengthFromLocationType('street'), isNull);
  });

  test('andere Typen sind keine Strasse', () {
    expect(isStreetLocationType(null), isFalse);
    expect(isStreetLocationType('streetcar'), isFalse);
    expect(streetLengthFromLocationType('stop'), isNull);
  });
}
