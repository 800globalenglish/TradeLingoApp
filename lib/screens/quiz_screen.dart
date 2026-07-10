// ============================================================================
// quiz_screen.dart (noun quiz) — UPDATED to track per-question ids
// ============================================================================
// Changes from your original:
//   1. Added six tracking lists, populated in _selectAnswer:
//        _correctQuizIds / _wrongQuizIds       -> question.quizId
//        _correctQuizOptionIds / _wrongQuizOptionIds -> the SELECTED option's optionId
//        _correctNounIds / _wrongNounIds        -> the TESTED noun's id (question.correctOption.nounId)
//      Note: the "tested noun" is always question.correctOption.nounId, whether
//      the student got it right or wrong — it identifies which vocab word this
//      question was about, matching the server's per-noun mastery tracking.
//   2. _finishQuiz now calls a NEW local_db method: saveDetailedNounResult
//      (defined in the next step). REPLACES savePendingResultIfBetter.
// Everything else (audio playback, UI, clue building) is unchanged.
// ============================================================================

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/lesson.dart';
import '../services/local_db.dart';
import '../services/api_service.dart';
import '../services/content_package_service.dart';
import '../services/resource_strings.dart';
import '../widgets/smart_image.dart';
import 'package:flutter/services.dart';
import '../services/sound_feedback.dart';

class QuizScreen extends StatefulWidget {
  final Lesson lesson;
  final String quizType; // "text/image", "image/audio", or "text/audio"
  final String screenTitle;
  final String resultKey;

  const QuizScreen({
    super.key,
    required this.lesson,
    required this.quizType,
    required this.screenTitle,
    required this.resultKey,
  });

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final AudioPlayer _player = AudioPlayer();
  final LocalDb _localDb = LocalDb.instance;

  late List<NounQuizQuestion> _questions;
  int _currentIndex = 0;
  int _correctCount = 0;
  bool _answered = false;
  NounQuizOption? _selectedOption;
  int _lastAutoPlayedIndex = -1;

  // NEW — per-question tracking, built up as the quiz progresses
  final List<int> _correctQuizIds = [];
  final List<int> _wrongQuizIds = [];
  final List<int> _correctQuizOptionIds = [];
  final List<int> _wrongQuizOptionIds = [];
  final List<int> _correctNounIds = [];
  final List<int> _wrongNounIds = [];

