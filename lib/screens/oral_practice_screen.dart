import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../services/resource_strings.dart';
import '../widgets/smart_image.dart';

// ============================================================================
// CHANGED FROM ORIGINAL — this screen used to take a Lesson and loop through
// lesson.keywords, saving pass/fail to LocalDb and pushing results to the
// server via ApiService.syncPendingResults(). None of that exists anymore:
//
//   - Lesson/Keyword models are gone (lesson-specific, removed)
//   - LocalDb is gone (was entirely quiz/lesson sync tables)
//   - Recordings stay on the phone only — no upload, no server sync call
//
// Instead this screen now takes a plain list of word items — the same shape
// GetResourceTree returns for a category's words: title, imageUrl, audioUrl.
// Pass/fail no longer persists between sessions (no LocalDb to store it in);
// self-grading here just moves to the next word in THIS session. If you want
// "don't show me words I've already passed" to persist across app restarts
// later, that would need a small new local store — much simpler than the
// old LocalDb, just a set of passed titles per category, but intentionally
// left out for now to keep this rebuild focused.
// ============================================================================

class PracticeWordItem {
  final String title;
  final String imageUrl; // filename, e.g. "02_01_01_01_01.jpg"
  final String audioUrl; // filename, e.g. "02_01_01_01_01.mp3" (native pronunciation)

  const PracticeWordItem({
    required this.title,
    required this.imageUrl,
    required this.audioUrl,
  });
}

class OralPracticeScreen extends StatefulWidget {
  final String categoryTitle;
  final List<PracticeWordItem> items;

  const OralPracticeScreen({
    super.key,
    required this.categoryTitle,
    required this.items,
  });

  @override
  State<OralPracticeScreen> createState() => _OralPracticeScreenState();
}

class _OralPracticeScreenState extends State<OralPracticeScreen> {
  final AudioPlayer _myRecordingPlayer = AudioPlayer();
  final AudioPlayer _nativePlayer = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();

  int _currentIndex = 0;
  bool _isRecording = false;
  bool _hasRecording = false;
  String? _recordingPath;

  bool _isComparing = false;
  bool _isPaused = false;

  Completer<void>? _activePlaybackCompleter;

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

  // TODO — once content_package_service.dart is adapted for TradeLingo's
  // flat images/sounds folders, resolve the local cached file here first
  // (same pattern as before: check local cache, fall back to CDN URL).
  // For now this always plays directly from the CDN.
  String _nativeAudioUrl(PracticeWordItem item) {
    return 'https://cdn.800globalenglish.com/content/tradelingo/restaurant/sounds/${item.audioUrl}';
  }

  Future<void> _playNativeAndWait() async {
    final item = widget.items[_currentIndex];
    await _playAndWait(_nativePlayer, UrlSource(_nativeAudioUrl(item)));
  }

  Future<void> _playNativeAudio() async {
    final item = widget.items[_currentIndex];
    try {
      await _nativePlayer.stop();
      await _nativePlayer.play(UrlSource(_nativeAudioUrl(item)));
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

    final item = widget.items[_currentIndex];
    final dir = await getApplicationDocumentsDirectory(); // persistent, not temp
    final safeTitle = item.title.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final path = '${dir.path}/tradelingo_${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.m4a';

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

  // Self-grading no longer saves anywhere — it's just "am I happy with this,
  // move on" for this session. The recording itself stays on disk at
  // _recordingPath regardless of pass/fail (nothing deletes it), so it's
  // still there if you want to build a "my recordings" playback list later.
  Future<void> _selfGrade(bool passed) async {
    await _stopComparisonLoop();
    _nextItem();
  }

  void _nextItem() {
    if (_currentIndex < widget.items.length - 1) {
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
        title: Text(ResourceStrings.instance.get('aiadd4063')),
        content: Text(ResourceStrings.instance.get('aiadd4064')),
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
    if (widget.items.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.categoryTitle)),
        body: Center(child: Text(ResourceStrings.instance.get('aiadd3958'))),
      );
    }

    final item = widget.items[_currentIndex];

    return Scaffold(
      appBar: AppBar(title: Text(widget.categoryTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${ResourceStrings.instance.get('aiadd3962')} ${_currentIndex + 1} ${ResourceStrings.instance.get('aiadd3963')} ${widget.items.length}',
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
              if (item.imageUrl.isNotEmpty)
                SizedBox(
                  height: 150,
                  child: SmartImage(
                    url: 'https://cdn.800globalenglish.com/content/tradelingo/images/${item.imageUrl}',
                    height: 150,
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                item.title,
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
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
