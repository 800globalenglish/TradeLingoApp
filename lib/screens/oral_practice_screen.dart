import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../models/lesson.dart';
import '../services/local_db.dart';
import '../services/api_service.dart';
import '../services/content_package_service.dart';
import '../services/resource_strings.dart';
import '../widgets/smart_image.dart';

class OralPracticeScreen extends StatefulWidget {
  final Lesson lesson;
  const OralPracticeScreen({super.key, required this.lesson});

  @override
  State<OralPracticeScreen> createState() => _OralPracticeScreenState();
}

class _OralPracticeScreenState extends State<OralPracticeScreen> {
  final AudioPlayer _myRecordingPlayer = AudioPlayer();
  final AudioPlayer _nativePlayer = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();
  final LocalDb _localDb = LocalDb.instance;

  List<Keyword> _items = [];
  bool _loading = true;
  int _currentIndex = 0;
  bool _isRecording = false;
  bool _hasRecording = false;
  String? _recordingPath;

  bool _isComparing = false;
  bool _isPaused = false;

  Completer<void>? _activePlaybackCompleter;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems({bool includeAll = false}) async {
    setState(() => _loading = true);

    List<Keyword> items = widget.lesson.keywords;
    if (!includeAll) {
      final passedKeys = await _localDb.getPassedItemKeys(widget.lesson.lessonGuid);
      items = widget.lesson.keywords.where((k) => !passedKeys.contains(k.title)).toList();
    }

    if (!mounted) return;
    setState(() {
      _items = items;
      _currentIndex = 0;
      _hasRecording = false;
      _recordingPath = null;
      _isComparing = false;
      _isPaused = false;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _isComparing = false;
    _myRecordingPlayer.dispose();
    _nativePlayer.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _playAndWait(AudioPlayer player, Source source) async {
    await player.release();

    final completer = Completer<void>();
    _activePlaybackCompleter = completer;

    late StreamSubscription sub;
    sub = player.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });

    await player.play(source);
    await completer.future;
    await sub.cancel();

    if (identical(_activePlaybackCompleter, completer)) {
      _activePlaybackCompleter = null;
    }
  }

  Future<void> _playMyRecordingAndWait() async {
    if (_recordingPath == null) return;
    await _playAndWait(_myRecordingPlayer, DeviceFileSource(_recordingPath!));
  }

  Future<void> _playNativeAndWait() async {
    final keyword = _items[_currentIndex];
    final localPath = await ContentPackageService.instance.resolveLocalPath(keyword.audioUrl);
    final source = localPath != null ? DeviceFileSource(localPath) : UrlSource(keyword.audioUrl);
    await _playAndWait(_nativePlayer, source);
  }

  Future<void> _playNativeAudio() async {
    final keyword = _items[_currentIndex];
    final localPath = await ContentPackageService.instance.resolveLocalPath(keyword.audioUrl);
    try {
      await _nativePlayer.stop();
      if (localPath != null) {
        await _nativePlayer.play(DeviceFileSource(localPath));
      } else {
        await _nativePlayer.play(UrlSource(keyword.audioUrl));
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ResourceStrings.instance.get('aiadd3954'))),
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/practice_recording.m4a';

    await _recorder.start(const RecordConfig(), path: path);
    setState(() {
      _isRecording = true;
      _hasRecording = false;
      _recordingPath = path;
      _isComparing = false;
      _isPaused = false;
    });
  }

  Future<void> _stopRecording() async {
    await _recorder.stop();
    setState(() {
      _isRecording = false;
      _hasRecording = true;
    });
    _startComparisonLoop();
  }

  void _startComparisonLoop() {
    _isComparing = true;
    _isPaused = false;
    _runComparisonLoop();
  }

  Future<void> _runComparisonLoop() async {
    while (_isComparing && mounted) {
      if (_isPaused) {
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }

      try {
        await _playMyRecordingAndWait();
      } catch (e) {
        // ignore
      }
      if (!_isComparing || _isPaused || !mounted) continue;

      try {
        await _playNativeAndWait();
      } catch (e) {
        // ignore
      }
    }
  }

  Future<void> _togglePause() async {
    if (_isPaused) {
      setState(() => _isPaused = false);
    } else {
      await _myRecordingPlayer.stop();
      await _nativePlayer.stop();
      if (_activePlaybackCompleter != null && !_activePlaybackCompleter!.isCompleted) {
        _activePlaybackCompleter!.complete();
      }
      setState(() => _isPaused = true);
    }
  }

  Future<void> _stopComparisonLoop() async {
    _isComparing = false;
    _isPaused = false;
    await _myRecordingPlayer.stop();
    await _nativePlayer.stop();
    if (_activePlaybackCompleter != null && !_activePlaybackCompleter!.isCompleted) {
      _activePlaybackCompleter!.complete();
    }
  }

  Future<void> _selfGrade(bool passed) async {
    await _stopComparisonLoop();
    final keyword = _items[_currentIndex];
    await _localDb.saveOralPracticeResult(
      widget.lesson.lessonGuid,
      keyword.title,
      passed,
      keywordId: keyword.id,
      lessonId: widget.lesson.lessonId,
    );

    ApiService().syncPendingResults();

    _nextItem();
  }

  void _nextItem() {
    if (_currentIndex < _items.length - 1) {
      setState(() {
        _currentIndex++;
        _hasRecording = false;
        _recordingPath = null;
        _isComparing = false;
        _isPaused = false;
      });
    } else {
      _finishPractice();
    }
  }

  Future<void> _finishPractice() async {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ResourceStrings.instance.get('aiadd3955')),
        content: Text(ResourceStrings.instance.get('aiadd3956')),
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

  @override
  Widget build(BuildContext context) {
    // CHANGED — all AppBars in this screen now show "Lesson N" for consistency
    // with the other quiz screens, instead of a generic "Oral Practice" title.
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text('Lesson ${widget.lesson.lessonNumber}')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (widget.lesson.keywords.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('Lesson ${widget.lesson.lessonNumber}')),
        body: Center(child: Text(ResourceStrings.instance.get('aiadd3958'))),
      );
    }

