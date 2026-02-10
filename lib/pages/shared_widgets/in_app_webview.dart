import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class InAppWebPage extends StatefulWidget {
  const InAppWebPage({
    super.key,
    required this.initialUrl,
    this.title,
    this.userAgent,
    this.navigationDelegate,
    this.onControllerReady,
    this.enablePullToRefresh = true,
    this.syncSystemBars = true,
    this.immersive = false,
  });

  final String initialUrl;
  final String? title;
  final String? userAgent;
  final NavigationDelegate? navigationDelegate;
  final Future<void> Function(WebViewController controller)? onControllerReady;
  final bool enablePullToRefresh;
  final bool syncSystemBars;
  final bool immersive;

  @override
  State<InAppWebPage> createState() => _InAppWebPageState();
}

class _InAppWebPageState extends State<InAppWebPage> {
  WebViewController? _controller;
  bool _cookiesConfigured = false;

  @override
  void initState() {
    super.initState();
    if (widget.immersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  void dispose() {
    if (widget.immersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  Future<void> _handleBack() async {
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      return;
    }
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            await _handleBack();
          },
          child: InAppWebView(
            initialUrl: widget.initialUrl,
            userAgent: widget.userAgent,
            navigationDelegate: widget.navigationDelegate,
            onControllerReady: (controller) async {
              _controller = controller;
              await _configureCookies(controller);
              if (widget.onControllerReady != null) {
                await widget.onControllerReady!(controller);
              }
            },
            enablePullToRefresh: widget.enablePullToRefresh,
            syncSystemBars: widget.syncSystemBars,
          ),
        ),
      ),
    );
  }

  Future<void> _configureCookies(WebViewController controller) async {
    if (_cookiesConfigured) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      final cookieManager = AndroidWebViewCookieManager(
        PlatformWebViewCookieManagerCreationParams(),
      );
      await cookieManager.setAcceptThirdPartyCookies(platform, true);
      _cookiesConfigured = true;
    }
  }
}

class InAppWebView extends StatefulWidget {
  const InAppWebView({
    super.key,
    required this.initialUrl,
    this.userAgent,
    this.navigationDelegate,
    this.onControllerReady,
    this.enablePullToRefresh = true,
    this.syncSystemBars = true,
  });

  final String initialUrl;
  final String? userAgent;
  final NavigationDelegate? navigationDelegate;
  final Future<void> Function(WebViewController controller)? onControllerReady;
  final bool enablePullToRefresh;
  final bool syncSystemBars;

  @override
  State<InAppWebView> createState() => _InAppWebViewState();
}

class _InAppWebViewState extends State<InAppWebView> {
  late final WebViewController _controller;
  bool _refreshing = false;
  bool _canRefresh = false;
  double _dragOffset = 0;
  int? _activePointer;
  double _startDy = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            widget.navigationDelegate?.onPageFinished?.call(url);
            if (!mounted) return;
            setState(() {
              _refreshing = false;
            });
            if (widget.syncSystemBars) {
              unawaited(_syncSystemBars());
            }
          },
          onNavigationRequest: (request) {
            if (widget.navigationDelegate?.onNavigationRequest == null) {
              return NavigationDecision.navigate;
            }
            return widget.navigationDelegate!.onNavigationRequest!(request);
          },
          onPageStarted: (url) {
            widget.navigationDelegate?.onPageStarted?.call(url);
          },
          onProgress: (progress) {
            widget.navigationDelegate?.onProgress?.call(progress);
          },
          onWebResourceError: (error) {
            widget.navigationDelegate?.onWebResourceError?.call(error);
          },
        ),
      );

    if (widget.userAgent != null && widget.userAgent!.isNotEmpty) {
      _controller.setUserAgent(widget.userAgent!);
    }
    unawaited(_startLoading());
  }

  Future<void> _startLoading() async {
    if (widget.onControllerReady != null) {
      await widget.onControllerReady!(_controller);
    }
    await _controller.loadRequest(Uri.parse(widget.initialUrl));
  }

  Future<void> _handleRefresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
    });
    await _controller.reload();
  }

  Future<void> _updateCanRefresh() async {
    _canRefresh = await _isAtTop();
  }

  Future<bool> _isAtTop() async {
    try {
      final result = await _controller.runJavaScriptReturningResult(
        'document.scrollingElement ? document.scrollingElement.scrollTop : 0;',
      );
      final value =
          result is num ? result.toDouble() : double.tryParse('$result') ?? 0;
      return value <= 0.0;
    } catch (_) {
      return false;
    }
  }

  Future<void> _syncSystemBars() async {
    try {
      final themeColorResult = await _controller.runJavaScriptReturningResult(
        "(function(){var meta=document.querySelector('meta[name=\"theme-color\"]');return meta?meta.content:'';})()",
      );
      final themeColor = _parseCssColor(themeColorResult);
      final prefersDarkResult = await _controller.runJavaScriptReturningResult(
        "window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches",
      );
      final prefersDark = prefersDarkResult == true || prefersDarkResult == 'true';
      final baseColor = themeColor ?? (prefersDark ? Colors.black : Colors.white);
      final isDark =
          ThemeData.estimateBrightnessForColor(baseColor) == Brightness.dark;
      final overlay = SystemUiOverlayStyle(
        statusBarColor: baseColor,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: baseColor,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      );
      SystemChrome.setSystemUIOverlayStyle(overlay);
    } catch (_) {}
  }

  Color? _parseCssColor(Object? value) {
    final raw = '$value'.trim().toLowerCase();
    if (raw.isEmpty || raw == 'null') return null;
    if (raw.startsWith('#')) {
      final hex = raw.substring(1);
      if (hex.length == 3) {
        final r = hex[0] * 2;
        final g = hex[1] * 2;
        final b = hex[2] * 2;
        return Color(int.parse('ff$r$g$b', radix: 16));
      }
      if (hex.length == 6) {
        return Color(int.parse('ff$hex', radix: 16));
      }
      if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
      return null;
    }
    if (raw.startsWith('rgb')) {
      final match = RegExp(r'rgba?\(([^)]+)\)').firstMatch(raw);
      if (match == null) return null;
      final parts = match.group(1)!.split(',').map((e) => e.trim()).toList();
      if (parts.length < 3) return null;
      final r = int.tryParse(parts[0]) ?? 0;
      final g = int.tryParse(parts[1]) ?? 0;
      final b = int.tryParse(parts[2]) ?? 0;
      final a = parts.length >= 4
          ? ((double.tryParse(parts[3]) ?? 1) * 255).round().clamp(0, 255)
          : 255;
      return Color.fromARGB(a, r, g, b);
    }
    return null;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null || !widget.enablePullToRefresh) return;
    _activePointer = event.pointer;
    _startDy = event.position.dy;
    _dragOffset = 0;
    _canRefresh = false;
    unawaited(_updateCanRefresh());
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_activePointer != event.pointer ||
        !_canRefresh ||
        _refreshing ||
        !widget.enablePullToRefresh) {
      return;
    }
    final delta = event.position.dy - _startDy;
    if (delta <= 0) return;
    _dragOffset = delta;
    if (_dragOffset >= 80) {
      _canRefresh = false;
      _handleRefresh();
    }
  }

  void _onPointerEnd(PointerEvent event) {
    if (_activePointer != event.pointer) return;
    _activePointer = null;
    _dragOffset = 0;
    _canRefresh = false;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerEnd,
            onPointerCancel: _onPointerEnd,
          ),
        ),
        if (_refreshing) const SizedBox.shrink(),
      ],
    );
  }
}
