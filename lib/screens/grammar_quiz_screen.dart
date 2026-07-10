
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/lesson.dart';
import '../services/local_db.dart';
import '../services/api_service.dart';
import '../services/resource_strings.dart';
import 'package:flutter/services.dart';
import '../services/sound_feedback.dart';

class GrammarQuizScreen extends StatefulWidget {
  final Lesson lesson;
  final String quizType; // "grammar", "spelling", or "advance"
  final String screenTitle; // e.g. "Grammar Quiz", "Spelling Quiz", "Advanced Quiz"
  final String resultKey; // key used when saving score locally, must be unique per type

  const GrammarQuizScreen({
    super.key,
    required this.lesson,
    required this.quizType,
    required this.screenTitle,
    required this.resultKey,
  });

  @override
  State<GrammarQuizScreen> createState() => _GrammarQuizScreenState();
}

class _GrammarQuizScreenState extends State<GrammarQuizScreen> {
  final LocalDb _localDb = LocalDb.instance;

  late List<GrammarQuizQuestion> _questions;
  int _currentIndex = 0;
  int _correctCount = 0;
  bool _answered = false;
  GrammarQuizOption? _selectedOption;

  // NEW — per-question tracking, built up as the quiz progresses
  final List<int> _correctQuizIds = [];
  final List<int> _wrongQuizIds = [];

  @override
  void initState() {
    super.initState();
    // FIXED — cap at 10 questions after shuffling, matching the website's own
    // PrePareQuizListing behavior (objQC.Take(10)). Without this, lessons with
    // more than ~14 questions of a type overflow the server's 100-character
    // CorrectQuizids column and every submission from that quiz silently fails.
    _questions = widget.lesson.grammarQuizzes
        .where((q) => q.quizType == widget.quizType)
        .toList()
      ..shuffle(Random());
    if (_questions.length > 10) {
      _questions = _questions.sublist(0, 10);
    }

    for (final q in _questions) {
      q.options.shuffle(Random());
    }
  }

  void _selectAnswer(GrammarQuizOption option) {
    if (_answered) return;
    final question = _questions[_currentIndex];

    setState(() {
      _answered = true;
      _selectedOption = option;
      if (option.isCorrect) {
        _correctCount++;
        _correctQuizIds.add(question.quizId); // NEW
      } else {
        _wrongQuizIds.add(question.quizId); // NEW
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

    // Maps widget.quizType ("grammar"/"spelling"/"advance") to the server's
    // RefQuizTypeID (1/2/3) — computed directly from the known quiz type,
    // not the hub resultKey, so it can't drift if resultKey naming changes.
    final apiQuizTypeId = widget.quizType == 'grammar'
        ? 1
        : widget.quizType == 'spelling'
        ? 2
        : 3; // 'advance'

    // CHANGED — was: savePendingResultIfBetter(widget.lesson.lessonGuid, widget.resultKey, score);
    // Now saves the full detail needed for server sync, not just the score.
    await _localDb.saveDetailedGrammarResult(
      lessonGuid: widget.lesson.lessonGuid,
      lessonId: widget.lesson.lessonId,
      quizType: widget.resultKey,
      apiQuizTypeId: apiQuizTypeId,
      totalQuiz: _questions.length,
      totalCorrect: _correctCount,
      totalWrong: _questions.length - _correctCount,
      correctQuizIds: _correctQuizIds,
      wrongQuizIds: _wrongQuizIds,
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
        title: Text(ResourceStrings.instance.get('aiadd3921')),
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

  Widget _buildOptionButton(GrammarQuizOption option) {
    Color? backgroundColor;
    if (_answered) {
      if (option.isCorrect) {
        backgroundColor = Colors.green.shade200;
      } else if (option == _selectedOption) {
        backgroundColor = Colors.red.shade200;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => _selectAnswer(option),
          child: Text(option.text, style: const TextStyle(fontSize: 18)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.screenTitle)),
        body: Center(child: Text(ResourceStrings.instance.get('aiadd3945'))),
      );
    }

    final question = _questions[_currentIndex];

    return Scaffold(
      key: ValueKey(_currentIndex),
      appBar: AppBar(title: Text('Lesson ${widget.lesson.lessonNumber}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.screenTitle} - ${_currentIndex + 1} of ${_questions.length}',
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
            if (question.promptText.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                question.promptText,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 32),
            ] else
              const SizedBox(height: 24),
            Text(
              ResourceStrings.instance.get('aiadd3946'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ...question.options.map(_buildOptionButton),
          ],
        ),
      ),
    );
  }
}
