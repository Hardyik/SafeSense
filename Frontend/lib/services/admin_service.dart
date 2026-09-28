import 'dart:async';

import 'api_service.dart';

/// Admin-only operations for the Admin Dashboard, backed by the local
/// Flask + MySQL admin endpoints. Every call here is also enforced
/// server-side by @require_admin — this class is typed convenience, not
/// the security boundary.
///
/// The dashboard tabs render via StreamBuilder; since a request/response
/// API has no realtime snapshots, streams here re-fetch on a timer (and
/// immediately on demand). Tabs also refresh on pull-to-refresh/visibility
/// changes through [refreshNow].
class AdminService {
  AdminService._internal();
  static final AdminService instance = AdminService._internal();

  static const _pollInterval = Duration(seconds: 10);

  // ---- Pending report verification (Section 18) ----

  Stream<List<Map<String, dynamic>>> streamPendingReports() =>
      _pollStream(_fetchPendingReports);

  Future<List<Map<String, dynamic>>> _fetchPendingReports() async {
    final data = await ApiService.get('/api/admin/pending-reports');
    return (data['reports'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(_normalizeReport)
        .toList();
  }

  /// MySQL row → the Firestore-era shape the dashboard renders. IDs are
  /// coerced to String so call sites that pass them around as doc-id-style
  /// strings keep working unchanged.
  static Map<String, dynamic> _normalizeReport(Map<String, dynamic> r) {
    final imageUrl = (r['imageUrl'] ?? r['image_url'] ?? '').toString();
    return {
      'id': '${r['image_id'] ?? r['id']}',
      'imageUrl':
          imageUrl.isNotEmpty ? ApiService.absoluteUrl(imageUrl) : '',
      'description': r['description'],
      'latitude': r['latitude'],
      'longitude': r['longitude'],
      'status': r['status'],
      'createdAt': r['uploaded_at'] ?? r['created_at'],
      'damageType': r['damage_type'] ?? r['damageType'],
      'hazard_level': r['hazard_level'],
      'severity': r['severity'] ?? r['hazard_level'],
      'confidence': r['confidence'],
      'road_status': r['road_status'],
    };
  }

  Future<void> setReportStatus(String reportId, String status) async {
    await ApiService.put('/api/reports/$reportId/status', {'status': status});
  }

  // ---- Shelters (Section 14/23) ----

  Stream<List<Map<String, dynamic>>> streamShelters() =>
      _pollStream(_fetchShelters);

  Future<List<Map<String, dynamic>>> _fetchShelters() async {
    final data = await ApiService.get('/api/shelters', auth: false);
    return (data['shelters'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((s) => {
              'id': '${s['shelter_id'] ?? s['id']}',
              'name': s['name'],
              'latitude': s['latitude'],
              'longitude': s['longitude'],
              'capacity': s['capacity'],
              'occupancy': s['occupancy'] ?? s['current_occupancy'],
              'contact': s['contact'] ?? s['phone'],
              'status': s['status'],
              'type': s['type'],
            })
        .toList();
  }

  Future<void> upsertShelter({
    String? id,
    required String name,
    required double latitude,
    required double longitude,
    required int capacity,
    required int occupancy,
    required String contact,
    required String status,
    required String type,
  }) async {
    final body = {
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'capacity': capacity,
      'occupancy': occupancy,
      'contact': contact,
      'status': status,
      'type': type,
    };
    if (id != null) {
      await ApiService.put('/api/admin/shelters/$id', body);
    } else {
      await ApiService.post('/api/admin/shelters', body);
    }
  }

  Future<void> deleteShelter(String id) =>
      ApiService.delete('/api/admin/shelters/$id');

  // ---- Emergency alerts (Section 11/23) ----

  Stream<List<Map<String, dynamic>>> streamAlerts() =>
      _pollStream(_fetchAlerts);

  Future<List<Map<String, dynamic>>> _fetchAlerts() async {
    final data = await ApiService.get('/api/admin/alerts');
    return (data['alerts'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(_normalizeAlert)
        .toList();
  }

  static Map<String, dynamic> _normalizeAlert(Map<String, dynamic> a) => {
        'id': '${a['alert_id'] ?? a['id']}',
        'disasterType': a['disaster_type'] ?? a['disasterType'],
        'severity': a['severity'],
        'affectedArea': a['affected_area'] ?? a['affectedArea'],
        'description': a['description'],
        'recommendedAction': a['recommended_action'] ?? a['recommendedAction'],
        'status': a['status'],
        'createdAt': a['created_at'] ?? a['createdAt'],
        'expiresAt': a['expires_at'] ?? a['expiresAt'],
      };

  /// Publishes an alert. The backend records who created it and sets an
  /// expiry (default 6h). Note: unlike the old Cloudflare Worker there is
  /// no push notification — users see the alert in Emergency Mode's
  /// Active Alerts list.
  Future<void> createAlert({
    required String disasterType,
    required String severity,
    required String affectedArea,
    required String description,
    required String recommendedAction,
    Duration validFor = const Duration(hours: 6),
  }) async {
    await ApiService.post('/api/admin/alerts', {
      'disasterType': disasterType,
      'severity': severity,
      'affectedArea': affectedArea,
      'description': description,
      'recommendedAction': recommendedAction,
      'validForHours': validFor.inMinutes / 60.0,
    });
  }

  Future<void> expireAlertNow(String alertId) =>
      ApiService.put('/api/admin/alerts/$alertId', {'status': 'expired'});

  // ---- Risk zones (Section 12/23) ----

  Stream<List<Map<String, dynamic>>> streamRiskZones() =>
      _pollStream(_fetchRiskZones);

  Future<List<Map<String, dynamic>>> _fetchRiskZones() async {
    final data = await ApiService.get('/api/risk-zones', auth: false);
    return (data['risk_zones'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((z) => {
              'id': '${z['id']}',
              'points': z['points'],
              'riskLevel': z['riskLevel'],
              'disasterType': z['disasterType'],
              'status': z['status'],
            })
        .toList();
  }

  Future<void> createSquareRiskZone({
    required double centerLat,
    required double centerLng,
    required double radiusKm,
    required String riskLevel,
    required String disasterType,
  }) async {
    await ApiService.post('/api/admin/risk-zones', {
      'centerLat': centerLat,
      'centerLng': centerLng,
      'radiusKm': radiusKm,
      'riskLevel': riskLevel,
      'disasterType': disasterType,
    });
  }

  Future<void> deleteRiskZone(String id) =>
      ApiService.delete('/api/admin/risk-zones/$id');

  // ---- Admin promotion (Section 23) ----

  /// Promotes a MySQL user_id (integer) to admin. The dashboard shows the
  /// user list so admins don't have to know IDs by heart.
  Future<void> promoteToAdmin(String uid) async {
    await ApiService.post('/api/admin/promote', {'uid': uid});
  }

  /// Users for the promotion picker (id, name, email, current role).
  Future<List<Map<String, dynamic>>> listUsers() async {
    final data = await ApiService.get('/api/admin/users');
    return (data['users'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  // ---- Polling helper ----

  /// Re-fetches every [_pollInterval] and emits snapshots. The timer only
  /// runs while there are listeners, and each list is cached so tabs don't
  /// flash empty between refreshes.
  Stream<List<Map<String, dynamic>>> _pollStream(
    Future<List<Map<String, dynamic>>> Function() fetch,
  ) {
    late StreamController<List<Map<String, dynamic>>> controller;
    Timer? timer;
    List<Map<String, dynamic>>? last;

    Future<void> tick() async {
      try {
        last = await fetch();
        controller.add(last!);
      } on ApiException catch (e) {
        // Emit the last known data on failure so the UI doesn't blank out;
        // a 403 means the viewer isn't an admin — surface that via empty.
        if (last != null && e.statusCode != 403) controller.add(last!);
        if (last == null) controller.add([]);
      } catch (_) {
        if (last == null) controller.add([]);
      }
    }

    controller = StreamController<List<Map<String, dynamic>>>.broadcast(
      onListen: () {
        tick();
        timer = Timer.periodic(_pollInterval, (_) => tick());
      },
      onCancel: () => timer?.cancel(),
    );
    return controller.stream;
  }
}
