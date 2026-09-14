import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(const SafeSenseApp());
}

// ============================================================
// CONSTANTS
// ============================================================
// Design goal: this is an EMERGENCY app. Every screen should answer
// "what do I do right now?" in under 2 seconds. Big touch targets,
// big text, minimal steps, color = meaning (never decoration only).

const Color kPrimary = Color(0xFF087F8C); // calm brand / trust
const Color kPrimaryDark = Color(0xFF065F68);
const Color kPrimaryLight = Color(0xFFB2EBF2);
const Color kDanger =
    Color(0xFFD32F2F); // slightly deeper red = more legible on white
const Color kWarning = Color(0xFFF57C00);
const Color kSafe = Color(0xFF2E7D32);
const Color kBg = Color(0xFFF4F6F9);
const Color kInk = Color(0xFF1A1A1A);

// Shared helpers so every screen agrees on what a color/icon means.
Color hazardColor(String? level) {
  switch (level) {
    case 'danger':
      return kDanger;
    case 'moderate':
      return kWarning;
    case 'safe':
      return kSafe;
    default:
      return Colors.grey;
  }
}

IconData hazardIcon(String? type) {
  switch (type?.toLowerCase()) {
    case 'flood':
      return Icons.water;
    case 'fire':
      return Icons.local_fire_department;
    case 'collapsed_building':
      return Icons.broken_image;
    case 'hazard':
      return Icons.report_problem;
    default:
      return Icons.warning_amber_rounded;
  }
}

