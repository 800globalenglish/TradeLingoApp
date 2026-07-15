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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              ResourceStrings.instance.get('aiadd4082'),
              style: const TextStyle(color: Colors.black87),
            ),
          ],
        ),
      ),
    );

    final uri = Uri.parse(url);

    // NEW — run the actual launch AND a minimum visible delay together, so
    // our overlay shows for at least a moment even though launchUrl itself
    // returns almost instantly (as soon as the browser view opens, not when
    // the PDF finishes loading) - otherwise the dialog pops before anyone
    // can actually perceive it.
    final results = await Future.wait([
      launchUrl(uri, mode: LaunchMode.inAppBrowserView),
      Future.delayed(const Duration(milliseconds: 800)),
    ]);
    final success = results[0] as bool;

    if (!mounted) return;
    Navigator.of(context).pop();

    if (!success) {
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
          ? Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              ResourceStrings.instance.get('aiadd4082'),
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      )
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