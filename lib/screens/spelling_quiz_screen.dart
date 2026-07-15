import 'dart:async'; // NEW
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart'; // NEW — for reading expert/beginner preference
import '../models/lesson.dart';
import '../services/local_db.dart';
import '../services/api_service.dart';
import '../services/content_package_service.dart';
import '../services/resource_strings.dart';
import '../widgets/smart_image.dart';
import 'package:flutter/services.dart';
import '../services/sound_feedback.dart';

class SpellingQuizScreen extends StatefulWidget {
  final Lesson lesson;
  const SpellingQuizScreen({super.key, required this.lesson});

  @override
  State<SpellingQuizScreen> createState() => _SpellingQuizScreenState();
}

class _SpellingQuizScreenState extends State<SpellingQuizScreen> {
  final AudioPlayer _player = AudioPlayer();
  final LocalDb _localDb = LocalDb.instance;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  late NounQuizQuestion _spellingQuiz;
  late List<NounQuizOption> _words;
  int _currentIndex = 0;
  int _correctCount = 0;
  bool _answered = false;
  bool _wasCorrect = false;
  int _lastAutoPlayedIndex = -1;

  final List<int> _correctQuizIds = [];
  final List<int> _wrongQuizIds = [];
  final List<int> _correctQuizOptionIds = [];
  final List<int> _wrongQuizOptionIds = [];
  final List<int> _correctNounIds = [];
  final List<int> _wrongNounIds = [];

  // NEW — timer state
  static const int _timerDuration = 20;
  int _secondsRemaining = _timerDuration;
  Timer? _questionTimer;

  // NEW — difficulty toggle state (set from the Quiz Hub screen, read here)
  bool _isExpertMode = false;
  int get _effectiveTimerDuration => _isExpertMode ? (_timerDuration / 2).round() : _timerDuration;

  @override
  void initState() {
    super.initState();

    _spellingQuiz = widget.lesson.nounQuizzes.firstWhere(
          (q) => q.quizType == 'spelling/typing',
      orElse: () => NounQuizQuestion(quizId: 0, quizType: 'spelling/typing', options: []),
    );

    _words = List.of(_spellingQuiz.options)..shuffle(Random());

    if (_words.isNotEmpty) _initDifficultyThenStartTimer(); // CHANGED — was: _startTimer();
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
    _player.dispose();
    _textController.dispose();
    _focusNode.dispose();
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

  // NEW — timeout is treated the same as a wrong/blank answer
  void _handleTimeout() {
    if (_answered) return;
    final currentWord = _words[_currentIndex];

    setState(() {
      _answered = true;
      _wasCorrect = false;
      _wrongQuizIds.add(_spellingQuiz.quizId);
      _wrongQuizOptionIds.add(currentWord.optionId);
      _wrongNounIds.add(currentWord.nounId);
    });

    SoundFeedback.playWrong();

    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) _nextWord();
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

  void _checkAnswer() {
    if (_answered) return;
    _questionTimer?.cancel(); // NEW

    final currentWord = _words[_currentIndex];
    final typed = _textController.text.trim().toLowerCase();
    final correct = currentWord.word.trim().toLowerCase();
    final isCorrect = typed == correct;

    setState(() {
      _answered = true;
      _wasCorrect = isCorrect;
      if (isCorrect) {
        _correctCount++;
        _correctQuizIds.add(_spellingQuiz.quizId);
        _correctQuizOptionIds.add(currentWord.optionId);
        _correctNounIds.add(currentWord.nounId);
      } else {
        _wrongQuizIds.add(_spellingQuiz.quizId);
        _wrongQuizOptionIds.add(currentWord.optionId);
        _wrongNounIds.add(currentWord.nounId);
      }
    });

    isCorrect ? SoundFeedback.playCorrect() : SoundFeedback.playWrong();

    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) _nextWord();
    });
  }

  void _nextWord() {
    if (_currentIndex < _words.length - 1) {
      setState(() {
        _currentIndex++;
        _answered = false;
        _textController.clear();
      });
      _focusNode.requestFocus();
      _startTimer(); // NEW
    } else {
      _finishQuiz();
    }
  }

  Future<void> _finishQuiz() async {
    final score = (_correctCount / _words.length) * 100;

    await _localDb.saveDetailedNounResult(
      lessonGuid: widget.lesson.lessonGuid,
      lessonId: widget.lesson.lessonId,
      nounQuizType: 'spellingQuiz',
      apiNounQuizType: 'spelling/typing',
      totalQuiz: _words.length,
      totalCorrect: _correctCount,
      totalWrong: _words.length - _correctCount,
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
        title: Text(ResourceStrings.instance.get('aiadd3982')),
        content: Text(
            '${ResourceStrings.instance.get('aiadd3922')} ${score.toStringAsFixed(0)}%\n($_correctCount ${ResourceStrings.instance.get('aiadd3923')} ${_words.length} ${ResourceStrings.instance.get('aiadd3924')})'),
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

  // NEW — same timer widget
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
    if (_words.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(ResourceStrings.instance.get('aiadd1462'))),
        body: Center(child: Text(ResourceStrings.instance.get('aiadd3984'))),
      );
    }

    final word = _words[_currentIndex];

    if (_lastAutoPlayedIndex != _currentIndex) {
      _lastAutoPlayedIndex = _currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _playAudio(word.audioUrl);
        _focusNode.requestFocus();
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text('Lesson ${widget.lesson.lessonNumber}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              '${ResourceStrings.instance.get('aiadd3962')} ${_currentIndex + 1} ${ResourceStrings.instance.get('aiadd3963')} ${_words.length}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            _buildTimer(), // NEW
            const SizedBox(height: 8),
            SizedBox(
              height: 150,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SmartImage(url: word.imageUrl, height: 150),
              ),
            ),
            const SizedBox(height: 12),
            IconButton(
              icon: const Icon(Icons.volume_up, size: 36),
              onPressed: () => _playAudio(word.audioUrl),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _textController,
              focusNode: _focusNode,
              enabled: !_answered,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: _currentIndex == 0
                    ? ResourceStrings.instance.get('aiadd3927')
                    : ResourceStrings.instance.get('aiadd3928'),
                filled: _answered,
                fillColor: _answered
                    ? (_wasCorrect ? Colors.green.shade100 : Colors.red.shade100)
                    : null,
              ),
              onSubmitted: (_) => _checkAnswer(),
            ),
            if (_answered && !_wasCorrect)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '${ResourceStrings.instance.get('aiadd3985')}: ${word.word}',
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
            const SizedBox(height: 24),
            if (!_answered)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _checkAnswer,
                  child: Text(ResourceStrings.instance.get('aiadd3986')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
