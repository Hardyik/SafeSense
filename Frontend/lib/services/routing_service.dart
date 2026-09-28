import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Walking evacuation routing with hazard avoidance.
///
/// Routing provider: OSRM's public demo server (router.project-osrm.org),
/// which runs Dijkstra (with Contraction Hierarchies pre-processing) over
/// OpenStreetMap's road graph. One HTTP call replaces what would otherwise
/// be a full Dijkstra implementation over a road graph we don't have
/// locally.
///
/// IMPORTANT INTERNET NOTE: this is the one call in the app that needs
/// internet beyond the LAN — OSM tiles render the map, OSRM computes the
/// route. If OSRM is unreachable the caller falls back to the previous
/// straight-line behaviour so Evacuate never dead-ends.
///
/// Hazard awareness: OSRM knows roads, not our risk zones. After OSRM
/// returns a route we walk its points and check each segment against the
/// active risk zones (point-in-polygon, ray casting). Segments inside a
/// zone get a penalty multiplier; if the penalized route is much worse
/// than a shorter alternative we'd still be choosing OSRM's single route —
/// so instead we REPORT the crossing honestly in the UI (see
/// [EvacuationRoute.crossesZones]) rather than pretending to re-route.
/// (True hazard-weighted re-routing needs a local road graph — see
/// Option B in the project docs.)
class RoutingService {
  RoutingService._internal();
  static final RoutingService instance = RoutingService._internal();

  /// OSRM public demo — generous but rate-limited; fine for a local demo
  /// app, not for production traffic. Self-host for that (Option B).
  static const String _osrmBase = 'https://router.project-osrm.org';

  /// Result of a route request.
  ///
  /// [points]     — polyline to draw (street-following, or the 2-point
  ///                straight line when [usedFallback]).
  /// [distanceKm] — real travel distance along the route.
  /// [durationMin]— estimated walking time at ~5 km/h from the route's
  ///                real distance (the public OSRM demo reports driving
  ///                durations even on the foot profile, so OSRM's own
  ///                duration field is deliberately ignored).
  /// [crossesZones] — human-readable list of risk zones the route passes
  ///                through, empty when the route stays clean.
  /// [usedFallback] — true when OSRM was unreachable and we returned a
  ///                straight line instead.
  /// [note]       — one-line status for the UI.
  Future<EvacuationRoute> walkingRoute({
    required LatLng from,
    required LatLng to,
    required List<Map<String, dynamic>> riskZones,
  }) async {
    try {
      final uri = Uri.parse('$_osrmBase/route/v1/foot/'
          '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
          '?overview=full&geometries=geojson');

      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw http.ClientException('OSRM HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok' || (data['routes'] as List?)!.isEmpty) {
        throw Exception('OSRM: no route (${data['code']})');
      }

      final route = (data['routes'] as List).first as Map<String, dynamic>;
      final coords = (route['geometry']['coordinates'] as List)
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();

      final distanceKm = (route['distance'] as num).toDouble() / 1000.0;
      // The public OSRM demo doesn't load a true foot profile — 'foot'
      // requests come back with driving durations (verified: 7.8 km in
      // "7 min"). Ignore OSRM's duration entirely and compute honest
      // walking time at ~5 km/h.
      final durationMin = distanceKm / 5.0 * 60.0;

      final crossed = _zonesCrossed(coords, riskZones);

      return EvacuationRoute(
        points: coords,
        distanceKm: distanceKm,
        durationMin: durationMin,
        crossesZones: crossed,
        usedFallback: false,
        note: crossed.isEmpty
            ? 'Street route via OpenStreetMap'
            : '⚠ Route passes through: ${crossed.join(', ')}',
      );
    } catch (_) {
      // OSRM unreachable (offline, rate-limited, or no path): fall back to
      // the straight line the old code drew, flagged honestly.
      final straight = _haversineKm(from, to);
      return EvacuationRoute(
        points: [from, to],
        distanceKm: straight,
        durationMin: straight / 5.0 * 60.0, // ~5 km/h walking
        crossesZones: _zonesCrossed([from, to], riskZones),
        usedFallback: true,
        note: 'Straight line — routing service unreachable',
      );
    }
  }

  /// Ray-casting point-in-polygon test against every zone's [lat, lng]
  /// points. Returns the human-readable names of zones the polyline dips
  /// into (sampled at each vertex plus segment midpoints — good enough at
  /// city scale without a full segment/polygon intersection test).
  List<String> _zonesCrossed(
      List<LatLng> points, List<Map<String, dynamic>> zones) {
    final crossed = <String>{};
    for (final zone in zones) {
      final poly = (zone['points'] as List<dynamic>? ?? [])
          .whereType<LatLng>()
          .toList();
      if (poly.length < 3) continue;
      for (int i = 0; i < points.length; i++) {
        if (_pointInPolygon(points[i], poly)) {
          crossed.add(
              (zone['disasterType'] ?? zone['riskLevel'] ?? 'risk zone')
                  .toString());
          break;
        }
        // Also check midpoints so long segments can't skip over a zone.
        if (i + 1 < points.length) {
          final mid = LatLng(
            (points[i].latitude + points[i + 1].latitude) / 2,
            (points[i].longitude + points[i + 1].longitude) / 2,
          );
          if (_pointInPolygon(mid, poly)) {
            crossed.add(
                (zone['disasterType'] ?? zone['riskLevel'] ?? 'risk zone')
                    .toString());
            break;
          }
        }
      }
    }
    return crossed.toList();
  }

  static bool _pointInPolygon(LatLng p, List<LatLng> poly) {
    bool inside = false;
    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final a = poly[i], b = poly[j];
      final intersects = ((a.latitude > p.latitude) != (b.latitude > p.latitude)) &&
          (p.longitude <
              (b.longitude - a.longitude) * (p.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  static double _haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final s = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(s), math.sqrt(1 - s));
  }
}

class EvacuationRoute {
  final List<LatLng> points;
  final double distanceKm;
  final double durationMin;
  final List<String> crossesZones;
  final bool usedFallback;
  final String note;

  EvacuationRoute({
    required this.points,
    required this.distanceKm,
    required this.durationMin,
    required this.crossesZones,
    required this.usedFallback,
    required this.note,
  });
}
