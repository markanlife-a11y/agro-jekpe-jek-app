// Экран входа — email+пароль как основной способ (без внешних подтверждений), Telegram —
// как дополнительный (для тех, кто предпочитает). Полностью нативный интерфейс с брендингом
// AgroAiqyn — WebView открывается ТОЛЬКО при явном нажатии "Войти через Telegram", отдельным
// экраном, а не как часть основного вида (сам вход через Telegram технически всегда идёт через
// веб-виджет Telegram — это не обходится, но не должно быть первым, что видит пользователь).
import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';
import 'home_screen.dart';
import 'telegram_webview.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
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

  void _openTelegramLogin() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TelegramWebViewScreen(
          title: 'Вход через Telegram',
          url: loginPageUrl,
          onSuccess: (data) async {
            final token = data['token']?.toString();
            if (token == null) return;
            await Api.instance.setSession(token);
            if (!mounted) return;
            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Брендированный фон — поле подсолнухов AgroAiqyn, слегка затемнённое для читаемости.
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
                  const Text(
                    '⚔️ Agro Jekpe-jek',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
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
                              child: Text('Email нужен только для входа и восстановления пароля.', style: TextStyle(fontSize: 11, color: Colors.black45)),
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
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('или', style: TextStyle(color: Colors.black38))), Expanded(child: Divider())]),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _openTelegramLogin,
                            icon: const Icon(Icons.send, size: 18),
                            label: const Text('Войти через Telegram'),
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
