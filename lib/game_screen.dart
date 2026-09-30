// Сам раунд баттла — вопрос (MCQ или открытый), ответ, вердикт, спор, переход между раундами
// и итог игры. Открытый вопрос слушает пользователя СРАЗУ, без нажатия кнопок — запись начинается
// автоматически при показе вопроса; ЗАВЕРШАЕТ её явная кнопка "Готово" (или таймер-потолок), а не
// распознавание пауз в речи — распознавание речи на устройстве (speech_to_text) было убрано
// целиком: именно оно было источником постоянных "голосовой не работает" (молча не запускало
// listen() на части устройств/прошивок без всякой диагностируемой причины). Вместо этого
// записывается настоящее аудио и уходит прямо в Gemini на бэкенде (тот же способ, что и у
// голосовых сообщений в чат-боте) — надёжнее и не зависит от стороннего движка распознавания.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'api.dart';
import 'sound.dart';
import 'theme.dart';
import 'profile_assets.dart';
import 'home_screen.dart';

enum _Phase { loading, question, grading, verdict, waitingOpponent, roundSummary, finalResult, error }

class GameScreen extends StatefulWidget {
  final int battleId;
  const GameScreen({super.key, required this.battleId});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
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
  bool _wasTimeout = false; // не успели ответить на MCQ до истечения таймера — см. _buildResultPanel

  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  // Между тапом/автозапуском и реальным стартом записи — жалоба: "сразу после вопроса он не
  // пишет что слушает", раньше в этот промежуток экран выглядел мёртвым.
  bool _recordStarting = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  bool _micDenied = false;
  // Отдельно от простого отказа — если пользователь один раз отказал совсем (или это уже не
  // первый показ системного диалога), Android больше НЕ показывает диалог запроса вообще, и
  // request() просто молча возвращает "отказано" — единственный выход тогда открыть настройки
  // приложения вручную (жалоба: "при запуске не просит разрешение").
  bool _micPermanentlyDenied = false;
  static const int _maxRecordSeconds = 45;

  Timer? _pollTimer;
  bool _submitting = false;

