// Экран входа — единственное место во всём приложении, где используется WebView (сам вход
// через Telegram технически устроен как веб-виджет на стороне Telegram, это не обходится).
// Дальше все экраны — полностью нативные, никакого браузера.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'api.dart';
import 'theme.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
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
        onMessageReceived: (message) async {
          try {
            final data = jsonDecode(message.message) as Map<String, dynamic>;
            if (data['token'] is String) {
              await Api.instance.setSession(data['token'] as String);
              if (!mounted) return;
              Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
            } else if (data['error'] != null) {
              setState(() => _error = data['error'].toString());
            }
          } catch (_) {
            setState(() => _error = 'Не получилось разобрать ответ входа.');
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => setState(() => _loading = false),
        ),
      )
      ..loadRequest(Uri.parse(loginPageUrl));
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
      appBar: AppBar(title: const Text('⚔️ Agro Jekpe-jek — вход')),
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
