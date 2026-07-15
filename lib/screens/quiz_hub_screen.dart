import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // NEW — for saving expert/beginner preference
import '../models/lesson.dart';
import '../services/local_db.dart';
import '../services/app_theme.dart';
import '../services/resource_strings.dart';
import 'quiz_screen.dart';
import 'spelling_quiz_screen.dart';
import 'grammar_quiz_screen.dart';
import 'oral_practice_screen.dart';

class QuizHubScreen extends StatefulWidget {
  final Lesson lesson;
  const QuizHubScreen({super.key, required this.lesson});

  @override
  State<QuizHubScreen> createState() => _QuizHubScreenState();
}

class _QuizHubScreenState extends State<QuizHubScreen> {
  final LocalDb _localDb = LocalDb.instance;

  Map<String, double?> _scores = {};
  bool _loading = true;

  // NEW — expert/beginner timer speed toggle, shared with quiz_screen.dart
  bool _isExpertMode = false;

  @override
  void initState() {
    super.initState();
    _loadScores();
    _loadExpertMode(); // NEW
  }

  // NEW — loads the saved expert/beginner preference
  Future<void> _loadExpertMode() async {
    final prefs = await SharedPreferences.getInstance();
    final isExpert = prefs.getBool('quizExpertMode') ?? false;
    if (!mounted) return;
    setState(() => _isExpertMode = isExpert);
  }

