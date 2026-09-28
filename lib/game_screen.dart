// Сам раунд баттла — вопрос (MCQ или открытый), ответ, вердикт, спор, переход между раундами
// и итог игры. Открытый вопрос слушает пользователя СРАЗУ, без нажатия кнопок — распознавание
// речи само определяет конец фразы по паузе (см. _startListening, pauseFor) и отправляет ответ.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'api.dart';
import 'sound.dart';
import 'audio.dart';
import 'theme.dart';
import 'home_screen.dart';

enum _Phase { loading, question, grading, verdict, waitingOpponent, roundSummary, finalResult, error }

class GameScreen extends StatefulWidget {
  final int battleId;
  const GameScreen({super.key, required this.battleId});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  _Phase _phase = _Phase.loading;
  String _errorMessage = '';

  int? _quizId;
  int _round = 0;
  int _totalRounds = 0;
  Map<String, dynamic>? _item; // текущий вопрос
  Map<String, dynamic>? _answerRes; // ответ /battle/answer (вердикт)
  Map<String, dynamic>? _disputeReply;
  Map<String, dynamic>? _statusRes; // /battle/status (ожидание/финал)

  final TextEditingController _openAnswerCtrl = TextEditingController();
  final TextEditingController _disputeCtrl = TextEditingController();
  int? _selectedOption;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;
  bool _speechDenied = false;
  String _partialTranscript = '';

