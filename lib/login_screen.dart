// Экран входа — Telegram (код + обычная ссылка t.me/bot?start=tglogin_<code>, БЕЗ WebView вообще
// — Telegram Login Widget в WebView оказался ненадёжным на практике, подтверждение в Telegram не
// всегда долетало обратно до приложения) как основной быстрый способ, и email+пароль как запасной
// — оба сразу на этом экране, чтобы новый пользователь не путался, где что искать.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'sound.dart';
import 'theme.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _registerMode = false;
  bool _busy = false;
  String? _error;
  bool _obscure = true;
  bool _showEmailForm = false;

  // --- Вход через Telegram ---
  String? _tgCode;
  String? _tgDeepLink;
  Timer? _tgPollTimer;
  bool _tgBusy = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _tgPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _goHome(String token) async {
    await Api.instance.setSession(token);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  Future<void> _startTelegramLogin() async {
    Haptics.tap();
    setState(() {
      _tgBusy = true;
      _error = null;
    });
    final res = await Api.instance.telegramLoginCode();
    if (!mounted) return;
    if (res['ok'] != true) {
      setState(() {
        _tgBusy = false;
        _error = res['message']?.toString() ?? 'Не получилось получить код входа.';
      });
      return;
    }
    setState(() {
      _tgBusy = false;
      _tgCode = res['code'] as String;
      _tgDeepLink = res['deepLink'] as String;
    });
    await _openTelegramDeepLink();
    _tgPollTimer?.cancel();
    _tgPollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final status = await Api.instance.telegramLoginStatus(_tgCode!);
      if (!mounted) return;
      if (status['ok'] == true && status['linked'] == true) {
        _tgPollTimer?.cancel();
        Haptics.correct();
        await _goHome(status['token'] as String);
      }
    });
  }

  Future<void> _openTelegramDeepLink() async {
    if (_tgDeepLink == null) return;
    final uri = Uri.parse(_tgDeepLink!);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _cancelTelegramLogin() {
    _tgPollTimer?.cancel();
    setState(() {
      _tgCode = null;
      _tgDeepLink = null;
    });
  }

  Future<void> _submitEmail() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Заполните email и пароль.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = _registerMode
        ? await Api.instance.registerEmail(email, password, _nameCtrl.text.trim())
        : await Api.instance.loginEmail(email, password);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['ok'] != true) {
      setState(() => _error = res['message']?.toString() ?? 'Не получилось.');
      return;
    }
    await _goHome(res['token'] as String);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/banner.jpg', fit: BoxFit.cover),
          Container(color: Colors.black.withOpacity(0.55)),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset('assets/images/logo.jpg', width: 96, height: 96, fit: BoxFit.cover),
                  ),
                  const SizedBox(height: 14),
                  const Text('⚔️ Agro Jekpe-jek', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  const Text('AgroAiqyn 🌾', style: TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 1)),
                  const SizedBox(height: 28),
                  Card(
                    color: Colors.white.withOpacity(0.97),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Добро пожаловать', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17), textAlign: TextAlign.center),
                          const SizedBox(height: 4),
                          const Text('Войдите одним нажатием через Telegram', style: TextStyle(fontSize: 12.5, color: Colors.black54), textAlign: TextAlign.center),
                          const SizedBox(height: 18),
                          if (_tgDeepLink == null) ...[
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _tgBusy ? null : _startTelegramLogin,
                                icon: _tgBusy
                                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.send),
                                label: const Text('Войти через Telegram'),
                              ),
                            ),
                          ] else ...[
                            const _TelegramWaitingCard(),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(child: OutlinedButton(onPressed: _openTelegramDeepLink, child: const Text('Открыть Telegram ещё раз'))),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Center(
                              child: TextButton(onPressed: _cancelTelegramLogin, child: const Text('Отмена', style: TextStyle(fontSize: 12))),
                            ),
                          ],
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: () => setState(() => _showEmailForm = !_showEmailForm),
                            child: Text(_showEmailForm ? 'Скрыть вход по почте' : 'Войти по почте и паролю вместо этого'),
                          ),
                          if (_showEmailForm) ...[
                            const Divider(height: 24),
                            Text(
                              _registerMode ? 'Создать аккаунт' : 'Вход по почте',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 14),
                            if (_registerMode) ...[
                              TextField(
                                controller: _nameCtrl,
                                decoration: const InputDecoration(labelText: 'Имя', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder()),
                              ),
                              const SizedBox(height: 12),
                            ],
                            TextField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined), border: OutlineInputBorder()),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _passwordCtrl,
                              obscureText: _obscure,
                              onSubmitted: (_) => _submitEmail(),
                              decoration: InputDecoration(
                                labelText: 'Пароль',
                                prefixIcon: const Icon(Icons.lock_outline),
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                ),
                              ),
                            ),
                            if (!_registerMode) ...[
                              const SizedBox(height: 4),
                              const Align(
                                alignment: Alignment.centerRight,
                                child: Text('Email — только для входа и восстановления пароля.', style: TextStyle(fontSize: 11, color: Colors.black45)),
                              ),
                            ],
                            const SizedBox(height: 14),
                            FilledButton.tonal(
                              onPressed: _busy ? null : _submitEmail,
                              child: _busy
                                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Text(_registerMode ? 'Зарегистрироваться' : 'Войти'),
                            ),
                            TextButton(
                              onPressed: _busy ? null : () => setState(() => _registerMode = !_registerMode),
                              child: Text(_registerMode ? 'Уже есть аккаунт? Войти' : 'Нет аккаунта? Зарегистрироваться'),
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Text('⚠️ $_error', style: const TextStyle(color: AgroColors.danger, fontSize: 13), textAlign: TextAlign.center),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Пока ждём подтверждения в Telegram — лёгкая пульсация вместо голого спиннера,
/// чтобы ожидание не ощущалось "зависшим".
class _TelegramWaitingCard extends StatefulWidget {
  const _TelegramWaitingCard();

  @override
  State<_TelegramWaitingCard> createState() => _TelegramWaitingCardState();
}

class _TelegramWaitingCardState extends State<_TelegramWaitingCard> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AgroColors.green.withOpacity(0.08), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, child) => Opacity(opacity: 0.5 + 0.5 * _ctrl.value, child: child),
            child: const Icon(Icons.send, color: AgroColors.green, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Открыли Telegram — подтвердите там, вернитесь сюда, вход произойдёт сам.', style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}
