// Agro Jekpe-jek — полноценное нативное Android-приложение (Flutter). Тот же баттл на знание
// агрономии, что и в Telegram-боте @agroexam_bot, но с собственным нативным интерфейсом и
// голосовым вводом для открытых вопросов (слушает сразу, без нажатия кнопок).
//
// Бэкенд — тот же Cloudflare Worker, что и у бота (см. lib/api.dart) — отдельной
// синхронизации данных нет, это буквально один и тот же сервер и база.
import 'package:flutter/material.dart';
import 'theme.dart';
import 'api.dart';
import 'audio.dart';
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

/// Анимированная заставка + решает, куда вести пользователя: если сохранённый токен ещё
/// действителен — сразу на главный экран (без повторного входа при каждом запуске), иначе —
/// на экран входа.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _textFade;

  bool _checked = false;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    _logoScale = CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.7, curve: Curves.elasticOut));
    _logoFade = CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.4, curve: Curves.easeIn));
    _textFade = CurvedAnimation(parent: _ctrl, curve: const Interval(0.45, 0.8, curve: Curves.easeIn));
    _ctrl.forward();
    _check();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    await Future.wait<void>([
      GameAudio.instance.init(),
      Api.instance.loadSession(),
      Future<void>.delayed(const Duration(milliseconds: 900)), // даём анимации доиграть, не мигаем
    ]);
    bool loggedIn = false;
    if (Api.instance.isLoggedIn) {
      final res = await Api.instance.me();
      loggedIn = res['ok'] == true;
      if (!loggedIn) await Api.instance.clearSession();
    }
    if (mounted) setState(() { _checked = true; _loggedIn = loggedIn; });
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AgroColors.greenDark, AgroColors.green],
            ),
          ),
          child: Center(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, child) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: _logoFade.value,
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: Image.asset('assets/images/logo.jpg', width: 120, height: 120, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Opacity(
                      opacity: _textFade.value,
                      child: const Column(
                        children: [
                          Text('⚔️ Agro Jekpe-jek', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text('AgroAiqyn · Точная агрономия', style: TextStyle(color: Colors.white70, fontSize: 12.5, letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 34),
                    Opacity(
                      opacity: _textFade.value,
                      child: const _PulsingDots(),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    }
    return _loggedIn ? const HomeScreen() : const LoginScreen();
  }
}

/// Три пульсирующие точки — лёгкая, не топорная индикация загрузки вместо голого спиннера.
class _PulsingDots extends StatefulWidget {
  const _PulsingDots();

  @override
  State<_PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<_PulsingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = (_ctrl.value - i * 0.2) % 1.0;
            final scale = 0.6 + 0.4 * (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Transform.scale(
                scale: scale,
                child: Container(width: 9, height: 9, decoration: const BoxDecoration(color: AgroColors.gold, shape: BoxShape.circle)),
              ),
            );
          }),
        );
      },
    );
  }
}
