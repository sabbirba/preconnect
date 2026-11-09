import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';

bool get _isMobile =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

WebViewController preConnectWebViewController() {
  final controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..enableZoom(true);
  if (_isMobile) {
    controller
      ..setUserAgent(kPreConnectUserAgent)
      ..setBackgroundColor(Colors.transparent);
  }
  return controller;
}

class PreConnectWebViewPage extends StatefulWidget {
  const PreConnectWebViewPage({
    super.key,
    this.url,
    this.controller,
    this.onBack,
    this.onNavigationRequest,
    this.onPageStarted,
    this.onPageFinished,
    this.onSslAuthError,
  });

  final Uri? url;
  final WebViewController? controller;
  final Future<void> Function()? onBack;
  final NavigationDecision Function(NavigationRequest request)?
  onNavigationRequest;
  final void Function(String url)? onPageStarted;
  final void Function(String url)? onPageFinished;
  final void Function(SslAuthError error)? onSslAuthError;

  @override
  State<PreConnectWebViewPage> createState() => _PreConnectWebViewPageState();
}

class _PreConnectWebViewPageState extends State<PreConnectWebViewPage> {
  late final WebViewController _controller =
      widget.controller ?? preConnectWebViewController();
  late bool _loading = widget.controller == null;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) return;
    _controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) =>
            widget.onNavigationRequest?.call(request) ??
            NavigationDecision.navigate,
        onPageStarted: (url) {
          if (mounted) setState(() => _loading = true);
          widget.onPageStarted?.call(url);
        },
        onPageFinished: (url) {
          if (mounted) setState(() => _loading = false);
          widget.onPageFinished?.call(url);
        },
        onSslAuthError: widget.onSslAuthError,
      ),
    );
    _controller.loadRequest(widget.url!);
  }

  Future<void> _back() async {
    if (widget.onBack != null) return widget.onBack!();
    final navigator = Navigator.of(context);
    if (await _controller.canGoBack()) return _controller.goBack();
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(
                controller: _controller,
                gestureRecognizers: {
                  const Factory<OneSequenceGestureRecognizer>(
                    EagerGestureRecognizer.new,
                  ),
                },
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: AppGlassContainer(
                  borderRadius: BorderRadius.circular(24),
                  blurSigma: 18,
                  isHighlighted: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: AppPalette.primary,
                        ),
                        onPressed: _back,
                      ),
                      AppRefreshButton(
                        onPressed: _controller.reload,
                        isLoading: _loading,
                        icon: Icons.refresh_rounded,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
