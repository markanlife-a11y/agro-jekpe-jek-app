// По просьбе пользователя — ОДНА музыка ("attack"), играет непрерывно фоном всё время, пока
// открыто приложение (с момента запуска), независимо от экрана. Раньше были два трека (тихий
// фон + отдельный стингер на каждый вопрос) — по факту только усложняло и не давало
// предсказуемого результата, поэтому упростили до одного.
//
// GameAudio слушает жизненный цикл приложения (WidgetsBindingObserver) и принудительно
// возобновляет воспроизведение при возврате на передний план — на части прошивок Android
// останавливает/приостанавливает плеер при сворачивании приложения или блокировке экрана без
// явного возобновления, даже с stayAwake.
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GameAudio with WidgetsBindingObserver {
  GameAudio._();
  static final GameAudio instance = GameAudio._();

  final AudioPlayer _player = AudioPlayer();

  bool _enabled = true;
  double _volume = 0.5;
  bool _started = false;

  bool get enabled => _enabled;
  double get volume => _volume;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool('musicEnabled') ?? true;
    _volume = prefs.getDouble('musicVolume') ?? 0.5;
    // stayAwake держит CPU-wakelock на время плеера, usageType media + audioFocus gain — как у
    // обычного музыкального проигрывателя, а не короткого звука уведомления, которое система
    // может оборвать при блокировке экрана.
    try {
      await AudioPlayer.global.setAudioContext(AudioContext(
        android: AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: true,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
      ));
    } catch (_) {
      // Не блокируем запуск приложения, если платформа не приняла контекст.
    }
    await _player.setReleaseMode(ReleaseMode.loop);
    WidgetsBinding.instance.addObserver(this);
    await _start();
  }

  Future<void> _start() async {
    if (_started || !_enabled) return;
    try {
      await _player.setVolume(_volume);
      await _player.play(AssetSource('audio/attack.mp4'));
      _started = true;
    } catch (_) {
      // нет звука — не критично для игры
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Свернули назад / разблокировали — на всякий случай убеждаемся, что музыка реально играет,
    // а не осталась молча приостановленной системой.
    if (state == AppLifecycleState.resumed) _ensurePlaying();
  }

  Future<void> _ensurePlaying() async {
    if (!_enabled) return;
    try {
      if (!_started) {
        await _start();
      } else {
        await _player.resume();
      }
    } catch (_) {}
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('musicEnabled', value);
    if (!value) {
      await _player.pause();
    } else if (_started) {
      await _player.resume();
    } else {
      await _start();
    }
  }

  Future<void> setVolume(double value) async {
    _volume = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('musicVolume', value);
    await _player.setVolume(value);
  }
}
