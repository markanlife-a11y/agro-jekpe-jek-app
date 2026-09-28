// Главный экран — приветствие, случайный соперник / ссылка-приглашение, активные игры, друзья
// (с прямым вызовом "Играть"), топ по победам. Тот же набор данных, что и у мини-аппа внутри
// Telegram (/miniapp/api/me) — статистика общая независимо от того, где играли.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'sound.dart';
import 'audio.dart';
import 'theme.dart';
import 'queue_screen.dart';
import 'game_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  Map<String, dynamic>? _data;
  String? _error;
  Map<String, dynamic>? _inviteInfo;
  bool _busyInvite = false;
  final Set<int> _busyChallenge = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await Api.instance.me();
    if (!mounted) return;
    if (res['ok'] != true) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? 'Не удалось загрузить.';
      });
      return;
    }
    setState(() {
      _loading = false;
      _data = res;
    });
  }

  Future<void> _logout() async {
    await Api.instance.logout();
    await Api.instance.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  void _showSoundSettings() {
    Haptics.tap();
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final audio = GameAudio.instance;
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🔊 Звук', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 14),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Музыка'),
                    value: audio.enabled,
                    onChanged: (v) async {
                      await audio.setEnabled(v);
                      setModalState(() {});
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
                                  setModalState(() {});
                                }
                              : null,
                        ),
                      ),
                      const Icon(Icons.volume_up),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _startRandom() {
    Haptics.tap();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QueueScreen())).then((_) => _load());
  }

  Future<void> _createInvite() async {
    Haptics.tap();
    setState(() {
      _busyInvite = true;
      _inviteInfo = null;
    });
    final res = await Api.instance.inviteCreate();
    if (!mounted) return;
    setState(() {
      _busyInvite = false;
      _inviteInfo = res;
    });
  }

  void _copyInviteLink() {
    final link = _inviteInfo?['link']?.toString();
    if (link == null) return;
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ссылка скопирована 🌾')));
  }

  Future<void> _challengeFriend(int friendChatId, String name) async {
    Haptics.tap();
    setState(() => _busyChallenge.add(friendChatId));
    final res = await Api.instance.friendChallenge(friendChatId);
    if (!mounted) return;
    setState(() => _busyChallenge.remove(friendChatId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res['ok'] == true ? 'Вызов отправлен $name — ждём ответа 🌾' : '⚠️ ${res['message']}')),
    );
  }

  void _openBattle(int battleId) {
    Haptics.tap();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(battleId: battleId))).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚔️ Agro Jekpe-jek'),
        actions: [
          IconButton(icon: const Icon(Icons.volume_up), tooltip: 'Звук', onPressed: _showSoundSettings),
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Выйти', onPressed: _logout),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildErrorBody()
                : _buildBody(),
      ),
    );
  }

  Widget _buildErrorBody() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 60),
        const Icon(Icons.error_outline, color: AgroColors.danger, size: 40),
        const SizedBox(height: 12),
        Text('⚠️ $_error', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(onPressed: _load, child: const Text('Повторить')),
      ],
    );
  }

  Widget _buildBody() {
    final data = _data!;
    final user = data['user'] as Map<String, dynamic>;
    final friends = ((data['friends'] as List?) ?? []).cast<Map<String, dynamic>>();
    final leaderboard = ((data['leaderboard'] as List?) ?? []).cast<Map<String, dynamic>>();
    final activeBattles = ((data['activeBattles'] as List?) ?? []).cast<Map<String, dynamic>>().where((b) => b['status'] == 'active').toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Привет, ${user['firstName'] ?? user['username'] ?? 'агроном'} 🌾', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: FilledButton.icon(onPressed: _startRandom, icon: const Icon(Icons.casino), label: const Text('Случайный'))),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _busyInvite ? null : _createInvite,
                icon: const Icon(Icons.link),
                label: Text(_busyInvite ? 'Готовлю…' : 'По ссылке'),
              ),
            ),
          ],
        ),
        if (_inviteInfo != null) _buildInviteCard(),
        const SizedBox(height: 22),
        _sectionTitle('🎮 Активные игры'),
        Card(
          child: activeBattles.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Пока нет активных игр — начните со случайного соперника или пригласите друга.'),
                )
              : Column(children: activeBattles.map((b) => _activeBattleTile(b)).toList()),
        ),
        const SizedBox(height: 22),
        _sectionTitle('👥 Друзья'),
        Card(
          child: friends.isEmpty
              ? const Padding(padding: EdgeInsets.all(16), child: Text('Пока нет друзей по батлам — пригласите первого кнопкой выше.'))
              : Column(children: friends.map((f) => _friendTile(f)).toList()),
        ),
        if (leaderboard.isNotEmpty) ...[
          const SizedBox(height: 22),
          _sectionTitle('🏆 Топ по победам'),
          Card(child: Column(children: List.generate(leaderboard.length, (i) => _leaderboardTile(leaderboard[i], i + 1)))),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildInviteCard() {
    final res = _inviteInfo!;
    if (res['ok'] != true) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Text('⚠️ ${res['message']}'))),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🔗 Ссылка готова (${res['totalRounds']} раундов):', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SelectableText(res['link']?.toString() ?? '', style: const TextStyle(fontSize: 12.5)),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _copyInviteLink, icon: const Icon(Icons.copy), label: const Text('Копировать'))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
      );

  Widget _avatar(String name) => CircleAvatar(
        backgroundColor: AgroColors.green,
        child: Text(name.isNotEmpty ? name.replaceAll('@', '')[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)),
      );

  Widget _activeBattleTile(Map<String, dynamic> b) {
    final opponentName = b['opponentName']?.toString() ?? '?';
    final myTurn = b['myTurn'] == true;
    return ListTile(
      leading: _avatar(opponentName),
      title: Text(opponentName),
      subtitle: Text('Раунд ${(b['round'] as num).toInt() + 1}/${b['totalRounds']} · счёт ${b['myScore']}:${b['opponentScore']}'),
      trailing: myTurn
          ? FilledButton(onPressed: () => _openBattle((b['id'] as num).toInt()), child: const Text('Играть'))
          : const Chip(label: Text('Ждём соперника')),
    );
  }

  Widget _friendTile(Map<String, dynamic> f) {
    final name = f['name']?.toString() ?? '?';
    final friendChatId = (f['friendChatId'] as num).toInt();
    final busy = _busyChallenge.contains(friendChatId);
    return ListTile(
      leading: _avatar(name),
      title: Text(name),
      subtitle: Text('${f['gamesPlayed']} игр · ${f['wins']}W-${f['losses']}L-${f['draws']}D'),
      trailing: OutlinedButton(
        onPressed: busy ? null : () => _challengeFriend(friendChatId, name),
        child: Text(busy ? '…' : '🎮 Играть'),
      ),
    );
  }

  Widget _leaderboardTile(Map<String, dynamic> l, int place) {
    return ListTile(
      leading: CircleAvatar(child: Text('$place')),
      title: Text(l['name']?.toString() ?? '?'),
      subtitle: Text('${l['gamesPlayed']} игр'),
      trailing: Chip(label: Text('${l['wins']} 🏆')),
    );
  }
}
