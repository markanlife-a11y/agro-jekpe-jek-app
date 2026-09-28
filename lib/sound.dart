// Вибрация под каждое действие — встроенный Flutter HapticFeedback, без сторонних пакетов
// (пакет vibration оказался несовместим по Android-сборке с другими плагинами — жёстко
// зашит на старый compileSdk и конфликтовал при сборке; переиспользовать его не стали).
// heavyImpact() на большинстве телефонов ощутимо "тяжелее"/длиннее lightImpact()/
// mediumImpact() — неверный ответ ощущается дольше, верный короче, как и просили.
import 'package:flutter/services.dart';

class Haptics {
  static void tap() => HapticFeedback.lightImpact();
  static void nav() => HapticFeedback.selectionClick();

  /// Короткий отклик — верный ответ.
  static void correct() => HapticFeedback.mediumImpact();

  /// Более выраженный, "тяжёлый" отклик — неверный ответ (длиннее и заметнее, чем на верный).
  static void wrong() => HapticFeedback.heavyImpact();

  static void win() => HapticFeedback.mediumImpact();
  static void lose() => HapticFeedback.heavyImpact();
}
