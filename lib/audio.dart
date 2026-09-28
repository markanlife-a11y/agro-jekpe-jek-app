// Фоновая музыка баттла: "attack" — короткий трек в самом начале боя, "taraz" — тихий луп
// по ходу всей игры. Настройки (вкл/выкл, громкость) — как в других играх, сохраняются между
// запусками (shared_preferences), применяются мгновенно к уже играющей музыке.
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GameAudio {
  GameAudio._();
  static final GameAudio instance = GameAudio._();

  final AudioPlayer _bgPlayer = AudioPlayer();
  final AudioPlayer _introPlayer = AudioPlayer();

  bool _enabled = true;
  double _volume = 0.5; // 0..1 — общий множитель громкости музыки

  bool get enabled => _enabled;
  double get volume => _volume;

  // Относительные уровни: фоновый луп заметно тише "стингера" старта боя, даже на одной и той
  // же общей громкости — так и просили ("taraz тихо").
  static const double _bgLevel = 0.35;
  static const double _introLevel = 0.85;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool('musicEnabled') ?? true;
    _volume = prefs.getDouble('musicVolume') ?? 0.5;
    await _bgPlayer.setReleaseMode(ReleaseMode.loop);
    await _introPlayer.setReleaseMode(ReleaseMode.release);
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('musicEnabled', value);
    if (!value) {
      await _bgPlayer.pause();
      await _introPlayer.pause();
    } else {
      await _bgPlayer.resume();
    }
  }

  Future<void> setVolume(double value) async {
    _volume = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('musicVolume', value);
    await _bgPlayer.setVolume(value * _bgLevel);
    await _introPlayer.setVolume(value * _introLevel);
  }

  /// Играет в начале раунда/боя: короткий "attack" поверх, и сразу тихий "taraz" луп под ним.
  Future<void> playBattleStart() async {
    if (!_enabled) return;
    try {
      await _introPlayer.setVolume(_volume * _introLevel);
      await _introPlayer.play(AssetSource('audio/attack.mp4'));
    } catch (_) {
      // нет звука — не критично для игры, просто тихо продолжаем
    }
    try {
      await _bgPlayer.setVolume(_volume * _bgLevel);
      await _bgPlayer.play(AssetSource('audio/taraz.mp4'));
    } catch (_) {}
  }

  Future<void> stopAll() async {
    await _bgPlayer.stop();
    await _introPlayer.stop();
  }
}
