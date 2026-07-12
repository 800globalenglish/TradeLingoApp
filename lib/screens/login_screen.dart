// ============================================================================
// login_screen.dart — ONE ADDITION
// ============================================================================
// After a successful login, kicks off syncPendingResults() in the background
// (not awaited — login navigation proceeds immediately, sync just runs
// quietly). Safe to call every login: it only sends rows still marked
// unsynced, so nothing gets sent twice.
// Everything else in this file is UNCHANGED from your original.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/resource_strings.dart';
import 'splash_screen.dart';
import 'download_manager_screen.dart';
import 'welcome_download_screen.dart';
import 'welcome_wizard_screen.dart';
import '../widgets/app_header.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _api = ApiService();

  bool _isLoading = false;
  String? _errorMessage;

  // NEW — for offline resume
  bool _checkingSession = true;
  String? _cachedUsername;

  @override
  void initState() {
    super.initState();
    _checkForCachedSession();
  }

  // NEW — checks whether there's a previous session on this device that
  // can be resumed without a network call.
  Future<void> _checkForCachedSession() async {
    final hasCached = await _api.hasCachedSession();
    final username = hasCached ? await _api.getSavedUsername() : null;
    if (!mounted) return;
    setState(() {
      _cachedUsername = username;
      _checkingSession = false;
    });
  }

  // NEW — resumes a cached session with no network call at all.
  Future<void> _handleResumeSession() async {
    await _api.resumeOfflineSession();
    if (!mounted) return;

    // Sync/pull attempts are safe to fire even offline - they fail silently
    // and retry later via the app's other sync trigger points.
    _api.syncPendingResults();
    _api.pullServerProgress();

    await _navigateAfterLogin();
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final success = await _api.login(
      _usernameController.text.trim(),
      _passwordController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (success) {
      if (!mounted) return;

      // NEW — fire-and-forget: pushes any locally-saved quiz/oral results up
      // to the server now that we have a fresh valid token. Not awaited, so
      // it doesn't delay the screen transition below.
      _api.syncPendingResults();

      // NEW — fire-and-forget: pulls down any results the member already has
      // on the server (e.g. from the website) and merges them into local
      // hub scores/oral pass status.
      _api.pullServerProgress();

      await _navigateAfterLogin();
    } else {
      setState(() {
        _errorMessage = ResourceStrings.instance.get('aiadd4005');
      });
    }
  }

  // NEW — shared by both a real login and an offline session resume, so the
  // onboarding/routing logic only lives in one place.
  Future<void> _navigateAfterLogin() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final hasSeenContentDownload = prefs.getBool('hasSeenWelcomeContentDownload') ?? false;

    if (!hasSeenContentDownload) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WelcomeDownloadScreen()),
      );
      return;
    }

    final hasSeenVideoOnboarding = prefs.getBool('hasSeenVideoOnboarding') ?? false;

    if (!hasSeenVideoOnboarding) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DownloadManagerScreen(isOnboarding: true)),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SplashScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF002E52),
      appBar: AppBar(
        backgroundColor: const Color(0xFF002E52),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            // FIXED — was Navigator.of(context).pop(), which just went back
            // to whatever screen happened to push Login. Now always lands on
            // the Choose Language screen specifically, with the whole stack
            // reset beneath it — so there's nothing left to "pop" to if the
            // person then hits back again on THAT screen.
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const WelcomeWizardScreen()),
                  (route) => false,
            );
          },
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppHeader(height: 60),
              const SizedBox(height: 32),
              // NEW — offline resume option, shown only if a cached session exists
              if (_checkingSession)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: CircularProgressIndicator(color: Colors.white),
                )
              else if (_cachedUsername != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.person),
                    label: Text('${ResourceStrings.instance.get('aiadd4062')} $_cachedUsername'),
                    onPressed: _handleResumeSession,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    children: [
                      Expanded(child: Divider(color: Colors.white24)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or', style: TextStyle(color: Colors.white54)),
                      ),
                      Expanded(child: Divider(color: Colors.white24)),
                    ],
                  ),
                ),
              ],
              TextField(
                controller: _usernameController,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: ResourceStrings.instance.get('aiadd3909'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: ResourceStrings.instance.get('aiadd3910'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.orangeAccent),
                    textAlign: TextAlign.center,
                  ),
                ),
              _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _handleLogin,
                  child: Text(ResourceStrings.instance.get('aiadd3953')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
