// Настройки — профиль (аватар/рамка/имя), привязка Telegram↔почта в ОБЕ стороны (код + обычная
// ссылка, БЕЗ WebView — тот способ оказался ненадёжным на практике), звук, выход.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'audio.dart';
import 'sound.dart';
import 'theme.dart';
import 'profile_assets.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  final Map<String, dynamic>? account; // {email, linkedTelegramUsername, isEmailPrimary} — null пока ничего не привязано
  final Map<String, dynamic>? user; // {id, firstName, username, avatarId, frameId, displayNameOverride, friendCode}
  const SettingsScreen({super.key, required this.account, required this.user});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? _account;
  String? _avatarId;
  String? _frameId;
  String? _displayName;
  bool _savingProfile = false;

  String? _linkCode;
  String? _linkDeepLink;
  Timer? _linkPollTimer;
  bool _linkBusy = false;
  bool _unlinkBusy = false;
  bool _emailLinkBusy = false;
  bool _emailUnlinkBusy = false;

  bool get _isTelegramAccount => ((widget.user?['id'] as num?) ?? -1) > 0;

  @override
  void initState() {
    super.initState();
    _account = widget.account;
    _avatarId = widget.user?['avatarId']?.toString();
    _frameId = widget.user?['frameId']?.toString();
    _displayName = widget.user?['displayNameOverride']?.toString();
  }

  @override
  void dispose() {
    _linkPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _logout() async {
    await Api.instance.logout();
    await Api.instance.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  Future<void> _saveProfile({String? avatarId, String? frameId, String? displayName}) async {
    Haptics.tap();
    setState(() {
      _avatarId = avatarId ?? _avatarId;
      _frameId = frameId ?? _frameId;
      if (displayName != null) _displayName = displayName;
      _savingProfile = true;
    });
    await Api.instance.updateProfile(avatarId: _avatarId, frameId: _frameId, displayName: displayName);
    if (mounted) setState(() => _savingProfile = false);
  }

  Future<void> _editDisplayName() async {
    final ctrl = TextEditingController(text: _displayName ?? widget.user?['firstName']?.toString() ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Имя в приложении'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(hintText: 'Как вас будут видеть другие'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('Сохранить')),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    await _saveProfile(displayName: result);
  }

  Future<void> _startTelegramLink() async {
    Haptics.tap();
    setState(() => _linkBusy = true);
    final res = await Api.instance.telegramLinkCode();
    if (!mounted) return;
    setState(() => _linkBusy = false);
    if (res['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ ${res['message'] ?? 'не получилось'}')));
      return;
    }
    setState(() {
      _linkCode = res['code'] as String;
      _linkDeepLink = res['deepLink'] as String;
    });
    _linkPollTimer?.cancel();
    _linkPollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final status = await Api.instance.telegramLinkStatus(_linkCode!);
      if (!mounted) return;
      if (status['ok'] == true && status['linked'] == true) {
        _linkPollTimer?.cancel();
        Haptics.correct();
        setState(() {
          _account = {..._account ?? {}, 'linkedTelegramUsername': status['telegramUsername'], 'isEmailPrimary': true};
          _linkCode = null;
          _linkDeepLink = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Telegram привязан 🌾')));
      }
    });
  }

  Future<void> _openTelegramDeepLink() async {
    if (_linkDeepLink == null) return;
    final uri = Uri.parse(_linkDeepLink!);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _unlinkTelegram() async {
    Haptics.tap();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отвязать Telegram?'),
        content: const Text('Уведомления о вызовах на батл в Telegram перестанут приходить. Вход по почте продолжит работать как обычно.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Отвязать')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _unlinkBusy = true);
    final res = await Api.instance.telegramUnlink();
    if (!mounted) return;
    setState(() => _unlinkBusy = false);
    if (res['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ ${res['message'] ?? 'не получилось'}')));
      return;
    }
    setState(() => _account = {..._account ?? {}, 'linkedTelegramUsername': null});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Telegram отвязан')));
  }

  // Обратная привязка — почта+пароль К Telegram-аккаунту (жалоба: "если вход был по телеграму,
  // должна быть кнопка привязать почту, на случай если забудут пароли").
  Future<void> _linkEmailDialog() async {
    Haptics.tap();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Привязать почту'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('На случай, если потеряете доступ к Telegram — сможете войти по почте и паролю.', style: TextStyle(fontSize: 12.5)),
            const SizedBox(height: 12),
            TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 10),
            TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Пароль (мин. 6 символов)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Привязать')),
        ],
      ),
    );
    if (result != true) return;
    if (!mounted) return;
    setState(() => _emailLinkBusy = true);
    final res = await Api.instance.linkEmail(emailCtrl.text.trim(), passCtrl.text);
    if (!mounted) return;
    setState(() => _emailLinkBusy = false);
    if (res['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ ${res['message'] ?? 'не получилось'}')));
      return;
    }
    setState(() => _account = {'email': emailCtrl.text.trim(), 'linkedTelegramUsername': null, 'isEmailPrimary': false});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Почта привязана 🌾')));
  }

  Future<void> _unlinkEmail() async {
    Haptics.tap();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отвязать почту?'),
        content: const Text('Вход по этой почте и паролю перестанет работать. Вход через Telegram продолжит работать как обычно.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Отвязать')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _emailUnlinkBusy = true);
    final res = await Api.instance.unlinkEmail();
    if (!mounted) return;
    setState(() => _emailUnlinkBusy = false);
    if (res['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ ${res['message'] ?? 'не получилось'}')));
      return;
    }
    setState(() => _account = null);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Почта отвязана')));
  }

  @override
  Widget build(BuildContext context) {
    final audio = GameAudio.instance;
    final linkedUsername = _account?['linkedTelegramUsername']?.toString();
    final isEmailPrimary = _account?['isEmailPrimary'] == true;

    return Scaffold(
      appBar: AppBar(title: const Text('⚙️ Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('Профиль'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ProfileAvatar(avatarId: _avatarId, frameId: _frameId, size: 76),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: _editDisplayName,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _displayName?.isNotEmpty == true ? _displayName! : (widget.user?['firstName']?.toString() ?? 'Игрок'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.edit, size: 16, color: Colors.black45),
                        ],
                      ),
                    ),
                  ),
                  if (widget.user?['friendCode'] != null) ...[
                    const SizedBox(height: 2),
                    Text('Ваш ID: ${widget.user!['friendCode']}', style: const TextStyle(fontSize: 11.5, color: Colors.black45)),
                  ],
                  if (_savingProfile) const Padding(padding: EdgeInsets.only(top: 4), child: Text('Сохраняю…', style: TextStyle(fontSize: 12, color: Colors.black45))),
                  const SizedBox(height: 14),
                  Align(alignment: Alignment.centerLeft, child: Text('Аватар', style: Theme.of(context).textTheme.labelLarge)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: kAvatars.map((a) {
                      final selected = a.id == _avatarId;
                      return GestureDetector(
                        onTap: () => _saveProfile(avatarId: a.id),
                        child: Container(
                          padding: EdgeInsets.all(selected ? 3 : 0),
                          decoration: selected ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AgroColors.gold, width: 2.5)) : null,
                          child: ProfileAvatar(avatarId: a.id, size: 48),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  Align(alignment: Alignment.centerLeft, child: Text('Рамка', style: Theme.of(context).textTheme.labelLarge)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: kFrames.map((f) {
                      final selected = f.id == _frameId;
                      return GestureDetector(
                        onTap: () => _saveProfile(frameId: f.id),
                        child: Column(
                          children: [
                            Container(
                              padding: EdgeInsets.all(selected ? 3 : 0),
                              decoration: selected ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AgroColors.green, width: 2.5)) : null,
                              child: ProfileAvatar(avatarId: _avatarId, frameId: f.id, size: 48),
                            ),
                            const SizedBox(height: 3),
                            Text(f.label + (f.premium ? ' 🔒' : ''), style: const TextStyle(fontSize: 10)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Аккаунт'),
          Card(
            child: Column(
              children: [
                if (_isTelegramAccount)
                  ListTile(
                    leading: const Icon(Icons.send, color: AgroColors.green),
                    title: const Text('Вход через Telegram'),
                    subtitle: Text(widget.user?['username'] != null ? '@${widget.user!['username']}' : 'Это и есть ваш аккаунт'),
                  )
                else
                  ListTile(leading: const Icon(Icons.email_outlined), title: const Text('Email'), subtitle: Text(_account?['email']?.toString() ?? '—')),
                const Divider(height: 1),
                // Telegram-блок: у email-первичных — привязка/отвязка Telegram (как раньше).
                // У Telegram-аккаунтов сам Telegram отдельно не показываем — это и есть личность.
                if (isEmailPrimary) ...[
                  if (linkedUsername != null)
                    ListTile(
                      leading: const Icon(Icons.check_circle, color: AgroColors.green),
                      title: const Text('Telegram'),
                      subtitle: Text('Привязан: $linkedUsername'),
                      trailing: _unlinkBusy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : TextButton(onPressed: _unlinkTelegram, child: const Text('Отвязать', style: TextStyle(color: AgroColors.danger))),
                    )
                  else if (_linkDeepLink != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Откройте Telegram и подтвердите — вернитесь сюда, привяжется само.'),
                          const SizedBox(height: 10),
                          FilledButton.icon(onPressed: _openTelegramDeepLink, icon: const Icon(Icons.send), label: const Text('Открыть Telegram')),
                          const SizedBox(height: 6),
                          const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                        ],
                      ),
                    )
                  else
                    ListTile(
                      leading: const Icon(Icons.send_outlined),
                      title: const Text('Telegram'),
                      subtitle: const Text('Не привязан — для уведомлений о вызовах на батл'),
                      trailing: _linkBusy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : OutlinedButton(onPressed: _startTelegramLink, child: const Text('Привязать')),
                    ),
                ] else ...[
                  // Telegram-аккаунт: наоборот — почта как запасной способ входа.
                  if (_account != null)
                    ListTile(
                      leading: const Icon(Icons.check_circle, color: AgroColors.green),
                      title: const Text('Почта (запасной вход)'),
                      subtitle: Text(_account!['email']?.toString() ?? '—'),
                      trailing: _emailUnlinkBusy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : TextButton(onPressed: _unlinkEmail, child: const Text('Отвязать', style: TextStyle(color: AgroColors.danger))),
                    )
                  else
                    ListTile(
                      leading: const Icon(Icons.email_outlined),
                      title: const Text('Почта'),
                      subtitle: const Text('Не привязана — на случай, если забудете доступ к Telegram'),
                      trailing: _emailLinkBusy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : OutlinedButton(onPressed: _linkEmailDialog, child: const Text('Привязать')),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
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
