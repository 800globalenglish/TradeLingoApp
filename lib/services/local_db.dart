import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/lesson.dart';

class LocalDb {
  static final LocalDb instance = LocalDb._internal();
  static Database? _db;

  LocalDb._internal();

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    String path = join(await getDatabasesPath(), '800_global_english.db');
    return await openDatabase(
      path,
      version: 9, // CHANGED — was 8, bumped for oral recording upload columns
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          await db.execute('DROP TABLE IF EXISTS lessons');
          await _createSchema(db);
        }
        if (oldVersion < 5) {
          await db.execute('DROP TABLE IF EXISTS lessons');
          await _createSchema(db);
        }
        if (oldVersion < 6) {
          await _createDetailedResultTables(db);
        }
        if (oldVersion < 7) {
          await db.execute('DROP TABLE IF EXISTS lessons');
          await _createSchema(db);
          try {
            await db.execute('ALTER TABLE oral_practice_results ADD COLUMN keywordId INTEGER');
          } catch (e) {
            // ignore: column may already exist on fresh installs
          }
        }
        if (oldVersion < 8) {
          for (final stmt in [
            'ALTER TABLE detailed_noun_quiz_results ADD COLUMN lessonId INTEGER',
            'ALTER TABLE detailed_noun_quiz_results ADD COLUMN apiNounQuizType TEXT',
            'ALTER TABLE detailed_grammar_quiz_results ADD COLUMN lessonId INTEGER',
            'ALTER TABLE detailed_grammar_quiz_results ADD COLUMN apiQuizTypeId INTEGER',
            'ALTER TABLE oral_practice_results ADD COLUMN lessonId INTEGER',
          ]) {
            try {
              await db.execute(stmt);
            } catch (e) {
              // ignore: column may already exist on fresh installs
            }
          }
        }
        if (oldVersion < 9) {
          // NEW — oral recording upload support
          for (final stmt in [
            'ALTER TABLE oral_practice_results ADD COLUMN recordingPath TEXT',
            'ALTER TABLE oral_practice_results ADD COLUMN recordedFileName TEXT',
          ]) {
            try {
              await db.execute(stmt);
            } catch (e) {
              // ignore: column may already exist on fresh installs
            }
          }
        }
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    // Lesson CONTENT - cached separately per language, since titles/keywords/
    // sentences differ by language. Composite key: lessonGuid + language.
    await db.execute('''
      CREATE TABLE lessons (
        lessonGuid TEXT,
        lessonId INTEGER,
        language TEXT,
        lessonNumber INTEGER,
        title TEXT,
        description TEXT,
        videoUrl TEXT,
        pdfUrl TEXT,
        keywordsJson TEXT,
        sentencesJson TEXT,
        nounQuizzesJson TEXT,
        grammarQuizzesJson TEXT,
        captionsJson TEXT,
        PRIMARY KEY (lessonGuid, language)
      )
    ''');
    await db.execute('''
  CREATE TABLE IF NOT EXISTS oral_practice_results (
    lessonGuid TEXT,
    itemKey TEXT,
    keywordId INTEGER,
    lessonId INTEGER,
    passed INTEGER,
    synced INTEGER DEFAULT 0,
    recordingPath TEXT,
    recordedFileName TEXT,
    PRIMARY KEY (lessonGuid, itemKey)
  )
''');
    // Download status is NOT language-specific (a video is a video regardless
    // of which language someone is studying in), so it lives in its own table,
    // keyed only by lessonGuid. IF NOT EXISTS protects existing download
    // status from being wiped during the upgrade from an older schema version.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS lesson_downloads (
        lessonGuid TEXT PRIMARY KEY,
        isVideoDownloaded INTEGER DEFAULT 0,
        isContentDownloaded INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_quiz_results (
        lessonGuid TEXT,
        quizType TEXT,
        score REAL,
        completedAt TEXT,
        PRIMARY KEY (lessonGuid, quizType)
      )
    ''');

    // NEW — detailed, syncable quiz result tables
    await _createDetailedResultTables(db);
  }

  // NEW — separated into its own method so it can also be called from the
  // oldVersion < 6 upgrade branch for people who already have the app installed.
  Future<void> _createDetailedResultTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS detailed_noun_quiz_results (
        lessonGuid TEXT,
        lessonId INTEGER,
        nounQuizType TEXT,
        apiNounQuizType TEXT,
        totalQuiz INTEGER,
        totalCorrect INTEGER,
        totalWrong INTEGER,
        correctQuizIds TEXT,
        wrongQuizIds TEXT,
        correctQuizOptionIds TEXT,
        wrongQuizOptionIds TEXT,
        correctNounIds TEXT,
        wrongNounIds TEXT,
        percentage REAL,
        completedAt TEXT,
        synced INTEGER DEFAULT 0,
        PRIMARY KEY (lessonGuid, nounQuizType)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS detailed_grammar_quiz_results (
        lessonGuid TEXT,
        lessonId INTEGER,
        quizType TEXT,
        apiQuizTypeId INTEGER,
        totalQuiz INTEGER,
        totalCorrect INTEGER,
        totalWrong INTEGER,
        correctQuizIds TEXT,
        wrongQuizIds TEXT,
        percentage REAL,
        completedAt TEXT,
        synced INTEGER DEFAULT 0,
        PRIMARY KEY (lessonGuid, quizType)
      )
    ''');
  }

  // ---------- LESSONS (per-language content) ----------

  Future<void> saveLessons(List<Lesson> lessons, String language) async {
    final db = await database;
    Batch batch = db.batch();

    for (var lesson in lessons) {
      final map = lesson.toMap();
      map['language'] = language;
      batch.insert(
        'lessons',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // Returns cached lessons for a SPECIFIC language only. If nothing has been
  // cached for this language yet (e.g. never been online with it selected),
  // this returns an empty list rather than silently showing another language.
  Future<List<Lesson>> getAllLessons(String language) async {
    final db = await database;
    final maps = await db.query(
      'lessons',
      where: 'language = ?',
      whereArgs: [language],
      orderBy: 'lessonNumber ASC',
    );

    final downloadStatusMap = await _getDownloadStatusMap();

    return maps.map((m) {
      final lesson = Lesson.fromMap(m);
      final status = downloadStatusMap[lesson.lessonGuid];
      if (status != null) {
        lesson.isVideoDownloaded = status['isVideoDownloaded'] == 1;
        lesson.isContentDownloaded = status['isContentDownloaded'] == 1;
      }
      return lesson;
    }).toList();
  }

  Future<Map<String, Map<String, dynamic>>> _getDownloadStatusMap() async {
    final db = await database;
    final rows = await db.query('lesson_downloads');
    final map = <String, Map<String, dynamic>>{};
    for (var row in rows) {
      map[row['lessonGuid'] as String] = row;
    }
    return map;
  }

  Future<void> markVideoDownloaded(String lessonGuid, bool downloaded) async {
    final db = await database;
    final existing = await db.query(
      'lesson_downloads',
      where: 'lessonGuid = ?',
      whereArgs: [lessonGuid],
    );
    final existingContentFlag = existing.isNotEmpty ? existing.first['isContentDownloaded'] : 0;
    await db.insert(
      'lesson_downloads',
      {
        'lessonGuid': lessonGuid,
        'isVideoDownloaded': downloaded ? 1 : 0,
        'isContentDownloaded': existingContentFlag,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> markContentDownloaded(String lessonGuid, bool downloaded) async {
    final db = await database;
    final existing = await db.query(
      'lesson_downloads',
      where: 'lessonGuid = ?',
      whereArgs: [lessonGuid],
    );
    final existingVideoFlag = existing.isNotEmpty ? existing.first['isVideoDownloaded'] : 0;
    await db.insert(
      'lesson_downloads',
      {
        'lessonGuid': lessonGuid,
        'isVideoDownloaded': existingVideoFlag,
        'isContentDownloaded': downloaded ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------- PENDING QUIZ RESULTS (used by the score-tracker hub screen) ----------

  Future<void> savePendingResultIfBetter(
      String lessonGuid, String quizType, double score) async {
    final db = await database;
    final existing = await db.query(
      'pending_quiz_results',
      where: 'lessonGuid = ? AND quizType = ?',
      whereArgs: [lessonGuid, quizType],
    );

    if (existing.isEmpty || (existing.first['score'] as double) < score) {
      await db.insert(
        'pending_quiz_results',
        {
          'lessonGuid': lessonGuid,
          'quizType': quizType,
          'score': score,
          'completedAt': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<List<Map<String, dynamic>>> getPendingResults() async {
    final db = await database;
    return await db.query('pending_quiz_results');
  }

  Future<double?> getScoreFor(String lessonGuid, String quizType) async {
    final db = await database;
    final rows = await db.query(
      'pending_quiz_results',
      where: 'lessonGuid = ? AND quizType = ?',
      whereArgs: [lessonGuid, quizType],
    );
    if (rows.isEmpty) return null;
    return rows.first['score'] as double;
  }

  Future<void> clearPendingResult(String lessonGuid, String quizType) async {
    final db = await database;
    await db.delete(
      'pending_quiz_results',
      where: 'lessonGuid = ? AND quizType = ?',
      whereArgs: [lessonGuid, quizType],
    );
  }

  // ---------- NEW: DETAILED NOUN QUIZ RESULTS (for server sync) ----------

  // Call this from the noun quiz screen instead of savePendingResultIfBetter.
  // It saves the full right/wrong breakdown needed for server sync, AND still
  // updates pending_quiz_results underneath, so the score-tracker hub screen
  // keeps working exactly as before with no changes needed there.
  Future<void> saveDetailedNounResult({
    required String lessonGuid,
    required int lessonId,
    required String nounQuizType,
    required String apiNounQuizType,
    required int totalQuiz,
    required int totalCorrect,
    required int totalWrong,
    required List<int> correctQuizIds,
    required List<int> wrongQuizIds,
    required List<int> correctQuizOptionIds,
    required List<int> wrongQuizOptionIds,
    required List<int> correctNounIds,
    required List<int> wrongNounIds,
    required double percentage,
  }) async {
    final db = await database;

    await savePendingResultIfBetter(lessonGuid, nounQuizType, percentage);

    await db.insert(
      'detailed_noun_quiz_results',
      {
        'lessonGuid': lessonGuid,
        'lessonId': lessonId,
        'nounQuizType': nounQuizType,
        'apiNounQuizType': apiNounQuizType,
        'totalQuiz': totalQuiz,
        'totalCorrect': totalCorrect,
        'totalWrong': totalWrong,
        'correctQuizIds': correctQuizIds.join(','),
        'wrongQuizIds': wrongQuizIds.join(','),
        'correctQuizOptionIds': correctQuizOptionIds.join(','),
        'wrongQuizOptionIds': wrongQuizOptionIds.join(','),
        'correctNounIds': correctNounIds.join(','),
        'wrongNounIds': wrongNounIds.join(','),
        'percentage': percentage,
        'completedAt': DateTime.now().toIso8601String(),
        'synced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getUnsyncedNounResults() async {
    final db = await database;
    return await db.query('detailed_noun_quiz_results', where: 'synced = 0');
  }

  Future<void> markNounResultSynced(String lessonGuid, String nounQuizType) async {
    final db = await database;
    await db.update(
      'detailed_noun_quiz_results',
      {'synced': 1},
      where: 'lessonGuid = ? AND nounQuizType = ?',
      whereArgs: [lessonGuid, nounQuizType],
    );
  }

  // ---------- NEW: DETAILED GRAMMAR QUIZ RESULTS (for server sync) ----------

  // Call this from the grammar quiz screen instead of savePendingResultIfBetter.
  // Same pattern as above: saves full detail for sync, still updates
  // pending_quiz_results underneath so the hub screen is unaffected.
  Future<void> saveDetailedGrammarResult({
    required String lessonGuid,
    required int lessonId,
    required String quizType,
    required int apiQuizTypeId,
    required int totalQuiz,
    required int totalCorrect,
    required int totalWrong,
    required List<int> correctQuizIds,
    required List<int> wrongQuizIds,
    required double percentage,
  }) async {
    final db = await database;

    await savePendingResultIfBetter(lessonGuid, quizType, percentage);

    await db.insert(
      'detailed_grammar_quiz_results',
      {
        'lessonGuid': lessonGuid,
        'lessonId': lessonId,
        'quizType': quizType,
        'apiQuizTypeId': apiQuizTypeId,
        'totalQuiz': totalQuiz,
        'totalCorrect': totalCorrect,
        'totalWrong': totalWrong,
        'correctQuizIds': correctQuizIds.join(','),
        'wrongQuizIds': wrongQuizIds.join(','),
        'percentage': percentage,
        'completedAt': DateTime.now().toIso8601String(),
        'synced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getUnsyncedGrammarResults() async {
    final db = await database;
    return await db.query('detailed_grammar_quiz_results', where: 'synced = 0');
  }

  Future<void> markGrammarResultSynced(String lessonGuid, String quizType) async {
    final db = await database;
    await db.update(
      'detailed_grammar_quiz_results',
      {'synced': 1},
      where: 'lessonGuid = ? AND quizType = ?',
      whereArgs: [lessonGuid, quizType],
    );
  }

  // ---------- ORAL PRACTICE RESULTS ----------

  Future<void> saveOralPracticeResult(String lessonGuid, String itemKey, bool passed,
      {int keywordId = 0, int lessonId = 0, String? recordingPath}) async {
    final db = await database;
    await db.insert(
      'oral_practice_results',
      {
        'lessonGuid': lessonGuid,
        'itemKey': itemKey,
        'keywordId': keywordId,
        'lessonId': lessonId,
        'passed': passed ? 1 : 0,
        'synced': 0,
        'recordingPath': recordingPath,
        'recordedFileName': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> getOralPracticeResult(String lessonGuid, String itemKey) async {
    final db = await database;
    final rows = await db.query(
      'oral_practice_results',
      where: 'lessonGuid = ? AND itemKey = ?',
      whereArgs: [lessonGuid, itemKey],
    );
    if (rows.isEmpty) return false;
    return rows.first['passed'] == 1;
  }

  Future<List<Map<String, dynamic>>> getUnsyncedOralPracticeResults() async {
    final db = await database;
    return await db.query('oral_practice_results', where: 'synced = 0');
  }

  Future<void> markOralPracticeResultSynced(String lessonGuid, String itemKey) async {
    final db = await database;
    await db.update(
      'oral_practice_results',
      {'synced': 1},
      where: 'lessonGuid = ? AND itemKey = ?',
      whereArgs: [lessonGuid, itemKey],
    );
  }

  // Checks whether every keyword in a lesson has been self-graded as passed
  Future<bool> isLessonPracticeComplete(String lessonGuid, List<String> allItemKeys) async {
    final db = await database;
    final rows = await db.query(
      'oral_practice_results',
      where: 'lessonGuid = ? AND passed = 1',
      whereArgs: [lessonGuid],
    );
    final passedKeys = rows.map((r) => r['itemKey'] as String).toSet();
    return allItemKeys.every((key) => passedKeys.contains(key));
  }

  Future<Set<String>> getPassedItemKeys(String lessonGuid) async {
    final db = await database;
    final rows = await db.query(
      'oral_practice_results',
      where: 'lessonGuid = ? AND passed = 1',
      whereArgs: [lessonGuid],
    );
    return rows.map((r) => r['itemKey'] as String).toSet();
  }

  Future<double> getOralPracticeScore(String lessonGuid, List<String> allItemKeys) async {
    if (allItemKeys.isEmpty) return 0;
    final db = await database;
    final rows = await db.query(
      'oral_practice_results',
      where: 'lessonGuid = ? AND passed = 1',
      whereArgs: [lessonGuid],
    );
    final passedKeys = rows.map((r) => r['itemKey'] as String).toSet();
    final passedCount = allItemKeys.where((key) => passedKeys.contains(key)).length;
    return (passedCount / allItemKeys.length) * 100;
  }
}
