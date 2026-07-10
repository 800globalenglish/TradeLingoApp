
import 'dart:convert';

// Base CDN folders - filenames from the API get combined with these
// to build full, downloadable URLs.
const String imageBaseUrl =
    'https://800PlusMedia.b-cdn.net/content/media/images/lessons48/';
const String audioBaseUrl =
    'https://800PlusMedia.b-cdn.net/content/media/sounds/lessons48/';
const String lessonNounAudioBaseUrl =
    'https://cdn.800globalenglish.com/content/media/sounds/LessonNoun/';

String _resolveAudioUrl(String filename) {
  final trimmed = filename.trim();

  final isNounGuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\.mp3$')
      .hasMatch(trimmed);
  if (isNounGuid) return lessonNounAudioBaseUrl + trimmed;

  // Supplemental sentence audio (e.g. "o001_01.mp3") lives on a different
  // CDN host than the regular word/sentence audio.
  final isSupplementalSentence = RegExp(r'^[a-zA-Z]\d{3}_\d{2}\.mp3$').hasMatch(trimmed);
  if (isSupplementalSentence) {
    return 'https://cdn.800globalenglish.com/content/media/sounds/lessons48/' + trimmed;
  }

  return audioBaseUrl + trimmed;
}

class Keyword {
  final String title;
  final int id; // NEW — maps to server's LessonVirtualClassRoomID, needed for oral quiz RefKeywordID
  final String? translation;
  final String imageUrl;
  final String audioUrl;

  Keyword({required this.id, required this.title, this.translation, required this.imageUrl, required this.audioUrl});

  factory Keyword.fromJson(Map<String, dynamic> json) {
    return Keyword(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      translation: json['translation'],
      imageUrl: imageBaseUrl + (json['image'] ?? '').toString().trim(),
      audioUrl: _resolveAudioUrl(json['audio'] ?? ''),
    );
  }

  Map<String, dynamic> toCacheMap() => {
    'id': id,
    'title': title,
    'translation': translation,
    'imageUrl': imageUrl,
    'audioUrl': audioUrl,
  };

  factory Keyword.fromCacheMap(Map<String, dynamic> map) {
    return Keyword(
      id: map['id'] ?? 0,
      title: map['title'] ?? '',
      translation: map['translation'],
      imageUrl: map['imageUrl'] ?? '',
      audioUrl: map['audioUrl'] ?? '',
    );
  }
}

class SentenceItem {
  final String title;
  final String? translation;
  final String audioUrl;

  SentenceItem({required this.title, this.translation, required this.audioUrl});

  factory SentenceItem.fromJson(Map<String, dynamic> json) {
    return SentenceItem(
      title: json['title'] ?? '',
      translation: json['translation'],
      audioUrl: _resolveAudioUrl(json['audio'] ?? ''),
    );
  }

  Map<String, dynamic> toCacheMap() => {
    'title': title,
    'translation': translation,
    'audioUrl': audioUrl,
  };

  factory SentenceItem.fromCacheMap(Map<String, dynamic> map) {
    return SentenceItem(
      title: map['title'] ?? '',
      translation: map['translation'],
      audioUrl: map['audioUrl'] ?? '',
    );
  }
}

// ============================================================================
// CHANGED: NounQuizOption — added optionId, nounId
// ============================================================================
class NounQuizOption {
  final int optionId; // NEW — maps to server's OptionAutoID (CorrectQuizOptionIds/WrongQuizOptionIds)
  final int nounId;    // NEW — maps to server's RefNounQuizOptionID (CorrectNounIds/WrongNounIds)
  final String word;
  final String imageUrl;
  final String audioUrl;
  final bool isCorrect;

  NounQuizOption({
    required this.optionId,
    required this.nounId,
    required this.word,
    required this.imageUrl,
    required this.audioUrl,
    required this.isCorrect,
  });

  factory NounQuizOption.fromJson(Map<String, dynamic> json) {
    return NounQuizOption(
      optionId: json['optionId'] ?? 0,
      nounId: json['nounId'] ?? 0,
      word: json['word'] ?? '',
      imageUrl: imageBaseUrl + (json['image'] ?? '').toString().trim(),
      audioUrl: _resolveAudioUrl(json['audio'] ?? ''),
      isCorrect: json['isCorrect'] ?? false,
    );
  }

  Map<String, dynamic> toCacheMap() => {
    'optionId': optionId,
    'nounId': nounId,
    'word': word,
    'imageUrl': imageUrl,
    'audioUrl': audioUrl,
    'isCorrect': isCorrect,
  };

  factory NounQuizOption.fromCacheMap(Map<String, dynamic> map) {
    return NounQuizOption(
      optionId: map['optionId'] ?? 0,
      nounId: map['nounId'] ?? 0,
      word: map['word'] ?? '',
      imageUrl: map['imageUrl'] ?? '',
      audioUrl: map['audioUrl'] ?? '',
      isCorrect: map['isCorrect'] ?? false,
    );
  }
}

