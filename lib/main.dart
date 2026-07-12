import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'services/content_package_service.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/welcome_wizard_screen.dart';
import 'services/resource_strings.dart';
import 'services/app_theme.dart';

void main() {
  runApp(const GlobalEnglishApp());
}

class GlobalEnglishApp extends StatelessWidget {
  const GlobalEnglishApp({super.key});

  @override
  Widget build(BuildContext context) {
    // CHANGED — wrapped MaterialApp in a ListenableBuilder that listens to
    // ResourceStrings (now a ChangeNotifier). Whenever the language changes
    // anywhere in the app (splash screen dropdown, welcome wizard, etc.),
    // this rebuilds MaterialApp with the correct text direction. Without
    // this, RTL/LTR would only ever be set correctly once, at first launch,
    // and switching to/from Arabic or Hebrew later wouldn't visually mirror
    // the layout even though the text itself would still translate fine.
    return ListenableBuilder(
      listenable: ResourceStrings.instance,
      builder: (context, _) {
        return MaterialApp(
          title: '800 Global English',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: Colors.white,
            colorScheme: ColorScheme.fromSeed(seedColor: brandDarkBlue),
            appBarTheme: const AppBarTheme(
              backgroundColor: brandDarkBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              iconTheme: IconThemeData(color: Colors.white),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: brandDarkBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: brandDarkBlue),
            ),
          ),
          // NEW — this is what actually flips the whole app's layout
          // (text alignment, Row ordering, EdgeInsetsDirectional, etc.)
          // for Arabic/Hebrew, applied globally to every screen.
          builder: (context, child) {
            return Directionality(
              textDirection: ResourceStrings.instance.isRtl ? TextDirection.rtl : TextDirection.ltr,
              child: child!,
            );
          },
          home: const StartupScreen(),
        );
      },
    );
  }
}

// Checks if the user already has a saved login token, and whether
// offline content has already been downloaded to this device.
class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  final _api = ApiService();

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    await ContentPackageService.instance.loadLocalStatus();

    final prefs = await SharedPreferences.getInstance();
    final language = prefs.getString('selectedLanguage') ?? 'en-US';
    await ResourceStrings.instance.load(language);

    final hasSeenWizard = prefs.getBool('hasSeenWelcomeWizard') ?? false;

    if (!hasSeenWizard) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WelcomeWizardScreen()),
      );
      return;
    }

    final loggedIn = await _api.isLoggedIn();
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => loggedIn ? const SplashScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF002E52),
      body: Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}
