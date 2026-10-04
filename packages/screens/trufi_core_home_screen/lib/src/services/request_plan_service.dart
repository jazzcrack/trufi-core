import 'package:trufi_core_interfaces/trufi_core_interfaces.dart';
import 'package:trufi_core_routing/trufi_core_routing.dart' as routing;

/// Abstract interface for route planning requests.
abstract class RequestPlanService {
  /// Fetch a route plan from origin to destination.
  Future<routing.Plan> fetchPlan({
    required TrufiLocation from,
    required TrufiLocation to,
    String? locale,
    required DateTime dateTime,
    bool arriveBy = false,
    // fahrplaner.de fork patch (see FAHRPLANER_PATCHES.md): "earlier/later
    // connections" pagination, forwarded to the routing provider.
    String? pageCursor,
    // fahrplaner.de fork patch (04.10.2026, Kapitel 3.27, siehe
    // FAHRPLANER_PATCHES.md): laesst "frueher/spaeter"-Anfragen eine
    // groessere Seitengroesse anfordern als die Erstsuche (Standard des
    // Managers, aktuell 5) - sonst liefert jeder "mehr laden"-Tap nur
    // dieselbe kleine Stapelgroesse.
    int? numItineraries,
  });
}
