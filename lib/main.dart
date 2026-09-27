// Agro Jekpe-jek — первая тестовая сборка нативного Android-приложения.
//
// Задача этой версии — не игровой функционал (он будет добавляться дальше), а проверка всей
// цепочки целиком: реальный Flutter-проект (не веб-страница в обёртке), собранный в облаке
// (GitHub Actions, без локальной установки Android SDK) в .apk, который ставится и запускается
// на настоящем Android-телефоне и умеет обращаться к уже существующему бэкенду бота
// (Cloudflare Worker) по сети.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String backendBaseUrl = 'https://examagro-bot.markanlife.workers.dev';

void main() {
  runApp(const AgroJekpeJekApp());
}

class AgroJekpeJekApp extends StatelessWidget {
  const AgroJekpeJekApp({super.key});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF2E7D32);
    const gold = Color(0xFFD9A441);

    return MaterialApp(
      title: 'Agro Jekpe-jek',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: green, secondary: gold, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF4EFE2),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: green, secondary: gold, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF16211A),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _CheckStatus { idle, loading, ok, error }

class _HomeScreenState extends State<HomeScreen> {
  _CheckStatus _status = _CheckStatus.idle;
  String _resultText = '';

  Future<void> _checkServer() async {
    setState(() {
      _status = _CheckStatus.loading;
      _resultText = '';
    });
    try {
      final res = await http.get(Uri.parse('$backendBaseUrl/health')).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        setState(() {
          _status = _CheckStatus.ok;
          _resultText = res.body;
        });
      } else {
        setState(() {
          _status = _CheckStatus.error;
          _resultText = 'HTTP ${res.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _status = _CheckStatus.error;
        _resultText = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⚔️ Agro Jekpe-jek'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.secondary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'NATIVE TEST',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: scheme.onSecondary),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🌾 Первая тестовая сборка', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      const Text(
                        'Это настоящее нативное Android-приложение (Flutter), а не веб-страница '
                        'в обёртке — интерфейс отрисован собственными нативными виджетами. '
                        'Собрано в облаке (GitHub Actions), без локальной установки Android Studio.',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Дальше сюда добавится сама игра "Agro Jekpe-jek": вход через Telegram, '
                        'друзья, случайный соперник, вопросы (в т.ч. голосом) — используя тот же '
                        'бэкенд, что и бот в Telegram.',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _status == _CheckStatus.loading ? null : _checkServer,
                icon: const Icon(Icons.wifi_tethering),
                label: Text(_status == _CheckStatus.loading ? 'Проверяю…' : 'Проверить связь с сервером'),
              ),
              const SizedBox(height: 12),
              if (_status == _CheckStatus.ok)
                _ResultCard(
                  icon: Icons.check_circle,
                  color: Colors.green,
                  title: '✅ Сервер ответил',
                  text: _resultText,
                ),
              if (_status == _CheckStatus.error)
                _ResultCard(
                  icon: Icons.error,
                  color: Colors.red,
                  title: '⚠️ Не получилось достучаться',
                  text: _resultText,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String text;

  const _ResultCard({required this.icon, required this.color, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withOpacity(0.12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(text),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