  @override
  void initState() {
    super.initState();

    _questions = widget.lesson.nounQuizzes
        .where((q) => q.quizType == widget.quizType)
        .toList()
      ..shuffle(Random());
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _playAudio(String url) async {
    try {
      await _player.stop();
      final localPath = await ContentPackageService.instance.resolveLocalPath(url);
      if (localPath != null) {
        await _player.play(DeviceFileSource(localPath));
      } else {
        await _player.play(UrlSource(url));
      }
    } catch (e) {
      // ignore
    }
  }

  String _answerType(String quizType) => quizType.split('/')[0];
  String _clueType(String quizType) => quizType.split('/')[1];

  void _selectAnswer(NounQuizOption option) {
    if (_answered) return;
    final question = _questions[_currentIndex];
    final testedNounId = question.correctOption.nounId; // NEW — the vocab word this question tests

    setState(() {
      _answered = true;
      _selectedOption = option;
      if (option.isCorrect) {
        _correctCount++;
        _correctQuizIds.add(question.quizId);           // NEW
        _correctQuizOptionIds.add(option.optionId);      // NEW
        _correctNounIds.add(testedNounId);               // NEW
      } else {
        _wrongQuizIds.add(question.quizId);              // NEW
        _wrongQuizOptionIds.add(option.optionId);         // NEW
        _wrongNounIds.add(testedNounId);                  // NEW
      }
    });

    option.isCorrect ? SoundFeedback.playCorrect() : SoundFeedback.playWrong();

    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _nextQuestion();
    });
  }

  void _nextQuestion() {
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _answered = false;
        _selectedOption = null;
      });
    } else {
      _finishQuiz();
    }
  }

  Future<void> _finishQuiz() async {
    final score = (_correctCount / _questions.length) * 100;

    // CHANGED — was: savePendingResultIfBetter(widget.lesson.lessonGuid, widget.resultKey, score);
    await _localDb.saveDetailedNounResult(
      lessonGuid: widget.lesson.lessonGuid,
      lessonId: widget.lesson.lessonId, // NEW
      nounQuizType: widget.resultKey,
      apiNounQuizType: widget.quizType, // NEW — the real server string, e.g. "text/image"
      totalQuiz: _questions.length,
      totalCorrect: _correctCount,
      totalWrong: _questions.length - _correctCount,
      correctQuizIds: _correctQuizIds,
      wrongQuizIds: _wrongQuizIds,
      correctQuizOptionIds: _correctQuizOptionIds,
      wrongQuizOptionIds: _wrongQuizOptionIds,
      correctNounIds: _correctNounIds,
      wrongNounIds: _wrongNounIds,
      percentage: score,
    );

    // NEW — fire-and-forget: pushes this result (and anything else pending)
    // to the server right after finishing, since the lesson list screen may
    // not get revisited this session. Not awaited so it doesn't delay the
    // score dialog below.
    ApiService().syncPendingResults();

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(ResourceStrings.instance.get('aiadd3979')),
        content: Text(
            '${ResourceStrings.instance.get('aiadd3922')} ${score.toStringAsFixed(0)}%\n($_correctCount ${ResourceStrings.instance.get('aiadd3923')} ${_questions.length} ${ResourceStrings.instance.get('aiadd3924')})'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: Text(ResourceStrings.instance.get('aiadd3925')),
          ),
        ],
      ),
    );
  }

  Widget _buildClue(NounQuizQuestion question, NounQuizOption correctAnswer) {
    final clueType = _clueType(question.quizType);

    if (clueType == 'image') {
      return SizedBox(
        height: 150,
        child: SmartImage(url: correctAnswer.imageUrl, height: 150),
      );
    } else {
      return Column(
        children: [
          IconButton(
            icon: const Icon(Icons.volume_up, size: 56),
            onPressed: () => _playAudio(correctAnswer.audioUrl),
          ),
          Text(ResourceStrings.instance.get('aiadd3980')),
        ],
      );
    }
  }

  Widget _buildOptionButton(NounQuizQuestion question, NounQuizOption option) {
    final answerType = _answerType(question.quizType);

    Color? backgroundColor;
    if (_answered) {
      if (option.isCorrect) {
        backgroundColor = Colors.green.shade200;
      } else if (option == _selectedOption) {
        backgroundColor = Colors.red.shade200;
      }
    }

    Widget content;
    if (answerType == 'image') {
      content = SmartImage(url: option.imageUrl);
    } else {
      content = Text(option.word, style: const TextStyle(fontSize: 18));
    }

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: EdgeInsets.zero,
      ),
      onPressed: () => _selectAnswer(option),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: content,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.screenTitle)),
        body: Center(child: Text(ResourceStrings.instance.get('aiadd3981'))),
      );
    }

    final question = _questions[_currentIndex];
    final correctAnswer = question.correctOption;

    if (!_answered && _clueType(question.quizType) == 'audio' && _lastAutoPlayedIndex != _currentIndex) {
      _lastAutoPlayedIndex = _currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _playAudio(correctAnswer.audioUrl);
      });
    }

    return Scaffold(
      key: ValueKey(_currentIndex),
      appBar: AppBar(title: Text('Lesson ${widget.lesson.lessonNumber}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              '${widget.screenTitle} - ${_currentIndex + 1} ${ResourceStrings.instance.get('aiadd3963')} ${_questions.length}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              widget.screenTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildClue(question, correctAnswer),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: question.options.map((option) => _buildOptionButton(question, option)).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