// Handles multi-word class names like "collapsed_building" -> "Collapsed Building"
String titleCase(String? s) {
  if (s == null || s.isEmpty) return 'Unknown';
  return s
      .replaceAll('_', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

// ============================================================
// API SERVICE (unchanged logic — only the transport layer)
// ============================================================

class ApiService {
  static const String baseUrl = 'http://localhost:5000';
  // For Android emulator: 'http://10.0.2.2:5000'
  // For physical device on WiFi: use your computer's IP (ipconfig/ifconfig)

  static String? _authToken;

  static void setToken(String? token) {
    _authToken = token;
  }

  static String? get token => _authToken;

  static Map<String, String> _authHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  static Map<String, String> _multipartHeaders() {
    final headers = <String, String>{};
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['token'] != null) {
          _authToken = data['token'];
        }
        return data;
      } else {
        return {
          'status': 'error',
          'error': 'Login failed: ${response.statusCode}'
        };
      }
    } catch (e) {
      return {'status': 'error', 'error': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String name,
    String? phone,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'password': password,
              'name': name,
              'phone': phone ?? '',
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 201 || response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {'status': 'error', 'error': 'Registration failed'};
      }
    } catch (e) {
      return {'status': 'error', 'error': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> uploadReport({
    required Uint8List imageBytes,
    required String fileName,
    required double latitude,
    required double longitude,
    int? userId,
    String? description,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/reports/upload');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(_multipartHeaders());

      request.files.add(
        http.MultipartFile.fromBytes('image', imageBytes, filename: fileName),
      );

      request.fields['latitude'] = latitude.toString();
      request.fields['longitude'] = longitude.toString();

      if (userId != null && userId > 0) {
        request.fields['user_id'] = userId.toString();
      }
      if (description != null && description.isNotEmpty) {
        request.fields['description'] = description;
      }

      final response =
          await request.send().timeout(const Duration(seconds: 30));
      final body = await response.stream.bytesToString();

      if (response.statusCode == 201 || response.statusCode == 200) {
        return jsonDecode(body);
      } else {
        return {'status': 'error', 'error': 'Upload failed'};
      }
    } catch (e) {
      return {'status': 'error', 'error': 'Network error: $e'};
    }
  }

  static Future<List<dynamic>> getHazards() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/reports/hazards'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['hazards'] as List<dynamic>? ?? [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<List<dynamic>> getNearbyHazards(
    double latitude,
    double longitude, {
    double radiusKm = 5,
  }) async {
    try {
      final response = await http
          .get(Uri.parse(
              '$baseUrl/api/reports/nearby?lat=$latitude&lng=$longitude&radius=$radiusKm'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['nearby_hazards'] as List<dynamic>? ?? [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> getNearestShelter(
    double latitude,
    double longitude,
  ) async {
    try {
      final response = await http
          .get(Uri.parse(
              '$baseUrl/api/shelters/nearest?lat=$latitude&lng=$longitude'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['nearest_shelter'] as Map<String, dynamic>? ?? {};
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  static Future<int> getUserReportCount(int userId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/reports/user/$userId'),
            headers: _authHeaders(),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['reports'] as List<dynamic>?)?.length ?? 0;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  static void logout() {
    _authToken = null;
  }
}

// ============================================================
// APP
// ============================================================

class SafeSenseApp extends StatelessWidget {
  const SafeSenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SafeSense',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kBg,
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: kPrimary,
          brightness: Brightness.light,
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 16, height: 1.4),
          bodyLarge: TextStyle(fontSize: 17, height: 1.4),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          centerTitle: true,
          surfaceTintColor: Colors.transparent,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
            elevation: 0,
            minimumSize: const Size.fromHeight(58),
            textStyle:
                const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: kPrimary,
            minimumSize: const Size.fromHeight(58),
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            side: const BorderSide(color: kPrimary, width: 1.5),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kPrimary, width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
      ),
      home: const WelcomePage(),
    );
  }
}

// ============================================================
// WELCOME PAGE
// The single entry point. Getting help never waits on an account —
// "Continue" drops you straight into the app as a guest. Login is a
// small secondary link for people who want to report hazards.
// ============================================================

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  color: kPrimary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_outlined,
                    size: 52, color: Colors.white),
              ),
              const SizedBox(height: 20),
              const Text(
                'SafeSense',
                style: TextStyle(
                    fontSize: 32, fontWeight: FontWeight.bold, color: kInk),
              ),
              const SizedBox(height: 8),
              Text(
                'See the hazard. Find the safe way.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.arrow_forward, size: 22),
                  label: const Text('Continue — See hazards & shelters'),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const HomePage(userId: 0, userName: 'Guest'),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                  );
                },
                child: const Text(
                  'Log in to report hazards',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: kPrimaryDark),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// LOGIN PAGE
// ============================================================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool showPassword = false;
  bool loading = false;
  String? errorMessage;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void login() async {
    setState(() => errorMessage = null);

    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => errorMessage = 'Please enter email and password');
      return;
    }
    if (!email.contains('@')) {
      setState(() => errorMessage = 'Please enter a valid email');
      return;
    }

    setState(() => loading = true);
    final result = await ApiService.login(email, password);
    setState(() => loading = false);

    if (!mounted) return;

    if (result['status'] == 'success' && result['user'] != null) {
      int userId = result['user']['id'];
      if (result['token'] != null) {
        ApiService.setToken(result['token']);
      }
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => HomePage(
              userId: userId, userName: result['user']['name'] ?? 'User'),
        ),
        (route) => false,
      );
    } else {
      setState(() => errorMessage = result['error'] ?? 'Login failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Welcome back',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Log in to report hazards near you',
                  style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
              const SizedBox(height: 28),
              if (errorMessage != null) ...[
                _ErrorBanner(message: errorMessage!),
                const SizedBox(height: 20),
              ],
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'you@example.com',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: !showPassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => login(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  hintText: 'Enter your password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () =>
                        setState(() => showPassword = !showPassword),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: loading ? null : login,
                  child: loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Log in'),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Text.rich(
                  TextSpan(
                    text: "Don't have an account? ",
                    style: const TextStyle(color: Colors.grey),
                    children: [
                      TextSpan(
                        text: 'Sign up',
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const RegisterPage()),
                            );
                          },
                        style: const TextStyle(
                            color: kPrimaryDark, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// REGISTER PAGE
// ============================================================

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final phoneController = TextEditingController();

  bool showPassword = false;
  bool loading = false;
  String? errorMessage;
  String? successMessage;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  void register() async {
    setState(() {
      errorMessage = null;
      successMessage = null;
    });

    final name = nameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text;
    final phone = phoneController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => errorMessage = 'Please fill all required fields');
      return;
    }
    if (!email.contains('@')) {
      setState(() => errorMessage = 'Please enter a valid email');
      return;
    }
    if (password.length < 6) {
      setState(() => errorMessage = 'Password must be at least 6 characters');
      return;
    }

    setState(() => loading = true);
    final result = await ApiService.register(
      email: email,
      password: password,
      name: name,
      phone: phone,
    );
    setState(() => loading = false);

    if (!mounted) return;

    if (result['status'] == 'success') {
      setState(
          () => successMessage = 'Account created! Redirecting to login...');
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context);
    } else {
      setState(() => errorMessage = result['error'] ?? 'Registration failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Create account',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Join SafeSense to report and help others',
                  style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
              const SizedBox(height: 24),
              if (errorMessage != null) ...[
                _ErrorBanner(message: errorMessage!),
                const SizedBox(height: 16),
              ],
              if (successMessage != null) ...[
                _SuccessBanner(message: successMessage!),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  hintText: 'John Doe',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'you@example.com',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                  hintText: '9876543210',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: passwordController,
                obscureText: !showPassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => register(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  hintText: 'At least 6 characters',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () =>
                        setState(() => showPassword = !showPassword),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: loading ? null : register,
                  child: loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Create account'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// HOME SHELL — 3 tabs + a big always-visible Report FAB
// ============================================================

class HomePage extends StatefulWidget {
  final int userId;
  final String userName;
  const HomePage({super.key, required this.userId, required this.userName});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  void _handleReportTap() {
    if (widget.userId == 0) {
      // Guests get prompted only at the point they actually need it —
      // not blocked from anything else in the app.
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 36, color: kPrimary),
              const SizedBox(height: 12),
              const Text('Log in to report a hazard',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'This helps us verify reports and keep the map trustworthy.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                    );
                  },
                  child: const Text('Log in'),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => UploadPage(userId: widget.userId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = widget.userId == 0;
    final pages = <Widget>[
      DashboardPage(
          userId: widget.userId,
          isGuest: isGuest,
          onReportTap: _handleReportTap),
      MapPage(userId: widget.userId),
      ProfilePage(userId: widget.userId, userName: widget.userName),
    ];

    return Scaffold(
      body: pages[_currentIndex],
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: SizedBox(
        width: 66,
        height: 66,
        child: FloatingActionButton(
          onPressed: _handleReportTap,
          backgroundColor: kDanger,
          elevation: 3,
          shape: const CircleBorder(),
          child: const Icon(Icons.camera_alt, color: Colors.white, size: 28),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: Colors.white,
        height: 74,
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(Icons.home_rounded, 'Home', 0),
            _navItem(Icons.map_rounded, 'Map', 1),
            const SizedBox(width: 48), // notch space for FAB
            _navItem(Icons.person_rounded, 'Profile', 2),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final selected = _currentIndex == index;
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: selected ? kPrimary : Colors.grey.shade400, size: 26),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? kPrimary : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// DASHBOARD / HOME — status-first layout
// ============================================================

class DashboardPage extends StatefulWidget {
  final int userId;
  final bool isGuest;
  final VoidCallback onReportTap;

  const DashboardPage({
    super.key,
    required this.userId,
    required this.isGuest,
    required this.onReportTap,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  List<dynamic> nearbyHazards = [];
  Map<String, dynamic> nearestShelter = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => loading = true);
    final hazards = await ApiService.getNearbyHazards(19.2456, 73.1300);
    final shelter = await ApiService.getNearestShelter(19.2456, 73.1300);
    if (mounted) {
      setState(() {
        nearbyHazards = hazards;
        nearestShelter = shelter;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final worstLevel = _worstLevel();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, color: kPrimary, size: 24),
            SizedBox(width: 8),
            Text('SafeSense',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: kPrimaryDark)),
          ],
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : RefreshIndicator(
              color: kPrimary,
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                children: [
                  // ---- STATUS CARD — the single most important thing on screen
                  _StatusCard(
                      level: worstLevel, hazardCount: nearbyHazards.length),

                  const SizedBox(height: 16),

                  // ---- TWO BIG PRIMARY ACTIONS
                  Row(
                    children: [
                      Expanded(
                        child: _BigActionTile(
                          icon: Icons.camera_alt_rounded,
                          label: 'Report\nHazard',
                          color: kDanger,
                          onTap: widget.onReportTap,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _BigActionTile(
                          icon: Icons.home_work_rounded,
                          label: 'Find\nShelter',
                          color: kPrimary,
                          onTap: () {
                            DefaultTabController.maybeOf(context);
                            final state = context
                                .findAncestorStateOfType<_HomePageState>();
                            state?.setState(() => state._currentIndex = 1);
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  if (widget.isGuest) ...[
                    _InfoBanner(
                      icon: Icons.info_outline,
                      color: Colors.blue,
                      message:
                          'Browsing as guest. Log in to submit hazard reports.',
                    ),
                    const SizedBox(height: 20),
                  ],

                  Text('Nearby Hazards (${nearbyHazards.length})',
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: kInk)),
                  const SizedBox(height: 10),

                  if (nearbyHazards.isEmpty)
                    _emptyState(
                      icon: Icons.check_circle_outline,
                      message: 'No hazards nearby. You are safe!',
                      color: kSafe,
                    )
                  else
                    ...nearbyHazards.map((h) => _HazardTile(hazard: h)),

                  const SizedBox(height: 24),

                  const Text('Nearest Shelter',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: kInk)),
                  const SizedBox(height: 10),

                  if (nearestShelter.isEmpty)
                    _emptyState(
                      icon: Icons.home_work_outlined,
                      message: 'No shelters found nearby',
                      color: Colors.grey,
                    )
                  else
                    _ShelterTile(shelter: nearestShelter),
                ],
              ),
            ),
    );
  }

  String? _worstLevel() {
    if (nearbyHazards.isEmpty) return 'safe';
    if (nearbyHazards.any((h) => h['hazard_level'] == 'danger'))
      return 'danger';
    if (nearbyHazards.any((h) => h['hazard_level'] == 'moderate'))
      return 'moderate';
    return 'safe';
  }

  Widget _emptyState({
    required IconData icon,
    required String message,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 36, color: color.withOpacity(0.5)),
            const SizedBox(height: 10),
            Text(message,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }
}

// ---- Status hero card: the one glance that tells you everything ----
class _StatusCard extends StatelessWidget {
  final String? level;
  final int hazardCount;
  const _StatusCard({required this.level, required this.hazardCount});

  @override
  Widget build(BuildContext context) {
    final color = hazardColor(level);
    final isSafe = level == 'safe' || level == null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.35),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          Icon(
            isSafe ? Icons.check_circle_rounded : Icons.warning_rounded,
            color: Colors.white,
            size: 42,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSafe ? 'You are safe' : 'Hazard nearby',
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  isSafe
                      ? 'No active hazards detected around you'
                      : '$hazardCount hazard${hazardCount == 1 ? '' : 's'} reported near your location',
                  style: TextStyle(
                      fontSize: 13, color: Colors.white.withOpacity(0.9)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BigActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _BigActionTile(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _HazardTile extends StatelessWidget {
  final dynamic hazard;
  const _HazardTile({required this.hazard});

  @override
  Widget build(BuildContext context) {
    final color = hazardColor(hazard['hazard_level']);
    final confidence = (hazard['confidence'] ?? 0) is num
        ? ((hazard['confidence'] ?? 0) * 100).toStringAsFixed(0)
        : '0';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                Icon(hazardIcon(hazard['damage_type']), color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titleCase(hazard['damage_type']),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 3),
                Text(
                  '${hazard['road_status'] ?? ''}  ·  $confidence% confidence',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Text(
              (hazard['hazard_level'] ?? 'unknown').toString().toUpperCase(),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShelterTile extends StatelessWidget {
  final Map<String, dynamic> shelter;
  const _ShelterTile({required this.shelter});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
                color: kPrimaryLight.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12)),
            child:
                const Icon(Icons.home_work_outlined, color: kPrimary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shelter['name'] ?? 'Unknown',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 3),
                Text(
                    '${(shelter['distance_km'] ?? 0).toStringAsFixed(1)} km away',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: kPrimaryLight.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8)),
            child: Text(shelter['phone'] ?? 'N/A',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: kPrimaryDark)),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;
  const _InfoBanner(
      {required this.icon, required this.color, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
              child: Text(message,
                  style:
                      TextStyle(fontSize: 13, color: color.withOpacity(0.9)))),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kDanger.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kDanger.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: kDanger, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message, style: const TextStyle(color: kDanger))),
        ],
      ),
    );
  }
}

class _SuccessBanner extends StatelessWidget {
  final String message;
  const _SuccessBanner({required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSafe.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kSafe.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: kSafe, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: kSafe))),
        ],
      ),
    );
  }
}

// ============================================================
// UPLOAD PAGE — as few steps as possible: open camera → confirm → send.
// Location is fetched automatically the moment the page opens instead
// of requiring manual entry.
// ============================================================

class UploadPage extends StatefulWidget {
  final int userId;
  const UploadPage({super.key, required this.userId});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  XFile? selectedImage;
  Uint8List? _imageBytes;
  bool loading = false;
  bool _locating = false;
  bool _showDetails = false;

  double? _lat;
  double? _lng;
  final notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Try to get GPS immediately so the user never has to think about it.
    _getCurrentLocation(silent: true);
    // Jump straight to the camera — reduces one tap for the most common path.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      pickImage(ImageSource.camera);
    });
  }

  @override
  void dispose() {
    notesController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation({bool silent = false}) async {
    setState(() => _locating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!silent)
          _showMessage('Location services are disabled. Please enable GPS.',
              isError: true);
        setState(() => _locating = false);
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!silent)
            _showMessage('Location permission denied', isError: true);
          setState(() => _locating = false);
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (!silent) {
          _showMessage(
              'Location permission permanently denied. Enable in settings.',
              isError: true);
        }
        setState(() => _locating = false);
        return;
      }
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
        _locating = false;
      });
    } catch (e) {
      setState(() => _locating = false);
      if (!silent) _showMessage('Could not get location', isError: true);
    }
  }

  Future<void> pickImage(ImageSource source) async {
    if (kIsWeb && source == ImageSource.camera) {
      _showMessage('Camera works best on mobile. On desktop, use Gallery.');
    }
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: source,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        selectedImage = image;
        _imageBytes = bytes;
      });
    }
  }

  Future<void> uploadReport() async {
    if (selectedImage == null || _imageBytes == null) {
      _showMessage('Please select a photo first', isError: true);
      return;
    }
    if (_lat == null || _lng == null) {
      _showMessage('Still finding your location — try again in a moment',
          isError: true);
      await _getCurrentLocation();
      if (_lat == null || _lng == null) return;
    }

    setState(() => loading = true);

    final result = await ApiService.uploadReport(
      imageBytes: _imageBytes!,
      fileName: selectedImage!.name,
      latitude: _lat!,
      longitude: _lng!,
      userId: widget.userId,
      description: notesController.text.trim().isNotEmpty
          ? notesController.text.trim()
          : null,
    );

    setState(() => loading = false);
    if (!mounted) return;

    if (result['status'] == 'success') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => ResultPage(analysis: result['analysis'])),
      );
    } else {
      _showMessage(result['error'] ?? 'Upload failed', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
                color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? kDanger : kSafe,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Hazard',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: selectedImage == null
                  ? GestureDetector(
                      onTap: () => _showImageSourceDialog(),
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: kPrimary.withOpacity(0.3), width: 2),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                  color: kPrimary.withOpacity(0.1),
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.add_a_photo_outlined,
                                  size: 40, color: kPrimary),
                            ),
                            const SizedBox(height: 16),
                            const Text('Tap to add a photo',
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87)),
                            const SizedBox(height: 6),
                            Text(
                                'This is the only thing we need to get started',
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey.shade500)),
                          ],
                        ),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _imageBytes != null
                              ? Image.memory(_imageBytes!, fit: BoxFit.cover)
                              : const Center(
                                  child: CircularProgressIndicator()),
                          Positioned(
                            top: 12,
                            right: 12,
                            child: GestureDetector(
                              onTap: () => setState(() {
                                selectedImage = null;
                                _imageBytes = null;
                              }),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.close,
                                    color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                          // Location chip overlay — visible confirmation, zero taps needed.
                          Positioned(
                            left: 12,
                            bottom: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _locating
                                      ? const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white))
                                      : const Icon(Icons.location_on,
                                          color: Colors.white, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    _lat != null
                                        ? '${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)}'
                                        : 'Locating…',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 14),
            if (selectedImage != null) ...[
              // Progressive disclosure — the notes field is hidden unless
              // the person actually wants to add more detail.
              if (!_showDetails)
                TextButton.icon(
                  onPressed: () => setState(() => _showDetails = true),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add details (optional)'),
                )
              else
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Additional info (optional)',
                    hintText:
                        'e.g. Road near river bridge, water rising fast...',
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: loading ? null : uploadReport,
                  icon: loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded),
                  label: Text(loading ? 'Analyzing…' : 'Submit Report'),
                ),
              ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Camera'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Gallery'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 20),
              const Text('Add a photo',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: kPrimary),
                title: const Text('Take Photo'),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                onTap: () {
                  Navigator.pop(ctx);
                  pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.photo_library_outlined, color: kPrimary),
                title: const Text('Choose from Gallery'),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                onTap: () {
                  Navigator.pop(ctx);
                  pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// RESULT PAGE
// ============================================================

class ResultPage extends StatelessWidget {
  final Map<String, dynamic> analysis;
  const ResultPage({super.key, required this.analysis});

  @override
  Widget build(BuildContext context) {
    final hazardLevel = analysis['hazard_level'] ?? 'unknown';
    final levelColor = hazardColor(hazardLevel);
    final damageType = analysis['damage_type'] ?? 'Unknown';
    final confidence = analysis['confidence'] ?? 0;
    final roadStatus = analysis['road_status'] ?? 'Unknown';

    return Scaffold(
      appBar: AppBar(
          title: const Text('Analysis Result',
              style: TextStyle(fontWeight: FontWeight.w600))),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                        color: levelColor.withOpacity(0.12),
                        shape: BoxShape.circle),
                    child: Icon(hazardIcon(damageType),
                        size: 40, color: levelColor),
                  ),
                  const SizedBox(height: 16),
                  Text('${damageType.toString().toUpperCase()} Detected',
                      style: const TextStyle(
                          fontSize: 21, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                        color: levelColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      hazardLevel.toString().toUpperCase(),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: levelColor,
                          letterSpacing: 1),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      _statItem(
                          label: 'Confidence',
                          value: '${(confidence * 100).toStringAsFixed(0)}%',
                          color: kPrimary),
                      Container(
                          width: 1, height: 40, color: Colors.grey.shade200),
                      _statItem(
                          label: 'Road Status',
                          value: roadStatus,
                          color: levelColor),
                    ],
                  ),
                ],
              ),
            ),
            if (hazardLevel == 'danger') ...[
              const SizedBox(height: 16),
              _InfoBanner(
                icon: Icons.info_outline,
                color: kDanger,
                message:
                    'This is a high-risk report. Check the Map tab for the nearest shelter and avoid this route.',
              ),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () =>
                    Navigator.popUntil(context, (route) => route.isFirst),
                icon: const Icon(Icons.home_outlined),
                label: const Text('Back to Home'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(
      {required String label, required String value, required Color color}) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

// ============================================================
// MAP PAGE
// ============================================================

class MapPage extends StatefulWidget {
  final int userId;
  const MapPage({super.key, required this.userId});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  List<dynamic> hazards = [];
  List<dynamic> shelters = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => loading = true);
    final h = await ApiService.getHazards();
    final s = await _fetchShelters();
    if (mounted) {
      setState(() {
        hazards = h;
        shelters = s;
        loading = false;
      });
    }
  }

  Future<List<dynamic>> _fetchShelters() async {
    try {
      final response = await http
          .get(Uri.parse('${ApiService.baseUrl}/api/shelters'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['shelters'] as List<dynamic>? ?? [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hazard Map',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData)
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : Stack(
              children: [
                FlutterMap(
                  options: const MapOptions(
                      initialCenter: LatLng(19.9975, 73.7898), initialZoom: 12),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.safesense.app',
                    ),
                    MarkerLayer(
                      markers: [
                        ...hazards.map(
                          (h) => Marker(
                            point: LatLng((h['latitude'] as num).toDouble(),
                                (h['longitude'] as num).toDouble()),
                            width: 44,
                            height: 44,
                            child: GestureDetector(
                              onTap: () => _showHazardSheet(h),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: hazardColor(h['hazard_level']),
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 3),
                                  boxShadow: [
                                    BoxShadow(
                                        color: hazardColor(h['hazard_level'])
                                            .withOpacity(0.4),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2)),
                                  ],
                                ),
                                child: const Center(
                                    child: Icon(Icons.warning_rounded,
                                        color: Colors.white, size: 20)),
                              ),
                            ),
                          ),
                        ),
                        ...shelters.map(
                          (s) => Marker(
                            point: LatLng((s['latitude'] as num).toDouble(),
                                (s['longitude'] as num).toDouble()),
                            width: 46,
                            height: 46,
                            child: GestureDetector(
                              onTap: () => _showShelterSheet(s),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: kPrimary, width: 3),
                                  boxShadow: [
                                    BoxShadow(
                                        color: kPrimary.withOpacity(0.3),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2)),
                                  ],
                                ),
                                child: const Center(
                                    child: Icon(Icons.home_rounded,
                                        color: kPrimary, size: 22)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 2))
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _legendItem(kDanger, 'Hazard'),
                        _legendItem(kPrimary, 'Shelter'),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 8)
                      ],
                    ),
                    child: Text(
                      '${hazards.length} hazard${hazards.length == 1 ? '' : 's'} · ${shelters.length} shelter${shelters.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                color: Colors.black54,
                fontWeight: FontWeight.w500)),
      ],
    );
  }

  void _showHazardSheet(dynamic hazard) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Text(
                '${(hazard['damage_type'] ?? 'Unknown').toString().toUpperCase()}',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _detailRow('Hazard Level', hazard['hazard_level'] ?? 'Unknown'),
            _detailRow('Road Status', hazard['road_status'] ?? 'Unknown'),
            _detailRow('Confidence',
                '${(hazard['confidence'] * 100).toStringAsFixed(0)}%'),
            _detailRow(
                'Location', '${hazard['latitude']}, ${hazard['longitude']}'),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showShelterSheet(dynamic shelter) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                      color: kPrimaryLight.withOpacity(0.4),
                      shape: BoxShape.circle),
                  child:
                      const Icon(Icons.home_rounded, color: kPrimary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(shelter['name'] ?? 'Unknown Shelter',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _detailRow('Type', shelter['type'] ?? 'N/A'),
            _detailRow('Capacity', '${shelter['capacity'] ?? 'N/A'}'),
            _detailRow('Occupancy', '${shelter['occupancy'] ?? 0}'),
            _detailRow('Contact', shelter['contact'] ?? 'N/A'),
            _detailRow('Status', shelter['status'] ?? 'N/A'),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
          Text(value,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ============================================================
// PROFILE PAGE
// ============================================================

class ProfilePage extends StatefulWidget {
  final int userId;
  final String userName;
  const ProfilePage({super.key, required this.userId, required this.userName});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  int reportCount = 0;
  bool loadingCount = true;

  @override
  void initState() {
    super.initState();
    _loadReportCount();
  }

  Future<void> _loadReportCount() async {
    if (widget.userId == 0) {
      setState(() => loadingCount = false);
      return;
    }
    final count = await ApiService.getUserReportCount(widget.userId);
    if (mounted) {
      setState(() {
        reportCount = count;
        loadingCount = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = widget.userId == 0;

    return Scaffold(
      appBar: AppBar(
          title: const Text('Profile',
              style: TextStyle(fontWeight: FontWeight.w600))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                      color: kPrimary.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.person, color: kPrimary, size: 32),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.userName,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: isGuest
                              ? Colors.grey.withOpacity(0.1)
                              : kPrimaryLight.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          isGuest ? 'Guest' : 'Verified',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isGuest ? Colors.grey : kPrimaryDark),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (isGuest) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                    (route) => false,
                  );
                },
                icon: const Icon(Icons.login),
                label: const Text('Log in'),
              ),
            ),
          ] else ...[
            const Text('Statistics',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: kPrimaryLight.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.description_outlined,
                        color: kPrimary, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                      child: Text('Reports Submitted',
                          style: TextStyle(fontWeight: FontWeight.w500))),
                  loadingCount
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('$reportCount',
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: kPrimary)),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  ApiService.logout();
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const WelcomePage()),
                    (route) => false,
                  );
                },
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
