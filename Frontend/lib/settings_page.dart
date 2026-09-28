import 'package:flutter/material.dart';
import 'main.dart' show kPrimary;
import 'services/theme_service.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Appearance',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeService.instance.themeMode,
            builder: (context, mode, _) {
              return Card(
                child: Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      title: const Text('Light'),
                      secondary: const Icon(Icons.light_mode_outlined),
                      value: ThemeMode.light,
                      groupValue: mode,
                      activeColor: kPrimary,
                      onChanged: (v) =>
                          ThemeService.instance.setThemeMode(v!),
                    ),
                    const Divider(height: 1),
                    RadioListTile<ThemeMode>(
                      title: const Text('Dark'),
                      secondary: const Icon(Icons.dark_mode_outlined),
                      value: ThemeMode.dark,
                      groupValue: mode,
                      activeColor: kPrimary,
                      onChanged: (v) =>
                          ThemeService.instance.setThemeMode(v!),
                    ),
                    const Divider(height: 1),
                    RadioListTile<ThemeMode>(
                      title: const Text('System default'),
                      secondary: const Icon(Icons.brightness_auto_outlined),
                      value: ThemeMode.system,
                      groupValue: mode,
                      activeColor: kPrimary,
                      onChanged: (v) =>
                          ThemeService.instance.setThemeMode(v!),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Your choice is saved and applied every time you open the app.',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.6),
                  fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
