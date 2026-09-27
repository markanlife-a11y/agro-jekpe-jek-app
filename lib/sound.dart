// Вибрация под каждое действие — как и просили: неверный ответ короткой вибрацией не
// отделаешься, нужна именно РАЗНАЯ ДЛИТЕЛЬНОСТЬ (короткая на верный, длинная на неверный), а
// не просто разная "сила" — поэтому используется пакет vibration с явным duration в мс, а не
// только предустановленные HapticFeedback.*Impact() (у них нет параметра длительности).
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

class Haptics {
  static Future<void> _vibrate(int ms) async {
    try {
      final has = await Vibration.hasVibrator();
      if (has == true) {
        await Vibration.vibrate(duration: ms);
        return;
      }
    } catch (_) {
      // нет доступа к вибромотору (эмулятор и т.п.) — тихо игнорируем
    }
  }

  static void tap() => HapticFeedback.lightImpact();
  static void nav() => HapticFeedback.selectionClick();

  /// Короткая вибрация — верный ответ.
  static void correct() {
    HapticFeedback.mediumImpact();
    _vibrate(60);
  }

  /// Длинная вибрация — неверный ответ (как и просили: длиннее, чем на верный).
  static void wrong() {
    HapticFeedback.heavyImpact();
    _vibrate(350);
  }

  static void win() => _vibrate(80);
  static void lose() => _vibrate(300);
}
