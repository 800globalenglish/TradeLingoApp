import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../models/lesson.dart';
import '../services/content_package_service.dart';
import '../services/resource_strings.dart';
import '../widgets/smart_image.dart';
import 'video_player_screen.dart';
import 'quiz_hub_screen.dart';

class LessonDetailScreen extends StatefulWidget {
  final Lesson lesson;
  const LessonDetailScreen({super.key, required this.lesson});

  @override
  State<LessonDetailScreen> createState() => _LessonDetailScreenState();
}

class _LessonDetailScreenState extends State<LessonDetailScreen>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _player.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // Checks for a local downloaded copy first, falls back to streaming
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ResourceStrings.instance.get('aiadd3947'))),
      );
    }
  }

  String? _keywordNoteKeyFor(int lessonNumber) {
    switch (lessonNumber) {
      case 1:
        return 'aiadd1068';
      default:
        return null;
    }
  }

  String? _sentenceNoteKeyFor(int lessonNumber) {
    switch (lessonNumber) {
      case 1:
        return 'aiadd1655';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lesson;

    return Scaffold(
      appBar: AppBar(
        title: Text('Lesson ${lesson.lessonNumber}'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: ResourceStrings.instance.get('aiadd3917')),
            Tab(text: ResourceStrings.instance.get('aiadd3918')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: lesson.keywords.length,
                  itemBuilder: (context, index) {
                    final keyword = lesson.keywords[index];
                    return ListTile(
                      leading: SizedBox(
                        width: 50,
                        height: 50,
                        child: SmartImage(url: keyword.imageUrl, width: 50, height: 50),
                      ),
                      title: Text(keyword.title),
                      subtitle: keyword.translation != null ? Text(keyword.translation!) : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.volume_up),
                        onPressed: () => _playAudio(keyword.audioUrl),
                      ),
                    );
                  },
                ),
              ),
              if (_keywordNoteKeyFor(lesson.lessonNumber) != null)
                Container(
                  width: double.infinity,
                  color: Colors.amber.shade50,
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    ResourceStrings.instance.get(_keywordNoteKeyFor(lesson.lessonNumber)!),
                    style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ),
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: lesson.sentences.length,
                  itemBuilder: (context, index) {
                    final sentence = lesson.sentences[index];
                    return ListTile(
                      title: Text(sentence.title),
                      subtitle: sentence.translation != null ? Text(sentence.translation!) : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.volume_up),
                        onPressed: () => _playAudio(sentence.audioUrl),
                      ),
                    );
                  },
                ),
              ),
              if (_sentenceNoteKeyFor(lesson.lessonNumber) != null)
                Container(
                  width: double.infinity,
                  color: Colors.amber.shade50,
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    ResourceStrings.instance.get(_sentenceNoteKeyFor(lesson.lessonNumber)!),
                    style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: widget.lesson.nounQuizzes.isNotEmpty
          ? Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: Colors.grey.shade300)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.quiz),
                  label: Text(ResourceStrings.instance.get('aiadd3940')),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => QuizHubScreen(lesson: widget.lesson)),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.play_circle),
                  label: Text(ResourceStrings.instance.get('aiadd3948')),
                  onPressed: () async {
                    final dir = await getApplicationSupportDirectory();
                    final localPath = '${dir.path}/lesson${widget.lesson.lessonNumber}.mp4';
                    final localFile = File(localPath);
                    final isDownloaded = await localFile.exists();

                    if (!context.mounted) return;

                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => VideoPlayerScreen(
                          videoSource: isDownloaded ? localPath : widget.lesson.videoUrl,
                          isLocalFile: isDownloaded,
                          title: widget.lesson.title,
                          captions: widget.lesson.captions,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      )
          : null,
    );
  }
}
