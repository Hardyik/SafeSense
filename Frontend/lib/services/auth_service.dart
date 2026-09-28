import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

/// Thrown for any auth failure with a message safe to show the user.
class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

/// The signed-in user, as returned by the Flask JWT endpoints.
class AuthUser {
  final String uid;
  final String email;
  final String? name;
  final String? phone;
  final String role;

  AuthUser({
    required this.uid,
    required this.email,
    this.name,
    this.phone,
    this.role = 'user',
  });

  factory AuthUser.fromMap(Map<String, dynamic> m) => AuthUser(
        uid: '${m['id'] ?? m['user_id'] ?? ''}',
        email: (m['email'] ?? '') as String,
        name: m['name'] as String?,
        phone: m['phone'] as String?,
        role: (m['role'] ?? 'user') as String,
      );
}

/// Wraps the Flask JWT auth endpoints and persists the session in
/// shared_preferences so the user stays signed in across restarts.
///
/// The rest of the app goes through this class — screens never talk to
/// ApiService auth endpoints directly.
class AuthService {
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  AuthUser? _currentUser;
  bool _loaded = false;

  /// Signed-in user, or null. Available synchronously after [restoreSession]
  /// (called once in main()).
  AuthUser? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;

  /// Restore the persisted session at startup. Returns the restored user
  /// (after re-validating the token against the backend) or null.
  Future<AuthUser?> restoreSession() async {
    if (_loaded) return _currentUser;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_kToken);
      final raw = prefs.getString(_kUser);
      if (token == null || raw == null) return null;

      ApiService.setToken(token);

      // Re-validate the token against the server. If the token is stale
      // (expired / DB reset) the session is dropped rather than kept.
      final me = await ApiService.get('/api/auth/me');
      final profile = me['profile'] as Map<String, dynamic>?;
      if (profile == null) {
        await _clear();
        return null;
      }
      _currentUser = AuthUser.fromMap(profile);
      await prefs.setString(_kUser, jsonEncode(profile));
      return _currentUser;
    } on ApiException catch (e) {
      debugPrint('Session restore failed: ${e.message}');
      await _clear();
      return null;
    } catch (e) {
      debugPrint('Session restore failed: $e');
      await _clear();
      return null;
    }
  }

  /// Emits immediately and after every sign-in/out — drop-in for the
  /// Firebase authStateChanges the pages used to listen to.
  Stream<AuthUser?> get authStateChanges => _stateController.stream;

  final _stateController = StreamController<AuthUser?>.broadcast();

  void _emit(AuthUser? user) {
    _currentUser = user;
    _stateController.add(user);
  }

  Future<AuthUser> register({
    required String email,
    required String password,
    required String name,
    String? phone,
  }) async {
    try {
      final data = await ApiService.post('/api/auth/register', {
        'email': email.trim(),
        'password': password,
        'name': name.trim(),
        'phone': phone ?? '',
      }, auth: false);
      final user = AuthUser.fromMap(
        (data['user'] as Map<String, dynamic>?) ??
            {'id': '', 'email': email.trim(), 'name': name.trim()},
      );
      final token = data['token'] as String?;
      if (token != null) await _persist(token, user);
      return user;
    } on ApiException catch (e) {
      throw AuthException(_mapError(e));
    }
  }

  Future<AuthUser> login({
    required String email,
    required String password,
  }) async {
    try {
      final data = await ApiService.post('/api/auth/login', {
        'email': email.trim(),
        'password': password,
      }, auth: false);
      final user = AuthUser.fromMap(data['user'] as Map<String, dynamic>);
      await _persist(data['token'] as String, user);
      return user;
    } on ApiException catch (e) {
      throw AuthException(_mapError(e));
    }
  }

  /// Local password reset — there's no email service on a fully-local
  /// backend, so this sends the new password over HTTP to the PC on your
  /// own network. Fine for a college demo; not for production.
  Future<void> resetPassword({
    required String email,
    required String newPassword,
  }) async {
    try {
      await ApiService.post('/api/auth/forgot-password', {
        'email': email.trim(),
        'new_password': newPassword,
      }, auth: false);
    } on ApiException catch (e) {
      throw AuthException(_mapError(e));
    }
  }

  Future<void> logout() async {
    ApiService.setToken(null);
    _emit(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUser);
  }

  Future<bool> isAdmin() async {
    final user = _currentUser;
    if (user == null) return false;
    // Fresh from the server — role changes take effect without re-login.
    try {
      final me = await ApiService.get('/api/auth/me');
      final profile = me['profile'] as Map<String, dynamic>?;
      if (profile != null) {
        _currentUser = AuthUser.fromMap(profile);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kUser, jsonEncode(profile));
      }
    } on ApiException catch (e) {
      debugPrint('isAdmin check failed: ${e.message}');
    }
    return _currentUser?.role == 'admin';
  }

  /// Profile fields for the current user (name/phone/role), or null.
  Future<Map<String, dynamic>?> getUserProfile() async {
    if (_currentUser == null) return null;
    try {
      final me = await ApiService.get('/api/auth/me');
      return me['profile'] as Map<String, dynamic>?;
    } on ApiException {
      return null;
    }
  }

  static const _kToken = 'safesense_jwt';
  static const _kUser = 'safesense_user';

  Future<void> _persist(String token, AuthUser user) async {
    ApiService.setToken(token);
    _emit(user);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
    await prefs.setString(_kUser, jsonEncode({
      'id': user.uid,
      'email': user.email,
      'name': user.name,
      'phone': user.phone,
      'role': user.role,
    }));
  }

  Future<void> _clear() async {
    ApiService.setToken(null);
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUser);
  }

  String _mapError(ApiException e) {
    if (e.statusCode == 401) return 'Incorrect email or password.';
    if (e.statusCode == 409) return 'An account with this email already exists.';
    final msg = e.message.toLowerCase();
    if (msg.contains('at least 6')) return 'Password should be at least 6 characters.';
    if (msg.contains('valid email')) return 'That email address looks invalid.';
    if (msg.contains('required')) return 'Please fill in all required fields.';
    return e.message;
  }
}
