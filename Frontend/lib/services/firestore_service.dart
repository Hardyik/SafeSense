import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import 'api_service.dart';

/// Compatibility facade: the pages were written against a Firestore-backed
/// service of this name; this version serves the exact same data shapes
/// from the local Flask + MySQL backend instead.
///
/// Key formats (kept deliberately legacy-shaped so the UI didn't change):
///   - hazard report: { id, damage_type, hazard_level, confidence,
///     road_status, latitude, longitude, created_at }
///   - shelter:       { id, name, latitude, longitude, capacity,
///     occupancy + current_occupancy, contact + phone, status, type }
///   - risk zone:     { id, points: List<LatLng>, riskLevel, disasterType }
class FirestoreService {
  FirestoreService._internal();
  static final FirestoreService instance = FirestoreService._internal();

  /// All approved hazard reports for the map.
  Future<List<dynamic>> getHazards() async {
    try {
      final data = await ApiService.get('/api/reports/hazards', auth: false);
      return data['hazards'] as List<dynamic>? ?? [];
    } on ApiException {
      return [];
    }
  }

  /// Hazards within [radiusKm] of a point (dashboard "near you" card).
  Future<List<dynamic>> getNearbyHazards(
    double latitude,
    double longitude, {
    double radiusKm = 5,
  }) async {
    try {
      final data = await ApiService.get('/api/reports/nearby', query: {
        'lat': '$latitude',
        'lng': '$longitude',
        'radius': '$radiusKm',
      }, auth: false);
      return data['nearby_hazards'] as List<dynamic>? ?? [];
    } on ApiException {
      return [];
    }
  }

  /// All shelters (sorted by the caller — Emergency Mode sorts by distance).
  /// Includes both `occupancy`/`contact` and `current_occupancy`/`phone`
  /// spellings because different screens read different keys.
  Future<List<dynamic>> getShelters() async {
    try {
      final data = await ApiService.get('/api/shelters', auth: false);
      final raw = data['shelters'] as List<dynamic>? ?? [];
      return raw.map(_normalizeShelter).toList();
    } on ApiException {
      return [];
    }
  }

  /// Nearest available shelter to a point (Evacuate button).
  Future<Map<String, dynamic>> getNearestShelter(
    double latitude,
    double longitude,
  ) async {
    try {
      final data = await ApiService.get('/api/shelters/nearest', query: {
        'lat': '$latitude',
        'lng': '$longitude',
      }, auth: false);
      final shelter = data['nearest_shelter'];
      if (shelter is Map<String, dynamic>) return _normalizeShelter(shelter);
      return {};
    } on ApiException {
      return {};
    }
  }

  /// Risk zones with `points` already parsed into List<LatLng>.
  Future<List<dynamic>> getRiskZones() async {
    try {
      final data = await ApiService.get('/api/risk-zones', auth: false);
      final raw = data['risk_zones'] as List<dynamic>? ?? [];
      return raw.map((z) {
        final m = z as Map<String, dynamic>;
        final pts = (m['points'] as List<dynamic>? ?? [])
            .whereType<List<dynamic>>()
            .where((p) => p.length >= 2)
            .map((p) => LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()))
            .toList();
        return {
          'id': m['id'],
          'points': pts,
          'riskLevel': m['riskLevel'],
          'disasterType': m['disasterType'],
          'status': m['status'],
        };
      }).toList();
    } on ApiException {
      return [];
    }
  }

  /// Submit a report (photo + location + optional note). The backend
  /// identifies the user from the JWT, so [userId] is accepted for call-site
  /// compatibility but not sent.
  Future<Map<String, dynamic>> uploadReport({
    required List<int> imageBytes,
    required String fileName,
    required double latitude,
    required double longitude,
    String? userId,
    String? description,
  }) async {
    try {
      return await ApiService.uploadReport(
        imageBytes: Uint8List.fromList(imageBytes),
        fileName: fileName,
        latitude: latitude,
        longitude: longitude,
        description: description,
      );
    } on ApiException catch (e) {
      return {'status': 'error', 'error': e.message};
    }
  }

  /// Reports submitted by [userId] (profile → Report History).
  Future<List<dynamic>> getUserReports(String userId) async {
    if (userId.isEmpty) return [];
    try {
      final data = await ApiService.get('/api/reports/user/$userId');
      return data['reports'] as List<dynamic>? ?? [];
    } on ApiException {
      return [];
    }
  }

  Future<int> getUserReportCount(String userId) async {
    final reports = await getUserReports(userId);
    return reports.length;
  }

  /// Full detail for the report-detail page (adds imageUrl/description on
  /// top of the legacy list-item shape). imageUrl is rewritten to an
  /// absolute URL so Image.network can load it directly.
  Future<Map<String, dynamic>?> getReportDetail(String reportId) async {
    try {
      final data = await ApiService.get('/api/reports/$reportId', auth: false);
      final report = data['report'] as Map<String, dynamic>?;
      if (report == null) return null;
      final url = (report['imageUrl'] ?? report['image_url'] ?? '').toString();
      return {
        ...report,
        'imageUrl': url.isNotEmpty ? ApiService.absoluteUrl(url) : '',
      };
    } on ApiException {
      return null;
    }
  }

  /// Debug/testing helper — inserts a row without a photo or AI analysis.
  Future<bool> createReport({
    required String damageType,
    required String hazardLevel,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final data = await ApiService.post('/api/reports/manual', {
        'damage_type': damageType,
        'hazard_level': hazardLevel,
        'latitude': latitude,
        'longitude': longitude,
      });
      return data['status'] == 'success';
    } on ApiException {
      return false;
    }
  }

  static Map<String, dynamic> _normalizeShelter(dynamic s) {
    final m = s as Map<String, dynamic>;
    return {
      'id': m['id'] ?? m['shelter_id'],
      'name': m['name'],
      'latitude': m['latitude'],
      'longitude': m['longitude'],
      'capacity': m['capacity'],
      'occupancy': m['occupancy'] ?? m['current_occupancy'],
      'current_occupancy': m['current_occupancy'] ?? m['occupancy'],
      'contact': m['contact'] ?? m['phone'],
      'phone': m['phone'] ?? m['contact'],
      'status': m['status'],
      'type': m['type'],
      if (m['distance_km'] != null) 'distance_km': m['distance_km'],
    };
  }
}
