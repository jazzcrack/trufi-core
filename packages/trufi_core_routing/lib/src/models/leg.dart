import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

import '../utils/polyline_decoder.dart';
import '../utils/json_utils.dart';
import 'agency.dart';
import 'place.dart';
import 'realtime_state.dart';
import 'route.dart';
import 'service_hours.dart';
import 'step.dart';
import 'transport_mode.dart';

/// A leg of an itinerary (walking, transit, etc.).
class Leg extends Equatable {
  const Leg({
    required this.mode,
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.distance,
    required this.transitLeg,
    this.encodedPoints,
    this.decodedPoints = const [],
    this.route,
    this.shortName,
    this.routeLongName,
    this.agency,
    this.realtimeState,
    this.fromPlace,
    this.toPlace,
    this.steps,
    this.intermediatePlaces,
    this.rentedBike,
    this.interlineWithPreviousLeg,
    this.headsign,
    this.tripPatternId,
    this.serviceHours,
    this.departureDelay,
    this.arrivalDelay,
    this.tripId,
  });

  final String mode;
  final DateTime startTime;
  final DateTime endTime;
  final Duration duration;
  final double distance;
  final bool transitLeg;
  final String? encodedPoints;
  final List<LatLng> decodedPoints;
  final Route? route;
  final String? shortName;
  final String? routeLongName;
  final Agency? agency;
  final RealtimeState? realtimeState;
  final Place? fromPlace;
  final Place? toPlace;
  final List<Step>? steps;
  final List<Place>? intermediatePlaces;
  final bool? rentedBike;
  final bool? interlineWithPreviousLeg;
  final String? headsign;
  final String? tripPatternId;

  /// Operating hours for the route this leg belongs to. Set by the
  /// local planner (which can read `calendar.txt` + `frequencies.txt`
  /// directly from the bundled GTFS); remote OTP providers leave it
  /// null. UI consumers (e.g. the itinerary plan leg) render a small
  /// status badge when this is non-null.
  final ServiceHours? serviceHours;

  /// Real-time offset from the scheduled departure at this leg's boarding
  /// stop, in either direction (positive = late, negative = early).
  /// fahrplaner.de fork patch (see FAHRPLANER_PATCHES.md): parsed from
  /// OTP's `start.estimated.delay`. Null when no real-time data is
  /// available for this leg (e.g. offline planner, or a feed without
  /// GTFS-RT coverage for this trip).
  final Duration? departureDelay;

  /// Real-time offset from the scheduled arrival at this leg's alighting
  /// stop. See [departureDelay].
  final Duration? arrivalDelay;

  /// GTFS-Trip-ID (`trip.gtfsId`), fahrplaner.de fork patch (06.10.2026,
  /// siehe FAHRPLANER_PATCHES.md). Noetig, um eine spaetere, per
  /// IRoutingProvider.fetchLiveStopDelays() abgefragte, nach Trip-ID
  /// geschluesselte Verspaetungs-Map dieser Fahrt zuzuordnen (siehe
  /// NavigationCubit.refreshCurrentLegDelay() im trufi_core_navigation-
  /// Paket). Null fuer Fussweg-/Fahrrad-Abschnitte ohne Trip.
  final String? tripId;

  /// Returns the transport mode enum.
  TransportMode get transportMode =>
      TransportModeExtension.fromString(mode, specificTransport: routeLongName);

