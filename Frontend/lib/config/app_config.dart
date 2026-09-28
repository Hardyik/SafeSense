// Build-time configuration for the fully local SafeSense stack.
//
// Nothing here is a secret — it's all the same kind of LAN-address
// config you'd put in a `.env` for local development. The Flask backend
// reads its own settings from Backend/.env; this file is the Flutter
// side of the same contract.
//
// Override at build/run time if needed (e.g. testing on a physical
// phone over WiFi):
//
// ```bash
// flutter run --dart-define=API_BASE_URL=http://192.168.1.20:5000
// ```
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class AppConfig {
  AppConfig._();

  /// Base URL of the local Flask backend (Backend/app.py).
  /// ApiService reads this as its default baseUrl.
  ///
  /// Sensible default per target:
  ///   - Web (Chrome/Edge):  http://localhost:5000 — the browser runs on
  ///     the same PC as Flask.
  ///   - Android emulator:   http://10.0.2.2:5000 — the emulator's alias
  ///     for the host PC's loopback.
  ///   - iOS sim / desktop:  http://localhost:5000 — Flask is on the same
  ///     machine.
  ///   - Physical phone on WiFi: pass the PC's LAN IP explicitly via
  ///     --dart-define (see the header comment).
  static String get apiBaseUrl {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) return override;
    if (kIsWeb) return 'http://localhost:5000';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5000';
    }
    return 'http://localhost:5000';
  }

  /// Whether image uploads can be served over HTTP by the backend
  /// (always true for the local stack — the backend serves /uploads/).
  static bool get isBackendConfigured => apiBaseUrl.isNotEmpty;
}
