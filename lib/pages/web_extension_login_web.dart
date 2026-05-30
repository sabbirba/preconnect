import 'dart:async';
import 'dart:js_interop';

import 'package:chrome_extension/runtime.dart';
import 'package:flutter/material.dart';
import 'package:preconnect/api/auth.dart';
import 'package:preconnect/app.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/token_storage.dart';

class WebExtensionLoginPage extends StatefulWidget {
  const WebExtensionLoginPage({super.key});

  @override
  State<WebExtensionLoginPage> createState() => _WebExtensionLoginPageState();
}

class _WebExtensionLoginPageState extends State<WebExtensionLoginPage> {
  StreamSubscription<OnMessageEvent>? _messageSub;
  bool _busy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _messageSub = chrome.runtime.onMessage.listen(_handleMessage);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final hasToken = await TokenStorage.instance.hasAccessToken();
      if (!mounted) return;
      final sessionReady = hasToken && await AuthService().ensureSignedIn();
      if (!mounted) return;
      if (sessionReady) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/home', (route) => false);
        return;
      }
      await _startLogin();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Unable to start login: $e';
      });
    }
  }

  Future<void> _handleMessage(OnMessageEvent event) async {
    final message = event.message;
    if (message is! Map) return;
    final type = '${message['type'] ?? ''}';

    if (type == 'preconnect.loginStarted') {
      _ack(event);
      if (!mounted) return;
      setState(() {
        _busy = true;
        _status = 'Opening BRACU SSO...';
      });
      return;
    }

    if (type == 'preconnect.loginComplete') {
      _ack(event);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Login complete. Opening the app...';
      });
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      return;
    }

    if (type == 'preconnect.loginFailed') {
      _ack(event);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '${message['error'] ?? 'Unable to sign in.'}';
      });
    }
  }

  void _ack(OnMessageEvent event) {
    try {
      event.sendResponse.callAsFunction(null, {'ok': true}.jsify());
    } catch (_) {}
  }

  Future<void> _startLogin() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Opening BRACU SSO...';
    });
    try {
      MyApp.warmStartupCaches();
      await chrome.runtime.sendMessage(null, {
        'type': 'preconnect.startLogin',
      }, null);
      if (!mounted) return;
      setState(() {
        _status = 'Waiting for BRACU SSO approval...';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Unable to start login: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bodyColor = BracuPalette.textSecondary(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              BracuPalette.bgTop(context),
              BracuPalette.bgBottom(context),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 390),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 28,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.center,
                        child: Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: BracuPalette.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Icon(
                            Icons.extension_rounded,
                            color: BracuPalette.primary,
                            size: 34,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _status ?? 'Open the browser extension to sign in.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: bodyColor,
                          height: 1.4,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      BracuActionButton(
                        onPressed: _busy ? null : _startLogin,
                        label: _busy ? 'Opening...' : 'Try again',
                        outlined: false,
                        isLoading: _busy,
                        backgroundColor: BracuPalette.primary.withValues(
                          alpha: 0.12,
                        ),
                        foregroundColor: BracuPalette.primary,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'You will be redirected to BRACU SSO in a new tab.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: bodyColor.withValues(alpha: 0.82),
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
