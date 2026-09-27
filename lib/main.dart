// Agro Jekpe-jek — полноценное нативное Android-приложение (Flutter). Тот же баттл на знание
// агрономии, что и в Telegram-боте @agroexam_bot, но с собственным нативным интерфейсом и
// голосовым вводом для открытых вопросов (слушает сразу, без нажатия кнопок).
//
// Бэкенд — тот же Cloudflare Worker, что и у бота (см. lib/api.dart) — отдельной
// синхронизации данных нет, это буквально один и тот же сервер и база.
import 'package:flutter/material.dart';
import 'theme.dart';
import 'api.dart';
import 'login_screen.dart';
import 'home_screen.dart';

void main() {
  runApp(const AgroApp());
}

class AgroApp extends StatelessWidget {
  const AgroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agro Jekpe-jek',
      debugShowCheckedModeBanner: false,
      theme: buildAgroTheme(Brightness.light),
      darkTheme: buildAgroTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const SplashGate(),
    );
  }
}

/// Решает, куда вести пользователя: если сохранённый токен ещё действителен — сразу на
/// главный экран (без повторного входа при каждом запуске), иначе — на экран входа.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _checked = false;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    await Api.instance.loadSession();
    if (Api.instance.isLoggedIn) {
      final res = await Api.instance.me();
      if (res['ok'] == true) {
        if (mounted) setState(() { _checked = true; _loggedIn = true; });
        return;
      }
      await Api.instance.clearSession();
    }
    if (mounted) setState(() { _checked = true; _loggedIn = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('⚔️🌾', style: TextStyle(fontSize: 48)),
              SizedBox(height: 16),
              CircularProgressIndicator(),
            ],
          ),
        ),
      );
    }
    return _loggedIn ? const HomeScreen() : const LoginScreen();
  }
}