  // 40-секундный таймер на MCQ-вопрос — при истечении сам шлёт "тайм-аут" (засчитывается
  // неверным, без выбранного варианта). Для открытых вопросов не используется — там уже свой
  // голосовой темп (пауза определяет конец фразы). Переход к следующему вопросу — только по
  // кнопке "Далее", без автоперехода по таймеру (жалоба: "автоперехода не надо").
  AnimationController? _questionTimer;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _questionTimer?.dispose();
    _recordTimer?.cancel();
    if (_recording) _recorder.stop();
    _recorder.dispose();
    _openAnswerCtrl.dispose();
    _disputeCtrl.dispose();
    super.dispose();
  }

  void _startQuestionTimer() {
    _questionTimer?.dispose();
    final ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 40));
    _questionTimer = ctrl;
    ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) _onQuestionTimeout();
    });
    ctrl.forward();
  }

  Future<void> _onQuestionTimeout() async {
    if (_submitting || _phase != _Phase.question || _quizId == null) return;
    Haptics.wrong();
    setState(() {
      _submitting = true;
      _selectedOption = null;
      _wasTimeout = true;
      _phase = _Phase.grading;
    });
    final res = await Api.instance.answerTimeout(_quizId!);
    _onAnswerResult(res);
  }

  Future<void> _loadCurrent() async {
    _questionTimer?.stop();
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
      _wasTimeout = false;
      _openAnswerCtrl.clear();
      _phase = _Phase.question;
    });
    if (_item?['type'] == 'open') {
      _beginListening();
    } else {
      _startQuestionTimer();
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

  // ---------------- Голос (открытые вопросы) — запись аудио, отправка в Gemini -------------

  Future<void> _beginListening() async {
    setState(() {
      _micDenied = false;
      _micPermanentlyDenied = false;
      _recordStarting = true; // сразу что-то показываем, не дожидаясь реального старта записи
    });
    // record сам разберётся с системным запросом разрешения — но если оно уже "запрещено
    // навсегда" (см. _micPermanentlyDenied), система больше НЕ покажет диалог, а request()
    // молча вернёт false: единственный выход тогда — кнопка "Открыть настройки" в UI ниже.
    bool granted = false;
    try {
      granted = await _recorder.hasPermission();
    } catch (_) {}
    if (!mounted) return;
    if (!granted) {
      final status = await Permission.microphone.status;
      setState(() {
        _micDenied = true;
        _micPermanentlyDenied = status.isPermanentlyDenied;
        _recordStarting = false;
      });
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/answer_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    } catch (_) {
      if (!mounted) return;
      setState(() { _micDenied = true; _recordStarting = false; });
      return;
    }
    if (!mounted) return;
    setState(() {
      _recording = true;
      _recordStarting = false;
      _recordSeconds = 0;
    });
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _recordSeconds++);
      // Потолок на случай, если забыли/не смогли нажать "Готово" — запись не должна идти вечно.
      if (_recordSeconds >= _maxRecordSeconds) _stopListeningManually();
    });
  }

  Future<void> _stopListeningManually() async {
    if (!_recording) return;
    _recordTimer?.cancel();
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _recording = false);
    if (path == null) return;
    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.isEmpty) return;
      await _submitOpenAnswerAudio(base64Encode(bytes));
    } catch (_) {}
  }

  // ---------------- Ответ / вердикт ----------------

  Future<void> _submitMcq(int optionIndex) async {
    if (_submitting || _quizId == null) return;
    Haptics.tap();
    _questionTimer?.stop();
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
    if (_recording) {
      _recordTimer?.cancel();
      try {
        await _recorder.stop();
      } catch (_) {}
    }
    setState(() {
      _submitting = true;
      _recording = false;
      _phase = _Phase.grading;
    });
    final res = await Api.instance.answerOpen(_quizId!, text.trim());
    _onAnswerResult(res);
  }

  Future<void> _submitOpenAnswerAudio(String audioBase64) async {
    if (_submitting || _quizId == null) return;
    setState(() {
      _submitting = true;
      _phase = _Phase.grading;
    });
    final res = await Api.instance.answerOpenAudio(_quizId!, audioBase64, 'audio/aac');
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
        return const Center(child: ThinkingIndicator(label: 'Загружаю…'));
      // Раньше "Проверяю ответ" полностью подменяло экран отдельной страницей-вердиктом —
      // топорно и рывком. Теперь вопрос и карточки вариантов остаются на месте всё время,
      // проверка и вердикт просто анимированно достраиваются под ними на том же экране.
      case _Phase.question:
      case _Phase.grading:
      case _Phase.verdict:
        return _buildQuestion();
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
    final locked = _phase != _Phase.question; // grading или verdict — карточки больше не тапаются

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _progressBar(idx, total),
          if (type == 'mcq' && _questionTimer != null) ...[
            const SizedBox(height: 10),
            _QuestionTimerBar(controller: _questionTimer!, locked: locked),
          ],
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
          if (type == 'mcq') _buildMcqGrid(item) else _buildOpenAnswer(),
          AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: locked ? _buildResultPanel() : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  // 2 карточки в ряд, плоские залитые цветом (жалоба: "ответы должны быть по два в ряд", "нужен
  // минималистичный дизайн, как в Борьба умов") — после ответа карточка подсветится сама
  // (зелёным/красным), правильный вариант тоже подсвечивается зелёным, если выбран был не он,
  // остальные гаснут; ответ друга (если уже ответил в этом раунде первым) отмечается маленьким
  // круглым аватаром на той карточке, которую он выбрал (жалоба: текстовый бейдж с именем
  // перекрывал сам текст варианта — круглая картинка компактнее и привычнее, как в референсе).
  // Текст — AutoSizeText: сам ужимает шрифт под карточку вместо обрезки многоточием.
  Widget _buildMcqGrid(Map<String, dynamic> item) {
    final options = (item['options'] as List).cast<dynamic>();
    final locked = _phase != _Phase.question;
    final grading = _phase == _Phase.grading;
    final correctIndex = locked ? (_answerRes?['correctIndex'] as num?)?.toInt() : null;
    final friendText = locked ? (_answerRes?['friendAnswerText'] as String?) : null;
    final friendAvatarId = _answerRes?['friendAvatarId'] as String?;
    final friendFrameId = _answerRes?['friendFrameId'] as String?;
    int? friendIdx;
    if (friendText != null) {
      final i = options.indexWhere((o) => o.toString() == friendText);
      if (i >= 0) friendIdx = i;
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: options.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.2,
      ),
      itemBuilder: (context, i) {
        final isSelected = _selectedOption == i;
        final isCorrectCard = locked && correctIndex != null && i == correctIndex;
        final isWrongSelected = locked && isSelected && correctIndex != null && i != correctIndex;
        final isFriendCard = friendIdx == i;
        final dimmed = locked && !isCorrectCard && !isWrongSelected;

        Color bg;
        Color textColor;
        if (isCorrectCard) {
          bg = AgroColors.green;
          textColor = Colors.white;
        } else if (isWrongSelected) {
          bg = AgroColors.danger;
          textColor = Colors.white;
        } else if (dimmed) {
          bg = Colors.grey.withOpacity(0.16);
          textColor = Colors.black45;
        } else {
          // Ещё не отвечено — один и тот же цвет у всех 4 карточек (жалоба: "почему карточки
          // разного цвета, половина зелёная половина жёлтая" — разные тона путали, что это
          // такое; плоская заливка вместо тонкой обводки осталась, но единая).
          bg = AgroColors.green;
          textColor = Colors.white;
        }

        return _AnswerCard(
          text: options[i].toString(),
          background: bg,
          textColor: textColor,
          pulsing: grading && isSelected,
          showCorrectIcon: isCorrectCard,
          showWrongIcon: isWrongSelected,
          friendAvatarId: isFriendCard ? friendAvatarId : null,
          friendFrameId: isFriendCard ? friendFrameId : null,
          showFriendMarker: isFriendCard,
          cornerIndex: i,
          onTap: locked ? null : () => _submitMcq(i),
        );
      },
    );
  }

  // Появляется анимированно под карточками — сразу разбор с оспариванием/переходом дальше.
  // Раньше это была ОТДЕЛЬНАЯ страница-вердикт (смена экрана ощущалась рывком) с текстовым
  // "Проверяю ответ" — теперь во время проверки тут вообще ничего нет (без слов "проверяю"),
  // сама выбранная карточка мягко пульсирует (см. _buildMcqGrid) — это и есть вся индикация.
  Widget _buildResultPanel() {
    if (_phase != _Phase.verdict || _answerRes == null) return const SizedBox.shrink();

    final res = _answerRes!;
    final correct = res['correct'] == true;
    // MCQ: верно/неверно и так видно по цвету карточки варианта (жалоба: "не надо писать
    // Засчитано и не засчитано, это и так зелёным и красным") — текстом дублируем только для
    // открытого вопроса, где такой цветной карточки нет вообще. Тайм-аут — отдельный случай:
    // карточки при нём не показывают красный (никто не был выбран), поэтому только тут и
    // объясняем словами, что вообще произошло.
    final isOpen = _item?['type'] == 'open';
    final canDispute = res['canDispute'] == true && _disputeReply == null;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: (correct ? AgroColors.green : AgroColors.danger).withOpacity(0.12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_wasTimeout) ...[
                    const Text('⏰ Время вышло — не успели ответить', style: TextStyle(fontWeight: FontWeight.bold, color: AgroColors.danger)),
                    const SizedBox(height: 6),
                  ] else if (isOpen) ...[
                    Text(correct ? '✅ Верно' : '❌ Не засчитано', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 6),
                  ],
                  Text('Объяснение: ${res['explanation']?.toString() ?? ''}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
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

  Widget _buildOpenAnswer() {
    // Вердикт уже пришёл — карточка ввода (микрофон/текстовое поле) должна ПОЛНОСТЬЮ уйти,
    // остаётся только разбор ИИ с кнопками "Оспорить"/"Далее" ниже (см. _buildResultPanel) —
    // жалоба: раньше карточка ввода оставалась висеть ПОВЕРХ/РЯДОМ с ответом ИИ одновременно.
    if (_phase == _Phase.verdict) return const SizedBox.shrink();
    // Проверка (grading) может занять несколько секунд — реальный запрос к ИИ, не мгновенный, как
    // у MCQ. Никакого текста "проверяю" (по просьбе), но и не оставляем экран мёртвым: мик/кнопки
    // прячем, показываем тонкую безмолвную полосу прогресса — жалоба "ответ от ии выходит
    // где-то в конце" была отчасти как раз про то, что в этот момент непонятно, что что-то
    // вообще происходит.
    if (_phase == _Phase.grading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 22),
          child: Center(
            child: SizedBox(width: 120, child: LinearProgressIndicator(minHeight: 4)),
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_micDenied) ...[
              const Icon(Icons.mic_off, size: 36, color: AgroColors.danger),
              const SizedBox(height: 8),
              Text(
                _micPermanentlyDenied
                    ? 'Микрофон заблокирован для этого приложения — включите его в настройках телефона, или напечатайте ответ ниже.'
                    : 'Нет доступа к микрофону — разрешите его, или напечатайте ответ ниже.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              if (_micPermanentlyDenied)
                OutlinedButton.icon(onPressed: openAppSettings, icon: const Icon(Icons.settings), label: const Text('Открыть настройки'))
              else
                OutlinedButton.icon(onPressed: _beginListening, icon: const Icon(Icons.mic), label: const Text('Попробовать снова')),
            ] else if (_recordStarting) ...[
              const SizedBox(height: 4),
              const ThinkingIndicator(label: 'Готовлю микрофон…', compact: true),
              const SizedBox(height: 8),
            ] else ...[
              Icon(_recording ? Icons.mic : Icons.mic_none, size: 44, color: _recording ? AgroColors.danger : Colors.grey),
              const SizedBox(height: 8),
              Text(
                _recording ? '🔴 Запись… ${_recordSeconds}с' : 'Микрофон выключен',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                _recording ? 'Говорите ответ, затем нажмите «Готово».' : 'Голосовой ответ отправляется как аудио — ИИ слушает его сам.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              if (_recording)
                FilledButton.icon(onPressed: _stopListeningManually, icon: const Icon(Icons.stop), label: const Text('Готово, отправить'))
              else
                OutlinedButton.icon(onPressed: _beginListening, icon: const Icon(Icons.mic), label: const Text('Начать заново')),
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
            const ThinkingIndicator(label: ''),
            const SizedBox(height: 10),
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
            else
              ThinkingIndicator(label: 'Ждём ход $opponentName…'),
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

/// Анимированный индикатор загрузки/проверки — вращающийся колос вместо голого спиннера,
/// с мягкой пульсацией и (для проверки ответа) сменяющимися фразами, чтобы ожидание не
/// ощущалось "зависшим".
class ThinkingIndicator extends StatefulWidget {
  final String label;
  final bool cycle;
  // Компактный горизонтальный вариант — для встраивания под карточками вариантов ответа
  // (см. GameScreen._buildResultPanel), а не на весь экран.
  final bool compact;
  const ThinkingIndicator({required this.label, this.cycle = false, this.compact = false});

  @override
  State<ThinkingIndicator> createState() => ThinkingIndicatorState();
}

class ThinkingIndicatorState extends State<ThinkingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Timer? _cycleTimer;
  int _phraseIdx = 0;

  static const _phrases = ['Проверяю ответ…', 'Сверяю с базой знаний…', 'Почти готово…'];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
    _cycleTimer = widget.cycle
        ? Timer.periodic(const Duration(milliseconds: 1300), (_) {
            if (mounted) setState(() => _phraseIdx = (_phraseIdx + 1) % _phrases.length);
          })
        : null;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _cycleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.cycle ? _phrases[_phraseIdx] : widget.label;
    final size = widget.compact ? 34.0 : 56.0;
    final icon = AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final bounce = 1.0 + 0.12 * (0.5 - (_ctrl.value - 0.5).abs()) * 2;
        return Transform.rotate(
          angle: _ctrl.value * 6.28319,
          child: Transform.scale(scale: bounce, child: child),
        );
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: [AgroColors.greenLight, AgroColors.green]),
          boxShadow: [BoxShadow(color: AgroColors.green.withOpacity(0.35), blurRadius: 12)],
        ),
        alignment: Alignment.center,
        child: Text('🌾', style: TextStyle(fontSize: widget.compact ? 16 : 26)),
      ),
    );
    if (widget.compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 14),
          Flexible(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(text, key: ValueKey(text), style: const TextStyle(fontSize: 13.5, color: Colors.black54)),
            ),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(text, key: ValueKey(text), style: const TextStyle(fontSize: 13.5, color: Colors.black54)),
        ),
      ],
    );
  }
}

