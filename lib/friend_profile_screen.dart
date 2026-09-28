// Профиль друга — жалоба: "в профиль друзей нельзя заходить, чтобы посмотреть их статистику".
// Данные те же, что уже приходят в списке друзей (/miniapp/api/me) — просто отдельный крупный
// экран вместо строки в списке, плюс вызов на батл прямо отсюда.
import 'package:flutter/material.dart';
import 'api.dart';
import 'sound.dart';
import 'theme.dart';
import 'profile_assets.dart';

class FriendProfileScreen extends StatefulWidget {
  final Map<String, dynamic> friend; // {name, friendChatId, avatarId, frameId, gamesPlayed, wins, losses, draws}
  const FriendProfileScreen({super.key, required this.friend});

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  bool _busy = false;

  Future<void> _challenge() async {
    Haptics.tap();
    setState(() => _busy = true);
    final friendChatId = (widget.friend['friendChatId'] as num).toInt();
    final res = await Api.instance.friendChallenge(friendChatId);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res['ok'] == true ? 'Вызов отправлен — ждём ответа 🌾' : '⚠️ ${res['message']}')),
    );
    if (res['ok'] == true) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.friend;
    final name = f['name']?.toString() ?? '?';
    final gamesPlayed = (f['gamesPlayed'] as num?)?.toInt() ?? 0;
    final wins = (f['wins'] as num?)?.toInt() ?? 0;
    final losses = (f['losses'] as num?)?.toInt() ?? 0;
    final draws = (f['draws'] as num?)?.toInt() ?? 0;
    final winRate = gamesPlayed == 0 ? 0 : (wins * 100 / gamesPlayed).round();

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(child: ProfileAvatar(avatarId: f['avatarId']?.toString(), frameId: f['frameId']?.toString(), size: 96)),
          const SizedBox(height: 12),
          Center(child: Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          const SizedBox(height: 24),
          Row(
            children: [
              _statCard('Игр', '$gamesPlayed', AgroColors.brown),
              const SizedBox(width: 10),
              _statCard('Побед', '$wins', AgroColors.green),
              const SizedBox(width: 10),
              _statCard('Поражений', '$losses', AgroColors.danger),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _statCard('Ничьих', '$draws', AgroColors.goldDark),
              const SizedBox(width: 10),
              _statCard('% побед', '$winRate%', AgroColors.greenDark),
            ],
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _challenge,
              icon: const Icon(Icons.sports_kabaddi),
              label: Text(_busy ? 'Отправляю…' : '🎮 Вызвать на батл'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Expanded(
      child: Card(
        color: color.withOpacity(0.10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
