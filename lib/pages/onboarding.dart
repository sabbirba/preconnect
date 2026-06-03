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
import 'package:preconnect/pages/shared_widgets/campus_map_shared.dart';
import 'package:preconnect/pages/wifi_printer.dart';
import 'package:preconnect/tools/chrome_runtime_available_stub.dart'
    if (dart.library.html) 'package:preconnect/tools/chrome_runtime_available_web.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/pages/login.dart';
import 'package:preconnect/pages/ui_kit.dart';

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

  @override
  void initState() {
    super.initState();
    if (!widget.isLoggedIn) {
      unawaited(LoginPage.preloadNextPage());
    }
    if (kIsWeb && !widget.isLoggedIn) {
      _webExtensionLoginFlow = WebExtensionLoginFlow();
      _webLoginSub = _webExtensionLoginFlow!.events.listen(_handleWebLogin);
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
      return;
    }
    if (widget.isLoggedIn) {
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
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
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
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
                            'Academic companion for BRACU students.\n'
                            'Open source built and maintained by students.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.55,
                              color: bodyColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
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
                          _InfoCard(
                            icon: Icons.auto_awesome_rounded,
                            title: 'Built for Daily Use',
                            body:
                                'Quickly check class schedules, notifications, exams, reminders, free labs, and more from one student-friendly app.',
                            color: const Color(0xFF7C4DFF),
                          ),
                          const SizedBox(height: 10),
                          _InfoCard(
                            icon: Icons.groups_rounded,
                            title: 'Student Maintained',
                            body:
                                'PreConnect is actively improved by students with open-source contributions, feedback, and community support.',
                            color: const Color(0xFF0EA5A4),
                          ),
                          const SizedBox(height: 10),
                          InkWell(
                            onTap: () =>
                                _openLink(context, ApiConfig.websiteBase),
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 6,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.public_rounded,
                                      size: 18,
                                      color: BracuPalette.accent,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Open PreConnect Website',
                                      style: TextStyle(
                                        color: BracuPalette.accent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => _openLink(
                              context,
                              'https://github.com/sabbirba/preconnect',
                            ),
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 6,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.code_rounded,
                                    size: 18,
                                    color: BracuPalette.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Open GitHub Repository',
                                    style: TextStyle(
                                      color: BracuPalette.primary,
                                      fontWeight: FontWeight.w600,
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
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final layout = quickAccessGridLayout(
                        constraints.maxWidth,
                        targetColumns: 5,
                        minItemWidth: 48,
                      );
                      return Center(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: layout.spacing,
                          runSpacing: layout.spacing,
                          children: [
                            _CompactQuickAccessCard(
                              width: layout.itemWidth,
                              icon: Icons.people_outline_rounded,
                              color: const Color(0xFF5B8DEF),
                              showLabels: false,
                              onTap: () => _openOnboardingQuickPage(
                                FriendSchedulePage(onNavigate: (_) {}),
                              ),
                            ),
                            _CompactQuickAccessCard(
                              width: layout.itemWidth,
                              icon: Icons.science_outlined,
                              color: const Color(0xFF22B573),
                              showLabels: false,
                              onTap: () => _openOnboardingQuickPage(
                                const FreeLabsPage(),
                              ),
                            ),
                            _CompactQuickAccessCard(
                              width: layout.itemWidth,
                              icon: Icons.event_seat_outlined,
                              color: const Color(0xFF2C9DFF),
                              showLabels: false,
                              onTap: () => _openOnboardingQuickPage(
                                const SeatStatusPage(),
                              ),
                            ),
                            _CompactQuickAccessCard(
                              width: layout.itemWidth,
                              icon: Icons.local_printshop_outlined,
                              color: const Color(0xFF22B573),
                              showLabels: false,
                              onTap: () => _openOnboardingQuickPage(
                                const CampusPrinterPage(),
                              ),
                            ),
                            _CompactQuickAccessCard(
                              width: layout.itemWidth,
                              icon: Icons.developer_mode_outlined,
                              color: const Color(0xFF5B8DEF),
                              showLabels: false,
                              onTap: () =>
                                  _openOnboardingQuickPage(const DevsPage()),
                            ),
                          ],
                        ),
                      );
                    },
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
                  SizedBox(
                    width: double.infinity,
                    child: BracuActionButton(
                      onPressed: _isStartingWebLogin
                          ? null
                          : () => _completeOnboarding(context),
                      outlined: false,
                      isLoading: _isStartingWebLogin,
                      label: 'Continue',
                      backgroundColor: const Color(0xFF1E5BFF),
                      foregroundColor: Colors.white,
                      borderRadius: 12,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 20,
                      ),
                      fontSize: 18,
                    ),
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
            child: Image.network(
              kIsWeb ? '/favicon.png' : 'https://preconnect.app/icon-round.png',
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
    required this.width,
    required this.icon,
    required this.color,
    required this.onTap,
    this.showLabels = true,
  });

  final double width;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final textPrimary = BracuPalette.textPrimary(context);
    final scale = (width / 64).clamp(0.72, 1.0);
    final outerPadding = 9.0 * scale;
    final iconShellPadding = 8.0 * scale;
    final iconSize = 22.0 * scale;
    final cardRadius = 12.0 * scale;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(cardRadius),
      child: Container(
        width: width,
        padding: EdgeInsets.all(outerPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(iconShellPadding),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(cardRadius),
              ),
              child: Icon(icon, color: color, size: iconSize),
            ),
            if (showLabels) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(fontSize: 11, color: textSecondary),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
