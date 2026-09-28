// Настройки — звук (вкл/выкл, громкость) и, для email-аккаунтов, привязка Telegram (только
// для уведомлений о вызовах на батл — не подменяет основной email-вход).
import 'package:flutter/material.dart';
import 'api.dart';
import 'audio.dart';
import 'sound.dart';
import 'theme.dart';
import 'telegram_webview.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  final Map<String, dynamic>? account; // {email, linkedTelegramUsername} — null для Telegram-аккаунтов
  const SettingsScreen({super.key, required this.account});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? _account;
  bool _linking = false;

  @override
  void initState() {
    super.initState();
    _account = widget.account;
  }

  Future<void> _logout() async {
    await Api.instance.logout();
    await Api.instance.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  void _linkTelegram() {
    Haptics.tap();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TelegramWebViewScreen(
          title: 'Привязать Telegram',
          url: loginPageUrl,
          onSuccess: (data) async {
            if (!mounted) return;
            Navigator.of(context).pop(); // закрыть WebView
            setState(() => _linking = true);
            final res = await Api.instance.linkTelegram(data);
            if (!mounted) return;
            setState(() => _linking = false);
            if (res['ok'] == true) {
              setState(() => _account = {..._account ?? {}, 'linkedTelegramUsername': res['telegramUsername'] ?? 'привязан'});
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Telegram привязан 🌾')));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ ${res['message'] ?? 'не получилось'}')));
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final audio = GameAudio.instance;
    final linkedUsername = _account?['linkedTelegramUsername']?.toString();

    return Scaffold(
      appBar: AppBar(title: const Text('⚙️ Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_account != null) ...[
            const _SectionTitle('Аккаунт'),
            Card(
              child: Column(
                children: [
                  ListTile(leading: const Icon(Icons.email_outlined), title: const Text('Email'), subtitle: Text(_account!['email']?.toString() ?? '—')),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.send),
                    title: const Text('Telegram'),
                    subtitle: Text(linkedUsername != null ? 'Привязан: $linkedUsername' : 'Не привязан — для уведомлений о вызовах'),
                    trailing: linkedUsername != null
                        ? const Icon(Icons.check_circle, color: AgroColors.green)
                        : _linking
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : OutlinedButton(onPressed: _linkTelegram, child: const Text('Привязать')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          const _SectionTitle('Звук'),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: StatefulBuilder(
                builder: (context, setLocal) {
                  return Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Музыка'),
                        value: audio.enabled,
                        onChanged: (v) async {
                          await audio.setEnabled(v);
                          setLocal(() {});
                        },
                      ),
                      Row(
                        children: [
                          const Icon(Icons.volume_down),
                          Expanded(
                            child: Slider(
                              value: audio.volume,
                              onChanged: audio.enabled
                                  ? (v) async {
                                      await audio.setVolume(v);
                                      setLocal(() {});
                                    }
                                  : null,
                            ),
                          ),
                          const Icon(Icons.volume_up),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 28),
          OutlinedButton.icon(onPressed: _logout, icon: const Icon(Icons.logout), label: const Text('Выйти из аккаунта')),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
    );
  }
}
