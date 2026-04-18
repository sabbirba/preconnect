import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:crypto/crypto.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/pages/web_login.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  static WebViewController? _preloadedWebViewController;
  static bool _isPreloadingWebView = false;
  static String? _pkceVerifier;

  static String _generatePkceVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(64, (_) => chars[random.nextInt(chars.length)]).join();
  }

  static String _codeChallengeS256(String verifier) {
    final bytes = sha256.convert(utf8.encode(verifier)).bytes;
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static Future<void> preloadNextPage() async {
    if (kIsWeb) return;
    if (_preloadedWebViewController != null || _isPreloadingWebView) return;
    _isPreloadingWebView = true;
    try {
      _pkceVerifier = _generatePkceVerifier();
      final codeChallenge = _codeChallengeS256(_pkceVerifier!);
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(kPreconnectUserAgent)
        ..loadRequest(Uri.parse(ApiConfig.authUrlWithPkce(codeChallenge)));
      await _configureCookies(controller);
      _preloadedWebViewController = controller;
    } catch (_) {
      _preloadedWebViewController = null;
    } finally {
      _isPreloadingWebView = false;
    }
  }

  static WebViewController? takePreloadedWebView() {
    final controller = _preloadedWebViewController;
    _preloadedWebViewController = null;
    return controller;
  }

  static Future<void> _configureCookies(WebViewController controller) async {
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      final cookieManager = AndroidWebViewCookieManager(
        PlatformWebViewCookieManagerCreationParams(),
      );
      await cookieManager.setAcceptThirdPartyCookies(platform, true);
    }
  }

  static Future<void> clearSessionArtifacts() async {
    _preloadedWebViewController = null;
    _isPreloadingWebView = false;
    if (kIsWeb) return;
    try {
      final manager = WebViewCookieManager();
      await manager.clearCookies();
    } catch (_) {}
  }

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const Duration _loginRequestTimeout = Duration(seconds: 12);
  WebViewController? _webViewController;
  bool _handledRedirect = false;

  bool _isLoggingIn = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    _webViewController =
        LoginPage.takePreloadedWebView() ?? _buildMobileWebView();
    _attachNavigationDelegate(_webViewController!);
  }

  WebViewController _buildMobileWebView() {
    LoginPage._pkceVerifier ??= LoginPage._generatePkceVerifier();
    final codeChallenge = LoginPage._codeChallengeS256(
      LoginPage._pkceVerifier!,
    );
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kPreconnectUserAgent)
      ..loadRequest(Uri.parse(ApiConfig.authUrlWithPkce(codeChallenge)));
    LoginPage._configureCookies(controller);
    return controller;
  }

  void _attachNavigationDelegate(WebViewController controller) {
    controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          if (_isRedirectUrl(request.url)) {
            _handleRedirect(request.url);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onPageStarted: (url) {
          if (_isRedirectUrl(url)) {
            _handleRedirect(url);
          }
        },
      ),
    );
  }

  bool _isRedirectUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.host == 'connect.bracu.ac.bd';
  }

  void _handleRedirect(String url) async {
    debugPrint('[LOGIN.REDIRECT] 🔴🔴🔴 OAUTH REDIRECT RECEIVED 🔴🔴🔴');
    if (_handledRedirect || _isLoggingIn) {
      debugPrint(
        '[LOGIN.REDIRECT] Already handling redirect or logging in, returning',
      );
      return;
    }
    final Uri uri = Uri.parse(url);
    final String? authCode = uri.queryParameters["code"];

    if (authCode == null || authCode.isEmpty) {
      debugPrint('[LOGIN.REDIRECT] ✗ No auth code in redirect URL');
      return;
    }

    debugPrint(
      '[LOGIN.REDIRECT] ✓ Got auth code: ${authCode.substring(0, 20)}...',
    );
    _handledRedirect = true;
    if (mounted) {
      setState(() => _isLoggingIn = true);
    }

    var needsRetry = false;
    try {
      debugPrint('[LOGIN.REDIRECT] Starting token exchange with auth code...');
      final didLogin = await _exchangeCodeForToken(authCode);
      debugPrint('[LOGIN.REDIRECT] Token exchange result: $didLogin');
      if (!didLogin) {
        needsRetry = true;
        if (mounted) {
          showAppSnackBar(context, 'Login failed. Please try again.');
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoggingIn = false);
      }
    }

    if (needsRetry && mounted) {
      _handledRedirect = false;
      try {
        await _webViewController?.loadRequest(Uri.parse(ApiConfig.authUrl));
      } catch (_) {}
    }
  }

  Future<bool> _exchangeCodeForToken(String code) async {
    debugPrint('[LOGIN.EXCHANGE] 🟠🟠🟠 _exchangeCodeForToken() CALLED 🟠🟠🟠');
    debugPrint(
      '[LOGIN.EXCHANGE] code=${code.substring(0, 20)}..., length=${code.length}',
    );
    try {
      final verifier = LoginPage._pkceVerifier;
      debugPrint(
        '[LOGIN.EXCHANGE] PKCE verifier available: ${verifier != null && verifier.isNotEmpty}',
      );
      if (verifier == null || verifier.isEmpty) {
        debugPrint('[LOGIN.EXCHANGE] ✗ PKCE verifier missing!');
        return false;
      }
      debugPrint(
        '[LOGIN.EXCHANGE] Sending token exchange request to ${ApiConfig.tokenEndpoint}...',
      );
      final response = await http
          .post(
            Uri.parse(ApiConfig.tokenEndpoint),
            headers: {"Content-Type": "application/x-www-form-urlencoded"},
            body: {
              "grant_type": "authorization_code",
              "client_id": ApiConfig.clientId,
              "code": code,
              "redirect_uri": ApiConfig.redirectUri,
              "code_verifier": verifier,
            },
          )
          .timeout(_loginRequestTimeout);

      debugPrint(
        '[LOGIN.EXCHANGE] Token endpoint response code: ${response.statusCode}',
      );
      if (response.statusCode != 200) {
        debugPrint(
          '[LOGIN.EXCHANGE] ✗ Token exchange failed with status ${response.statusCode}',
        );
        final bodySample = response.body.length > 200
            ? response.body.substring(0, 200)
            : response.body;
        debugPrint('[LOGIN.EXCHANGE] Response body: $bodySample');
        return false;
      }

      debugPrint('[LOGIN.EXCHANGE] ✓ Received 200 response, parsing JSON...');
      final data = json.decode(response.body);
      if (data is! Map<String, dynamic>) {
        debugPrint('[LOGIN.EXCHANGE] ✗ Response JSON is not a Map');
        return false;
      }

      final accessToken = data["access_token"] as String?;
      final refreshToken = data["refresh_token"] as String?;
      if (accessToken == null ||
          accessToken.isEmpty ||
          refreshToken == null ||
          refreshToken.isEmpty) {
        debugPrint(
          '[LOGIN.EXCHANGE] ✗ ERROR: OAuth2 token response missing tokens',
        );
        debugPrint(
          '[LOGIN.EXCHANGE]   access_token present: ${accessToken != null}, length=${accessToken?.length}',
        );
        debugPrint(
          '[LOGIN.EXCHANGE]   refresh_token present: ${refreshToken != null}, length=${refreshToken?.length}',
        );
        return false;
      }

      debugPrint(
        '[LOGIN.EXCHANGE] ✓✓ OAuth2 received VALID tokens: access_token_length=${accessToken.length}, refresh_token_length=${refreshToken.length}',
      );

      try {
        debugPrint(
          '[LOGIN.EXCHANGE] 🟢 Writing access_token to TokenStorage...',
        );
        await TokenStorage.instance.write(
          key: 'access_token',
          value: accessToken,
        );
        debugPrint('[LOGIN.EXCHANGE] ✓ access_token write completed');

        debugPrint(
          '[LOGIN.EXCHANGE] 🟢 Writing refresh_token to TokenStorage...',
        );
        await TokenStorage.instance.write(
          key: 'refresh_token',
          value: refreshToken,
        );
        debugPrint('[LOGIN.EXCHANGE] ✓ refresh_token write completed');
      } on TokenPersistenceException catch (e) {
        debugPrint('[LOGIN] ✗ CRITICAL - Token persistence failed: $e');
        debugPrint('[LOGIN] Login failed - tokens could not be persisted');
        return false;
      }

      // CRITICAL: Give disk multiple attempts to persist tokens
      // Some Android emulators have slow storage, so we wait longer
      debugPrint(
        '[LOGIN] Waiting 500ms (extended) for tokens to persist to disk...',
      );
      await Future.delayed(const Duration(milliseconds: 500));

      // Verify tokens were actually persisted before proceeding
      debugPrint(
        '[LOGIN] Starting AGGRESSIVE token persistence verification (up to 7 attempts)...',
      );
      bool accessTokenVerified = false;
      bool refreshTokenVerified = false;
      for (int attempt = 0; attempt < 7; attempt++) {
        final delayMs = 150 + (attempt * 100);
        debugPrint(
          '[LOGIN] Verification attempt ${attempt + 1}/7: waiting ${delayMs}ms before read...',
        );
        await Future.delayed(Duration(milliseconds: delayMs));

        // Verify access_token using TokenStorage.read() (checks AppStorage + secure storage)
        if (!accessTokenVerified) {
          final verifyAccessToken = await TokenStorage.instance.read(
            key: 'access_token',
          );
          if (verifyAccessToken != null &&
              verifyAccessToken.length == accessToken.length) {
            debugPrint(
              '[LOGIN] ✓ Access token verification PASSED on attempt ${attempt + 1}: ${verifyAccessToken.length} bytes recovered',
            );
            accessTokenVerified = true;
          } else {
            debugPrint(
              '[LOGIN] ✗ Access token verification FAILED on attempt ${attempt + 1}',
            );
            debugPrint('[LOGIN]   Expected: ${accessToken.length} bytes');
            debugPrint(
              '[LOGIN]   Got: ${verifyAccessToken?.length ?? 0} bytes',
            );
          }
        }

        // Verify refresh_token using TokenStorage.read() (checks AppStorage + secure storage)
        if (!refreshTokenVerified) {
          final verifyRefreshToken = await TokenStorage.instance.read(
            key: 'refresh_token',
          );
          if (verifyRefreshToken != null &&
              verifyRefreshToken.length == refreshToken.length) {
            debugPrint(
              '[LOGIN] ✓ Refresh token verification PASSED on attempt ${attempt + 1}: ${verifyRefreshToken.length} bytes recovered',
            );
            refreshTokenVerified = true;
          } else {
            debugPrint(
              '[LOGIN] ✗ Refresh token verification FAILED on attempt ${attempt + 1}',
            );
            debugPrint('[LOGIN]   Expected: ${refreshToken.length} bytes');
            debugPrint(
              '[LOGIN]   Got: ${verifyRefreshToken?.length ?? 0} bytes',
            );
          }
        }

        // Both tokens verified, exit loop
        if (accessTokenVerified && refreshTokenVerified) {
          debugPrint(
            '[LOGIN] ✓✓✓ ALL TOKENS VERIFIED - READY FOR API CALLS ✓✓✓',
          );
          break;
        }

        // If we're on last attempt and still failing, do final full wait
        if (attempt == 5) {
          debugPrint(
            '[LOGIN] ⚠ Tokens still not verified after 6 attempts, doing final 1000ms wait...',
          );
          await Future.delayed(const Duration(milliseconds: 1000));
        }
      }

      if (!accessTokenVerified || !refreshTokenVerified) {
        debugPrint('[LOGIN] ✗✗✗ CRITICAL - Token verification INCOMPLETE ✗✗✗');
        debugPrint(
          '[LOGIN] access=$accessTokenVerified, refresh=$refreshTokenVerified',
        );
        debugPrint('[LOGIN] Login FAILED - tokens did not persist to disk!');
        return false;
      }

      debugPrint(
        '[LOGIN] ✓ Tokens verified and ready. Notifying RefreshBus and starting service data fetch...',
      );
      unawaited(ProfileService().fetchProfile());
      unawaited(ScheduleService().fetchStudentSchedule());
      unawaited(PaymentService().fetchPaymentInfo());
      unawaited(AttendanceService().fetchAttendanceInfo());
      unawaited(AdvisingService().fetchAdvisingInfo());

      RefreshBus.instance.notify(reason: 'auth');
      debugPrint('[LOGIN] Navigating to /home');
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/home', (route) => false);
      }
      return true;
    } catch (e, stack) {
      debugPrint('[LOGIN.EXCHANGE] ✗✗✗ EXCEPTION IN TOKEN EXCHANGE ✗✗✗');
      debugPrint('[LOGIN.EXCHANGE] Error: $e');
      debugPrint('[LOGIN.EXCHANGE] Stack: $stack');
      return false;
    }
  }

  Future<void> _handlePullToRefresh() async {
    if (_isLoggingIn) return;
    _handledRedirect = false;
    await _webViewController?.reload();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const WebLoginPage();
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => BracuRefreshList(
            onRefresh: _handlePullToRefresh,
            padding: EdgeInsets.zero,
            children: [
              SizedBox(
                height: constraints.maxHeight,
                child: PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, result) async {
                    final controller = _webViewController;
                    if (controller == null) return;
                    if (!mounted) return;
                    final navigator = Navigator.of(context);
                    if (await controller.canGoBack()) {
                      await controller.goBack();
                    } else {
                      navigator.maybePop();
                    }
                  },
                  child: Stack(
                    children: [
                      if (_webViewController != null)
                        Positioned.fill(
                          child: WebViewWidget(controller: _webViewController!),
                        ),
                      if (_isLoggingIn)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.08),
                            alignment: Alignment.center,
                            child: const SizedBox.shrink(),
                          ),
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

  @override
  void dispose() {
    super.dispose();
  }
}
