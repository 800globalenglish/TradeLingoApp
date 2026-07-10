import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String resourceStringsBaseUrl = 'https://rpm.aibiz4u.com/MobileApi/GetResourceStrings';

class ResourceStrings {
  static final ResourceStrings instance = ResourceStrings._internal();
  ResourceStrings._internal();

  Map<String, String> _strings = {};
  String _loadedLanguage = '';

  // Call this once at startup, and again whenever the language changes.
  Future<void> load(String languageCode) async {
    // Try loading from local cache first, so the app has something to
    // show immediately even before a fresh fetch completes.
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('resourceStrings_$languageCode');
    if (cached != null) {
      final Map<String, dynamic> decoded = jsonDecode(cached);
      _strings = decoded.map((k, v) => MapEntry(k, v.toString()));
      _loadedLanguage = languageCode;
    }

    // Then try to get a fresh copy from the server
    try {
      final response = await http.get(Uri.parse('$resourceStringsBaseUrl?lang=$languageCode'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final Map<String, String> fresh = {
          for (var item in data) item['key'].toString(): item['value'].toString()
        };
        _strings = fresh;
        _loadedLanguage = languageCode;
        await prefs.setString('resourceStrings_$languageCode', jsonEncode(fresh));
      }
    } catch (e) {
      // offline - whatever was cached above (if anything) is used instead
    }
  }

  // Looks up a resource by its key name (e.g. "aiadd2636").
  // Falls back to showing the key itself if not found, so a missing
  // translation is obvious rather than silently blank.
  String get(String key) {
    return _strings[key] ?? key;
  }

  String get currentLanguage => _loadedLanguage;
}