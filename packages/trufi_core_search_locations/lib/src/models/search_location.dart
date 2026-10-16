/// fahrplaner.de fork patch (05.10.2026, siehe FAHRPLANER_PATCHES.md):
/// grobe Art eines Suchergebnisses, fuer eine optisch unterscheidbare
/// Trefferliste (Nutzer-Feedback: "wäre es schön wenn bei
/// Suchergebnissen auf optisch klar zwischen den unterschiedlichen
/// Ortsarten unterschieden würde"). Bewusst nur vier grobe Kategorien
/// statt der vollen OSM-Tag-Vielfalt - genug fuer eine sinnvolle Ikone,
/// ohne jeden Geocoder-Service zu einer vollstaendigen OSM-Tag-Zuordnung
/// zu zwingen.
enum SearchLocationType {
  /// Haltestelle/Bahnhof (OSM railway=station/halt, public_transport=*).
  stop,

  /// Point of Interest - Geschaeft, Gastronomie, Sehenswuerdigkeit etc.
  poi,

  /// Eine Strasse (ohne Hausnummer) - typischerweise mit Ecken/Abschnitten.
  street,

  /// Eine konkrete Adresse (Strasse + Hausnummer) oder ein Ort/eine Stadt.
  address,
}

/// Represents a location that can be searched and selected.
///
/// This is a simple data class that holds the essential information
/// about a location for display and identification purposes.
class SearchLocation {
  /// Unique identifier for this location.
  final String id;

  /// The display name of the location.
  final String displayName;

  /// Optional address or secondary description.
  final String? address;

  /// Latitude coordinate.
  final double latitude;

  /// Longitude coordinate.
  final double longitude;

  /// fahrplaner.de fork patch (05.10.2026, siehe FAHRPLANER_PATCHES.md):
  /// grobe Art dieses Ergebnisses, additiv und optional - Dienste, die sie
  /// (noch) nicht befuellen, verhalten sich unveraendert (null = frueheres
  /// Verhalten, generisches Pin-Icon).
  final SearchLocationType? locationType;

  /// fahrplaner.de fork patch 62 (16.10.2026): ungefaehre Ausdehnung in
  /// Metern (bei Strassen ~ Laenge, aus dem Begrenzungsrahmen des Geocoders)
  /// - fuer den Hinweis "Ziel ist die Strassenmitte (Strasse ca. 650 m
  /// lang)". Optional, null = unbekannt.
  final double? extentMeters;

  const SearchLocation({
    required this.id,
    required this.displayName,
    this.address,
    required this.latitude,
    required this.longitude,
    this.locationType,
    this.extentMeters,
  });

  /// Returns a formatted display string combining name and address.
  String get formattedDisplay {
    if (address != null && address!.isNotEmpty) {
      return '$displayName, $address';
    }
    return displayName;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchLocation &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SearchLocation(id: $id, displayName: $displayName)';
}

/// fahrplaner.de fork patch 62: Kennzeichnung "nur Strasse, ohne Hausnummer"
/// in `TrufiLocation.type` (dort wird der Ort gespeichert und an den Planer
/// uebergeben - `SearchLocationType` existiert dort nicht). Format
/// `street` bzw. `street:<Meter>` mit der ungefaehren Strassenlaenge.
const streetLocationTypePrefix = 'street';

String streetLocationTypeTag(double? extentMeters) => extentMeters == null
    ? streetLocationTypePrefix
    : '$streetLocationTypePrefix:${extentMeters.round()}';

/// Ist [type] (aus `TrufiLocation.type`) eine Strasse ohne Hausnummer?
bool isStreetLocationType(String? type) =>
    type == streetLocationTypePrefix ||
    (type?.startsWith('$streetLocationTypePrefix:') ?? false);

/// Ungefaehre Strassenlaenge aus [type], null wenn unbekannt.
int? streetLengthFromLocationType(String? type) {
  if (!isStreetLocationType(type)) return null;
  final parts = type!.split(':');
  return parts.length > 1 ? int.tryParse(parts[1]) : null;
}
