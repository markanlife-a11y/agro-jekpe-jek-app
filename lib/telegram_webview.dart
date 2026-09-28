// Переиспользуемый WebView для входа через Telegram Login Widget — используется и на экране
// входа, и в "Настройках" для привязки Telegram к email-аккаунту.
//
// ГЛАВНЫЙ ФИКС: сам виджет при подтверждении входа переходит по ссылке tg://resolve?domain=...,
// чтобы открыть приложение Telegram — обычный WebView такие схемы (не http/https) не понимает
// и падает с ERR_UNKNOWN_URL_SCHEME (именно так и было). Перехватываем это в
// onNavigationRequest и открываем ссылку через url_launcher — тогда Android сам передаёт её
// установленному Telegram, как и должно быть.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme.dart';

class TelegramWebViewScreen extends StatefulWidget {
  final String title;
  final String url;
  final void Function(Map<String, dynamic> authPayload) onSuccess;

  const TelegramWebViewScreen({super.key, required this.title, required this.url, required this.onSuccess});

  @override
  State<TelegramWebViewScreen> createState() => _TelegramWebViewScreenState();
}

class _TelegramWebViewScreenState extends State<TelegramWebViewScreen> {
  late final WebViewController _controller;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AgroColors.bgLight)
      ..addJavaScriptChannel(
        'AuthChannel',
        onMessageReceived: (message) {
          try {
            final data = jsonDecode(message.message) as Map<String, dynamic>;
            if (data['token'] != null || data['id'] != null) {
              widget.onSuccess(data);
            } else if (data['error'] != null) {
              setState(() => _error = data['error'].toString());
            }
          } catch (_) {
            setState(() => _error = 'Не получилось разобрать ответ.');
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null && uri.scheme != 'http' && uri.scheme != 'https') {
              // Схема вроде tg:// — сам WebView её не откроет, отдаём в систему (откроет
              // установленный Telegram напрямую на подтверждение входа).
              launchUrl(uri, mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  void _reload() {
    setState(() {
      _error = null;
      _loading = true;
    });
    _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Card(
                color: AgroColors.danger.withOpacity(0.12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('⚠️ $_error'),
                      const SizedBox(height: 8),
                      FilledButton(onPressed: _reload, child: const Text('Попробовать снова')),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
