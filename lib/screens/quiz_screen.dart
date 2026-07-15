import 'dart:async'; // NEW — needed for Timer
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart'; // NEW — for saving expert/beginner preference
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
  final String quizType;
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

  final List<int> _correctQuizIds = [];
  final List<int> _wrongQuizIds = [];
  final List<int> _correctQuizOptionIds = [];
  final List<int> _wrongQuizOptionIds = [];
  final List<int> _correctNounIds = [];
  final List<int> _wrongNounIds = [];

  // NEW — timer state
  static const int _timerDuration = 15;
  int _secondsRemaining = _timerDuration;
  Timer? _questionTimer;

  // NEW — difficulty toggle state
  bool _isExpertMode = false;
  int get _effectiveTimerDuration => _isExpertMode ? (_timerDuration / 2).round() : _timerDuration;

  @override
  void initState() {
    super.initState();

    _questions = widget.lesson.nounQuizzes
        .where((q) => q.quizType == widget.quizType)
        .toList()
      ..shuffle(Random());

    _initDifficultyThenStartTimer(); // CHANGED — was: _startTimer();
  }

  // NEW — loads the saved expert/beginner preference before the first timer starts
  Future<void> _initDifficultyThenStartTimer() async {
    final prefs = await SharedPreferences.getInstance();
    final isExpert = prefs.getBool('quizExpertMode') ?? false;
    if (mounted) {
      setState(() => _isExpertMode = isExpert);
    }
    _startTimer();
  }

  // NEW — called when the student flips the switch mid-quiz
  Future<void> _toggleExpertMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('quizExpertMode', value);
    setState(() => _isExpertMode = value);
    _startTimer(); // restart the current question's timer at the new speed
  }

  @override
  void dispose() {
    _questionTimer?.cancel(); // NEW
    _player.dispose();
    super.dispose();
  }

  // NEW — starts (or restarts) the countdown for the current question
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

  // NEW — called when the timer runs out before the student answers
  void _handleTimeout() {
    if (_answered) return; // safety check in case answer landed right as timer expired
    final question = _questions[_currentIndex];
    final testedNounId = question.correctOption.nounId;

    setState(() {
      _answered = true;
      _selectedOption = null; // no option was chosen
      _wrongQuizIds.add(question.quizId);
      _wrongQuizOptionIds.add(-1); // -1 signals "no answer selected / timed out"
      _wrongNounIds.add(testedNounId);
    });

    SoundFeedback.playWrong();

    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _nextQuestion();
    });
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
    _questionTimer?.cancel(); // NEW — stop the countdown once an answer is picked
    final question = _questions[_currentIndex];
    final testedNounId = question.correctOption.nounId;

    setState(() {
      _answered = true;
      _selectedOption = option;
      if (option.isCorrect) {
        _correctCount++;
        _correctQuizIds.add(question.quizId);
        _correctQuizOptionIds.add(option.optionId);
        _correctNounIds.add(testedNounId);
      } else {
        _wrongQuizIds.add(question.quizId);
        _wrongQuizOptionIds.add(option.optionId);
        _wrongNounIds.add(testedNounId);
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
      _startTimer(); // NEW — restart the countdown for the new question
    } else {
      _finishQuiz();
    }
  }

  Future<void> _finishQuiz() async {
    final score = (_correctCount / _questions.length) * 100;

    await _localDb.saveDetailedNounResult(
      lessonGuid: widget.lesson.lessonGuid,
      lessonId: widget.lesson.lessonId,
      nounQuizType: widget.resultKey,
      apiNounQuizType: widget.quizType,
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

  // NEW — small countdown widget shown at the top of the screen
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
            _buildTimer(), // NEW — countdown display
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
