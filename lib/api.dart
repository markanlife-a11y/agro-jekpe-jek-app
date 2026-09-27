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

  // --- Раунд/ответ/спор ---
  Future<Map<String, dynamic>> battlePlay(int battleId) => _post('/miniapp/api/battle/play', {'battleId': battleId});
  Future<Map<String, dynamic>> battleStatus(int battleId) => _post('/miniapp/api/battle/status', {'battleId': battleId});
  Future<Map<String, dynamic>> answerMcq(int quizId, int optionIndex) =>
      _post('/miniapp/api/battle/answer', {'quizId': quizId, 'optionIndex': optionIndex});
  Future<Map<String, dynamic>> answerOpen(int quizId, String text) =>
      _post('/miniapp/api/battle/answer', {'quizId': quizId, 'text': text});
  Future<Map<String, dynamic>> dispute(int quizId, String text) =>
      _post('/miniapp/api/battle/dispute', {'quizId': quizId, 'text': text});

  String photoUrl(String relativeUrl) => '$backendBaseUrl$relativeUrl';
}