  /// Creates a [Leg] from JSON.
  factory Leg.fromJson(
    Map<String, dynamic> json, {
    List<LatLng> Function(String)? polylineDecoder,
  }) {
    final encodedPoints = json['legGeometry']?['points'] as String?;
    final decoder = polylineDecoder ?? PolylineDecoder.decode;
    final decodedPoints = encodedPoints != null
        ? decoder(encodedPoints)
        : <LatLng>[];

    return Leg(
      mode: json['mode'] as String,
      startTime: json.getDateTimeOr('startTime', DateTime.now()),
      endTime: json.getDateTimeOr('endTime', DateTime.now()),
      duration: json.getDurationOr('duration'),
      distance: json.getDoubleOr('distance', 0),
      transitLeg: json['transitLeg'] as bool,
      encodedPoints: encodedPoints,
      decodedPoints: decodedPoints,
      route: _parseRoute(json['route']),
      shortName: _parseShortName(json['route']),
      routeLongName: json['routeLongName'] as String? ?? '',
      agency: json['agency'] != null
          ? Agency.fromJson(json['agency'] as Map<String, dynamic>)
          : null,
      realtimeState: RealtimeStateExtension.fromString(
        json['realtimeState'] as String?,
      ),
      fromPlace: json['fromPlace'] != null
          ? Place.fromJson(json['fromPlace'] as Map<String, dynamic>)
          : null,
      toPlace: json['toPlace'] != null
          ? Place.fromJson(json['toPlace'] as Map<String, dynamic>)
          : null,
      steps: json['steps'] != null
          ? (json['steps'] as List<dynamic>)
                .map((e) => Step.fromJson(e as Map<String, dynamic>))
                .toList()
          : null,
      intermediatePlaces: json['intermediatePlaces'] != null
          ? (json['intermediatePlaces'] as List<dynamic>)
                .map((e) => Place.fromJson(e as Map<String, dynamic>))
                .toList()
          : null,
      rentedBike: json['rentedBike'] as bool?,
      interlineWithPreviousLeg: json['interlineWithPreviousLeg'] as bool?,
      headsign: json['headsign'] as String?,
      tripPatternId: json['tripPatternId'] as String?,
      serviceHours: json['serviceHours'] != null
          ? ServiceHours.fromJson(
              json['serviceHours'] as Map<String, dynamic>,
            )
          : null,
      departureDelay:
          _parseDelayFromLegTime(json['start']) ?? json.getDuration('departureDelay'),
      arrivalDelay:
          _parseDelayFromLegTime(json['end']) ?? json.getDuration('arrivalDelay'),
      tripId: json['tripId'] as String?,
    );
  }

  /// Extracts the real-time delay (seconds) from a GraphQL `LegTime`
  /// object (`{scheduledTime, estimated: {delay}}`), fahrplaner.de fork
  /// patch (see FAHRPLANER_PATCHES.md). Null whenever `estimated` itself
  /// is null - OTP's own documented signal for "no real-time data here".
  /// The `?? json.getDuration(...)` fallback in [fromJson] above is what
  /// makes `toJson()`/`fromJson()` round-trip correctly for our own local
  /// persistence (`HomeScreenRepository.savePlan`), which serializes via
  /// [toJson] into the flat `departureDelay`/`arrivalDelay` keys, not the
  /// nested GraphQL shape.
  static Duration? _parseDelayFromLegTime(dynamic legTimeJson) {
    if (legTimeJson is! Map<String, dynamic>) return null;
    final estimated = legTimeJson['estimated'];
    if (estimated is! Map<String, dynamic>) return null;
    final delaySeconds = estimated['delay'];
    if (delaySeconds is! num) return null;
    return Duration(seconds: delaySeconds.toInt());
  }

  static Route? _parseRoute(dynamic routeData) {
    if (routeData == null) return null;
    if (routeData is Map<String, dynamic>) {
      return Route.fromJson(routeData);
    }
    return null;
  }

  static String? _parseShortName(dynamic routeData) {
    if (routeData == null) return null;
    if (routeData is String && routeData.isNotEmpty) {
      return routeData;
    }
    if (routeData is Map<String, dynamic>) {
      return routeData['shortName'] as String?;
    }
    return null;
  }

