import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'lesson_list_screen.dart';
import 'pdf_list_screen.dart';
import 'download_manager_screen.dart';
import 'content_download_screen.dart';
import '../services/languages.dart';
import '../services/api_service.dart';
import '../services/local_db.dart';
import '../widgets/app_header.dart';
import '../services/content_package_service.dart';
import '../services/resource_strings.dart';
import 'help_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _selectedLanguage = 'en-US';
  // NEW — the dropdown's current pick, which may differ from _selectedLanguage
  // until the person actually confirms it with the arrow button.
  String _pendingLanguage = 'en-US';
  String? _username;
  bool _showOfflineContentButton = true;
  bool _isConfirmingLanguage = false;

  // NEW — tracks which languages already have lesson content cached locally
  Set<String> _downloadedLanguages = {};

  final Map<String, String> _languages = appLanguages;

  @override
  void initState() {
    super.initState();
    _loadSavedLanguage();
    _loadUsername();
    _checkOfflineContentStatus();
    _loadDownloadedLanguages(); // NEW
  }

  // NEW — checks each language's local cache to see which ones already have lessons saved
  Future<void> _loadDownloadedLanguages() async {
    final downloaded = <String>{};
    for (final code in _languages.keys) {
      final lessons = await LocalDb.instance.getAllLessons(code);
      if (lessons.isNotEmpty) {
        downloaded.add(code);
      }
    }
    if (mounted) {
      setState(() => _downloadedLanguages = downloaded);
    }
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
    final saved = prefs.getString('selectedLanguage') ?? 'en-US';
    setState(() {
      _selectedLanguage = saved;
      _pendingLanguage = saved;
    });
  }

  // NEW — actually applies the pending language: saves it, reloads UI text,
  // and pre-fetches/caches that language's lesson list right away (while
  // online), so switching to a brand-new language and going offline
  // afterward doesn't leave the person stuck with an empty lesson list and
  // no explanation.
  Future<void> _confirmLanguageChange() async {
    if (_pendingLanguage == _selectedLanguage) return; // nothing changed

    final code = _pendingLanguage;

    // NEW — only block the switch if this language ISN'T already downloaded.
    // A language with cached lessons/resource strings can switch to safely
    // offline; only a brand-new, never-downloaded language actually needs
    // a live connection to fetch anything.
    final connectivityResult = await Connectivity().checkConnectivity();
    final isOffline = connectivityResult.contains(ConnectivityResult.none) || connectivityResult.isEmpty;
    if (isOffline && !_downloadedLanguages.contains(code)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ResourceStrings.instance.get('aiadd4076'))),
      );
      return;
    }

    setState(() => _isConfirmingLanguage = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedLanguage', code);
    await ResourceStrings.instance.load(code); // already falls back to cache gracefully when offline

    // Pre-fetch this language's lessons now, while we know we're online
    // (the person just interacted with the app). If offline but the
    // language is already downloaded, this simply does nothing new -
    // the existing local cache is used as-is.
    try {
      final serverLessons = await ApiService().fetchLessonsFromServer();
      if (serverLessons != null) {
        await LocalDb.instance.saveLessons(serverLessons, code);
      }
    } catch (e) {
      // ignore - lesson list screen handles the offline case on its own
    }

    await _loadDownloadedLanguages();

    if (!mounted) return;
    setState(() {
      _selectedLanguage = code;
      _isConfirmingLanguage = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_languages[code]} ✓')),
    );
  }

  // NEW — builds the personal subdomain link and copies it to the clipboard.
  Future<void> _copyShareLink() async {
    if (_username == null) return;
    final link = 'https://$_username.800globalenglish.com';
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${ResourceStrings.instance.get('aiadd2959')} ${ResourceStrings.instance.get('aiadd2840')} $link')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF002E52),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
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
                      SizedBox(
                        width: double.infinity,
                        child: Column( // CHANGED — was Row directly; wrapped in Column so we can add loading text below
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: DropdownButton<String>(
                                    value: _pendingLanguage,
                                    underline: const SizedBox(),
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    items: _languages.entries
                                        .map((e) => DropdownMenuItem(
                                      value: e.key,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('${appLanguageFlags[e.key] ?? ''}  ${e.value}'),
                                          if (_downloadedLanguages.contains(e.key)) ...[
                                            const SizedBox(width: 6),
                                            const Icon(Icons.check_circle, size: 16, color: Colors.green),
                                          ],
                                        ],
                                      ),
                                    ))
                                        .toList(),
                                    onChanged: (code) {
                                      if (code != null) setState(() => _pendingLanguage = code);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // NEW — explicit confirm button. Only enabled once a
                                // DIFFERENT language is actually picked, so it's
                                // clear something needs to happen, and tapping it
                                // gives visible feedback (spinner, then a snackbar)
                                // instead of the previous silent instant-switch.
                                if (_isConfirmingLanguage)
                                  const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    ),
                                  )
                                else
                                  IconButton.filled(
                                    icon: const Icon(Icons.arrow_forward),
                                    tooltip: 'Apply language',
                                    onPressed: _confirmLanguageChange,
                                  ),
                              ],
                            ),
                            // NEW — shown only while the new language is loading
                            if (_isConfirmingLanguage)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  ResourceStrings.instance.get('aiadd4075'),
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32), // CHANGED — removed the accidental duplicate of this line
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
                          label: Text('${ResourceStrings.instance.get('aiadd2883')} FAQs'),
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
            ),
            // NEW — footer with the share-link action, only shown once we know the username
            if (_username != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.15),
                  border: const Border(top: BorderSide(color: Colors.white24)),
                ),
                child: TextButton.icon(
                  icon: const Icon(Icons.link, color: Colors.white70, size: 18),
                  label: Text(
                    ResourceStrings.instance.get('aiadd2597'),
                    style: const TextStyle(color: Colors.white70),
                  ),
                  onPressed: _copyShareLink,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
