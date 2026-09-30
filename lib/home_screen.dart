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

  // silent — обновить данные в фоне, не подменяя экран на "Загружаю" (жалоба: каждый возврат из
  // профиля/настроек/игры перерисовывал весь экран заново, "не смотрится красиво, нужно без
  // него"). Полноэкранный индикатор нужен только один раз, на самом первом открытии.
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
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
      _error = null;
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
        .then((_) => _load(silent: true));
  }

  void _startRandom() {
    Haptics.tap();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QueueScreen())).then((_) => _load(silent: true));
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
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(battleId: battleId))).then((_) => _load(silent: true));
  }

  void _openFriendProfile(Map<String, dynamic> friend) {
    Haptics.tap();
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => FriendProfileScreen(friend: friend)))
        .then((_) => _load(silent: true));
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
        onRefresh: () => _load(silent: true), // свой спиннер снизу уже есть, полноэкранный не нужен
        child: _loading
            ? const Center(child: ThinkingIndicator(label: 'Загружаю…'))
            : _error != null
                ? _buildErrorBody()
                // Плавный переход между вкладками (жалоба: "переход между вкладками должен быть
                // анимированным") — лёгкое затухание + сдвиг вместо мгновенной подмены контента.
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(animation),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(key: ValueKey(_tab), child: _buildTabBody()),
                  ),
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
  // Полноценная: добавление по поиску имени/ID (жалоба: "должна быть кнопка добавить друга,
  // поиск по имени или ID"), свой ID для тех, кого добавляют по коду, удаление друга (с
  // завершением активной игры прямо тут же, если она есть — жалоба: "прекратить игру с ним там
  // же если игра есть").

  Widget _buildFriendsTab() {
    final friends = ((_data!['friends'] as List?) ?? []).cast<Map<String, dynamic>>();
    final myCode = _data!['user']?['friendCode']?.toString();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.badge_outlined, color: AgroColors.green),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    myCode != null ? 'Ваш ID: $myCode — скажите его другу, чтобы он добавил вас' : 'Загружаю ваш ID…',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(onPressed: _openAddFriendDialog, icon: const Icon(Icons.person_add_alt_1), label: const Text('Добавить друга')),
        ),
        const SizedBox(height: 18),
        if (friends.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 30),
            child: Column(
              children: [
                Icon(Icons.people_outline, size: 40, color: Colors.black38),
                SizedBox(height: 12),
                Text('Пока никого нет — добавьте по ID/имени или сыграйте случайную игру во вкладке «Игры».', textAlign: TextAlign.center),
              ],
            ),
          )
        else
          Card(child: Column(children: friends.map((f) => _friendTile(f)).toList())),
      ],
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton(
            onPressed: busy ? null : () => _challengeFriend(friendChatId, name),
            child: Text(busy ? '…' : '🎮 Играть'),
          ),
          IconButton(
            icon: const Icon(Icons.person_remove_outlined, color: AgroColors.danger, size: 20),
            tooltip: 'Удалить из друзей',
            onPressed: () => _confirmDeleteFriend(friendChatId, name),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddFriendDialog() async {
    Haptics.tap();
    final queryCtrl = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool searching = false;
    String? error;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 16),
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              Future<void> runSearch() async {
                final q = queryCtrl.text.trim();
                if (q.isEmpty) return;
                setLocal(() {
                  searching = true;
                  error = null;
                });
                final res = await Api.instance.friendSearch(q);
                searching = false;
                if (res['ok'] != true) {
                  error = res['message']?.toString() ?? 'Не получилось';
                  results = [];
                } else {
                  results = ((res['results'] as List?) ?? []).cast<Map<String, dynamic>>();
                  if (results.isEmpty) error = 'Никого не нашлось.';
                }
                setLocal(() {});
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Добавить друга', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: queryCtrl,
                          autofocus: true,
                          decoration: const InputDecoration(hintText: 'Имя или ID друга', border: OutlineInputBorder()),
                          onSubmitted: (_) => runSearch(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: searching ? null : runSearch, child: const Text('Найти')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (searching) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: CircularProgressIndicator())
                  else if (error != null)
                    Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('⚠️ $error', style: const TextStyle(color: AgroColors.danger)))
                  else
                    ...results.map((r) {
                      final already = r['alreadyFriend'] == true;
                      return ListTile(
                        leading: ProfileAvatar(avatarId: r['avatarId']?.toString(), frameId: r['frameId']?.toString(), size: 38),
                        title: Text(r['name']?.toString() ?? '?'),
                        subtitle: r['friendCode'] != null ? Text('ID: ${r['friendCode']}', style: const TextStyle(fontSize: 11)) : null,
                        trailing: already
                            ? const Chip(label: Text('Уже друг'))
                            : FilledButton(
                                onPressed: () async {
                                  final addRes = await Api.instance.friendAdd((r['chatId'] as num).toInt());
                                  if (ctx.mounted) Navigator.of(ctx).pop();
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(addRes['ok'] == true ? 'Друг добавлен 🌾' : '⚠️ ${addRes['message']}')),
                                  );
                                  if (addRes['ok'] == true) _load(silent: true);
                                },
                                child: const Text('Добавить'),
                              ),
                      );
                    }),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteFriend(int friendChatId, String name) async {
    Haptics.tap();
    // Всегда подтверждение сразу — удаление необратимо стирает историю игр с этим другом, даже
    // если активной игры нет.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить $name из друзей?'),
        content: const Text('Вся статистика и история игр с этим другом удалится безвозвратно.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed != true) return;

    final res = await Api.instance.friendRemove(friendChatId);
    if (res['ok'] == true) {
      if (mounted) _load(silent: true);
      return;
    }
    if (res['hasOngoingGame'] != true) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ ${res['message'] ?? 'не получилось'}')));
      return;
    }

    if (!mounted) return;
    final confirmedEndGame = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Есть незавершённая игра'),
        content: Text('С $name сейчас идёт игра — удаление из друзей завершит и её. Продолжить?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Удалить и завершить игру')),
        ],
      ),
    );
    if (confirmedEndGame != true) return;
    final res2 = await Api.instance.friendRemove(friendChatId, endGame: true);
    if (!mounted) return;
    if (res2['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ ${res2['message'] ?? 'не получилось'}')));
      return;
    }
    _load(silent: true);
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
      leading: ProfileAvatar(avatarId: l['avatarId']?.toString(), frameId: l['frameId']?.toString(), size: 42),
      title: Text('$place. ${l['name']?.toString() ?? '?'}'),
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