    if (_items.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('Lesson ${widget.lesson.lessonNumber}')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ResourceStrings.instance.get('aiadd1452'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Icon(Icons.check_circle, size: 64, color: Colors.green),
                const SizedBox(height: 16),
                Text(
                  ResourceStrings.instance.get('aiadd3960'),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text(
                  ResourceStrings.instance.get('aiadd3959'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => _loadItems(includeAll: true),
                  child: Text(ResourceStrings.instance.get('aiadd3961')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final keyword = _items[_currentIndex];

    return Scaffold(
      // CHANGED — was: Text('${aiadd3962} ${_currentIndex + 1} ${aiadd3963} ${_items.length}')
      appBar: AppBar(title: Text('Lesson ${widget.lesson.lessonNumber}')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // NEW — word progress moved here, above the existing heading
              Text(
                '${ResourceStrings.instance.get('aiadd3962')} ${_currentIndex + 1} ${ResourceStrings.instance.get('aiadd3963')} ${_items.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Text(
                ResourceStrings.instance.get('aiadd1452'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              if (keyword.imageUrl.isNotEmpty)
                SizedBox(
                  height: 150,
                  child: SmartImage(url: keyword.imageUrl, height: 150),
                ),
              const SizedBox(height: 16),
              Text(
                keyword.title,
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),

              if (!_hasRecording)
                ElevatedButton.icon(
                  icon: const Icon(Icons.volume_up),
                  label: Text(ResourceStrings.instance.get('aiadd3964')),
                  onPressed: _playNativeAudio,
                ),
              const SizedBox(height: 16),

              if (!_hasRecording)
                ElevatedButton.icon(
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                  label: Text(_isRecording
                      ? ResourceStrings.instance.get('aiadd4006')
                      : ResourceStrings.instance.get('aiadd4007')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRecording ? Colors.red : null,
                  ),
                  onPressed: _isRecording ? _stopRecording : _startRecording,
                ),

              if (_hasRecording) ...[
                Text(
                  ResourceStrings.instance.get('aiadd3965'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                IconButton(
                  iconSize: 48,
                  icon: Icon(_isPaused ? Icons.play_circle : Icons.pause_circle),
                  onPressed: _togglePause,
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  icon: const Icon(Icons.mic),
                  label: Text(ResourceStrings.instance.get('aiadd3966')),
                  onPressed: () async {
                    await _stopComparisonLoop();
                    setState(() {
                      _hasRecording = false;
                      _recordingPath = null;
                    });
                  },
                ),
              ],

              const SizedBox(height: 32),

              if (_hasRecording) ...[
                Text(
                  ResourceStrings.instance.get('aiadd3967'),
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.close),
                        label: Text(ResourceStrings.instance.get('aiadd3969')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade100,
                          foregroundColor: Colors.red.shade900,
                        ),
                        onPressed: () => _selfGrade(false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check),
                        label: Text(ResourceStrings.instance.get('aiadd3968')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade100,
                          foregroundColor: Colors.green.shade900,
                        ),
                        onPressed: () => _selfGrade(true),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
