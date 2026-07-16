import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'content_download_screen.dart';
import 'resource_browser_screen.dart';
import 'login_screen.dart';
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
  // The dropdown's current pick, which may differ from _selectedLanguage
  // until the person actually confirms it with the arrow button.
  String _pendingLanguage = 'en-US';
  String? _username;
  bool _isConfirmingLanguage = false;

  final Map<String, String> _languages = appLanguages;

  @override
  void initState() {
    super.initState();
    _loadSavedLanguage();
    _loadUsername();
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

  // Applies the pending language: saves it and reloads UI text. Unlike the
  // original app, there's no per-language lesson content to pre-fetch here —
  // word/image data for TradeLingo is fetched per-industry via
  // GetResourceTree when someone actually opens an industry, not tied to
  // this language switcher.
  Future<void> _confirmLanguageChange() async {
    if (_pendingLanguage == _selectedLanguage) return; // nothing changed

    final code = _pendingLanguage;
    setState(() => _isConfirmingLanguage = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedLanguage', code);
    await ResourceStrings.instance.load(code); // falls back to cache gracefully when offline

    if (!mounted) return;
    setState(() {
      _selectedLanguage = code;
      _isConfirmingLanguage = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_languages[code]} ✓')),
    );
  }

  // Builds the personal subdomain link and copies it to the clipboard.
  Future<void> _copyShareLink() async {
    if (_username == null) return;
    final link = 'https://$_username.800globalenglish.com';
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${ResourceStrings.instance.get('aiadd2959')} ${ResourceStrings.instance.get('aiadd2840')} $link')),
    );
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ResourceStrings.instance.get('aiadd4083')),
        content: Text(ResourceStrings.instance.get('aiadd4084')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(ResourceStrings.instance.get('aiadd3911'))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(ResourceStrings.instance.get('aiadd4083'))),
        ],
      ),
    );
    if (confirmed != true) return;

    await ApiService().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
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
                      const SizedBox(height: 16),
                      Text(
                        ResourceStrings.instance.get('aiadd2032'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w500),
                      ),
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
                        child: Column(
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
                                      child: Text('${appLanguageFlags[e.key] ?? ''}  ${e.value}'),
                                    ))
                                        .toList(),
                                    onChanged: (code) {
                                      if (code != null) setState(() => _pendingLanguage = code);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
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
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.restaurant),
                          label: Text(
                            ResourceStrings.instance.get('aiadd1468'),
                            style: const TextStyle(fontSize: 18),
                          ),
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ResourceBrowserScreen(
                                  pageId: 1,
                                  screenTitle: ResourceStrings.instance.get('aiadd1468'),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.construction),
                          label: Text(
                            ResourceStrings.instance.get('aiadd1469'),
                            style: const TextStyle(fontSize: 18),
                          ),
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ResourceBrowserScreen(
                                  pageId: 2,
                                  screenTitle: ResourceStrings.instance.get('aiadd1469'),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
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

            if (_username != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.15),
                  border: const Border(top: BorderSide(color: Colors.white24)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.link, color: Colors.white70, size: 18),
                      label: Text(
                        ResourceStrings.instance.get('aiadd2597'),
                        style: const TextStyle(color: Colors.white70),
                      ),
                      onPressed: _copyShareLink,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.logout, color: Colors.white70, size: 18),
                      label: Text(ResourceStrings.instance.get('aiadd4083'), style: const TextStyle(color: Colors.white70)),
                      onPressed: _handleLogout,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
