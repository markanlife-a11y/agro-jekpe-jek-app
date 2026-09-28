// Экран входа — email+пароль, без внешних подтверждений и без WebView вообще (Telegram Login
// Widget в WebView оказался ненадёжным на практике — подтверждение в Telegram не всегда
// долетало обратно до приложения). Привязать Telegram (для уведомлений о вызовах на батл)
// можно позже в "Настройках" — там это сделано надёжно, через код + обычную ссылку t.me/...
import 'package:flutter/material.dart';
import 'api.dart';
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

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
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
    await Api.instance.setSession(res['token'] as String);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
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
                          Text(
                            _registerMode ? 'Создать аккаунт' : 'Вход',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
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
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Text('⚠️ $_error', style: const TextStyle(color: AgroColors.danger, fontSize: 13)),
                          ],
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _busy ? null : _submitEmail,
                            child: _busy
                                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Text(_registerMode ? 'Зарегистрироваться' : 'Войти'),
                          ),
                          TextButton(
                            onPressed: _busy ? null : () => setState(() => _registerMode = !_registerMode),
                            child: Text(_registerMode ? 'Уже есть аккаунт? Войти' : 'Нет аккаунта? Зарегистрироваться'),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Telegram можно будет привязать позже в Настройках — для уведомлений о вызовах на батл.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: Colors.black38),
                          ),
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
