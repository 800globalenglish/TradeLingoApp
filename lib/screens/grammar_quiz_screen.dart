import 'dart:async'; // NEW
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // NEW — for reading expert/beginner preference
import '../models/lesson.dart';
import '../services/local_db.dart';
import '../services/api_service.dart';
import '../services/resource_strings.dart';
import 'package:flutter/services.dart';
import '../services/sound_feedback.dart';

class GrammarQuizScreen extends StatefulWidget {
  final Lesson lesson;
  final String quizType;
  final String screenTitle;
  final String resultKey;

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

  final List<int> _correctQuizIds = [];
  final List<int> _wrongQuizIds = [];

  // NEW — timer state
  static const int _timerDuration = 24;
  int _secondsRemaining = _timerDuration;
  Timer? _questionTimer;

  // NEW — difficulty toggle state (set from the Quiz Hub screen, read here)
  bool _isExpertMode = false;
  int get _effectiveTimerDuration => _isExpertMode ? (_timerDuration / 2).round() : _timerDuration;

  @override
  void initState() {
    super.initState();
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

    _initDifficultyThenStartTimer(); // CHANGED — was: _startTimer();
  }

  // NEW — loads the expert/beginner preference set on the Quiz Hub screen
  Future<void> _initDifficultyThenStartTimer() async {
    final prefs = await SharedPreferences.getInstance();
    final isExpert = prefs.getBool('quizExpertMode') ?? false;
    if (mounted) {
      setState(() => _isExpertMode = isExpert);
    }
    _startTimer();
  }

  @override
  void dispose() {
    _questionTimer?.cancel(); // NEW
    super.dispose();
  }

  // NEW
  void _startTimer() {
    _questionTimer?.cancel();
    _secondsRemaining = _effectiveTimerDuration; // CHANGED — was: _timerDuration
    _questionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _secondsRemaining--;
      });
      if (_secondsRemaining <= 0) {
        timer.cancel();
        _handleTimeout();
      }
    });
  }

  // NEW
  void _handleTimeout() {
    if (_answered) return;
    final question = _questions[_currentIndex];

    setState(() {
      _answered = true;
      _selectedOption = null;
      _wrongQuizIds.add(question.quizId);
    });

    SoundFeedback.playWrong();

    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _nextQuestion();
    });
  }

  void _selectAnswer(GrammarQuizOption option) {
    if (_answered) return;
    _questionTimer?.cancel(); // NEW
    final question = _questions[_currentIndex];

    setState(() {
      _answered = true;
      _selectedOption = option;
      if (option.isCorrect) {
        _correctCount++;
        _correctQuizIds.add(question.quizId);
      } else {
        _wrongQuizIds.add(question.quizId);
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
      _startTimer(); // NEW
    } else {
      _finishQuiz();
    }
  }

  Future<void> _finishQuiz() async {
    final score = (_correctCount / _questions.length) * 100;

    final apiQuizTypeId = widget.quizType == 'grammar'
        ? 1
        : widget.quizType == 'spelling'
        ? 2
        : 3;

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

  // NEW — same timer widget as the noun quiz
  Widget _buildTimer() {
    final isLow = _secondsRemaining <= 3;
    return Column(
      children: [
        Text(
          '$_secondsRemaining',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: isLow ? Colors.red : Colors.black87,
          ),
        ),
        SizedBox(
          width: 120,
          child: LinearProgressIndicator(
            value: _secondsRemaining / _effectiveTimerDuration, // CHANGED — was: _timerDuration
            color: isLow ? Colors.red : Colors.blue,
            backgroundColor: Colors.grey.shade300,
          ),
        ),
      ],
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
            _buildTimer(), // NEW
            const SizedBox(height: 8),
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