  /// Converts this leg to JSON.
  Map<String, dynamic> toJson() {
    return {
      'mode': mode,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
      'duration': duration.inSeconds,
      'distance': distance,
      'transitLeg': transitLeg,
      'legGeometry': {'points': encodedPoints},
      'route': route?.toJson() ?? shortName,
      'routeLongName': routeLongName,
      'agency': agency?.toJson(),
      'realtimeState': realtimeState?.name,
      'fromPlace': fromPlace?.toJson(),
      'toPlace': toPlace?.toJson(),
      'steps': steps?.map((e) => e.toJson()).toList(),
      'intermediatePlaces': intermediatePlaces?.map((e) => e.toJson()).toList(),
      'rentedBike': rentedBike,
      'interlineWithPreviousLeg': interlineWithPreviousLeg,
      'headsign': headsign,
      'tripPatternId': tripPatternId,
      'serviceHours': serviceHours?.toJson(),
      'departureDelay': departureDelay?.inSeconds,
      'arrivalDelay': arrivalDelay?.inSeconds,
      'tripId': tripId,
    };
  }

  /// Creates a copy of this leg with the given fields replaced.
  Leg copyWith({
    String? mode,
    DateTime? startTime,
    DateTime? endTime,
    Duration? duration,
    double? distance,
    bool? transitLeg,
    String? encodedPoints,
    List<LatLng>? decodedPoints,
    Route? route,
    String? shortName,
    String? routeLongName,
    Agency? agency,
    RealtimeState? realtimeState,
    Place? fromPlace,
    Place? toPlace,
    List<Step>? steps,
    List<Place>? intermediatePlaces,
    bool? rentedBike,
    bool? interlineWithPreviousLeg,
    String? headsign,
    String? tripPatternId,
    ServiceHours? serviceHours,
    Duration? departureDelay,
    Duration? arrivalDelay,
    String? tripId,
  }) {
    return Leg(
      mode: mode ?? this.mode,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      duration: duration ?? this.duration,
      distance: distance ?? this.distance,
      transitLeg: transitLeg ?? this.transitLeg,
      encodedPoints: encodedPoints ?? this.encodedPoints,
      decodedPoints: decodedPoints ?? this.decodedPoints,
      route: route ?? this.route,
      shortName: shortName ?? this.shortName,
      routeLongName: routeLongName ?? this.routeLongName,
      agency: agency ?? this.agency,
      realtimeState: realtimeState ?? this.realtimeState,
      fromPlace: fromPlace ?? this.fromPlace,
      toPlace: toPlace ?? this.toPlace,
      steps: steps ?? this.steps,
      intermediatePlaces: intermediatePlaces ?? this.intermediatePlaces,
      rentedBike: rentedBike ?? this.rentedBike,
      interlineWithPreviousLeg:
          interlineWithPreviousLeg ?? this.interlineWithPreviousLeg,
      headsign: headsign ?? this.headsign,
      tripPatternId: tripPatternId ?? this.tripPatternId,
      serviceHours: serviceHours ?? this.serviceHours,
      departureDelay: departureDelay ?? this.departureDelay,
      arrivalDelay: arrivalDelay ?? this.arrivalDelay,
      tripId: tripId ?? this.tripId,
    );
  }

  /// Returns true if this is a walking leg.
  bool get isLegOnFoot => transportMode == TransportMode.walk;

  /// Whether this leg is traversed with a rented GBFS vehicle.
  /// fahrplaner.de fork patch (Kapitel 3.23): generalizes [rentedBike] -
  /// this fork's query has no "ride your own scooter" concept, so any
  /// SCOOTER-mode leg is definitionally a rental, while BICYCLE legs
  /// still rely on the existing [rentedBike] flag to distinguish an
  /// owned bike from a shared one. Derived, not stored - no query/parser
  /// change needed.
  bool get isRentedVehicle =>
      rentedBike == true || transportMode == TransportMode.scooter;

  /// Returns the route color (should be set by Itinerary._assignDefaultColors).
  String get routeColor => route?.color ?? '';

  /// Returns the display name for the route.
  String get displayName => route?.shortName ?? shortName ?? '';

  @override
  List<Object?> get props => [
    mode,
    startTime,
    endTime,
    duration,
    distance,
    transitLeg,
    encodedPoints,
    route,
    shortName,
    routeLongName,
    headsign,
    tripPatternId,
    tripId,
  ];
}

/// Backwards compatibility alias.
@Deprecated('Use Leg instead')
typedef ItineraryLeg = Leg;
