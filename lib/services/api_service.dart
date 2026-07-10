import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lesson.dart';
import 'local_db.dart';

// TODO: replace with your real server address once the endpoints exist,
// e.g. https://www.800globalenglish.com
const String baseUrl = 'https://rpm.aibiz4u.com';

class ApiService {
  final LocalDb _localDb = LocalDb.instance;

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
    return token != null;
  }

  // ---------- LESSONS ----------

  // Fetches the full lesson list (words, sentences, quizzes, video URLs)
  // Returns null on failure so the caller can fall back to local cache.
  Future<List<Lesson>?> fetchLessonsFromServer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lang = prefs.getString('selectedLanguage') ?? 'en-US';
      final token = await getSavedToken();
      final response = await http.get(Uri.parse('$baseUrl/MobileApi/GetAllLessons?lang=$lang&token=$token'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => Lesson.fromJson(json)).toList();
      }
      return null;
    } catch (e) {
      return null; // offline - caller should load from local db instead
    }
  }

  // ============================================================================
  // QUIZ RESULT SYNC
  // ============================================================================
  // NOTE ON totalTime/totalScoreStar: the server's Submit* endpoints accept a
  // TotalTime and TotalScoreStar for the leaderboard, but nothing in the app
  // currently tracks a quiz timer or star rating locally. These are sent as
  // placeholder values (0 / "00:00.000") for now, which means app-submitted
  // leaderboard entries will always show 0 time and 0 stars. Flagging this
  // as a known limitation — if leaderboard timing/stars matter for app
  // users, that would need its own tracking added to the quiz screens later.
  // ============================================================================

  Future<bool> _submitNounResult(Map<String, dynamic> row, String token) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/MobileApi/SubmitNounQuizResult'),
        body: {
          'token': token,
          'lessonId': row['lessonId'].toString(),
          'totalQuiz': row['totalQuiz'].toString(),
          'totalCorrect': row['totalCorrect'].toString(),
          'totalWrong': row['totalWrong'].toString(),
          'correctQuizIds': row['correctQuizIds'] ?? '0',
          'wrongQuizIds': row['wrongQuizIds'] ?? '0',
          'correctQuizOptionIds': row['correctQuizOptionIds'] ?? '0',
          'wrongQuizOptionIds': row['wrongQuizOptionIds'] ?? '0',
          'correctNounIds': row['correctNounIds'] ?? '0',
          'wrongNounIds': row['wrongNounIds'] ?? '0',
          'getPercentage': row['percentage'].toString(),
          'nounQuizType': row['apiNounQuizType'],
          'totalTime': '00:00.000',
          'totalQuizSeconds': '0',
          'totalScoreStar': '0',
        },
      );
      // ignore: avoid_print
      print('DEBUG submitNounResult status=${response.statusCode} body=${response.body}');
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (e) {
      // ignore: avoid_print
      print('DEBUG submitNounResult ERROR: $e');
      return false; // still offline - try again later
    }
  }

  Future<bool> _submitGrammarResult(Map<String, dynamic> row, String token) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/MobileApi/SubmitGrammarQuizResult'),
        body: {
          'token': token,
          'lessonId': row['lessonId'].toString(),
          'totalQuiz': row['totalQuiz'].toString(),
          'totalCorrect': row['totalCorrect'].toString(),
          'totalWrong': row['totalWrong'].toString(),
          'correctQuizIds': row['correctQuizIds'] ?? '0',
          'wrongQuizIds': row['wrongQuizIds'] ?? '0',
          'getPercentage': row['percentage'].toString(),
          'quizTypeId': row['apiQuizTypeId'].toString(),
          'totalTime': '00:00.000',
          'totalQuizSeconds': '0',
          'totalScoreStar': '0',
        },
      );
      // ignore: avoid_print
      print('DEBUG submitGrammarResult status=${response.statusCode} body=${response.body}');
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (e) {
      // ignore: avoid_print
      print('DEBUG submitGrammarResult ERROR: $e');
      return false;
    }
  }

  Future<bool> _submitOralResult(Map<String, dynamic> row, String token) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/MobileApi/SubmitOralQuizResult'),
        body: {
          'token': token,
          'lessonId': (row['lessonId'] ?? 0).toString(),
          'keywordId': (row['keywordId'] ?? 0).toString(),
          'isPassed': (row['passed'] == 1).toString(),
        },
      );
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  // ============================================================================
  // SYNC ORCHESTRATOR — call this whenever you want to push pending results
  // (e.g. app launch, or when connectivity is restored). Safe to call
  // repeatedly: only rows still marked unsynced get sent, and each is only
  // marked synced after a confirmed server success, so nothing is lost or
  // double-sent if the app closes mid-sync or the network drops partway.
  // ============================================================================
  Future<void> syncPendingResults() async {
    final token = await getSavedToken();
    if (token == null) {
      // ignore: avoid_print
      print('DEBUG syncPendingResults: no saved token, skipping sync');
      return; // not logged in - nothing to sync yet
    }

    final unsyncedNoun = await _localDb.getUnsyncedNounResults();
    // ignore: avoid_print
    print('DEBUG syncPendingResults: found ${unsyncedNoun.length} unsynced noun results');
    for (final row in unsyncedNoun) {
      final success = await _submitNounResult(row, token);
      // ignore: avoid_print
      print('DEBUG noun sync result for ${row['lessonGuid']}/${row['nounQuizType']}: $success');
      if (success) {
        await _localDb.markNounResultSynced(
          row['lessonGuid'] as String,
          row['nounQuizType'] as String,
        );
      }
    }

    final unsyncedGrammar = await _localDb.getUnsyncedGrammarResults();
    // ignore: avoid_print
    print('DEBUG syncPendingResults: found ${unsyncedGrammar.length} unsynced grammar results');
    for (final row in unsyncedGrammar) {
      final success = await _submitGrammarResult(row, token);
      // ignore: avoid_print
      print('DEBUG grammar sync result for ${row['lessonGuid']}/${row['quizType']}: $success');
      if (success) {
        await _localDb.markGrammarResultSynced(
          row['lessonGuid'] as String,
          row['quizType'] as String,
        );
      }
    }

    final unsyncedOral = await _localDb.getUnsyncedOralPracticeResults();
    // ignore: avoid_print
    print('DEBUG syncPendingResults: found ${unsyncedOral.length} unsynced oral results');
    for (final row in unsyncedOral) {
      final success = await _submitOralResult(row, token);
      if (success) {
        await _localDb.markOralPracticeResultSynced(
          row['lessonGuid'] as String,
          row['itemKey'] as String,
        );
      }
    }
  }

  // ============================================================================
  // PULL SYNC — brings down results the member already has on the SERVER
  // (e.g. from using the website) and merges them into the local hub scores
  // and oral-practice pass status, so progress looks the same everywhere.
  //
  // Safe to call repeatedly:
  //   - Noun/grammar scores go through savePendingResultIfBetter, which only
  //     overwrites the local hub score if the server's is actually higher —
  //     never creates a new row in the detailed sync tables, so this can't
  //     cause anything to get pushed back up needlessly.
  //   - Oral practice only writes if the word isn't ALREADY marked passed
  //     locally, to avoid resetting its synced flag and re-pushing it every
  //     single pull for no reason.
  // ============================================================================
  Future<void> pullServerProgress() async {
    final token = await getSavedToken();
    if (token == null) return;

    try {
      final response = await http.get(Uri.parse('$baseUrl/MobileApi/GetMyProgress?token=$token'));
      if (response.statusCode != 200) {
        // ignore: avoid_print
        print('DEBUG pullServerProgress: status=${response.statusCode}');
        return;
      }

      final data = jsonDecode(response.body);
      if (data['success'] != true) {
        // ignore: avoid_print
        print('DEBUG pullServerProgress: server returned success=false');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final language = prefs.getString('selectedLanguage') ?? 'en-US';
      final lessons = await _localDb.getAllLessons(language);

      // Build lookup maps from whatever's cached locally: lessonId -> lessonGuid,
      // and keywordId -> (lessonGuid, title) for oral practice.
      final lessonIdToGuid = <int, String>{};
      final keywordIdToLesson = <int, Map<String, String>>{}; // keywordId -> {lessonGuid, title}
      for (final lesson in lessons) {
        lessonIdToGuid[lesson.lessonId] = lesson.lessonGuid;
        for (final keyword in lesson.keywords) {
          keywordIdToLesson[keyword.id] = {'lessonGuid': lesson.lessonGuid, 'title': keyword.title};
        }
      }

      // ignore: avoid_print
      print('DEBUG pullServerProgress: server returned ${(data['nounResults'] as List?)?.length ?? 0} noun, ${(data['grammarResults'] as List?)?.length ?? 0} grammar, ${(data['passedOralKeywordIds'] as List?)?.length ?? 0} oral');
      // ignore: avoid_print
      print('DEBUG pullServerProgress: locally cached lessonIds = ${lessons.map((l) => l.lessonId).toList()}');

      const nounTypeToHubKey = {
        'text/image': 'nounQuizTextImage',
        'text/audio': 'nounQuizTextAudio',
        'image/audio': 'nounQuizImageAudio',
        'spelling/typing': 'spellingQuiz',
      };
      const grammarTypeIdToHubKey = {
        1: 'grammarQuiz',
        2: 'grammarSpellingQuiz',
        3: 'advanceQuiz',
      };

      int mergedCount = 0;

      final nounResults = data['nounResults'] as List<dynamic>? ?? [];
      for (final r in nounResults) {
        final lessonGuid = lessonIdToGuid[r['lessonId']];
        final hubKey = nounTypeToHubKey[r['nounQuizType']];
        if (lessonGuid == null || hubKey == null) {
          // ignore: avoid_print
          print('DEBUG pullServerProgress: SKIPPED noun result lessonId=${r['lessonId']} nounQuizType=${r['nounQuizType']} (lessonGuid found=${lessonGuid != null}, hubKey found=${hubKey != null})');
          continue; // lesson not cached locally yet, or unrecognized type
        }
        await _localDb.savePendingResultIfBetter(lessonGuid, hubKey, (r['percentage'] as num).toDouble());
        // ignore: avoid_print
        print('DEBUG pullServerProgress: MERGED noun lessonId=${r['lessonId']} -> $hubKey = ${r['percentage']}%');
        mergedCount++;
      }

      final grammarResults = data['grammarResults'] as List<dynamic>? ?? [];
      for (final r in grammarResults) {
        final lessonGuid = lessonIdToGuid[r['lessonId']];
        final hubKey = grammarTypeIdToHubKey[r['quizTypeId']];
        if (lessonGuid == null || hubKey == null) continue;
        await _localDb.savePendingResultIfBetter(lessonGuid, hubKey, (r['percentage'] as num).toDouble());
        mergedCount++;
      }

      final passedOralKeywordIds = data['passedOralKeywordIds'] as List<dynamic>? ?? [];
      for (final rawId in passedOralKeywordIds) {
        final keywordId = rawId as int;
        final info = keywordIdToLesson[keywordId];
        if (info == null) continue; // keyword not cached locally yet

        final alreadyPassed = await _localDb.getOralPracticeResult(info['lessonGuid']!, info['title']!);
        if (alreadyPassed) continue; // don't rewrite - avoids resetting synced flag needlessly

        await _localDb.saveOralPracticeResult(
          info['lessonGuid']!,
          info['title']!,
          true,
          keywordId: keywordId,
        );
        // Immediately mark it synced too, since this data literally came FROM
        // the server - pushing it right back up would be pointless.
        await _localDb.markOralPracticeResultSynced(info['lessonGuid']!, info['title']!);
        mergedCount++;
      }

      // ignore: avoid_print
      print('DEBUG pullServerProgress: merged $mergedCount results from server');
    } catch (e) {
      // ignore: avoid_print
      print('DEBUG pullServerProgress ERROR: $e');
    }
  }
}
