import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../services/content_package_service.dart';
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
  final String otherTitle; // translated title, empty if none for the selected language
  final String imageUrl; // filename, e.g. "02_01_01_01_01.jpg"
  final String audioUrl; // filename, e.g. "02_01_01_01_01.mp3" (native pronunciation)

  const PracticeWordItem({
    required this.title,
    this.otherTitle = '',
    required this.imageUrl,
    required this.audioUrl,
  });
}

class OralPracticeScreen extends StatefulWidget {
  final String categoryTitle;
  final List<PracticeWordItem> items;
  final int initialIndex;
  // 1 = Restaurant/Household, 2 = Construction/General — used to build the
  // correct sounds folder path (images are flat/shared, but sounds live in
  // per-industry folders per the web version's CDN layout).
  final int pageId;

  const OralPracticeScreen({
    super.key,
    required this.categoryTitle,
    required this.items,
    this.initialIndex = 0,
    this.pageId = 1,
  });

  @override
  State<OralPracticeScreen> createState() => _OralPracticeScreenState();
}

class _OralPracticeScreenState extends State<OralPracticeScreen> {
  final AudioPlayer _myRecordingPlayer = AudioPlayer();
  final AudioPlayer _nativePlayer = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();

  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.items.isEmpty ? 0 : widget.items.length - 1);
  }

  bool _isRecording = false;
  bool _hasRecording = false;
  String? _recordingPath;

  bool _isComparing = false;
  bool _isPaused = false;

  // Tracks which word indices have been marked Fail at least once this
  // session (and haven't since been marked Pass) — used to offer a
  // "practice failed words" option once the whole list has been graded.
  final Set<int> _failedIndices = {};

  // Tracks every word that's been explicitly graded (Pass OR Fail) at
  // least once this session, regardless of current pass/fail status.
  // "Oral Exam Complete" now means every word has one of these, not just
  // "you scrolled to the last position" — since someone can jump straight
  // to any word via its mic button on the browse screen, position alone
  // doesn't mean everything's been covered.
  final Set<int> _gradedIndices = {};

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
    if (_recordingPath == null) {
      // ignore: avoid_print
      print('DEBUG _playMyRecordingAndWait: _recordingPath is null');
      return;
    }
    final file = File(_recordingPath!);
    final exists = await file.exists();
    final size = exists ? await file.length() : 0;
    // ignore: avoid_print
    print('DEBUG _playMyRecordingAndWait: path=$_recordingPath exists=$exists size=$size bytes');
    if (!exists || size == 0) {
      // ignore: avoid_print
      print('DEBUG _playMyRecordingAndWait: file missing or empty, skipping playback');
      return;
    }
    try {
      await _playAndWait(_myRecordingPlayer, DeviceFileSource(_recordingPath!));
    } catch (e) {
      // ignore: avoid_print
      print('DEBUG _playMyRecordingAndWait: playback threw: $e');
      rethrow;
    }
  }

  // Checks the local downloaded copy first (from images.zip/sounds.zip),
  // falling back to the CDN if it's not there. Sounds on the CDN always
  // live under the "restaurant" folder regardless of industry — this
  // matches the web version's own behavior (it hardcodes this same path
  // even on the Construction page) — but that only applies to the network
  // fallback; the local downloaded copy doesn't split by industry at all.
  String _nativeAudioUrl(PracticeWordItem item) {
    return 'https://cdn.800globalenglish.com/content/tradelingo/restaurant/sounds/${item.audioUrl}';
  }

  Future<Source> _nativeAudioSource(PracticeWordItem item) async {
    final localPath = await ContentPackageService.instance.resolveLocalSoundPath(item.audioUrl);
    if (localPath != null) return DeviceFileSource(localPath);
    return UrlSource(_nativeAudioUrl(item));
  }

  Future<void> _playNativeAndWait() async {
    final item = widget.items[_currentIndex];
    final source = await _nativeAudioSource(item);
    await _playAndWait(_nativePlayer, source);
  }

  Future<void> _playNativeAudio() async {
    final item = widget.items[_currentIndex];
    try {
      await _nativePlayer.stop();
      final source = await _nativeAudioSource(item);
      await _nativePlayer.play(source);
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
    final actualPath = await _recorder.stop();
    // ignore: avoid_print
    print('DEBUG _stopRecording: recorder.stop() returned path=$actualPath, our tracked path=$_recordingPath');
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
        // ignore: avoid_print
        print('DEBUG comparison loop: recording playback failed: $e');
      }
      if (!_isComparing || _isPaused || !mounted) continue;

      try {
        await _playNativeAndWait();
      } catch (e) {
        // ignore: avoid_print
        print('DEBUG comparison loop: native playback failed: $e');
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

  // Pass: marks this word graded, clears any earlier fail mark, then jumps
  // to the next word that hasn't been graded yet (wrapping around the list
  // if needed) — or finishes if that was the last ungraded one. Fail:
  // marks this word graded AND failed, resets the recording so you can
  // try it again right here, and also checks completion (grading the last
  // remaining word can finish the session even if you failed it).
  Future<void> _selfGrade(bool passed) async {
    await _stopComparisonLoop();
    _gradedIndices.add(_currentIndex);

    if (passed) {
      _failedIndices.remove(_currentIndex);
      _advanceAfterGrading();
    } else {
      _failedIndices.add(_currentIndex);
      setState(() {
        _hasRecording = false;
        _recordingPath = null;
      });
      if (_gradedIndices.length == widget.items.length) {
        _finishPractice();
      }
    }
  }

  // Finds the next word that hasn't been graded yet, searching forward
  // from the current position and wrapping around the list — this covers
  // the case where someone jumped in partway through via a word's mic
  // button, so earlier words still need attention even after reaching
  // the sequential "end" of the list.
  void _advanceAfterGrading() {
    if (_gradedIndices.length == widget.items.length) {
      _finishPractice();
      return;
    }

    final total = widget.items.length;
    for (var offset = 1; offset <= total; offset++) {
      final idx = (_currentIndex + offset) % total;
      if (!_gradedIndices.contains(idx)) {
        setState(() {
          _currentIndex = idx;
          _hasRecording = false;
          _recordingPath = null;
          _isComparing = false;
          _isPaused = false;
        });
        return;
      }
    }
    // Shouldn't be reachable given the length check above, but just in case.
    _finishPractice();
  }

  // Plain sequential navigation, used only by the Previous/Next arrows —
  // this never grades anything and never triggers "Exam Complete" on its
  // own. Completion is entirely driven by _selfGrade/_advanceAfterGrading
  // now, since someone can jump to any word directly via its mic button,
  // so just scrolling to the last position doesn't mean everything's done.
  void _nextItem() {
    if (_currentIndex < widget.items.length - 1) {
      setState(() {
        _currentIndex++;
        _hasRecording = false;
        _recordingPath = null;
        _isComparing = false;
        _isPaused = false;
      });
    }
  }

  // NEW — lets someone move forward without recording/grading first, so they
  // can just page through and listen/practice at their own pace instead of
  // being forced back out to the word list after every single word.
  Future<void> _skipToNext() async {
    await _stopComparisonLoop();
    final wasLastItem = _currentIndex >= widget.items.length - 1;
    _nextItem();
    if (!wasLastItem) {
      _playNativeAudio();
    }
  }

  Future<void> _skipToPrevious() async {
    await _stopComparisonLoop();
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _hasRecording = false;
        _recordingPath = null;
        _isComparing = false;
        _isPaused = false;
      });
      _playNativeAudio();
    }
  }

  Future<void> _finishPractice() async {
    if (!mounted) return;

    final failedItems = _failedIndices.toList()..sort();
    final hasFailed = failedItems.isNotEmpty;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ResourceStrings.instance.get('aiadd4063')),
        content: Text(
          hasFailed
              ? '${ResourceStrings.instance.get('aiadd4064')} (${failedItems.length})'
              : ResourceStrings.instance.get('aiadd4064'),
        ),
        actions: [
          if (hasFailed)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // close dialog
                Navigator.of(context).pop(); // close this practice screen
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OralPracticeScreen(
                      categoryTitle: widget.categoryTitle,
                      items: failedItems.map((i) => widget.items[i]).toList(),
                      pageId: widget.pageId,
                    ),
                  ),
                );
              },
              child: const Text('Practice Failed Words'),
            ),
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
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              if (item.imageUrl.isNotEmpty)
                SizedBox(
                  width: 225,
                  height: 225,
                  child: SmartImage(
                    url: 'https://cdn.800globalenglish.com/content/tradelingo/images/${item.imageUrl}',
                    width: 225,
                    height: 225,
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                item.title,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              if (item.otherTitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  item.otherTitle,
                  style: const TextStyle(fontSize: 18, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),

              // Round play button — plays the native pronunciation before a
              // recording exists, or toggles the compare-loop play/pause
              // once a recording has been made.
              Center(
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: const CircleBorder(),
                      backgroundColor: Colors.grey.shade800,
                      padding: EdgeInsets.zero,
                      elevation: 2,
                    ),
                    onPressed: _hasRecording ? _togglePause : _playNativeAudio,
                    child: Icon(
                      _hasRecording && !_isPaused ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              if (!_hasRecording)
                ElevatedButton.icon(
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                  label: Text(_isRecording
                      ? ResourceStrings.instance.get('aiadd4006')
                      : ResourceStrings.instance.get('aiadd4007')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRecording ? Colors.red : null,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                  onPressed: _isRecording ? _stopRecording : _startRecording,
                ),



              if (_hasRecording) ...[
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.close),
                        label: Text(ResourceStrings.instance.get('aiadd3969')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade100,
                          foregroundColor: Colors.red.shade900,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
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
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => _selfGrade(true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  icon: const Icon(Icons.mic, size: 18),
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

              const SizedBox(height: 12),

              // Small previous/next arrows — always available, independent
              // of recording/self-grading, so someone can just move through
              // every word in the list without being forced back out to the
              // browse screen.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, size: 18),
                    tooltip: 'Previous word',
                    onPressed: _currentIndex > 0 ? _skipToPrevious : null,
                  ),
                  const SizedBox(width: 40),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, size: 18),
                    tooltip: 'Next word',
                    onPressed: _skipToNext,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
