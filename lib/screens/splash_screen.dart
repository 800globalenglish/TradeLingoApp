import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'lesson_list_screen.dart';
import 'pdf_list_screen.dart';
import 'download_manager_screen.dart';
import 'content_download_screen.dart';
import '../services/languages.dart';
import '../services/api_service.dart';
import '../widgets/app_header.dart';
import '../services/content_package_service.dart';
import '../services/resource_strings.dart';
import 'help_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _selectedLanguage = 'en-US';
  String? _username;
  bool _showOfflineContentButton = true;

  final Map<String, String> _languages = appLanguages;

  @override
  void initState() {
    super.initState();
    _loadSavedLanguage();
    _loadUsername();
    _checkOfflineContentStatus();
  }

  Future<void> _checkOfflineContentStatus() async {
    final service = ContentPackageService.instance;

    if (!service.isContentAvailableLocally) {
      // Never downloaded yet - definitely show the button
      if (mounted) setState(() => _showOfflineContentButton = true);
      return;
    }

    // Already downloaded - only show the button again if a newer version exists
    final updateAvailable = await service.isUpdateAvailable();
    if (mounted) setState(() => _showOfflineContentButton = updateAvailable);
  }

  Future<void> _loadUsername() async {
    final username = await ApiService().getSavedUsername();
    if (mounted) setState(() => _username = username);
  }

  Future<void> _loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage = prefs.getString('selectedLanguage') ?? 'en-US';
    });
  }

  Future<void> _changeLanguage(String? code) async {
    if (code == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedLanguage', code);
    await ResourceStrings.instance.load(code);
    setState(() => _selectedLanguage = code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF002E52),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppHeader(height: 60),
              if (_username != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${ResourceStrings.instance.get('aiadd2890')}: $_username',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String>(
                  value: _selectedLanguage,
                  underline: const SizedBox(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  items: _languages.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: _changeLanguage,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.menu_book),
                  label: Text(ResourceStrings.instance.get('aiadd1437')),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LessonListScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  label: Text(ResourceStrings.instance.get('aiadd3971')),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PdfListScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.download),
                  label: Text(ResourceStrings.instance.get('aiadd3934')),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DownloadManagerScreen()),
                    );
                  },
                ),
              ),
              if (_showOfflineContentButton) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.offline_bolt),
                    label: Text(ResourceStrings.instance.get('aiadd3932')),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ContentDownloadScreen()),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 32),
              Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.help_outline),
                  label: Text(ResourceStrings.instance.get('aiadd3890')),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const HelpScreen()),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}