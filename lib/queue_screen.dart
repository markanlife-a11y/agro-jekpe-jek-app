// Поиск случайного соперника — опрашивает /random/status, пока не найдётся матч.
import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'sound.dart';
import 'game_screen.dart';

class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  Timer? _timer;
  String? _error;
  bool _matched = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final res = await Api.instance.randomStart();
    _handle(res);
  }

  void _poll() {
    _timer ??= Timer.periodic(const Duration(seconds: 3), (_) async {
      final res = await Api.instance.randomStatus();
      _handle(res);
    });
  }

  void _handle(Map<String, dynamic> res) {
    if (!mounted || _matched) return;
    final status = res['status'];
    if (status == 'matched') {
      _matched = true;
      _timer?.cancel();
      Haptics.correct();
      final battleId = (res['battleId'] as num).toInt();
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => GameScreen(battleId: battleId)));
    } else if (status == 'error') {
      _timer?.cancel();
      setState(() => _error = res['message']?.toString() ?? 'Не получилось найти соперника.');
    } else {
      _poll();
    }
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    await Api.instance.randomCancel();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Поиск соперника')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _error == null
                ? [
                    const ThinkingIndicator(label: 'Ищем соперника…'),
                    const SizedBox(height: 12),
                    const Text('Обычно занимает пару секунд, если сейчас кто-то ещё в поиске.', textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    OutlinedButton(onPressed: _cancel, child: const Text('❌ Отменить поиск')),
                  ]
                : [
                    Text('⚠️ $_error', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Назад')),
                  ],
          ),
        ),
      ),
    );
  }
}
