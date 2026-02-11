import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:preconnect/app.dart';
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
  @override
  void initState() {
    super.initState();
    if (!widget.isLoggedIn) {
      unawaited(LoginPage.preloadNextPage());
    }
  }

  Future<void> _completeOnboarding(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingPage.seenKey, true);
    if (!context.mounted) return;
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
    final uri = Uri.parse(url);
    final mode = kIsWeb
        ? LaunchMode.platformDefault
        : LaunchMode.inAppBrowserView;
    var launched = await launchUrl(uri, mode: mode);
    if (!launched && !kIsWeb) {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!launched && context.mounted) {
      showAppSnackBar(context, 'Unable to open link.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
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
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ValueListenableBuilder<ThemeMode>(
                        valueListenable: ThemeController.of(context),
                        builder: (context, mode, _) {
                          final isDarkMode =
                              Theme.of(context).brightness == Brightness.dark;
                          return IconButton(
                            tooltip: isDarkMode
                                ? 'Switch to light'
                                : 'Switch to dark',
                            onPressed: () => ThemeController.setTheme(
                              context,
                              isDarkMode ? ThemeMode.light : ThemeMode.dark,
                            ),
                            icon: Icon(
                              isDarkMode
                                  ? Icons.wb_sunny_outlined
                                  : Icons.dark_mode_outlined,
                              color: BracuPalette.primary,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
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
                                'Track classes, exams, reminders, and shared schedules in one place with your BRACU SSO account.',
                            color: BracuPalette.primary,
                          ),
                          const SizedBox(height: 10),
                          _InfoCard(
                            icon: Icons.privacy_tip_outlined,
                            title: 'Privacy First',
                            body:
                                'PreConnect is not an official BRAC University app. It is an initiative run by BRAC University students. Your data stays on your device via SharedPreferences cache with sign-in tokens in secure storage.',
                            color: BracuPalette.accent,
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
                                    'Open PreConnect Web',
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
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _completeOnboarding(context),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Continue'),
                      style: FilledButton.styleFrom(
                        backgroundColor: BracuPalette.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(54),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [Colors.black, Colors.black]
              : [Colors.white.withValues(alpha: 0.95), const Color(0xFFEAF4FF)],
        ),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : BracuPalette.primary.withValues(alpha: 0.10),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 210,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: isDark
                  ? Colors.white.withValues(alpha: 0.03)
                  : const Color(0xFFF5F9FF),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: 18,
                  left: 16,
                  child: _BadgeIcon(
                    icon: Icons.school_outlined,
                    color: BracuPalette.accent,
                  ),
                ),
                Positioned(
                  top: 22,
                  right: 16,
                  child: _BadgeIcon(
                    icon: Icons.schedule_outlined,
                    color: const Color(0xFF7C56FF),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  left: 20,
                  child: _BadgeIcon(
                    icon: Icons.alarm_outlined,
                    color: const Color(0xFFEF6C35),
                  ),
                ),
                Positioned(
                  bottom: 26,
                  right: 20,
                  child: _BadgeIcon(
                    icon: Icons.people_outline,
                    color: const Color(0xFF5B8DEF),
                  ),
                ),
                _BrandLockup(isDark: isDark),
              ],
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
      ),
    );
  }
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final logoColor = BracuPalette.textPrimary(context);
    return SizedBox(
      width: double.infinity,
      child: Align(
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Transform.translate(
            offset: const Offset(10, 0),
            child: SvgPicture.network(
              'https://preconnect.app/logo.svg',
              width: 210,
              height: 56,
              colorFilter: ColorFilter.mode(logoColor, BlendMode.srcIn),
              placeholderBuilder: (_) => const SizedBox(
                width: 210,
                height: 56,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 19, color: color),
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