/// Одна карточка варианта ответа — плоская, залитая цветом, с текстом, который сам ужимается
/// под размер карточки (AutoSizeText), и мягкой пульсацией, пока ответ отправлен, но вердикт ещё
/// не пришёл (единственная индикация "проверяю" — без единого слова текста).
class _AnswerCard extends StatefulWidget {
  final String text;
  final Color background;
  final Color textColor;
  final bool pulsing;
  final bool showCorrectIcon;
  final bool showWrongIcon;
  final bool showFriendMarker;
  final String? friendAvatarId;
  final String? friendFrameId;
  // Позиция карточки в сетке 2×2 (0=слева сверху, 1=справа сверху, 2=слева снизу, 3=справа
  // снизу) — аватар друга садится в СВОЙ угол каждой карточки, а не всегда в один и тот же
  // (жалоба: аватар в одном углу "негармонично"), не залезая на текст самого варианта.
  final int cornerIndex;
  final VoidCallback? onTap;

  const _AnswerCard({
    required this.text,
    required this.background,
    required this.textColor,
    required this.pulsing,
    required this.showCorrectIcon,
    required this.showWrongIcon,
    required this.showFriendMarker,
    required this.friendAvatarId,
    required this.friendFrameId,
    required this.cornerIndex,
    required this.onTap,
  });

