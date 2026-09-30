// Клиент бэкенда — того же Cloudflare Worker, что и Telegram-бот и мини-апп внутри Telegram
// (src/miniapp.ts). Отдельная синхронизация не нужна: это один и тот же сервер и база данных.
//
// Авторизация — sessionToken (см. src/miniappLoginPage.ts, "Вход через Telegram Login Widget"),
// а не Telegram.WebApp.initData — у нативного приложения его просто нет.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String backendBaseUrl = 'https://examagro-bot.markanlife.workers.dev';
const String loginPageUrl = '$backendBaseUrl/miniapp/login';

class Api {
  Api._();
  static final Api instance = Api._();

  String? _sessionToken;

  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionToken = prefs.getString('sessionToken');
  }

  bool get isLoggedIn => _sessionToken != null && _sessionToken!.isNotEmpty;

  Future<void> setSession(String token) async {
    _sessionToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sessionToken', token);
  }

  Future<void> clearSession() async {
    _sessionToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sessionToken');
  }

  Future<Map<String, dynamic>> _post(String path, [Map<String, dynamic>? params]) async {
    final payload = <String, dynamic>{
      if (_sessionToken != null) 'sessionToken': _sessionToken,
      ...?params,
    };
    try {
      final res = await http
          .post(
            Uri.parse('$backendBaseUrl$path'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'ok': false, 'message': 'Некорректный ответ сервера.'};
    } catch (e) {
      return {'ok': false, 'message': 'Ошибка сети: $e'};
    }
  }

  // --- Вход ---
  Future<Map<String, dynamic>> logout() => _post('/miniapp/api/auth/logout');

  Future<Map<String, dynamic>> registerEmail(String email, String password, String displayName) =>
      _post('/miniapp/api/auth/register', {'email': email, 'password': password, 'displayName': displayName});

  Future<Map<String, dynamic>> loginEmail(String email, String password) =>
      _post('/miniapp/api/auth/login', {'email': email, 'password': password});

  // Привязка Telegram — код + обычная ссылка t.me/bot?start=link_<code>, открывается системой
  // напрямую (никакого WebView): надёжнее, чем Telegram Login Widget в WebView, который на
  // практике не всегда возвращал подтверждение обратно в приложение.
  Future<Map<String, dynamic>> telegramLinkCode() => _post('/miniapp/api/auth/telegram-link-code');
  Future<Map<String, dynamic>> telegramLinkStatus(String code) => _post('/miniapp/api/auth/telegram-link-status', {'code': code});
  Future<Map<String, dynamic>> telegramUnlink() => _post('/miniapp/api/auth/telegram-unlink');

  // Вход через Telegram прямо с экрана логина — тот же код+ссылка механизм, но БЕЗ авторизации
  // (это и есть способ авторизоваться) и без email-аккаунта: как только бот подтвердит код,
  // сразу выдаётся сессия для настоящего chat_id.
  Future<Map<String, dynamic>> telegramLoginCode() => _post('/miniapp/api/auth/telegram-login-code');
  Future<Map<String, dynamic>> telegramLoginStatus(String code) => _post('/miniapp/api/auth/telegram-login-status', {'code': code});

  Future<Map<String, dynamic>> updateProfile({String? avatarId, String? frameId, String? displayName}) =>
      _post('/miniapp/api/profile/update', {'avatarId': avatarId, 'frameId': frameId, if (displayName != null) 'displayName': displayName});

  // Обратная привязка — почта+пароль ДЛЯ Telegram-аккаунта (на случай, если забудут доступ к
  // Telegram): резолвится в тот же chat_id, а не заводит параллельный аккаунт.
  Future<Map<String, dynamic>> linkEmail(String email, String password) =>
      _post('/miniapp/api/auth/link-email', {'email': email, 'password': password});
  Future<Map<String, dynamic>> unlinkEmail() => _post('/miniapp/api/auth/unlink-email');

  // --- Главный экран ---
  Future<Map<String, dynamic>> me() => _post('/miniapp/api/me');

  // --- Случайный соперник ---
  Future<Map<String, dynamic>> randomStart() => _post('/miniapp/api/random/start');
  Future<Map<String, dynamic>> randomStatus() => _post('/miniapp/api/random/status');
  Future<Map<String, dynamic>> randomCancel() => _post('/miniapp/api/random/cancel');

  // --- Приглашение по ссылке / вызов друга ---
  Future<Map<String, dynamic>> inviteCreate() => _post('/miniapp/api/invite/create');
  Future<Map<String, dynamic>> inviteAccept(String code) => _post('/miniapp/api/invite/accept', {'code': code});
  Future<Map<String, dynamic>> friendChallenge(int friendChatId) =>
      _post('/miniapp/api/friends/challenge', {'friendChatId': friendChatId});
  // Поиск/добавление/удаление друга напрямую — по имени или его личному коду, без совместной
  // игры (раньше единственным способом попасть в друзья была сыгранная партия).
  Future<Map<String, dynamic>> friendSearch(String query) => _post('/miniapp/api/friends/search', {'query': query});
  Future<Map<String, dynamic>> friendAdd(int friendChatId) => _post('/miniapp/api/friends/add', {'friendChatId': friendChatId});
  Future<Map<String, dynamic>> friendRemove(int friendChatId, {bool endGame = false}) =>
      _post('/miniapp/api/friends/remove', {'friendChatId': friendChatId, 'endGame': endGame});

  // --- Раунд/ответ/спор ---
  Future<Map<String, dynamic>> battlePlay(int battleId) => _post('/miniapp/api/battle/play', {'battleId': battleId});
  Future<Map<String, dynamic>> battleStatus(int battleId) => _post('/miniapp/api/battle/status', {'battleId': battleId});
  Future<Map<String, dynamic>> answerMcq(int quizId, int optionIndex) =>
      _post('/miniapp/api/battle/answer', {'quizId': quizId, 'optionIndex': optionIndex});
  Future<Map<String, dynamic>> answerTimeout(int quizId) =>
      _post('/miniapp/api/battle/answer', {'quizId': quizId, 'timedOut': true});
  Future<Map<String, dynamic>> answerOpen(int quizId, String text) =>
      _post('/miniapp/api/battle/answer', {'quizId': quizId, 'text': text});
  // Голос — настоящее аудио уходит прямо в Gemini на бэкенде (та же схема, что и у голосовых
  // сообщений в чате), а не распознанный на устройстве текст — надёжнее: см. lib/game_screen.dart.
  Future<Map<String, dynamic>> answerOpenAudio(int quizId, String audioBase64, String mimeType) =>
      _post('/miniapp/api/battle/answer', {'quizId': quizId, 'audioBase64': audioBase64, 'audioMimeType': mimeType});
  Future<Map<String, dynamic>> dispute(int quizId, String text) =>
      _post('/miniapp/api/battle/dispute', {'quizId': quizId, 'text': text});

  String photoUrl(String relativeUrl) => '$backendBaseUrl$relativeUrl';
}