// ============================================================================
// CHANGED: NounQuizQuestion — added quizId
// ============================================================================
class NounQuizQuestion {
  final int quizId; // NEW — maps to server's NounQuizAutoID (CorrectQuizIds/WrongQuizIds)
  final String quizType;
  final List<NounQuizOption> options;

  NounQuizQuestion({required this.quizId, required this.quizType, required this.options});

  factory NounQuizQuestion.fromJson(Map<String, dynamic> json) {
    return NounQuizQuestion(
      quizId: json['quizId'] ?? 0,
      quizType: json['quizType'] ?? '',
      options: (json['options'] as List<dynamic>? ?? [])
          .map((o) => NounQuizOption.fromJson(o))
          .toList(),
    );
  }

  NounQuizOption get correctOption =>
      options.firstWhere((o) => o.isCorrect, orElse: () => options.first);

  Map<String, dynamic> toCacheMap() => {
    'quizId': quizId,
    'quizType': quizType,
    'options': options.map((o) => o.toCacheMap()).toList(),
  };

  factory NounQuizQuestion.fromCacheMap(Map<String, dynamic> map) {
    return NounQuizQuestion(
      quizId: map['quizId'] ?? 0,
      quizType: map['quizType'] ?? '',
      options: (map['options'] as List<dynamic>? ?? [])
          .map((o) => NounQuizOption.fromCacheMap(o))
          .toList(),
    );
  }
}

// ============================================================================
// CHANGED: GrammarQuizOption — added optionId
// ============================================================================
class GrammarQuizOption {
  final int optionId; // NEW — maps to server's QuizAutoOptionID (app-internal use; not sent back to server, see note in GetAllLessons patch)
  final String text;
  final bool isCorrect;

  GrammarQuizOption({required this.optionId, required this.text, required this.isCorrect});

  factory GrammarQuizOption.fromJson(Map<String, dynamic> json) {
    return GrammarQuizOption(
      optionId: json['optionId'] ?? 0,
      text: json['text'] ?? '',
      isCorrect: json['isCorrect'] ?? false,
    );
  }

  Map<String, dynamic> toCacheMap() => {
    'optionId': optionId,
    'text': text,
    'isCorrect': isCorrect,
  };

  factory GrammarQuizOption.fromCacheMap(Map<String, dynamic> map) {
    return GrammarQuizOption(
      optionId: map['optionId'] ?? 0,
      text: map['text'] ?? '',
      isCorrect: map['isCorrect'] ?? false,
    );
  }
}

// ============================================================================
// CHANGED: GrammarQuizQuestion — added quizId
// ============================================================================
class GrammarQuizQuestion {
  final int quizId; // NEW — maps to server's QuizCollectionAutoID (CorrectQuizIds/WrongIds)
  final String quizType; // "grammar", "spelling", or "advance"
  final String promptText; // blank for grammar/spelling, the word itself for advance
  final List<GrammarQuizOption> options;

  GrammarQuizQuestion({
    required this.quizId,
    required this.quizType,
    required this.promptText,
    required this.options,
  });

  factory GrammarQuizQuestion.fromJson(Map<String, dynamic> json) {
    return GrammarQuizQuestion(
      quizId: json['quizId'] ?? 0,
      quizType: json['quizType'] ?? '',
      promptText: json['promptText'] ?? '',
      options: (json['options'] as List<dynamic>? ?? [])
          .map((o) => GrammarQuizOption.fromJson(o))
          .toList(),
    );
  }

  GrammarQuizOption get correctOption =>
      options.firstWhere((o) => o.isCorrect, orElse: () => options.first);

  Map<String, dynamic> toCacheMap() => {
    'quizId': quizId,
    'quizType': quizType,
    'promptText': promptText,
    'options': options.map((o) => o.toCacheMap()).toList(),
  };

  factory GrammarQuizQuestion.fromCacheMap(Map<String, dynamic> map) {
    return GrammarQuizQuestion(
      quizId: map['quizId'] ?? 0,
      quizType: map['quizType'] ?? '',
      promptText: map['promptText'] ?? '',
      options: (map['options'] as List<dynamic>? ?? [])
          .map((o) => GrammarQuizOption.fromCacheMap(o))
          .toList(),
    );
  }
}

// ============================================================================
// UNCHANGED BELOW — Lesson, VideoCaption (same as your original file)
// ============================================================================

class Lesson {
  final String lessonGuid;
  final int lessonId; // NEW — maps to server's LessonVirtualClassRoomID, needed as RefLessonID for all Submit* sync calls
  final int lessonNumber;
  final String title;
  final String description;
  final String videoUrl;
  final String pdfUrl;
  final List<Keyword> keywords;
  final List<SentenceItem> sentences;
  final List<NounQuizQuestion> nounQuizzes;
  final List<GrammarQuizQuestion> grammarQuizzes;
  final List<VideoCaption> captions;
  bool isVideoDownloaded;
  bool isContentDownloaded;

