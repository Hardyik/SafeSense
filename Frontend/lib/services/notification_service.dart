import 'dart:async';

import 'package:flutter/material.dart';

import 'api_service.dart';
import '../main.dart' show rootScaffoldMessengerKey;

/// Local replacement for Firebase Cloud Messaging: polls the backend's
/// active emergency alerts and surfaces brand-new ones as in-app
/// SnackBars (the app's only UI surface for push — see Section 7).
///
/// A fully-local stack has no push channel, so "notifications" here means:
///   - in-app banners while the app is open (this poller), and
///   - the always-visible Active Alerts list on Emergency Mode.
///
/// [onNotificationTap] lets the host app navigate when a banner is
/// tapped (e.g. open Emergency Mode).
class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  Timer? _pollTimer;
  final Set<String> _shownAlertIds = {};
  bool _initialized = false;

  /// Called when the user taps an alert banner. Wire this from main.dart.
  void Function(Map<String, dynamic> alert)? onNotificationTap;

  /// Starts polling. Safe to call multiple times.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
    _check();
  }

  Future<void> _check() async {
    try {
      final data = await ApiService.get('/api/alerts', auth: false);
      final alerts = data['alerts'] as List<dynamic>? ?? [];
      for (final a in alerts) {
        if (a is! Map<String, dynamic>) continue;
        final id = '${a['id']}';
        if (_shownAlertIds.contains(id)) continue;
        _shownAlertIds.add(id);
        _showBanner(a);
      }
      // Keep the set bounded.
      if (_shownAlertIds.length > 200) {
        _shownAlertIds
            .removeAll(_shownAlertIds.take(_shownAlertIds.length - 100));
      }
    } on ApiException {
      // Backend down — try again next tick.
    } catch (_) {}
  }

  void _showBanner(Map<String, dynamic> a) {
    final severity = (a['severity'] ?? '').toString().toLowerCase();
    final color = severity == 'high' || severity == 'danger'
        ? Colors.red.shade700
        : severity == 'moderate'
            ? Colors.orange.shade800
            : Colors.teal;

    final messenger = rootScaffoldMessengerKey.currentState;
    messenger?.showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (a['disasterType'] ?? 'Emergency alert').toString(),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
            if ((a['affectedArea'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  a['affectedArea'].toString(),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.white,
          onPressed: () => onNotificationTap?.call(a),
        ),
      ),
    );
  }
}