  @override
  State<_AnswerCard> createState() => _AnswerCardState();
}

class _AnswerCardState extends State<_AnswerCard> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      decoration: BoxDecoration(color: widget.background, borderRadius: BorderRadius.circular(16)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onTap,
          child: Padding(
            // Свой угол занят аватаром (см. ниже) — отступаем от него чуть больше, чтобы не
            // читалось впритык, но не трогаем противоположные углы.
            padding: EdgeInsets.only(
              left: 12 + (widget.showFriendMarker && widget.cornerIndex % 2 == 0 ? 14 : 0),
              right: 12 + (widget.showFriendMarker && widget.cornerIndex % 2 == 1 ? 14 : 0),
              top: 8,
              bottom: 8,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Центр по горизонтали И вертикали (жалоба: "текст должен центрироваться ровно
                // по горизонтали и вертикали") — Center внутри Stack растягивается на весь размер
                // карточки, текст выравнивается внутри него в обе стороны.
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: AutoSizeText(
                          widget.text,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: widget.textColor),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          minFontSize: 10,
                          // Если даже при минимальном шрифте в 3 строки не влезает (жалоба: "текст
                          // должен быть анимированным, чтобы можно было читать невмещающуюся
                          // часть") — вместо обрезки бегущая строка, прокручивающая весь текст.
                          overflowReplacement: _MarqueeText(
                            text: widget.text,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: widget.textColor),
                          ),
                        ),
                      ),
                      if (widget.showCorrectIcon) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.check_circle, color: Colors.white, size: 20)),
                      if (widget.showWrongIcon) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.cancel, color: Colors.white, size: 20)),
                    ],
                  ),
                ),
                // Маленький круглый аватар — жалоба: всегда в одном и том же (нижнем правом)
                // углу выглядело негармонично и иногда перекрывало текст; теперь у каждой из 4
                // карточек СВОЙ угол (0 слева-сверху, 1 справа-сверху, 2 слева-снизу, 3
                // справа-снизу), подальше от центра, где живёт текст.
                if (widget.showFriendMarker)
                  Positioned(
                    left: widget.cornerIndex % 2 == 0 ? -4 : null,
                    right: widget.cornerIndex % 2 == 1 ? -4 : null,
                    top: widget.cornerIndex < 2 ? -6 : null,
                    bottom: widget.cornerIndex >= 2 ? -6 : null,
                    child: Container(
                      padding: const EdgeInsets.all(1.5),
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                      child: ProfileAvatar(avatarId: widget.friendAvatarId, frameId: widget.friendFrameId, size: 22),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!widget.pulsing) return card;
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, child) => Opacity(opacity: 0.55 + 0.45 * _pulseCtrl.value, child: child),
      child: card,
    );
  }
}

