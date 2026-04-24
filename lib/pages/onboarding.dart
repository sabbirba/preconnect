import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:preconnect/pages/devs.dart';
import 'package:preconnect/pages/friend_schedule.dart';
import 'package:preconnect/pages/free_labs.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/pages/notifications.dart';
import 'package:preconnect/pages/shared_widgets/campus_map_shared.dart';
import 'package:preconnect/pages/wifi_printer.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/pages/home.dart';
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
  String? _webLoginStatus;

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
    if (kIsWeb && !widget.isLoggedIn) {
      if (_isStartingWebLogin) return;
      setState(() {
        _isStartingWebLogin = true;
        _webLoginStatus = 'Opening BRACU SSO...';
      });
      await _webExtensionLoginFlow?.start();
      return;
    }
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            widget.isLoggedIn ? const HomePage() : const LoginPage(),
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

  void _handleWebLogin(WebExtensionLoginState state) {
    if (!mounted) return;
    if (state.isStarted) {
      setState(() {
        _isStartingWebLogin = true;
        _webLoginStatus = 'Opening BRACU SSO...';
      });
      return;
    }
    if (state.isComplete) {
      setState(() {
        _isStartingWebLogin = false;
        _webLoginStatus = 'Login complete. Opening the app...';
      });
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      return;
    }
    if (state.isFailed) {
      setState(() {
        _isStartingWebLogin = false;
        _webLoginStatus = state.message?.isNotEmpty == true
            ? state.message
            : 'Unable to sign in.';
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
                                'PreConnect is not an official BRAC University app. It is an initiative run by BRAC University students. Your data stays on your device with sign-in tokens in secure storage.',
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
                                _openLink(context, 'https://preconnect.app'),
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 6,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.language_rounded,
                                    size: 16,
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
                                  Icon(
                                    Icons.open_in_new,
                                    size: 16,
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
                  if (_webLoginStatus != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: BracuCard(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              if (_isStartingWebLogin)
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                  ),
                                )
                              else
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 18,
                                  color: BracuPalette.primary,
                                ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _webLoginStatus!,
                                  style: TextStyle(
                                    color: bodyColor,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final layout = quickAccessGridLayout(
                        constraints.maxWidth,
                        targetColumns: 5,
                        minItemWidth: 62,
                      );
                      return Center(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: layout.spacing,
                          runSpacing: layout.spacing,
                          children: [
                            _CompactQuickAccessCard(
                              width: layout.itemWidth,
                              icon: Icons.notifications_outlined,
                              color: const Color(0xFF2C9DFF),
                              showLabels: false,
                              onTap: () => _openOnboardingQuickPage(
                                const NotificationsPage(),
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
                              icon: Icons.people_outline_rounded,
                              color: const Color(0xFF5B8DEF),
                              showLabels: false,
                              onTap: () => _openOnboardingQuickPage(
                                FriendSchedulePage(onNavigate: (HomeTab _) {}),
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
                    child: OutlinedButton.icon(
                      onPressed: _openCampusMapBottomSheet,
                      icon: const Icon(Icons.map_rounded),
                      label: const Text('Campus Map'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(42),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isStartingWebLogin
                          ? null
                          : () => _completeOnboarding(context),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: Text(
                        _isStartingWebLogin && kIsWeb
                            ? 'Signing in...'
                            : 'Continue',
                        style: const TextStyle(fontSize: 17),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
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
          child: Image.asset(
            'web/icons/Icon-512.png',
            width: 96,
            height: 96,
            filterQuality: FilterQuality.high,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
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
