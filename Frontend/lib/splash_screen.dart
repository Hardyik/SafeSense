import 'package:flutter/material.dart';
import 'main.dart' show WelcomePage;
import 'theme/app_theme.dart';

/// Brief branded splash shown right after Flutter's first frame (the
/// native Android splash — drawable/launch_background.xml — covers the
/// gap before that). Kept short and simple per Section 28: "keep the
/// splash screen fast... do not delay application startup unnecessarily."
/// This does NOT do any loading work itself — Firebase/notifications are
/// already initialized in main() before runApp() even runs.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();

    // WelcomePage itself already checks AuthService for a persisted
    // session and skips ahead to Home when one exists — this just hands
    // off to it after a brief, fixed, branded beat.
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WelcomePage()),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepNavy,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.safetyCyan,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.shield_rounded,
                      color: AppColors.deepNavy, size: 52),
                ),
                const SizedBox(height: 20),
                const Text(
                  'SafeSense',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Stay aware. Stay safe.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.75),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