/// Бегущая строка — показывается вместо AutoSizeText, когда текст варианта не влезает в карточку
/// даже при минимальном шрифте в 3 строки; непрерывно прокручивает текст целиком по кругу, чтобы
/// прочитать можно было всё, а не только то, что обрезано многоточием.
class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _MarqueeText({required this.text, required this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();
        final textWidth = painter.width;
        final boxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : textWidth;
        if (textWidth <= boxWidth) {
          return Text(widget.text, style: widget.style, maxLines: 1, overflow: TextOverflow.ellipsis);
        }
        final gap = 36.0;
        final cycle = textWidth + gap;
        return ClipRect(
          child: SizedBox(
            height: painter.height,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, child) {
                final dx = -(_ctrl.value * cycle);
                return Stack(
                  children: [
                    Positioned(left: dx, top: 0, child: Text(widget.text, style: widget.style, maxLines: 1, softWrap: false)),
                    Positioned(left: dx + cycle, top: 0, child: Text(widget.text, style: widget.style, maxLines: 1, softWrap: false)),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Полоса обратного отсчёта на MCQ-вопрос (40 секунд) — зелёная → жёлтая → красная по мере
/// приближения к нулю, останавливается (и просто гаснет), как только вопрос отвечен, чтобы не
/// продолжала бежать поверх уже подсвеченных карточек.
class _QuestionTimerBar extends StatelessWidget {
  final AnimationController controller;
  final bool locked;
  const _QuestionTimerBar({required this.controller, required this.locked});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final remaining = 1.0 - controller.value;
        final color = remaining > 0.5 ? AgroColors.green : (remaining > 0.25 ? AgroColors.gold : AgroColors.danger);
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: locked ? 0.35 : 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: remaining, minHeight: 6, color: color, backgroundColor: color.withOpacity(0.15)),
          ),
        );
      },
    );
  }
}
