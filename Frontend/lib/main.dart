import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

void main() {
  runApp(const SafeSenseApp());
}

// ============================================================
// CONSTANTS
// ============================================================

const Color kPrimary = Color(0xFF087F8C);
const Color kPrimaryDark = Color(0xFF065F68);
const Color kPrimaryLight = Color(0xFFB2EBF2);
const Color kDanger = Color(0xFFE53935);
const Color kWarning = Color(0xFFFF9800);
const Color kSafe = Color(0xFF43A047);
const Color kBg = Color(0xFFF4F6F9);

// ============================================================
// API SERVICE
// ============================================================

class ApiService {
  static const String baseUrl = 'http://localhost:5000';
  // For Android emulator: 'http://10.0.2.2:5000'
  // For physical device: 'http://192.168.X.X:5000'

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

  // Login
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

  // Register
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
            headers: _authHeaders(),
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

  // Upload report with image
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

  // Get all hazards
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

  // Get nearby hazards
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

  // Get nearest shelter
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

  // Get user reports count
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

  // Logout (clear token)
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
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: kPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            side: const BorderSide(color: kPrimary),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kPrimary, width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
      ),
      home: const LoginPage(),
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
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomePage(
              userId: userId, userName: result['user']['name'] ?? 'User'),
        ),
      );
    } else {
      setState(() => errorMessage = result['error'] ?? 'Login failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Hero Section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 60, 24, 40),
                decoration: const BoxDecoration(
                  color: kPrimary,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'SafeSense',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'See the hazard. Find the safe way.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                  ],
                ),
              ),

              // Form Section
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: kDanger.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kDanger.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: kDanger, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                errorMessage!,
                                style: const TextStyle(color: kDanger),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    const Text(
                      'Email',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: 'you@example.com',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Password',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: passwordController,
                      obscureText: !showPassword,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => login(),
                      decoration: InputDecoration(
                        hintText: 'Enter your password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
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
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Log in',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const HomePage(userId: 0, userName: 'Guest'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.explore_outlined),
                        label: const Text('Continue as guest'),
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
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
      setState(
          () => errorMessage = 'Password must be at least 6 characters');
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
              Text(
                'Create Account',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Join SafeSense to report and help others',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
              ),
              const SizedBox(height: 28),
              if (errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kDanger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kDanger.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: kDanger, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(errorMessage!,
                            style: const TextStyle(color: kDanger)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (successMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kSafe.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kSafe.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          color: kSafe, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(successMessage!,
                            style: const TextStyle(color: kSafe)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Text('Full Name',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: Colors.black87)),
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: 'John Doe',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Email',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: Colors.black87)),
              const SizedBox(height: 8),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: 'you@example.com',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Phone (optional)',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: Colors.black87)),
              const SizedBox(height: 8),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: '9876543210',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Password',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: Colors.black87)),
              const SizedBox(height: 8),
              TextField(
                controller: passwordController,
                obscureText: !showPassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => register(),
                decoration: InputDecoration(
                  hintText: 'At least 6 characters',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () =>
                        setState(() => showPassword = !showPassword),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: loading ? null : register,
                  child: loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Create Account',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
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
// HOME PAGE (Bottom Nav Shell)
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

  @override
  Widget build(BuildContext context) {
    final isGuest = widget.userId == 0;

    // Build page list — guests skip upload (index 1)
    final pages = <Widget>[
      DashboardPage(userId: widget.userId, isGuest: isGuest),
      if (!isGuest) UploadPage(userId: widget.userId),
      MapPage(userId: widget.userId),
      ProfilePage(userId: widget.userId, userName: widget.userName),
    ];

    // Clamp index if needed
    if (_currentIndex >= pages.length) {
      _currentIndex = 0;
    }

    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        backgroundColor: Colors.white,
        surfaceTintColor: kPrimaryLight,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: kPrimary),
            label: 'Home',
          ),
          if (!isGuest)
            const NavigationDestination(
              icon: Icon(Icons.camera_alt_outlined),
              selectedIcon: Icon(Icons.camera_alt, color: kPrimary),
              label: 'Report',
            ),
          const NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map, color: kPrimary),
            label: 'Map',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: kPrimary),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// ============================================================
// DASHBOARD PAGE
// ============================================================

class DashboardPage extends StatefulWidget {
  final int userId;
  final bool isGuest;

  const DashboardPage({super.key, required this.userId, required this.isGuest});

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

  Color _hazardColor(String? level) {
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

  IconData _hazardIcon(String? type) {
    switch (type) {
      case 'flood':
        return Icons.water;
      case 'fire':
        return Icons.local_fire_department;
      case 'collapse':
        return Icons.broken_image;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final topAlert = nearbyHazards.isNotEmpty ? nearbyHazards.first : null;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, color: kPrimary, size: 24),
            SizedBox(width: 8),
            Text(
              'SafeSense',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: kPrimaryDark),
            ),
          ],
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : RefreshIndicator(
              color: kPrimary,
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Guest banner
                  if (widget.isGuest)
                    _infoBanner(
                      icon: Icons.info_outline,
                      color: Colors.blue,
                      message:
                          'You are browsing as guest. Sign up to report hazards.',
                    ),

                  // Top danger alert (from real data)
                  if (!widget.isGuest && topAlert != null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _hazardColor(topAlert['hazard_level'])
                                .withOpacity(0.15),
                            _hazardColor(topAlert['hazard_level'])
                                .withOpacity(0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _hazardColor(topAlert['hazard_level'])
                              .withOpacity(0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: _hazardColor(topAlert['hazard_level'])
                                  .withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.warning_amber_rounded,
                              color: _hazardColor(topAlert['hazard_level']),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${(topAlert['damage_type'] ?? 'Hazard').toString().toUpperCase()} detected',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  topAlert['road_status'] ?? 'Check route',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: Colors.grey.shade400,
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Section header: Nearby Hazards
                  _sectionHeader('Nearby Hazards', '${nearbyHazards.length} active'),
                  const SizedBox(height: 12),

                  if (nearbyHazards.isEmpty)
                    _emptyState(
                      icon: Icons.check_circle_outline,
                      message: 'No hazards nearby. You are safe!',
                      color: kSafe,
                    )
                  else
                    ...nearbyHazards.map((h) => Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: _hazardColor(h['hazard_level'])
                                      .withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  _hazardIcon(h['damage_type']),
                                  color: _hazardColor(h['hazard_level']),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _capitalize(h['damage_type'] ?? 'Unknown'),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${h['road_status'] ?? ''}  ·  ${(h['confidence'] * 100).toStringAsFixed(0)}% confidence',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _levelBadge(h['hazard_level']),
                            ],
                          ),
                        )),

                  const SizedBox(height: 24),

                  // Section header: Nearest Shelter
                  _sectionHeader('Nearest Shelter', ''),
                  const SizedBox(height: 12),

                  if (nearestShelter.isEmpty)
                    _emptyState(
                      icon: Icons.home_work_outlined,
                      message: 'No shelters found nearby',
                      color: Colors.grey,
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: kPrimaryLight.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.home_work_outlined,
                              color: kPrimary,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nearestShelter['name'] ?? 'Unknown',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${(nearestShelter['distance_km'] ?? 0).toStringAsFixed(1)} km away',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: kPrimaryLight.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              nearestShelter['phone'] ?? 'N/A',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                color: kPrimaryDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  // --- Helpers ---

  Widget _sectionHeader(String title, String subtitle) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: kPrimaryLight.withOpacity(0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: kPrimaryDark,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _levelBadge(String? level) {
    final color = _hazardColor(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        (level ?? 'unknown').toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _infoBanner({
    required IconData icon,
    required Color color,
    required String message,
  }) {
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
            child: Text(
              message,
              style: TextStyle(
                  fontSize: 13, color: color.withOpacity(0.9)),
            ),
          ),
        ],
      ),
    );
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 36, color: color.withOpacity(0.5)),
            const SizedBox(height: 10),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}

// ============================================================
// UPLOAD PAGE
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

  final latController = TextEditingController(text: '19.9975');
  final lngController = TextEditingController(text: '73.7898');
  final notesController = TextEditingController();

  @override
  void dispose() {
    latController.dispose();
    lngController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> pickImage(ImageSource source) async {
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
      _showMessage('Please select an image first', isError: true);
      return;
    }

    final lat = double.tryParse(latController.text);
    final lng = double.tryParse(lngController.text);
    if (lat == null || lng == null) {
      _showMessage('Please enter valid coordinates', isError: true);
      return;
    }

    setState(() => loading = true);

    final result = await ApiService.uploadReport(
      imageBytes: _imageBytes!,
      fileName: selectedImage!.name,
      latitude: lat,
      longitude: lng,
      userId: widget.userId,
      description: notesController.text.trim().isNotEmpty ? notesController.text.trim() : null,
    );

    setState(() => loading = false);

    if (!mounted) return;

    if (result['status'] == 'success') {
      setState(() {
        selectedImage = null;
        _imageBytes = null;
      });
      notesController.clear();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultPage(analysis: result['analysis']),
        ),
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
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 18,
            ),
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
            // Image preview area
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
                            color: kPrimary.withOpacity(0.3),
                            width: 2,
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: kPrimary.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.add_a_photo_outlined,
                                size: 36,
                                color: kPrimary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Tap to add a photo',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Take a photo or choose from gallery',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Show image from bytes (works on web + mobile)
                          _imageBytes != null
                              ? Image.memory(
                                  _imageBytes!,
                                  fit: BoxFit.cover,
                                )
                              : const Center(
                                  child: CircularProgressIndicator(),
                                ),
                          // Remove button
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
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 16),

            // Action buttons
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
            const SizedBox(height: 16),

            // Editable coordinates
            Row(
              children: [
                const Icon(Icons.location_on_outlined, color: kPrimary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: latController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(
                      labelText: 'Latitude',
                      hintText: '19.9975',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: lngController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(
                      labelText: 'Longitude',
                      hintText: '73.7898',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Additional info
            TextField(
              controller: notesController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Additional info (optional)',
                hintText: 'e.g. Road near river bridge, water rising fast...',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                prefixIcon: Padding(
                  padding: EdgeInsets.only(left: 12, right: 8),
                  child: Icon(Icons.notes_outlined, size: 18),
                ),
                prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: loading ? null : uploadReport,
                icon: loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(
                  loading ? 'Analyzing...' : 'Analyze & Submit',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Add a photo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
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

  Color _hazardColor(String? level) {
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

  IconData _hazardIcon(String? type) {
    switch (type) {
      case 'flood':
        return Icons.water;
      case 'fire':
        return Icons.local_fire_department;
      case 'collapse':
        return Icons.broken_image;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hazardLevel = analysis['hazard_level'] ?? 'unknown';
    final levelColor = _hazardColor(hazardLevel);
    final damageType = analysis['damage_type'] ?? 'Unknown';
    final confidence = analysis['confidence'] ?? 0;
    final roadStatus = analysis['road_status'] ?? 'Unknown';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis Result',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Hero card
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
                  // Icon + Type
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: levelColor.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _hazardIcon(damageType),
                      size: 36,
                      color: levelColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${damageType.toString().toUpperCase()} Detected',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Level badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: levelColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      hazardLevel.toString().toUpperCase(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: levelColor,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Stats row
                  Row(
                    children: [
                      _statItem(
                        label: 'Confidence',
                        value: '${(confidence * 100).toStringAsFixed(0)}%',
                        color: kPrimary,
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: Colors.grey.shade200,
                      ),
                      _statItem(
                        label: 'Road Status',
                        value: roadStatus,
                        color: levelColor,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Action button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () =>
                    Navigator.popUntil(context, (route) => route.isFirst),
                icon: const Icon(Icons.home_outlined),
                label: const Text(
                  'Back to Home',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem({
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
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

  Color _getColorForLevel(String? level) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hazard Map',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : Stack(
              children: [
                FlutterMap(
                  options: const MapOptions(
                    initialCenter: LatLng(19.9975, 73.7898),
                    initialZoom: 12,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.safesense.app',
                    ),
                    MarkerLayer(
                      markers: [
                        // Hazard markers
                        ...hazards.map(
                          (h) => Marker(
                            point: LatLng(
                              (h['latitude'] as num).toDouble(),
                              (h['longitude'] as num).toDouble(),
                            ),
                            width: 40,
                            height: 40,
                            child: GestureDetector(
                              onTap: () => _showHazardSheet(h),
                              child: Container(
                                decoration: BoxDecoration(
                                  color:
                                      _getColorForLevel(h['hazard_level']),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 2.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _getColorForLevel(
                                              h['hazard_level'])
                                          .withOpacity(0.4),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.warning_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Shelter markers
                        ...shelters.map(
                          (s) => Marker(
                            point: LatLng(
                              (s['latitude'] as num).toDouble(),
                              (s['longitude'] as num).toDouble(),
                            ),
                            width: 42,
                            height: 42,
                            child: GestureDetector(
                              onTap: () => _showShelterSheet(s),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: kPrimary, width: 2.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: kPrimary.withOpacity(0.3),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.home_rounded,
                                    color: kPrimary,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // Legend
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
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
                // Hazard count badge
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Text(
                      '${hazards.length} hazard${hazards.length == 1 ? '' : 's'} · ${shelters.length} shelter${shelters.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
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
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }

  void _showHazardSheet(dynamic hazard) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${(hazard['damage_type'] ?? 'Unknown').toString().toUpperCase()}',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _detailRow('Hazard Level', hazard['hazard_level'] ?? 'Unknown'),
            _detailRow('Road Status', hazard['road_status'] ?? 'Unknown'),
            _detailRow(
                'Confidence', '${(hazard['confidence'] * 100).toStringAsFixed(0)}%'),
            _detailRow('Location',
                '${hazard['latitude']}, ${hazard['longitude']}'),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: kPrimaryLight.withOpacity(0.4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.home_rounded, color: kPrimary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    shelter['name'] ?? 'Unknown Shelter',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
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
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600)),
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
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile card
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
                    color: kPrimary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person, color: kPrimary, size: 32),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.userName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                            color: isGuest ? Colors.grey : kPrimaryDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Stats
          if (!isGuest) ...[
            const Text(
              'Statistics',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: kPrimaryLight.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.description_outlined,
                        color: kPrimary, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Reports Submitted',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  loadingCount
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          '$reportCount',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: kPrimary,
                          ),
                        ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),

          // Logout
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                ApiService.logout();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                  (route) => false,
                );
              },
              icon: const Icon(Icons.logout),
              label: const Text('Logout',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
