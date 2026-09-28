import 'dart:async';

import 'api_service.dart';

/// CRUD for a user's emergency contacts (Section 9), backed by the local
/// API's per-user emergency_contact table. Ownership is enforced
/// server-side from the JWT.
class EmergencyContactsService {
  EmergencyContactsService._internal();
  static final EmergencyContactsService instance =
      EmergencyContactsService._internal();

  /// Emits the current list and re-fetches on a short timer while listened
  /// to (request/response has no realtime snapshots). Add/edit/delete call
  /// [refreshNow] so the UI updates immediately after a change.
  Stream<List<Map<String, dynamic>>> streamContacts(String userId) {
    if (userId.isEmpty) return const Stream.empty();
    return (_streams.putIfAbsent(userId, () => _makeStream(userId))!)
        .stream;
  }

  final Map<String, StreamController<List<Map<String, dynamic>>>?> _streams =
      {};

  StreamController<List<Map<String, dynamic>>> _makeStream(String userId) {
    late StreamController<List<Map<String, dynamic>>> controller;
    Timer? timer;
    List<Map<String, dynamic>>? last;

    Future<void> tick() async {
      try {
        final data = await ApiService.get('/api/emergency-contacts');
        last = (data['contacts'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(_normalize)
            .toList();
        controller.add(last!);
      } on ApiException {
        if (last == null) controller.add([]);
      } catch (_) {
        if (last == null) controller.add([]);
      }
    }

    controller = StreamController<List<Map<String, dynamic>>>.broadcast(
      onListen: () {
        tick();
        timer = Timer.periodic(const Duration(seconds: 15), (_) => tick());
      },
      onCancel: () {
        timer?.cancel();
        // Allow a fresh stream (and immediate fetch) next time the page
        // is opened — otherwise a contact added elsewhere wouldn't appear
        // until the next tick.
        Future.delayed(const Duration(seconds: 1), () {
          if (!controller.hasListener) _streams.remove(userId);
        });
      },
    );
    return controller;
  }

  /// Force the cached stream for [userId] to re-fetch immediately.
  Future<void> refreshNow(String userId) async {
    final controller = _streams[userId];
    if (controller != null && !controller.isClosed) {
      try {
        final data = await ApiService.get('/api/emergency-contacts');
        controller.add((data['contacts'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(_normalize)
            .toList());
      } catch (_) {}
    }
  }

  /// MySQL row → Firestore-era shape (string id, camel-free keys the
  /// pages already read).
  static Map<String, dynamic> _normalize(Map<String, dynamic> c) => {
        'id': '${c['contact_id'] ?? c['id']}',
        'name': c['name'],
        'phone': c['phone'],
        'relationship': c['relationship'] ?? '',
      };

  Future<void> addContact({
    required String userId,
    required String name,
    required String phone,
    String relationship = '',
  }) async {
    await ApiService.post('/api/emergency-contacts', {
      'name': name.trim(),
      'phone': phone.trim(),
      'relationship': relationship.trim(),
    });
    await refreshNow(userId);
  }

  Future<void> updateContact(
    String contactId, {
    required String name,
    required String phone,
    String relationship = '',
  }) async {
    await ApiService.put('/api/emergency-contacts/$contactId', {
      'name': name.trim(),
      'phone': phone.trim(),
      'relationship': relationship.trim(),
    });
  }

  Future<void> deleteContact(String contactId) =>
      ApiService.delete('/api/emergency-contacts/$contactId');
}
