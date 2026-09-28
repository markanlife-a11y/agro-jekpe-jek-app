// Аватары и рамки — полностью программные (эмодзи + цвет + градиентная рамка), без внешних
// файлов-картинок: быстро, легко расширять, и уже сейчас закладывает основу для будущей
// монетизации (часть рамок/аватаров можно будет открывать за победы или покупкой).
import 'package:flutter/material.dart';

class AvatarOption {
  final String id;
  final String emoji;
  final Color color;
  const AvatarOption(this.id, this.emoji, this.color);
}

const List<AvatarOption> kAvatars = [
  AvatarOption('wheat', '🌾', Color(0xFFD9A441)),
  AvatarOption('sunflower', '🌻', Color(0xFFE3B23C)),
  AvatarOption('tractor', '🚜', Color(0xFF2E7D32)),
  AvatarOption('sprout', '🌱', Color(0xFF66BB6A)),
  AvatarOption('leaf', '🍃', Color(0xFF4CAF50)),
  AvatarOption('corn', '🌽', Color(0xFFF2C14E)),
  AvatarOption('bug', '🐛', Color(0xFF8D6E63)),
  AvatarOption('apple', '🍎', Color(0xFFC1462F)),
  AvatarOption('grapes', '🍇', Color(0xFF7B5CB0)),
  AvatarOption('cow', '🐄', Color(0xFF6D4C41)),
];

class FrameOption {
  final String id;
  final String label;
  final List<Color>? gradient; // null = без рамки
  final bool premium; // задел на монетизацию — пока просто визуальная пометка "🔒"
  const FrameOption(this.id, this.label, this.gradient, {this.premium = false});
}

const List<FrameOption> kFrames = [
  FrameOption('none', 'Без рамки', null),
  FrameOption('bronze', 'Бронза', [Color(0xFFCD7F32), Color(0xFF8C5A2B)]),
  FrameOption('silver', 'Серебро', [Color(0xFFC0C0C0), Color(0xFF8A8A8A)]),
  FrameOption('gold', 'Золото', [Color(0xFFFFD700), Color(0xFFB8860B)], premium: true),
  FrameOption('emerald', 'Изумруд', [Color(0xFF00C896), Color(0xFF00695C)], premium: true),
];

AvatarOption avatarById(String? id) => kAvatars.firstWhere((a) => a.id == id, orElse: () => kAvatars.first);
FrameOption frameById(String? id) => kFrames.firstWhere((f) => f.id == id, orElse: () => kFrames.first);

class ProfileAvatar extends StatelessWidget {
  final String? avatarId;
  final String? frameId;
  final double size;
  const ProfileAvatar({super.key, this.avatarId, this.frameId, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final avatar = avatarById(avatarId);
    final frame = frameById(frameId);
    final inner = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: avatar.color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(avatar.emoji, style: TextStyle(fontSize: size * 0.55)),
    );
    if (frame.gradient == null) return inner;
    return Container(
      padding: EdgeInsets.all(size * 0.08),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: frame.gradient!, begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: frame.gradient!.first.withOpacity(0.55), blurRadius: 8, spreadRadius: 0.5)],
      ),
      child: inner,
    );
  }
}
