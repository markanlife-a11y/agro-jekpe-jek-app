// Музыка ("attack") играет, ПОКА приложение реально на экране (по просьбе пользователя — до
// этого было наоборот, недопонимание: нужно, чтобы звук ВЫКЛЮЧАЛСЯ, когда сворачиваешь
// приложение или блокируешь телефон, а не продолжал играть в фоне).
//
// GameAudio слушает жизненный цикл приложения (WidgetsBindingObserver): сворачивание/блокировка
// (paused/inactive/hidden) — сразу пауза; возврат на экран (resumed) — снова играет, если музыка
// включена в настройках.
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
    if (state == AppLifecycleState.resumed) {
      _resumeIfEnabled();
    } else {
      // paused / inactive / hidden / detached — экран не виден (свернули приложение ИЛИ
      // заблокировали телефон): звук должен замолкнуть.
      _pause();
    }
  }

  Future<void> _pause() async {
    try {
      await _player.pause();
    } catch (_) {}
  }

  Future<void> _resumeIfEnabled() async {
    if (!_enabled) return;
    try {
      if (_started) {
        await _player.resume();
      } else {
        await _start();
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
