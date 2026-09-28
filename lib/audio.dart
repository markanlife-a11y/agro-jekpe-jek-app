// "taraz" — фоновая музыка, играет ВСЕГДА, пока открыто приложение (запускается один раз при
// старте, не привязана к конкретному экрану). "attack" — короткий трек именно в момент, когда
// идёт ответ на вопрос (при показе каждого вопроса, не один раз на весь бой).
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GameAudio {
  GameAudio._();
  static final GameAudio instance = GameAudio._();

  final AudioPlayer _bgPlayer = AudioPlayer();
  final AudioPlayer _cuePlayer = AudioPlayer();

  bool _enabled = true;
  double _volume = 0.5;
  bool _bgStarted = false;

  bool get enabled => _enabled;
  double get volume => _volume;

  static const double _bgLevel = 0.35;
  static const double _cueLevel = 0.85;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool('musicEnabled') ?? true;
    _volume = prefs.getDouble('musicVolume') ?? 0.5;
    await _bgPlayer.setReleaseMode(ReleaseMode.loop);
    await _cuePlayer.setReleaseMode(ReleaseMode.release);
    await _startBackgroundLoop();
  }

  Future<void> _startBackgroundLoop() async {
    if (_bgStarted || !_enabled) return;
    try {
      await _bgPlayer.setVolume(_volume * _bgLevel);
      await _bgPlayer.play(AssetSource('audio/taraz.mp4'));
      _bgStarted = true;
    } catch (_) {
      // нет звука — не критично для игры
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('musicEnabled', value);
    if (!value) {
      await _bgPlayer.pause();
    } else if (_bgStarted) {
      await _bgPlayer.resume();
    } else {
      await _startBackgroundLoop();
    }
  }

  Future<void> setVolume(double value) async {
    _volume = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('musicVolume', value);
    await _bgPlayer.setVolume(value * _bgLevel);
    await _cuePlayer.setVolume(value * _cueLevel);
  }

  /// Короткий трек-стингер — на каждый показ вопроса ("идут ответы на вопросы").
  Future<void> playQuestionCue() async {
    if (!_enabled) return;
    try {
      await _cuePlayer.stop();
      await _cuePlayer.setVolume(_volume * _cueLevel);
      await _cuePlayer.play(AssetSource('audio/attack.mp4'));
    } catch (_) {}
  }
}
