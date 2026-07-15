import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io';
import '../models/lesson.dart';
import '../services/api_service.dart';
import '../services/local_db.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'splash_screen.dart';
import '../services/content_package_service.dart';
import '../services/resource_strings.dart';

class DownloadManagerScreen extends StatefulWidget {
  final bool isOnboarding;

  const DownloadManagerScreen({super.key, this.isOnboarding = false});

  @override
  State<DownloadManagerScreen> createState() => _DownloadManagerScreenState();
}

class _DownloadManagerScreenState extends State<DownloadManagerScreen> {
  final _api = ApiService();
  final _localDb = LocalDb.instance;

  List<Lesson> _lessons = [];
  Set<String> _selectedGuids = {};
  bool _isLoading = true;
  bool _isDownloading = false;
  bool _isRefreshingList = false;
  bool _showHeaderMessage = false;
  String _statusMessage = '';
  int _downloadedSoFar = 0;
  double _currentFileProgress = 0.0;
  bool _isPaidMember = true;
  String? _username;

  @override
  void initState() {
    super.initState();
    _loadLessons();
    _checkFirstVisit();
  }

  Future<void> _checkFirstVisit() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenHint = prefs.getBool('hasSeenDownloadHint') ?? false;

    if (!hasSeenHint) {
      if (mounted) setState(() => _showHeaderMessage = true);
    }
  }

  Future<void> _dismissHeaderMessage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenDownloadHint', true);
    if (mounted) setState(() => _showHeaderMessage = false);
  }

  Future<void> _loadLessons() async {
    final prefs = await SharedPreferences.getInstance();
    final language = prefs.getString('selectedLanguage') ?? 'en-US';

    // FIXED — checkIsPaidNow() now returns bool?; null means "couldn't
    // verify" (e.g. offline, or a URL/token mismatch), not "confirmed free".
    // Previously this fell straight into `_isPaidMember = isPaid` even when
    // isPaid was really just a failed-check default of false — so a genuine
    // paid member would see "Welcome Free Member!" any time the check
    // couldn't complete. Now we fall back to the last known confirmed tier
    // instead of assuming free.
    final isPaidResult = await ContentPackageService.instance.checkIsPaidNow();
    final downloadedTier = prefs.getString('contentPackageTier');
    final isPaid = isPaidResult ?? (downloadedTier == 'full');

    final serverLessons = await _api.fetchLessonsFromServer();

    if (serverLessons != null) {
      await _localDb.saveLessons(serverLessons, language);
    }

    final lessons = await _localDb.getAllLessons(language);

    if (!mounted) return;
    setState(() {
      _lessons = lessons;
      _isPaidMember = isPaid;
      _isLoading = false;
    });
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenVideoOnboarding', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SplashScreen()),
    );
  }

  Future<bool> _isOnWifi() async {
    final result = await Connectivity().checkConnectivity();
    return result.contains(ConnectivityResult.wifi);
  }

  Future<String> _localVideoPath(int lessonNumber) async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/lesson$lessonNumber.mp4';
  }

  Future<void> _downloadSelected() async {
    final onWifi = await _isOnWifi();

    if (!onWifi) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(ResourceStrings.instance.get('aiadd3913')),
          content: Text(
              '${ResourceStrings.instance.get('aiadd3914')} ${ResourceStrings.instance.get('aiadd3915')} ${ResourceStrings.instance.get('aiadd3916')}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(ResourceStrings.instance.get('aiadd3911'))),
            TextButton(onPressed: () => Navigator.pop(context, true), child: Text(ResourceStrings.instance.get('aiadd3912'))),
          ],
        ),
      );
      if (proceed != true) return;
    }

    final toDownload = _lessons.where((l) => _selectedGuids.contains(l.lessonGuid)).toList();
    if (toDownload.isEmpty) return;

    setState(() {
      _isDownloading = true;
      _downloadedSoFar = 0;
      _currentFileProgress = 0.0;
    });

    int actualSuccesses = 0;
    List<String> failures = [];

    for (final lesson in toDownload) {
      setState(() {
        _statusMessage = '${ResourceStrings.instance.get('aiadd3992')} ${lesson.lessonNumber} (${_downloadedSoFar + 1} ${ResourceStrings.instance.get('aiadd3963')} ${toDownload.length})...';
        _currentFileProgress = 0.0;
      });

      try {
        final request = http.Request('GET', Uri.parse(lesson.videoUrl));
        final streamedResponse = await http.Client().send(request);

        if (streamedResponse.statusCode == 200) {
          final contentLength = streamedResponse.contentLength ?? 0;
          final path = await _localVideoPath(lesson.lessonNumber);
          final file = File(path);
          final sink = file.openWrite();
          int received = 0;

          await for (final chunk in streamedResponse.stream) {
            sink.add(chunk);
            received += chunk.length;
            if (contentLength > 0 && mounted) {
              setState(() => _currentFileProgress = received / contentLength);
            }
          }

          await sink.close();
          await _localDb.markVideoDownloaded(lesson.lessonGuid, true);
          actualSuccesses++;
        } else {
          failures.add('Lesson ${lesson.lessonNumber}: HTTP ${streamedResponse.statusCode}');
        }
      } catch (e) {
        failures.add('Lesson ${lesson.lessonNumber}: $e');
      }

      setState(() {
        _downloadedSoFar++;
        _currentFileProgress = 0.0;
      });
    }

    if (failures.isNotEmpty) {
      debugPrint('Download failures: ${failures.join(', ')}');
    }

    setState(() {
      _isDownloading = false;
      _isRefreshingList = true;
      _statusMessage = '${ResourceStrings.instance.get('aiadd3993')} $actualSuccesses ${ResourceStrings.instance.get('aiadd3963')} ${toDownload.length} ${ResourceStrings.instance.get('aiadd3994')}';
      _selectedGuids.clear();
    });

    await _loadLessons(); // refresh checkmarks

    if (!mounted) return;
    setState(() => _isRefreshingList = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${ResourceStrings.instance.get('aiadd4061')}${_username != null ? " ($_username)" : ""}'),
        actions: widget.isOnboarding
            ? [
          TextButton(
            onPressed: () async {
              final proceed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(ResourceStrings.instance.get('aiadd3935')),
                  content: Text(
                      '${ResourceStrings.instance.get('aiadd3936')} ${ResourceStrings.instance.get('aiadd3937')}'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: Text(ResourceStrings.instance.get('aiadd3938'))),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: Text(ResourceStrings.instance.get('aiadd3939'))),
                  ],
                ),
              );
              if (proceed == true) await _finishOnboarding();
            },
            child: Text(ResourceStrings.instance.get('aiadd3941'), style: const TextStyle(color: Colors.white)),
          ),
        ]
            : null,
      ),
      body: _isLoading
          ? Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              ResourceStrings.instance.get('aiadd4081'),
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      )
          : Column(
        children: [
          if (_showHeaderMessage)
            Container(
              width: double.infinity,
              color: Colors.grey.shade100,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: ResourceStrings.instance.get('aiadd3903'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        TextSpan(text: '\n(${ResourceStrings.instance.get('aiadd3904')})', style: const TextStyle(fontSize: 14)),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _dismissHeaderMessage,
                    child: Text(ResourceStrings.instance.get('aiadd3973')),
                  ),
                ],
              ),
            ),
          if (!_isPaidMember)
            Container(
              width: double.infinity,
              color: Colors.blue.shade50,
              padding: const EdgeInsets.all(12),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: ResourceStrings.instance.get('aiadd3905'),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 13),
                    ),
                    TextSpan(text: '\n${ResourceStrings.instance.get('aiadd3906')}\n', style: const TextStyle(color: Colors.blueGrey, fontSize: 13)),
                    TextSpan(
                      text: ResourceStrings.instance.get('aiadd3907'),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 13),
                    ),
                    TextSpan(text: '\n${ResourceStrings.instance.get('aiadd3908')}', style: const TextStyle(color: Colors.blueGrey, fontSize: 13)),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          if (_isDownloading)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(_statusMessage),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (_downloadedSoFar + _currentFileProgress) / _selectedGuids.length.clamp(1, double.infinity),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(_currentFileProgress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            )
          else if (_statusMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(
                    _statusMessage,
                    style: const TextStyle(color: Colors.green),
                    textAlign: TextAlign.center,
                  ),
                  if (_isRefreshingList) ...[
                    const SizedBox(height: 8),
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _lessons.length,
              itemBuilder: (context, index) {
                final lesson = _lessons[index];
                final isDownloaded = lesson.isVideoDownloaded;
                final isSelected = _selectedGuids.contains(lesson.lessonGuid);

                return CheckboxListTile(
                  value: isDownloaded ? true : isSelected,
                  onChanged: isDownloaded
                      ? null
                      : (checked) {
                    setState(() {
                      if (checked == true) {
                        _selectedGuids.add(lesson.lessonGuid);
                      } else {
                        _selectedGuids.remove(lesson.lessonGuid);
                      }
                    });
                  },
                  secondary: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(child: Text('${lesson.lessonNumber}')), // NEW — matches PDF page's numbered circle
                      const SizedBox(width: 8),
                      isDownloaded
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : const Icon(Icons.cloud_download_outlined, color: Colors.grey),
                    ],
                  ),
                  title: Text(lesson.title.isNotEmpty ? lesson.title : 'Lesson ${lesson.lessonNumber}'),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: widget.isOnboarding && !_isDownloading && _lessons.any((l) => l.isVideoDownloaded)
          ? FloatingActionButton.extended(
        icon: const Icon(Icons.arrow_forward),
        label: Text(ResourceStrings.instance.get('aiadd3942')),
        onPressed: _finishOnboarding,
      )
          : (!_isDownloading && _selectedGuids.isNotEmpty)
          ? FloatingActionButton.extended(
        icon: const Icon(Icons.download),
        label: Text('${ResourceStrings.instance.get('aiadd3943')} ${_selectedGuids.length}'),
        onPressed: _downloadSelected,
      )
          : null,
    );
  }
}