  Lesson({
    required this.lessonGuid,
    required this.lessonId,
    required this.lessonNumber,
    required this.title,
    required this.description,
    required this.videoUrl,
    required this.pdfUrl,
    this.keywords = const [],
    this.sentences = const [],
    this.nounQuizzes = const [],
    this.grammarQuizzes = const [],
    this.isVideoDownloaded = false,
    this.isContentDownloaded = false,
    this.captions = const [],
  });

  factory Lesson.fromJson(Map<String, dynamic> json) {
    return Lesson(
      lessonGuid: json['lessonGuid'] ?? '',
      lessonId: json['lessonId'] ?? 0,
      lessonNumber: json['lessonNumber'] ?? 0,
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      videoUrl: json['videoUrl'] ?? '',
      pdfUrl: json['pdfUrl'] ?? '',
      keywords: (json['keywords'] as List<dynamic>? ?? [])
          .map((k) => Keyword.fromJson(k))
          .toList(),
      sentences: (json['sentences'] as List<dynamic>? ?? [])
          .map((s) => SentenceItem.fromJson(s))
          .toList(),
      nounQuizzes: (json['nounQuizzes'] as List<dynamic>? ?? [])
          .map((q) => NounQuizQuestion.fromJson(q))
          .toList(),
      grammarQuizzes: (json['grammarQuizzes'] as List<dynamic>? ?? [])
          .map((q) => GrammarQuizQuestion.fromJson(q))
          .toList(),
      captions: (json['captions'] as List<dynamic>? ?? [])
          .map((c) => VideoCaption.fromJson(c))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'lessonGuid': lessonGuid,
      'lessonId': lessonId,
      'lessonNumber': lessonNumber,
      'title': title,
      'description': description,
      'videoUrl': videoUrl,
      'pdfUrl': pdfUrl,
      'keywordsJson': jsonEncode(keywords.map((k) => k.toCacheMap()).toList()),
      'sentencesJson': jsonEncode(sentences.map((s) => s.toCacheMap()).toList()),
      'nounQuizzesJson': jsonEncode(nounQuizzes.map((q) => q.toCacheMap()).toList()),
      'grammarQuizzesJson': jsonEncode(grammarQuizzes.map((q) => q.toCacheMap()).toList()),
      'captionsJson': jsonEncode(captions.map((c) => c.toCacheMap()).toList()),
    };
  }

  factory Lesson.fromMap(Map<String, dynamic> map) {
    List<Keyword> keywords = [];
    List<SentenceItem> sentences = [];
    List<NounQuizQuestion> nounQuizzes = [];
    List<GrammarQuizQuestion> grammarQuizzes = [];
    List<VideoCaption> captions = [];

    try {
      if (map['keywordsJson'] != null) {
        final decoded = jsonDecode(map['keywordsJson']) as List<dynamic>;
        keywords = decoded.map((k) => Keyword.fromCacheMap(k)).toList();
      }
      if (map['sentencesJson'] != null) {
        final decoded = jsonDecode(map['sentencesJson']) as List<dynamic>;
        sentences = decoded.map((s) => SentenceItem.fromCacheMap(s)).toList();
      }
      if (map['nounQuizzesJson'] != null) {
        final decoded = jsonDecode(map['nounQuizzesJson']) as List<dynamic>;
        nounQuizzes = decoded.map((q) => NounQuizQuestion.fromCacheMap(q)).toList();
      }
      if (map['grammarQuizzesJson'] != null) {
        final decoded = jsonDecode(map['grammarQuizzesJson']) as List<dynamic>;
        grammarQuizzes = decoded.map((q) => GrammarQuizQuestion.fromCacheMap(q)).toList();
      }
      if (map['captionsJson'] != null) {
        final decoded = jsonDecode(map['captionsJson']) as List<dynamic>;
        captions = decoded.map((c) => VideoCaption.fromCacheMap(c)).toList();
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error parsing cached lesson content: $e');
    }

    return Lesson(
      lessonGuid: map['lessonGuid'],
      lessonId: map['lessonId'] ?? 0,
      lessonNumber: map['lessonNumber'],
      title: map['title'],
      description: map['description'],
      videoUrl: map['videoUrl'],
      pdfUrl: map['pdfUrl'],
      keywords: keywords,
      sentences: sentences,
      nounQuizzes: nounQuizzes,
      grammarQuizzes: grammarQuizzes,
      captions: captions,
    );
  }
}

class VideoCaption {
  final String text;
  final double startTime;

  VideoCaption({required this.text, required this.startTime});

  factory VideoCaption.fromJson(Map<String, dynamic> json) {
    return VideoCaption(
      text: json['text'] ?? '',
      startTime: (json['startTime'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toCacheMap() => {
    'text': text,
    'startTime': startTime,
  };

  factory VideoCaption.fromCacheMap(Map<String, dynamic> map) {
    return VideoCaption(
      text: map['text'] ?? '',
      startTime: (map['startTime'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
