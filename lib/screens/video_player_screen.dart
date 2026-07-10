import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../models/lesson.dart';
import '../services/resource_strings.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoSource; // either a local file path or a network URL
  final bool isLocalFile;
  final String title;
  final List<VideoCaption> captions;

  const VideoPlayerScreen({
    super.key,
    required this.videoSource,
    required this.isLocalFile,
    required this.title,
    this.captions = const [],
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _videoController;
  ChewieController? _chewieController;
  bool _hasError = false;
  String _currentCaption = '';

  @override
  void initState() {
    super.initState();

    _videoController = widget.isLocalFile
        ? VideoPlayerController.file(File(widget.videoSource))
        : VideoPlayerController.networkUrl(Uri.parse(widget.videoSource));

    _videoController.addListener(_updateCaption);
    _initializeVideo();
  }

  void _updateCaption() {
    if (widget.captions.isEmpty) return;

    final positionSeconds = _videoController.value.position.inMilliseconds / 1000.0;

    String matched = '';
    for (final caption in widget.captions) {
      if (positionSeconds >= caption.startTime) {
        matched = caption.text;
      } else {
        break;
      }
    }

    if (matched != _currentCaption) {
      setState(() => _currentCaption = matched);
    }
  }

  Future<void> _initializeVideo() async {
    try {
      await _videoController.initialize();
      setState(() {
        _chewieController = ChewieController(
          videoPlayerController: _videoController,
          autoPlay: true,
          looping: false,
          aspectRatio: _videoController.value.aspectRatio,
          allowFullScreen: true,
          allowMuting: true,
          materialProgressColors: ChewieProgressColors(
            playedColor: Colors.blue,
            handleColor: Colors.blueAccent,
            backgroundColor: Colors.grey,
            bufferedColor: Colors.blueGrey,
          ),
        );
      });
    } catch (e) {
      setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
    _videoController.removeListener(_updateCaption);
    _chewieController?.dispose();
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: _hasError
            ? Text(
          '${ResourceStrings.instance.get('aiadd3987')} ${ResourceStrings.instance.get('aiadd3988')}',
        )
            : _chewieController != null
            ? Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Chewie(controller: _chewieController!),
            if (_currentCaption.isNotEmpty)
              Positioned(
                bottom: 60,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _currentCaption,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
          ],
        )
            : const CircularProgressIndicator(),
      ),
    );
  }
}