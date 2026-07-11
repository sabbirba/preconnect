import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/app.dart';
import 'package:preconnect/pages/devs.dart';
import 'package:preconnect/pages/free_labs.dart';
import 'package:preconnect/pages/friend_schedule.dart';
import 'package:preconnect/pages/seat_status.dart';
import 'package:preconnect/pages/shared_widgets/map_shared.dart';
import 'package:preconnect/pages/wifi_printer.dart';
import 'package:preconnect/tools/runtime_stub.dart'
    if (dart.library.html) 'package:preconnect/tools/runtime_web.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/build_info.dart';
import 'package:preconnect/pages/login.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/pages/shared_widgets/import_dialog.dart';
import 'package:preconnect/pages/home.dart';
import 'package:preconnect/libsync/libsync_page.dart';
import 'package:preconnect/tools/pkce.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, this.isLoggedIn = false});

  static const String seenKey = 'hasSeenOnboarding';
  final bool isLoggedIn;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  Future<CampusMapData?>? _campusMapFuture;
  Future<String?>? _transportScheduleUrlFuture;
  WebExtensionLoginFlow? _webExtensionLoginFlow;
  StreamSubscription<WebExtensionLoginState>? _webLoginSub;
  bool _isStartingWebLogin = false;
  bool _isGoogleLoggingIn = false;
  String _appVersion = '';

  Future<void> _handleGoogleSignIn() async {
    if (_isGoogleLoggingIn) return;
    setState(() {
      _isGoogleLoggingIn = true;
    });
    try {
      LoginPage.takePreloadedWebView();
      LoginPage.pkceVerifier = generatePkceVerifier();
      final challenge = codeChallengeS256(LoginPage.pkceVerifier!);

      final googleSsoUri = Uri.parse(ApiConfig.authUrlWithPkce(challenge))
          .replace(
            queryParameters: {
              ...Uri.parse(
                ApiConfig.authUrlWithPkce(challenge),
              ).queryParameters,
              'kc_idp_hint': 'google',
            },
          );

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LoginPage(customAuthUrl: googleSsoUri.toString()),
        ),
      );
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          'Google Sign In failed: ${e.toString().replaceAll('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleLoggingIn = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadVersion();
    if (!widget.isLoggedIn) {
      unawaited(LoginPage.preloadNextPage());
      unawaited(LoginPage.preloadGoogleLogin());
      _campusMapFuture = fetchCampusMapData();
      _transportScheduleUrlFuture = fetchTransportScheduleUrl();
    }
    if (kIsWeb && !widget.isLoggedIn) {
      _webExtensionLoginFlow = WebExtensionLoginFlow();
      _webLoginSub = _webExtensionLoginFlow!.events.listen(_handleWebLogin);
    }
  }

  Future<void> _loadVersion() async {
    final ver = await BuildInfo.displayVersion();
    if (mounted) {
      setState(() {
        _appVersion = ver;
      });
    }
  }

  @override
  void dispose() {
    _webLoginSub?.cancel();
    _webExtensionLoginFlow?.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding(BuildContext context) async {
    final prefs = AppStorage.instance;
    await prefs.setBool(OnboardingPage.seenKey, true);
    if (!context.mounted) return;
    if (kIsWeb && !widget.isLoggedIn && isChromeRuntimeAvailable()) {
      await _startWebExtensionLogin();
      return;
    }
    if (kIsWeb && !widget.isLoggedIn) {
      await _openWebLoginSheet();
      return;
    }
    if (widget.isLoggedIn) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomePage()),
        (route) => false,
      );
      return;
    }
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            const LoginPage(),
      ),
    );
  }

  Future<void> _openLink(BuildContext context, String url) async {
    await openExternalUrl(context, url);
  }

  Future<void> _openCampusMapBottomSheet() async {
    _campusMapFuture ??= fetchCampusMapData();
    _transportScheduleUrlFuture ??= fetchTransportScheduleUrl();
    if (!mounted) return;
    await showCampusMapBottomSheet(
      context,
      campusMapFuture: _campusMapFuture!,
      transportScheduleUrlFuture: _transportScheduleUrlFuture!,
      showContacts: true,
      showCallAction: false,
      collapsedVisibleCount: 5,
    );
  }

  Future<void> _openOnboardingQuickPage(Widget page) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _openWebLoginSheet() async {
    if (!mounted) return;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _WebLoginSheet(),
    );
    if (result == true) {
      if (!mounted) return;
      RefreshBus.instance.notify(reason: 'auth');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomePage()),
        (route) => false,
      );
    }
  }

  Future<void> _startWebExtensionLogin() async {
    if (_isStartingWebLogin) return;
    setState(() {
      _isStartingWebLogin = true;
    });
    try {
      MyApp.warmStartupCaches();
      await _webExtensionLoginFlow?.start();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isStartingWebLogin = false;
      });
    }
  }

  Future<void> _handleWebLogin(WebExtensionLoginState state) async {
    if (!mounted) return;
    if (state.isStarted) {
      setState(() {
        _isStartingWebLogin = true;
      });
      return;
    }
    if (state.isComplete) {
      setState(() {
        _isStartingWebLogin = false;
      });
      await MyApp.warmStartupCachesAsync();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomePage()),
        (route) => false,
      );
      return;
    }
    if (state.isFailed) {
      setState(() {
        _isStartingWebLogin = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemStatusBarContrastEnforced: false,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    );
    final titleColor = BracuPalette.textPrimary(context);
    final bodyColor = BracuPalette.textSecondary(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          const SizedBox(height: 10),
                          _HeroCard(isDark: isDark),
                          const SizedBox(height: 28),
                          Text(
                            'Welcome to PreConnect',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 31,
                              height: 1.1,
                              fontWeight: FontWeight.w800,
                              color: titleColor,
                              letterSpacing: -0.6,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Academic Companion for BRACU\n'
                            'Open Source Built by BRACU Students',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.55,
                              color: bodyColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (_appVersion.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              _appVersion,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: bodyColor.withValues(alpha: 0.65),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          _InfoCard(
                            icon: Icons.info_outline_rounded,
                            title: 'About the App',
                            body:
                                'Track classes, exams, and reminders in one place with your BRACU SSO account.',
                            color: BracuPalette.primary,
                          ),
                          const SizedBox(height: 10),
                          _InfoCard(
                            icon: Icons.privacy_tip_outlined,
                            title: 'Privacy First',
                            body:
                                'PreConnect is not an official BRAC University app. It is an initiative run by BRAC University students. Your data stays on your device with sign-in tokens kept locally.',
                            color: BracuPalette.accent,
                          ),
                          const SizedBox(height: 10),
                          const SizedBox(height: 10),
                          _InfoCard(
                            icon: Icons.groups_rounded,
                            title: 'Student Maintained',
                            body:
                                'PreConnect is actively improved by students with open-source contributions, feedback, and community support.',
                            color: const Color(0xFF0EA5A4),
                          ),
                          const SizedBox(height: 12),
                          BracuActionBannerCard(
                            iconWidget: const PreConnectGithubIcon(size: 24),
                            title: 'Open GitHub Repository',
                            subtitle: 'Explore the source code and contribute',
                            onTap: () => _openLink(
                              context,
                              'https://github.com/sabbirba/preconnect',
                            ),
                          ),
                          const SizedBox(height: 10),
                          BracuActionBannerCard(
                            icon: Icons.public_rounded,
                            iconColor: BracuPalette.accent,
                            title: 'Open PreConnect Website',
                            subtitle:
                                'Visit our official website for more things.',
                            onTap: () =>
                                _openLink(context, ApiConfig.websiteBase),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _CompactQuickAccessCard(
                          icon: Icons.people_outline_rounded,
                          color: const Color(0xFF5B8DEF),
                          onTap: () => _openOnboardingQuickPage(
                            FriendSchedulePage(onNavigate: (_) {}),
                          ),
                        ),
                        _CompactQuickAccessCard(
                          icon: Icons.science_outlined,
                          color: const Color(0xFF22B573),
                          onTap: () =>
                              _openOnboardingQuickPage(const FreeLabsPage()),
                        ),
                        _CompactQuickAccessCard(
                          icon: Icons.event_seat_outlined,
                          color: const Color(0xFF2C9DFF),
                          onTap: () =>
                              _openOnboardingQuickPage(const SeatStatusPage()),
                        ),
                        _CompactQuickAccessCard(
                          icon: Icons.local_library_outlined,
                          color: const Color(0xFF1B8EFF),
                          onTap: () =>
                              _openOnboardingQuickPage(const LibSyncPage()),
                        ),
                        _CompactQuickAccessCard(
                          icon: Icons.local_printshop_outlined,
                          color: const Color(0xFF22B573),
                          onTap: () => _openOnboardingQuickPage(
                            const CampusPrinterPage(),
                          ),
                        ),
                        _CompactQuickAccessCard(
                          icon: Icons.developer_mode_outlined,
                          color: const Color(0xFF5B8DEF),
                          onTap: () =>
                              _openOnboardingQuickPage(const DevsPage()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: BracuActionButton(
                      onPressed: _openCampusMapBottomSheet,
                      label: 'Campus Map',
                      borderRadius: 12,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: BracuActionButton(
                          onPressed: _isGoogleLoggingIn
                              ? null
                              : _handleGoogleSignIn,
                          label: 'Sign in with Google',
                          borderRadius: 12,
                          isLoading: _isGoogleLoggingIn,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 16,
                          ),
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: BracuActionButton(
                          onPressed: _isStartingWebLogin
                              ? null
                              : () => _completeOnboarding(context),
                          outlined: false,
                          isLoading: _isStartingWebLogin,
                          label: 'Continue SSO',
                          backgroundColor: const Color(0xFF1E5BFF),
                          foregroundColor: Colors.white,
                          borderRadius: 12,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 16,
                          ),
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WebLoginSheet extends StatelessWidget {
  const _WebLoginSheet();

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: Material(
          color: BracuPalette.card(context),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: const ImportSessionDialog(
                  showCancelButton: true,
                  showCloseButton: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Image.asset(
              'assets/icon.png',
              width: 96,
              height: 96,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Prepare. Connect. Succeed.',
          style: TextStyle(
            color: BracuPalette.textPrimary(context),
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BracuPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.12)),
        boxShadow: isDark
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: BracuPalette.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: BracuPalette.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactQuickAccessCard extends StatelessWidget {
  const _CompactQuickAccessCard({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 12.0),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}
