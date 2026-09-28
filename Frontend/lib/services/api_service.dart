import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Single HTTP entry point to the local Flask + MySQL backend.
///
/// Every service (auth, reports, shelters, alerts, contacts, location
/// shares, admin) goes through here so:
///   - the base URL lives in exactly one place, and
///   - the JWT auth header is attached consistently.
///
/// Base URL by target:
///   - Android emulator:  http://10.0.2.2:5000  (emulator's alias for host PC)
///   - Physical device:   http://<your-PC-LAN-IP>:5000  (ipconfig/ifconfig)
///   - iOS simulator:     http://localhost:5000
class ApiService {
  /// Base URL comes from AppConfig (override with
  /// --dart-define=API_BASE_URL=...). See the mapping above.
  static String get baseUrl => AppConfig.apiBaseUrl;

  /// JWT from POST /api/auth/login. Null when signed out / guest.
  static String? _authToken;

  static void setToken(String? token) {
    _authToken = token;
  }

  static String? get token => _authToken;

  static Map<String, String> _headers({bool auth = true, bool json = true}) {
    final headers = <String, String>{};
    if (json) headers['Content-Type'] = 'application/json';
    if (auth && _authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  /// Decoded JSON map, or throws [ApiException] with a user-safe message.
  static Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    bool auth = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
    try {
      final response = await http
          .get(uri, headers: _headers(auth: auth))
          .timeout(const Duration(seconds: 15));
      return _handle(response);
    } on Exception catch (e) {
      throw ApiException._(_networkMessage(e));
    }
  }

  static Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final response = await http
          .post(uri, headers: _headers(auth: auth), body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
      return _handle(response);
    } on Exception catch (e) {
      throw ApiException._(_networkMessage(e));
    }
  }

  static Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final response = await http
          .put(uri, headers: _headers(auth: auth), body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      return _handle(response);
    } on Exception catch (e) {
      throw ApiException._(_networkMessage(e));
    }
  }

  static Future<Map<String, dynamic>> delete(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final response = await http
          .delete(uri, headers: _headers(json: false))
          .timeout(const Duration(seconds: 15));
      return _handle(response);
    } on Exception catch (e) {
      throw ApiException._(_networkMessage(e));
    }
  }

  /// Multipart image upload (POST /api/reports/upload).
  static Future<Map<String, dynamic>> uploadReport({
    required Uint8List imageBytes,
    required String fileName,
    required double latitude,
    required double longitude,
    String? description,
  }) async {
    final uri = Uri.parse('$baseUrl/api/reports/upload');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_headers(json: false));

    request.files.add(
      http.MultipartFile.fromBytes('image', imageBytes, filename: fileName),
    );
    request.fields['latitude'] = latitude.toString();
    request.fields['longitude'] = longitude.toString();
    if (description != null && description.isNotEmpty) {
      request.fields['description'] = description;
    }

    try {
      final response =
          await request.send().timeout(const Duration(seconds: 60));
      final body = await response.stream.bytesToString();
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(body) as Map<String, dynamic>;
      }
      String message = 'Upload failed (${response.statusCode})';
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map && decoded['error'] != null) {
          message = decoded['error'].toString();
        }
      } catch (_) {}
      throw ApiException._(message);
    } on ApiException {
      rethrow;
    } on Exception catch (e) {
      throw ApiException._(_networkMessage(e));
    }
  }

  /// Absolute URL for a server-relative path like '/uploads/x.jpg' —
  /// used by Image.network for report photos.
  static String absoluteUrl(String pathOrUrl) {
    if (pathOrUrl.startsWith('http')) return pathOrUrl;
    return '$baseUrl${pathOrUrl.startsWith('/') ? '' : '/'}$pathOrUrl';
  }

  static Map<String, dynamic> _handle(http.Response response) {
    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? {} : jsonDecode(response.body);
    } catch (_) {
      decoded = <String, dynamic>{};
    }
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (ok) {
      if (decoded is Map<String, dynamic>) return decoded;
      return {'data': decoded};
    }
    String message = 'Request failed (${response.statusCode})';
    if (decoded is Map) {
      final err = decoded['error'] ?? decoded['message'];
      if (err != null) message = err.toString();
    }
    if (response.statusCode == 401 && message.contains('Token expired')) {
      message =
          'Your session expired — please log in again.';
    }
    throw ApiException._(message, statusCode: response.statusCode);
  }

  static String _networkMessage(Exception e) {
    final s = e.toString();
    if (s.contains('TimeoutException') || s.contains('timed out')) {
      return 'The server took too long to respond. Is the Flask backend running?';
    }
    if (s.contains('Connection refused') ||
        s.contains('Failed host lookup') ||
        s.contains('SocketException') ||
        s.contains('Connection attempt')) {
      return "Can't reach the server — check the backend is running and the address is correct.";
    }
    return 'Network error — please try again.';
  }
}

/// Thrown for any failed API call with a message safe to show directly.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException._(this.message, {this.statusCode});

  @override
  String toString() => message;
}
