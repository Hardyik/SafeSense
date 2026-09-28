import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'api_service.dart';

/// Temporary location sharing (Section 10): explicit start/stop, auto-
/// expires after a chosen duration, backed by the local API's
/// location_share table.
///
/// IMPORTANT LIMITATION (unchanged from the Firestore version): updates
/// run on a timer while the app is open in the foreground — no background
/// service, no tracking when the app is closed. The UI makes "keep the app
/// open while sharing" clear.
class LocationSharingService {
  LocationSharingService._internal();
  static final LocationSharingService instance =
      LocationSharingService._internal();

  Timer? _updateTimer;
  String? _activeShareId;

  bool get isSharing => _activeShareId != null;

  /// Starts sharing. [sharedWithUserIds] is accepted for call-site
  /// compatibility; a fully-local build has no other-app-user sharing, so
  /// contacts you share with are the ones you'd send your live location to
  /// yourself (or verify in the DB).
  Future<String> startSharing({
    required String userId,
    required List<String> sharedWithUserIds,
    Duration duration = const Duration(hours: 1),
  }) async {
    final position = await Geolocator.getCurrentPosition();
    final data = await ApiService.post('/api/location-shares', {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'durationHours': duration.inMinutes / 60.0,
    });

    _activeShareId = '${data['id']}';
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _pushLocationUpdate(_activeShareId!);
    });

    return _activeShareId!;
  }

  Future<void> _pushLocationUpdate(String shareId) async {
    try {
      final position = await Geolocator.getCurrentPosition();
      await ApiService.put('/api/location-shares/$shareId', {
        'latitude': position.latitude,
        'longitude': position.longitude,
      });
    } catch (_) {
      // Non-fatal — next tick tries again.
    }
  }

  /// Stop early. (Automatic expiry after the chosen duration happens
  /// server-side via expires_at.)
  Future<void> stopSharing() async {
    _updateTimer?.cancel();
    _updateTimer = null;
    final id = _activeShareId;
    _activeShareId = null;
    if (id != null) {
      try {
        await ApiService.delete('/api/location-shares/$id');
      } catch (_) {
        // If the stop call fails the share still expires server-side.
      }
    }
  }

  /// Check for an active share on startup so the UI can reflect that state.
  Future<Map<String, dynamic>?> getActiveShare(String userId) async {
    if (userId.isEmpty) return null;
    try {
      final data = await ApiService.get('/api/location-shares');
      final shares = data['shares'] as List<dynamic>? ?? [];
      if (shares.isEmpty) return null;
      final doc = shares.first as Map<String, dynamic>;
      _activeShareId = '${doc['id']}';
      _updateTimer?.cancel();
      _updateTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _pushLocationUpdate(_activeShareId!);
      });
      return {
        'id': '${doc['id']}',
        'expiresAt': doc['expires_at'] != null
            ? DateTime.tryParse(doc['expires_at'].toString())?.toLocal()
            : null,
      };
    } on ApiException {
      return null;
    }
  }
}