  Timer? _pollTimer;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    GameAudio.instance.playBattleStart();
    _loadCurrent();
  }

  @override
  void dispose() {
    GameAudio.instance.stopAll();
    _pollTimer?.cancel();
    _speech.stop();
    _openAnswerCtrl.dispose();
    _disputeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrent() async {
    setState(() => _phase = _Phase.loading);
    final res = await Api.instance.battlePlay(widget.battleId);
    if (!mounted) return;
    if (res['ok'] != true) {
      setState(() {
        _phase = _Phase.error;
        _errorMessage = res['message']?.toString() ?? 'Не получилось загрузить раунд.';
      });
      return;
    }
    _quizId = res['quizId'] as int?;
    _round = (res['round'] as num?)?.toInt() ?? 0;
    _totalRounds = (res['totalRounds'] as num?)?.toInt() ?? 0;
    if (res['finished'] == true) {
      await _checkStatus();
      return;
    }
    setState(() {
      _item = (res['item'] as Map).cast<String, dynamic>();
      _answerRes = null;
      _disputeReply = null;
      _selectedOption = null;
      _openAnswerCtrl.clear();
      _partialTranscript = '';
      _phase = _Phase.question;
    });
    if (_item?['type'] == 'open') {
      _beginListening();
    }
  }

  Future<void> _checkStatus() async {
    final res = await Api.instance.battleStatus(widget.battleId);
    if (!mounted) return;
    _statusRes = res;
    if (res['ok'] != true) {
      setState(() {
        _phase = _Phase.error;
        _errorMessage = res['message']?.toString() ?? 'Игра недоступна.';
      });
      return;
    }
    if (res['status'] == 'finished') {
      _pollTimer?.cancel();
      final outcome = (res['final']?['outcome'] ?? '') as String;
      if (outcome == 'win') {
        Haptics.win();
      } else if (outcome == 'lose') {
        Haptics.lose();
      }
      setState(() => _phase = _Phase.finalResult);
      return;
    }
    if (res['status'] == 'active' && res['myTurn'] == true && res['alreadyStarted'] != true) {
      _pollTimer?.cancel();
      Haptics.correct();
      await _loadCurrent();
      return;
    }
    setState(() => _phase = _Phase.waitingOpponent);
    _pollTimer ??= Timer.periodic(const Duration(seconds: 4), (_) => _checkStatus());
  }

  // ---------------- Голос (открытые вопросы) ----------------

  Future<void> _beginListening() async {
    setState(() {
      _speechDenied = false;
      _partialTranscript = '';
    });
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      setState(() => _speechDenied = true);
      return;
    }
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted && _listening) {
            setState(() => _listening = false);
          }
        }
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!available) {
      setState(() => _speechDenied = true);
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      localeId: 'ru_RU',
      onResult: (result) {
        if (!mounted) return;
        setState(() => _partialTranscript = result.recognizedWords);
        if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
          _submitOpenAnswer(result.recognizedWords.trim());
        }
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: true,
    );
  }

  void _stopListeningManually() {
    _speech.stop();
    setState(() => _listening = false);
    if (_partialTranscript.trim().isNotEmpty) {
      _submitOpenAnswer(_partialTranscript.trim());
    }
  }

  // ---------------- Ответ / вердикт ----------------

  Future<void> _submitMcq(int optionIndex) async {
    if (_submitting || _quizId == null) return;
    Haptics.tap();
    setState(() {
      _submitting = true;
      _selectedOption = optionIndex;
      _phase = _Phase.grading;
    });
    final res = await Api.instance.answerMcq(_quizId!, optionIndex);
    _onAnswerResult(res);
  }

  Future<void> _submitOpenAnswer(String text) async {
    if (_submitting || _quizId == null || text.trim().isEmpty) return;
    _speech.stop();
    setState(() {
      _submitting = true;
      _listening = false;
      _phase = _Phase.grading;
    });
    final res = await Api.instance.answerOpen(_quizId!, text.trim());
    _onAnswerResult(res);
  }

  void _onAnswerResult(Map<String, dynamic> res) {
    if (!mounted) return;
    _submitting = false;
    if (res['ok'] != true) {
      setState(() {
        _phase = _Phase.error;
        _errorMessage = res['message']?.toString() ?? 'Не получилось отправить ответ.';
      });
      return;
    }
    if (res['correct'] == true) {
      Haptics.correct();
    } else {
      Haptics.wrong();
    }
    setState(() {
      _answerRes = res;
      _phase = _Phase.verdict;
    });
  }

  Future<void> _sendDispute(String text) async {
    if (text.trim().isEmpty || _quizId == null) return;
    Haptics.tap();
    final res = await Api.instance.dispute(_quizId!, text.trim());
    if (!mounted) return;
    if (res['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ ${res['message'] ?? 'не получилось'}')));
      return;
    }
    if (res['verdictChanged'] == true) Haptics.correct();
    setState(() {
      _disputeReply = res;
      if (res['verdictChanged'] == true && _answerRes != null) {
        _answerRes = {..._answerRes!, 'correct': true};
      }
    });
  }

  Future<void> _next() async {
    Haptics.nav();
    final res = _answerRes;
    if (res == null) return;
    if (res['roundFinished'] == true) {
      if (res['battleFinished'] == true) {
        final outcome = (res['final']?['outcome'] ?? '') as String;
        if (outcome == 'win') {
          Haptics.win();
        } else if (outcome == 'lose') {
          Haptics.lose();
        }
        setState(() => _phase = _Phase.finalResult);
        return;
      }
      final round = res['round'] as Map<String, dynamic>?;
      if (round != null && round['opponentScore'] == null) {
        setState(() => _phase = _Phase.waitingOpponent);
        _pollTimer ??= Timer.periodic(const Duration(seconds: 4), (_) => _checkStatus());
        return;
      }
      setState(() => _phase = _Phase.roundSummary);
      return;
    }
    await _loadCurrent();
  }

  void _backHome() {
    _pollTimer?.cancel();
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeScreen()), (route) => false);
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('⚔️ Раунд ${_round + 1}/${_totalRounds == 0 ? '?' : _totalRounds}'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: _backHome),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.loading:
      case _Phase.grading:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(_phase == _Phase.grading ? 'Проверяю ответ…' : 'Загружаю…'),
            ],
          ),
        );
      case _Phase.question:
        return _buildQuestion();
      case _Phase.verdict:
        return _buildVerdict();
      case _Phase.waitingOpponent:
        return _buildWaiting();
      case _Phase.roundSummary:
        return _buildRoundSummary();
      case _Phase.finalResult:
        return _buildFinal();
      case _Phase.error:
        return _buildError();
    }
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AgroColors.danger, size: 40),
            const SizedBox(height: 12),
            Text(_errorMessage, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(onPressed: _backHome, child: const Text('На главный экран')),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion() {
    final item = _item!;
    final type = item['type'] as String;
    final idx = (item['idx'] as num).toInt();
    final total = (item['total'] as num).toInt();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _progressBar(idx, total),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _categoryTag(item['category']?.toString() ?? ''),
                  if (item['photoUrl'] != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(Api.instance.photoUrl(item['photoUrl'] as String), fit: BoxFit.cover, height: 200, width: double.infinity),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(item['question']?.toString() ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (type == 'mcq') _buildMcqOptions(item) else _buildOpenAnswer(),
        ],
      ),
    );
  }

  Widget _buildMcqOptions(Map<String, dynamic> item) {
    final options = (item['options'] as List).cast<dynamic>();
    return Column(
      children: List.generate(options.length, (i) {
        final letter = String.fromCharCode(65 + i);
        return Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: OutlinedButton(
            onPressed: () => _submitMcq(i),
            style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
            child: Row(
              children: [
                CircleAvatar(radius: 12, backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest, child: Text(letter, style: const TextStyle(fontSize: 12))),
                const SizedBox(width: 10),
                Expanded(child: Text(options[i].toString())),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildOpenAnswer() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_speechDenied) ...[
              const Icon(Icons.mic_off, size: 36, color: AgroColors.danger),
              const SizedBox(height: 8),
              const Text('Нет доступа к микрофону — разрешите его в настройках телефона для этого приложения, или напечатайте ответ ниже.', textAlign: TextAlign.center),
            ] else ...[
              Icon(_listening ? Icons.mic : Icons.mic_none, size: 44, color: _listening ? AgroColors.green : Colors.grey),
              const SizedBox(height: 8),
              Text(_listening ? '🎤 Слушаю…' : 'Микрофон выключен', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text(_partialTranscript.isEmpty ? 'Говорите — ответ отправится сам, как только вы замолчите.' : _partialTranscript, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              if (_listening)
                OutlinedButton.icon(onPressed: _stopListeningManually, icon: const Icon(Icons.stop), label: const Text('Готово, отправить'))
              else
                FilledButton.icon(onPressed: _beginListening, icon: const Icon(Icons.mic), label: const Text('Начать заново')),
            ],
            const Divider(height: 28),
            TextField(
              controller: _openAnswerCtrl,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Или напечатайте ответ здесь…', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _submitOpenAnswer(_openAnswerCtrl.text),
                child: const Text('Отправить текст'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerdict() {
    final res = _answerRes!;
    final correct = res['correct'] == true;
    final canDispute = res['canDispute'] == true && _disputeReply == null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: (correct ? AgroColors.green : AgroColors.danger).withOpacity(0.12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(correct ? '✅ Верно' : '❌ Не засчитано', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text(res['explanation']?.toString() ?? ''),
                ],
              ),
            ),
          ),
          if (res['friendNote'] != null) ...[
            const SizedBox(height: 10),
            Card(child: Padding(padding: const EdgeInsets.all(12), child: Text('👥 ${res['friendNote']}'))),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              if (canDispute) Expanded(child: OutlinedButton(onPressed: _showDisputeSheet, child: const Text('⚖️ Оспорить'))),
              if (canDispute) const SizedBox(width: 10),
              Expanded(child: FilledButton(onPressed: _next, child: const Text('➡️ Далее'))),
            ],
          ),
          if (_disputeReply != null) ...[
            const SizedBox(height: 14),
            if (_disputeReply!['verdictChanged'] == true)
              const Padding(padding: EdgeInsets.only(bottom: 6), child: Text('🔄 Вердикт пересмотрен на «Засчитано»', style: TextStyle(color: AgroColors.green, fontWeight: FontWeight.bold))),
            Card(child: Padding(padding: const EdgeInsets.all(12), child: Text('🌾 ${_disputeReply!['reply']}'))),
          ],
        ],
      ),
    );
  }

  void _showDisputeSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('С чем именно вы не согласны?', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              TextField(controller: _disputeCtrl, maxLines: 3, autofocus: true, decoration: const InputDecoration(border: OutlineInputBorder())),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _sendDispute(_disputeCtrl.text);
                    _disputeCtrl.clear();
                  },
                  child: const Text('Отправить'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWaiting() {
    final opponentName = _statusRes?['opponentName']?.toString() ?? 'соперника';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            const Text('✅ Ваши ответы приняты!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Text('Ждём $opponentName — обновится само, как только доиграет.', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            OutlinedButton(onPressed: _backHome, child: const Text('На главный экран')),
          ],
        ),
      ),
    );
  }

  Widget _buildRoundSummary() {
    final round = _answerRes!['round'] as Map<String, dynamic>;
    final myScore = round['myScore'];
    final opponentScore = round['opponentScore'];
    final myTurnNext = round['myTurnNext'] == true;
    final opponentName = round['opponentName']?.toString() ?? 'соперник';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🌾', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 8),
            const Text('Раунд завершён!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('$myScore : $opponentScore', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
            Text('Счёт раунда против $opponentName.'),
            const SizedBox(height: 20),
            if (myTurnNext)
              SizedBox(width: double.infinity, child: FilledButton(onPressed: _loadCurrent, child: const Text('▶️ Играть дальше')))
            else ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 8),
              Text('Ждём ход $opponentName…'),
            ],
            const SizedBox(height: 14),
            OutlinedButton(onPressed: _backHome, child: const Text('На главный экран')),
          ],
        ),
      ),
    );
  }

  Widget _buildFinal() {
    final finalRes = (_answerRes?['final'] ?? _statusRes?['final']) as Map<String, dynamic>?;
    if (finalRes == null) return _buildError();
    final outcome = finalRes['outcome'] as String;
    final myScore = finalRes['myScore'];
    final opponentScore = finalRes['opponentScore'];
    final opponentName = finalRes['opponentName']?.toString() ?? 'соперник';
    final opponentChatId = (finalRes['opponentChatId'] as num?)?.toInt();
    final emoji = outcome == 'win' ? '🏆' : outcome == 'lose' ? '😔' : '🤝';
    final title = outcome == 'win' ? 'Победа!' : outcome == 'lose' ? 'Поражение' : 'Ничья!';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 8),
            Text('Игра окончена — $title', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('$myScore : $opponentScore', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
            Text('Итог против $opponentName.'),
            const SizedBox(height: 20),
            if (opponentChatId != null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: () async {
                    final res = await Api.instance.friendChallenge(opponentChatId);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(res['ok'] == true ? 'Вызов на реванш отправлен 🌾' : '⚠️ ${res['message']}')),
                    );
                    if (res['ok'] == true) _backHome();
                  },
                  child: Text('🔄 Реванш с $opponentName'),
                ),
              ),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: OutlinedButton(onPressed: _backHome, child: const Text('На главный экран'))),
          ],
        ),
      ),
    );
  }

  Widget _progressBar(int idx, int total) {
    final value = total == 0 ? 0.0 : idx / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text('Раунд ${_round + 1}/$_totalRounds'), Text('Вопрос ${idx + 1}/$total')],
        ),
        const SizedBox(height: 6),
        ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: value, minHeight: 7)),
      ],
    );
  }

  Widget _categoryTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: AgroColors.green.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: const TextStyle(color: AgroColors.greenDark, fontWeight: FontWeight.bold, fontSize: 11.5)),
    );
  }
}