  // NEW — saves the preference whenever the switch is flipped here
  Future<void> _toggleExpertMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('quizExpertMode', value);
    setState(() => _isExpertMode = value);
  }

  Future<void> _loadScores() async {
    final lessonGuid = widget.lesson.lessonGuid;

    final nounQuizTextImage = await _localDb.getScoreFor(lessonGuid, 'nounQuizTextImage');
    final nounQuizTextAudio = await _localDb.getScoreFor(lessonGuid, 'nounQuizTextAudio');
    final nounQuizImageAudio = await _localDb.getScoreFor(lessonGuid, 'nounQuizImageAudio');
    final spellingQuiz = await _localDb.getScoreFor(lessonGuid, 'spellingQuiz');
    final grammarQuiz = await _localDb.getScoreFor(lessonGuid, 'grammarQuiz');
    final grammarSpellingQuiz = await _localDb.getScoreFor(lessonGuid, 'grammarSpellingQuiz');
    final advanceQuiz = await _localDb.getScoreFor(lessonGuid, 'advanceQuiz');

    final itemKeys = widget.lesson.keywords.map((k) => k.title).toList();
    final oralPractice = await _localDb.getOralPracticeScore(lessonGuid, itemKeys);

    if (!mounted) return;
    setState(() {
      _scores = {
        'nounQuizTextImage': nounQuizTextImage,
        'nounQuizTextAudio': nounQuizTextAudio,
        'nounQuizImageAudio': nounQuizImageAudio,
        'spellingQuiz': spellingQuiz,
        'grammarQuiz': grammarQuiz,
        'grammarSpellingQuiz': grammarSpellingQuiz,
        'advanceQuiz': advanceQuiz,
        'oralPractice': oralPractice,
      };
      _loading = false;
    });
  }

  Widget _buildRow({
    required IconData icon,
    required String label,
    required String scoreKey,
    required Future<void> Function() onTap,
  }) {
    final score = _scores[scoreKey];
    final subtitle = score == null ? ResourceStrings.instance.get('aiadd4008') : '${score.toStringAsFixed(0)}%';
    final isDone = score != null && score >= 100;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: brandDarkBlue.withValues(alpha: 0.1),
        foregroundColor: brandDarkBlue,
        child: Icon(icon, size: 20),
      ),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            subtitle,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: isDone ? Colors.green.shade700 : Colors.grey.shade600,
            ),
          ),
          if (isDone) const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Icon(Icons.check_circle, color: Colors.green, size: 18),
          ),
        ],
      ),
      onTap: () async {
        await onTap();
        _loadScores();
      },
    );
  }

  Widget _sectionPanel(String title, List<Widget> rows) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          backgroundColor: Colors.white,
          collapsedBackgroundColor: brandDarkBlue,
          iconColor: brandDarkBlue,
          collapsedIconColor: Colors.white,
          textColor: brandDarkBlue,
          collapsedTextColor: Colors.white,
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          children: [
            const Divider(height: 1, color: Colors.black12),
            ...rows,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Lesson ${widget.lesson.lessonNumber}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // NEW — expert/beginner timer speed toggle, applies to all quizzes below
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🐢', style: TextStyle(fontSize: 24)),
                Switch(
                  value: _isExpertMode,
                  onChanged: _toggleExpertMode,
                ),
                const Text('🐇', style: TextStyle(fontSize: 24)),
              ],
            ),
          ),
          if (widget.lesson.lessonNumber == 27)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              color: Colors.amber.shade50,
              padding: const EdgeInsets.all(12),
              child: Text(
                ResourceStrings.instance.get('nonounsinlesson'),
                style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
              ),
            ),
          _sectionPanel(ResourceStrings.instance.get('aiadd3975'), [
            _buildRow(
              icon: Icons.image,
              label: ResourceStrings.instance.get('aiadd3976'),
              scoreKey: 'nounQuizTextImage',
              onTap: () async => await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => QuizScreen(
                    lesson: widget.lesson,
                    quizType: 'text/image',
                    screenTitle: ResourceStrings.instance.get('aiadd3976'),
                    resultKey: 'nounQuizTextImage',
                  ),
                ),
              ),
            ),
            _buildRow(
              icon: Icons.volume_up,
              label: ResourceStrings.instance.get('aiadd3977'),
              scoreKey: 'nounQuizTextAudio',
              onTap: () async => await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => QuizScreen(
                    lesson: widget.lesson,
                    quizType: 'text/audio',
                    screenTitle: ResourceStrings.instance.get('aiadd3977'),
                    resultKey: 'nounQuizTextAudio',
                  ),
                ),
              ),
            ),
            _buildRow(
              icon: Icons.headphones,
              label: ResourceStrings.instance.get('aiadd3978'),
              scoreKey: 'nounQuizImageAudio',
              onTap: () async => await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => QuizScreen(
                    lesson: widget.lesson,
                    quizType: 'image/audio',
                    screenTitle: ResourceStrings.instance.get('aiadd3978'),
                    resultKey: 'nounQuizImageAudio',
                  ),
                ),
              ),
            ),
            _buildRow(
              icon: Icons.spellcheck,
              label: ResourceStrings.instance.get('aiadd1462'),
              scoreKey: 'spellingQuiz',
              onTap: () async => await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => SpellingQuizScreen(lesson: widget.lesson)),
              ),
            ),
          ]),
          _sectionPanel(ResourceStrings.instance.get('aiadd4009'), [
            _buildRow(
              icon: Icons.menu_book,
              label: ResourceStrings.instance.get('aiadd4010'),
              scoreKey: 'grammarQuiz',
              onTap: () async => await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GrammarQuizScreen(
                    lesson: widget.lesson,
                    quizType: 'grammar',
                    screenTitle: ResourceStrings.instance.get('aiadd4010'),
                    resultKey: 'grammarQuiz',
                  ),
                ),
              ),
            ),
            _buildRow(
              icon: Icons.spellcheck,
              label: ResourceStrings.instance.get('aiadd3983'),
              scoreKey: 'grammarSpellingQuiz',
              onTap: () async => await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GrammarQuizScreen(
                    lesson: widget.lesson,
                    quizType: 'spelling',
                    screenTitle: ResourceStrings.instance.get('aiadd3983'),
                    resultKey: 'grammarSpellingQuiz',
                  ),
                ),
              ),
            ),
            _buildRow(
              icon: Icons.trending_up,
              label: ResourceStrings.instance.get('aiadd4011'),
              scoreKey: 'advanceQuiz',
              onTap: () async => await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GrammarQuizScreen(
                    lesson: widget.lesson,
                    quizType: 'advance',
                    screenTitle: ResourceStrings.instance.get('aiadd4011'),
                    resultKey: 'advanceQuiz',
                  ),
                ),
              ),
            ),
          ]),
          _sectionPanel(ResourceStrings.instance.get('aiadd1452'), [
            _buildRow(
              icon: Icons.mic,
              label: ResourceStrings.instance.get('aiadd1452'),
              scoreKey: 'oralPractice',
              onTap: () async => await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => OralPracticeScreen(lesson: widget.lesson)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
