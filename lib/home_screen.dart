// Главный экран — теперь с нижними вкладками (жалоба: "внизу красивые вкладки должны быть:
// Игры, Друзья, Рейтинг, Магазин"): Игры (случайный соперник/по ссылке/активные игры), Друзья
// (список, с переходом в профиль каждого — жалоба: "нельзя зайти в профиль друзей"), Рейтинг
// (топ по победам), Магазин (пока пустая заглушка — задел под будущую монетизацию). Тот же
// набор данных, что и у мини-аппа внутри Telegram (/miniapp/api/me) — статистика общая
// независимо от того, где играли.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'sound.dart';
import 'theme.dart';
import 'profile_assets.dart';
import 'queue_screen.dart';
import 'game_screen.dart';
import 'settings_screen.dart';
import 'friend_profile_screen.dart';

// ThinkingIndicator доступен через game_screen.dart (единая точка определения виджета).

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
  int _tab = 0;

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

  void _openSettings() {
    Haptics.tap();
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => SettingsScreen(
            account: _data?['account'] as Map<String, dynamic>?,
            user: _data?['user'] as Map<String, dynamic>?,
          ),
        ))
        .then((_) => _load());
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

  void _openFriendProfile(Map<String, dynamic> friend) {
    Haptics.tap();
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => FriendProfileScreen(friend: friend)))
        .then((_) => _load());
  }

  static const _titles = ['⚔️ Agro Jekpe-jek', '👥 Друзья', '🏆 Рейтинг', '🛍️ Магазин'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Настройки', onPressed: _openSettings)],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: ThinkingIndicator(label: 'Загружаю…'))
            : _error != null
                ? _buildErrorBody()
                : _buildTabBody(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          Haptics.tap();
          setState(() => _tab = i);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.sports_esports_outlined), selectedIcon: Icon(Icons.sports_esports), label: 'Игры'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Друзья'),
          NavigationDestination(icon: Icon(Icons.leaderboard_outlined), selectedIcon: Icon(Icons.leaderboard), label: 'Рейтинг'),
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Магазин'),
        ],
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

  Widget _buildTabBody() {
    switch (_tab) {
      case 0:
        return _buildGamesTab();
      case 1:
        return _buildFriendsTab();
      case 2:
        return _buildRatingTab();
      default:
        return _buildShopTab();
    }
  }

  // --- Вкладка "Игры" ---------------------------------------------------------------------

  Widget _buildGamesTab() {
    final data = _data!;
    final user = data['user'] as Map<String, dynamic>;
    final activeBattles = ((data['activeBattles'] as List?) ?? []).cast<Map<String, dynamic>>().where((b) => b['status'] == 'active').toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            ProfileAvatar(avatarId: user['avatarId']?.toString(), frameId: user['frameId']?.toString(), size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Привет, ${user['firstName'] ?? user['username'] ?? 'агроном'} 🌾', style: Theme.of(context).textTheme.titleMedium),
            ),
          ],
        ),
        const SizedBox(height: 16),
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

  Widget _activeBattleTile(Map<String, dynamic> b) {
    final opponentName = b['opponentName']?.toString() ?? '?';
    final myTurn = b['myTurn'] == true;
    return ListTile(
      leading: _letterAvatar(opponentName),
      title: Text(opponentName),
      subtitle: Text('Раунд ${(b['round'] as num).toInt() + 1}/${b['totalRounds']} · счёт ${b['myScore']}:${b['opponentScore']}'),
      trailing: myTurn
          ? FilledButton(onPressed: () => _openBattle((b['id'] as num).toInt()), child: const Text('Играть'))
          : const Chip(label: Text('Ждём соперника')),
    );
  }

  // --- Вкладка "Друзья" --------------------------------------------------------------------

  Widget _buildFriendsTab() {
    final friends = ((_data!['friends'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (friends.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          SizedBox(height: 60),
          Icon(Icons.people_outline, size: 40, color: Colors.black38),
          SizedBox(height: 12),
          Text('Пока нет друзей по батлам — сыграйте случайную игру или пригласите кого-то по ссылке во вкладке «Игры».', textAlign: TextAlign.center),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [Card(child: Column(children: friends.map((f) => _friendTile(f)).toList()))],
    );
  }

  Widget _friendTile(Map<String, dynamic> f) {
    final name = f['name']?.toString() ?? '?';
    final friendChatId = (f['friendChatId'] as num).toInt();
    final busy = _busyChallenge.contains(friendChatId);
    return ListTile(
      onTap: () => _openFriendProfile(f),
      leading: ProfileAvatar(avatarId: f['avatarId']?.toString(), frameId: f['frameId']?.toString(), size: 42),
      title: Text(name),
      subtitle: Text('${f['gamesPlayed']} игр · ${f['wins']}W-${f['losses']}L-${f['draws']}D'),
      trailing: OutlinedButton(
        onPressed: busy ? null : () => _challengeFriend(friendChatId, name),
        child: Text(busy ? '…' : '🎮 Играть'),
      ),
    );
  }

  // --- Вкладка "Рейтинг" -------------------------------------------------------------------

  Widget _buildRatingTab() {
    final leaderboard = ((_data!['leaderboard'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (leaderboard.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          SizedBox(height: 60),
          Icon(Icons.leaderboard_outlined, size: 40, color: Colors.black38),
          SizedBox(height: 12),
          Text('Пока рейтинг пуст — сыграйте несколько игр, и он заполнится.', textAlign: TextAlign.center),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [Card(child: Column(children: List.generate(leaderboard.length, (i) => _leaderboardTile(leaderboard[i], i + 1))))],
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

  // --- Вкладка "Магазин" (заглушка) ---------------------------------------------------------

  Widget _buildShopTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        SizedBox(height: 60),
        Icon(Icons.storefront_outlined, size: 48, color: AgroColors.gold),
        SizedBox(height: 16),
        Text('Магазин скоро откроется', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center),
        SizedBox(height: 8),
        Text(
          'Здесь появятся новые аватары, рамки и другие украшения профиля — часть уже можно выбрать бесплатно в Настройках.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
      );

  Widget _letterAvatar(String name) => CircleAvatar(
        backgroundColor: AgroColors.green,
        child: Text(name.isNotEmpty ? name.replaceAll('@', '')[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)),
      );
}
