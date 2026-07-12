import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lesson.dart';
import '../services/api_service.dart';
import '../services/local_db.dart';
import '../services/resource_strings.dart';
import 'login_screen.dart';
import 'lesson_detail_screen.dart';
import '../services/app_theme.dart';

class LessonListScreen extends StatefulWidget {
  const LessonListScreen({super.key});

  @override
  State<LessonListScreen> createState() => _LessonListScreenState();
}

class _LessonListScreenState extends State<LessonListScreen> {
  final _api = ApiService();
  final _localDb = LocalDb.instance;

  List<Lesson> _lessons = [];
  bool _isLoading = true;
  bool _isOffline = false;
  List<int> _stepOrder = [];

  @override
  void initState() {
    super.initState();
    _loadLessons();
  }

  Future<void> _loadStepOrder(int totalSteps) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('stepOrder');

    if (saved != null) {
      final List<dynamic> decoded = jsonDecode(saved);
      final order = decoded.map((e) => e as int).toList();
      // If the saved order doesn't match the current number of steps
      // (e.g. lesson count changed), fall back to natural order instead.
      if (order.length == totalSteps && order.toSet().length == totalSteps) {
        _stepOrder = order;
        return;
      }
    }

    _stepOrder = List.generate(totalSteps, (i) => i + 1);
  }

  Future<void> _saveStepOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('stepOrder', jsonEncode(_stepOrder));
  }

  Future<void> _loadLessons() async {
    setState(() => _isLoading = true);

    await _api.syncPendingResults();

    final prefs = await SharedPreferences.getInstance();
    final language = prefs.getString('selectedLanguage') ?? 'en-US';

    final serverLessons = await _api.fetchLessonsFromServer();

    List<Lesson> lessons;
    bool offline;

    if (serverLessons != null) {
      await _localDb.saveLessons(serverLessons, language);
      lessons = serverLessons;
      offline = false;
    } else {
      lessons = await _localDb.getAllLessons(language);
      offline = true;
    }

    // MOVED — now runs AFTER lessons are fetched/saved fresh, so its internal
    // lessonId -> lessonGuid lookup is built from current data, not stale cache.
    await _api.pullServerProgress();

    final totalSteps = (lessons.length / 4).ceil();
    await _loadStepOrder(totalSteps);

    if (!mounted) return;

    setState(() {
      _lessons = lessons;
      _isOffline = offline;
      _isLoading = false;
    });
  }


  Future<void> _logout() async {
    await ApiService().logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Map<int, List<Lesson>> _groupIntoSteps(List<Lesson> lessons) {
    final Map<int, List<Lesson>> steps = {};
    for (var lesson in lessons) {
      final stepNumber = ((lesson.lessonNumber - 1) ~/ 4) + 1;
      steps.putIfAbsent(stepNumber, () => []).add(lesson);
    }
    return steps;
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _stepOrder.removeAt(oldIndex);
      _stepOrder.insert(newIndex, item);
    });
    _saveStepOrder();
  }

  @override
  Widget build(BuildContext context) {
    final steps = _groupIntoSteps(_lessons);

    return Scaffold(
      appBar: AppBar(
        title: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: ResourceStrings.instance.get('aiadd2123'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              TextSpan(text: ' (${ResourceStrings.instance.get('aiadd1437')})'),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: ResourceStrings.instance.get('aiadd3949'),
            onPressed: _logout,
          ),
          if (_isOffline)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  ResourceStrings.instance.get('aiadd3950'),
                  style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
      body: Container(
        color: brandDarkBlue,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : (_isOffline && _lessons.isEmpty)
            ? Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  ResourceStrings.instance.get('aiadd3951'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: Colors.grey),
                ),
              ],
            ),
          ),
        )

            : ReorderableListView.builder(
          buildDefaultDragHandles: false,
          itemCount: _stepOrder.length,
          onReorder: _onReorder,
          itemBuilder: (context, index) {
            final stepNumber = _stepOrder[index];
            final lessonsInStep = steps[stepNumber] ?? [];

            return ExpansionTile(
              key: ValueKey(stepNumber),
              backgroundColor: Colors.white,
              collapsedBackgroundColor: brandDarkBlue,
              textColor: Colors.black,
              collapsedTextColor: Colors.white,
              iconColor: Colors.black,
              collapsedIconColor: Colors.white,
              leading: ReorderableDragStartListener(
                index: index,
                child: const Tooltip(
                  message: 'Drag to reorder',
                  child: Icon(Icons.drag_handle),
                ),
              ),
              title: Text(
                '${ResourceStrings.instance.get('aiadd3952')} $stepNumber',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              children: lessonsInStep.map((lesson) {
                return ListTile(
                  leading: CircleAvatar(child: Text('${lesson.lessonNumber}')),
                  title: Text(lesson.title.isNotEmpty
                      ? lesson.title
                      : 'Lesson ${lesson.lessonNumber}'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.red),                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => LessonDetailScreen(lesson: lesson)),
                    );
                  },
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}