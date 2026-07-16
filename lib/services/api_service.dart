import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// TODO: replace with your real server address once the endpoints exist,
// e.g. https://www.800globalenglish.com
const String baseUrl = 'https://www.800globalenglish.com';

class ApiService {
  // ---------- LOGIN ----------

  // Calls your MobileLogin endpoint. On success, saves the token locally
  // so the app can stay "logged in" even after closing/reopening.
  Future<bool> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/MobileApi/MobileLogin'),
        body: {'username': username, 'password': password},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', data['token']);
          await prefs.setInt('memberId', data['memberId']);
          await prefs.setString('username', username);
          return true;
        }
      }
      return false;
    } catch (e) {
      // ignore: avoid_print
      print('DEBUG login error: $e');
      return false;
    }
  }

  Future<String?> getSavedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('username');
  }

  Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<bool> isLoggedIn() async {
    final token = await getSavedToken();
    if (token == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final loggedOut = prefs.getBool('isLoggedOut') ?? false;
    return !loggedOut;
  }

  // ============================================================================
  // LOGOUT / OFFLINE RESUME
  // ============================================================================
  // logout() doesn't delete the saved token/username/memberId. It only sets a
  // flag marking the session as "logged out" in the UI. This lets someone log
  // back in via resumeOfflineSession() below WITHOUT a network call, as long
  // as it's the same device/cached session — important because fully
  // deleting the token would mean someone who logged out while offline has no
  // way back into the app, even though everything they downloaded is still
  // sitting on the device untouched.
  //
  // Tradeoff, by design: this means "Continue as {username}" on the login
  // screen can resume a session without re-checking the password. Anyone
  // with physical access to the device could do this. Acceptable here since
  // account-sharing is already a policy matter, not something technically
  // enforced.
  // ============================================================================
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedOut', true);
  }

  // True if there's a cached session available to resume, regardless of
  // whether it's currently marked logged-out. Used by the login screen to
  // decide whether to show a "Continue as {username}" option.
  Future<bool> hasCachedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final username = prefs.getString('username');
    return token != null && username != null;
  }

  // Re-activates a cached session without any network call — this is what
  // makes offline resume possible.
  Future<void> resumeOfflineSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedOut', false);
  }

  // ---------- RESOURCE TREE (words/images/audio) ----------

  // Fetches the full flat list of resources (folders + words) for one
  // industry (pageId 1 = Restaurant/Household, 2 = Construction/General),
  // with titles translated to the given language where a translation exists,
  // falling back to English otherwise. The app builds the tree structure
  // locally from id/parentId. Returns null on failure so the caller can
  // decide how to handle being offline (e.g. show cached tree if available).
  Future<List<Map<String, dynamic>>?> fetchResourceTree({
    required int pageId,
    required int languageId,
  }) async {
    try {
      final token = await getSavedToken();
      // ignore: avoid_print
      print('DEBUG fetchResourceTree: pageId=$pageId languageId=$languageId token=$token');

      final response = await http.get(Uri.parse(
          '$baseUrl/MobileApi/GetResourceTree?pageId=$pageId&languageId=$languageId&token=$token'));

      // ignore: avoid_print
      print('DEBUG fetchResourceTree: statusCode=${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['items']);
        }
        // ignore: avoid_print
        print('DEBUG fetchResourceTree: server responded but success=false. Message: ${data['message']}');
        return null;
      }

      // ignore: avoid_print
      print('DEBUG fetchResourceTree: non-200 response body: ${response.body}');
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('DEBUG fetchResourceTree error: $e');
      return null; // offline - caller should fall back to cached tree if any
    }
  }

  // The local cache key format is shared between here and
  // ResourceBrowserScreen — keep both in sync if this ever changes.
  static String resourceTreeCacheKey(int pageId, int languageId) =>
      'cachedResourceTree_${pageId}_$languageId';

  // Fetches one industry's tree and saves it to local cache on success,
  // returning whether it succeeded. Used both by ResourceBrowserScreen
  // itself (when someone opens an industry) and proactively right after
  // the content package finishes downloading, so both industries are
  // ready to browse offline without requiring a separate live visit to each.
  Future<bool> fetchAndCacheResourceTree({
    required int pageId,
    required int languageId,
  }) async {
    final raw = await fetchResourceTree(pageId: pageId, languageId: languageId);
    if (raw == null) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(resourceTreeCacheKey(pageId, languageId), jsonEncode(raw));
    return true;
  }

  // Pre-warms the local cache for BOTH industries at once, for the given
  // language. Call this right after the content package (images/sounds)
  // finishes downloading, so someone doesn't have to separately open both
  // Restaurant and Construction while still online just to make them
  // available offline later.
  Future<void> prefetchBothIndustryTrees(int languageId) async {
    await Future.wait([
      fetchAndCacheResourceTree(pageId: 1, languageId: languageId),
      fetchAndCacheResourceTree(pageId: 2, languageId: languageId),
    ]);
  }
}
