import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:preconnect/pages/ui_kit.dart';

class PreConnectWebViewPage extends StatefulWidget {
  const PreConnectWebViewPage({
    super.key,
    required this.initialUrl,
    this.userAgent,
    this.onNavigationRequest,
    this.onPageStarted,
    this.onPageFinished,
    this.onBackPress,
    this.enablePullToRefresh = true,
    this.preloadedController,
    this.delayLoadUntilTransition = false,
  });

  final String initialUrl;
  final String? userAgent;
  final NavigationDecision Function(NavigationRequest request)?
  onNavigationRequest;
  final void Function(String url)? onPageStarted;
  final void Function(String url)? onPageFinished;
  final Future<void> Function(
    BuildContext context,
    WebViewController controller,
  )?
  onBackPress;
  final bool enablePullToRefresh;
  final WebViewController? preloadedController;
  final bool delayLoadUntilTransition;

  static Future<void> configureCookies(WebViewController controller) async {
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      final cookieManager = AndroidWebViewCookieManager(
        PlatformWebViewCookieManagerCreationParams(),
      );
      await cookieManager.setAcceptThirdPartyCookies(platform, true);
    }
  }

  @override
  State<PreConnectWebViewPage> createState() => _PreConnectWebViewPageState();
}

class _PreConnectWebViewPageState extends State<PreConnectWebViewPage> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.preloadedController != null) {
      _controller = widget.preloadedController!;
      _loading = false;
    } else {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted);

      if (widget.userAgent != null) {
        _controller.setUserAgent(widget.userAgent);
      }

      try {
        _controller.setBackgroundColor(Colors.transparent);
      } catch (_) {}

      _controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (widget.onNavigationRequest != null) {
              return widget.onNavigationRequest!(request);
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (url) {
            if (mounted) setState(() => _loading = true);
            if (widget.onPageStarted != null) widget.onPageStarted!(url);
          },
          onPageFinished: (url) {
            if (mounted) setState(() => _loading = false);
            if (widget.onPageFinished != null) widget.onPageFinished!(url);
          },
        ),
      );

      if (widget.delayLoadUntilTransition) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final route = ModalRoute.of(context);
          if (route == null) {
            _controller.loadRequest(Uri.parse(widget.initialUrl));
            return;
          }
          if (route.animation?.isCompleted == true) {
            _controller.loadRequest(Uri.parse(widget.initialUrl));
          } else {
            void listener(AnimationStatus status) {
              if (status == AnimationStatus.completed) {
                route.animation?.removeStatusListener(listener);
                if (mounted) {
                  _controller.loadRequest(Uri.parse(widget.initialUrl));
                }
              }
            }

            route.animation?.addStatusListener(listener);
          }
        });
      } else {
        _controller.loadRequest(Uri.parse(widget.initialUrl));
      }

      unawaited(PreConnectWebViewPage.configureCookies(_controller));
    }
  }

  Future<void> _handlePullToRefresh() async {
    if (!mounted) return;
    await _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black87;

    final popScopeChild = Stack(
      children: [
        Positioned.fill(child: WebViewWidget(controller: _controller)),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 48,
            color: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_rounded, color: iconColor),
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    if (widget.onBackPress != null) {
                      await widget.onBackPress!(context, _controller);
                    } else if (await _controller.canGoBack()) {
                      await _controller.goBack();
                    } else {
                      if (mounted) {
                        navigator.pop();
                      }
                    }
                  },
                ),
                const Spacer(),
                IconButton(
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: BracuPalette.primary,
                          ),
                        )
                      : Icon(Icons.refresh_rounded, color: iconColor),
                  onPressed: _loading ? null : () => _controller.reload(),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    final innerContent = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (widget.onBackPress != null) {
          await widget.onBackPress!(context, _controller);
        } else if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else {
          if (mounted) {
            navigator.pop();
          }
        }
      },
      child: widget.enablePullToRefresh
          ? LayoutBuilder(
              builder: (context, constraints) => BracuRefreshList(
                onRefresh: _handlePullToRefresh,
                padding: EdgeInsets.zero,
                children: [
                  SizedBox(height: constraints.maxHeight, child: popScopeChild),
                ],
              ),
            )
          : popScopeChild,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: SafeArea(child: innerContent),
    );
  }
}
