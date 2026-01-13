import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../utils/version_provider.dart';

class SettingsScreen extends StatelessWidget {

  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final brightness = MediaQuery.of(context).platformBrightness;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSettingsSection('Appearance', [
                  _buildThemeSelector(context, themeProvider),
                  _buildSettingsOption(
                    Icons.contrast,
                    'Dark Mode',
                    null,
                    trailing: Switch(
                      value:
                          themeProvider.themeMode == ThemeMode.system
                              ? brightness == Brightness.dark
                              : themeProvider.isDarkMode,
                      onChanged: (value) {
                        if (themeProvider.themeMode == ThemeMode.system) {
                          themeProvider.setThemeMode(
                            brightness == Brightness.dark
                                ? ThemeMode.light
                                : ThemeMode.dark,
                          );
                        } else {
                          themeProvider.toggleTheme();
                        }
                      },
                    ),
                  ),
                ]),
                _buildSettingsSection('More', [
                  _buildSettingsOption(Icons.info, 'About', () {}),
                ]),
              ],
            ),
          ),
          FutureBuilder<String>(
            future: VersionProvider.getAppVersion(),
            builder: (context, snapshot) {
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Version ${snapshot.data ?? "Loading..."}',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.6),
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              );
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildThemeSelector(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    return ListTile(
      leading: const Icon(Icons.palette),
      title: const Text('App Theme'),
      trailing: DropdownButton<ThemeMode>(
        value: themeProvider.themeMode,
        items: const [
          DropdownMenuItem(
            value: ThemeMode.system,
            child: Text('System Default'),
          ),
          DropdownMenuItem(value: ThemeMode.light, child: Text('Light Theme')),
          DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark Theme')),
        ],
        onChanged: (ThemeMode? mode) {
          if (mode != null) {
            themeProvider.setThemeMode(mode);
          }
        },
      ),
    );
  }

  Widget _buildSettingsSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSettingsOption(
    IconData icon,
    String title,
    VoidCallback? onTap, {
    bool isDanger = false,
    Widget? trailing,
  }) {
    return ListTile(
      leading: Icon(icon, color: isDanger ? Colors.red : null),
      title: Text(title, style: TextStyle(color: isDanger ? Colors.red : null)),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
