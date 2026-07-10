import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lesson.dart';
import '../services/api_service.dart';
import '../services/local_db.dart';
import '../services/resource_strings.dart';

class PdfListScreen extends StatefulWidget {
  const PdfListScreen({super.key});

  @override
  State<PdfListScreen> createState() => _PdfListScreenState();
}

class _PdfListScreenState extends State<PdfListScreen> {
  final _api = ApiService();
  final _localDb = LocalDb.instance;

  List<Lesson> _lessons = [];
  bool _isLoading = true;
  bool _showHint = false;

  @override
  void initState() {
    super.initState();
    _loadLessons();
    _checkFirstVisit();
  }

  Future<void> _checkFirstVisit() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenHint = prefs.getBool('hasSeenPdfHint') ?? false;

    if (!hasSeenHint) {
      setState(() => _showHint = true);
      await prefs.setBool('hasSeenPdfHint', true);
    }
  }

  Future<void> _loadLessons() async {
    final prefs = await SharedPreferences.getInstance();
    final language = prefs.getString('selectedLanguage') ?? 'en-US';

    final serverLessons = await _api.fetchLessonsFromServer();
    if (serverLessons != null) {
      setState(() {
        _lessons = serverLessons;
        _isLoading = false;
      });
    } else {
      final cachedLessons = await _localDb.getAllLessons(language);
      setState(() {
        _lessons = cachedLessons;
        _isLoading = false;
      });
    }
  }

  Future<void> _openPdf(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ResourceStrings.instance.get('aiadd3970'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(ResourceStrings.instance.get('aiadd3971'))),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          if (_showHint)
            Container(
              width: double.infinity,
              color: Colors.blue.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  Text(
                    ResourceStrings.instance.get('aiadd3972'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.blueGrey, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () {
                      setState(() => _showHint = false);
                    },
                    child: Text(ResourceStrings.instance.get('aiadd3973')),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _lessons.length,
              itemBuilder: (context, index) {
                final lesson = _lessons[index];
                return ListTile(
                  leading: CircleAvatar(child: Text('${lesson.lessonNumber}')),
                  title: Text(lesson.title.isNotEmpty
                      ? lesson.title
                      : 'Lesson ${lesson.lessonNumber}'),
                  trailing: const Icon(Icons.picture_as_pdf, color: Colors.red),
                  onTap: () => _openPdf(lesson.pdfUrl),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}