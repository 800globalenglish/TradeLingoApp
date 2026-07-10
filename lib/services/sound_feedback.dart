import 'package:audioplayers/audioplayers.dart';

// Correct/wrong feedback using bundled sound assets.
class SoundFeedback {
  static final AudioPlayer _player = AudioPlayer();
  static Future<void> playCorrect() async {
    try {
      await _player.play(AssetSource('sounds/correct.mp3'));
    } catch (e) {
      // ignore
    }
  }

  static Future<void> playWrong() async {
    try {
      await _player.play(AssetSource('sounds/wrong.mp3'));
    } catch (e) {
      // ignore
    }
  }
}