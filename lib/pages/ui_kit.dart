import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart'
    show ValueListenable, TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/notification_service.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/progress_service.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/api/grade_sheet_service.dart';
import 'package:preconnect/model/progress_info.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/cgpa_calculator.dart';
import 'package:preconnect/tools/ads_bridge.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/reward_support_controller.dart';
import 'package:preconnect/tools/cached_image.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/time_utils.dart';
import 'package:preconnect/tools/web_shared.dart';
import 'package:preconnect/pages/shared_widgets/current_session_helper.dart';
import 'package:url_launcher/url_launcher.dart';

export 'package:preconnect/tools/web_shared.dart';

part 'shared_widgets/ui_kit_components.dart';

const MethodChannel _pdfOpenChannel = MethodChannel('preconnect/open_pdf');

String formatDate(String? input) {
  if (input == null || input.trim().isEmpty) return '';
  final raw = input.trim();
  final candidates = <DateFormat>[
    DateFormat('yyyy-MM-dd'),
    DateFormat('yyyy/MM/dd'),
    DateFormat('yyyy.MM.dd'),
    DateFormat('dd-MM-yyyy'),
    DateFormat('dd/MM/yyyy'),
    DateFormat('d/M/yyyy'),
    DateFormat('d MMM yyyy'),
    DateFormat('d MMM, yyyy'),
    DateFormat('d-MMM-yyyy'),
    DateFormat('MMM d, yyyy'),
  ];

  DateTime? dt;
  for (final f in candidates) {
    try {
      dt = f.parseStrict(raw);
      break;
    } catch (_) {}
  }
  dt ??= DateTime.tryParse(raw);
  if (dt == null) return raw;
  return DateFormat('d MMMM, y').format(dt);
}

String formatTime(String? input) {
  return BracuTime.format(input);
}

String formatTimeRange(String? start, String? end) {
  return BracuTime.range(start, end);
}

String formatLongDate(DateTime date) {
  return DateFormat('d MMMM, yyyy').format(date.toLocal());
}

String formatRelativeDayLabel(
  DateTime date, {
  bool includeYesterday = false,
  bool includeTomorrow = false,
  String? unknownLabel,
}) {
  final localDate = date.toLocal();
  if (unknownLabel != null && localDate.year == 1970) return unknownLabel;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(localDate.year, localDate.month, localDate.day);
  if (target == today) return 'Today';
  if (includeYesterday && target == today.subtract(const Duration(days: 1))) {
    return 'Yesterday';
  }
  if (includeTomorrow && target == today.add(const Duration(days: 1))) {
    return 'Tomorrow';
  }
  return DateFormat('EEEE').format(date);
}

String formatDateTimeLabel(
  DateTime dateTime, {
  String separator = ' • ',
  bool includeYear = true,
}) {
  final localDateTime = dateTime.toLocal();
  final date = includeYear
      ? formatLongDate(localDateTime)
      : DateFormat('d MMMM').format(localDateTime);
  return '$date$separator${BracuTime.formatDateTime(localDateTime)}';
}

Future<bool> showRewardSupportFlow(BuildContext context) async {
  if (!AdsPreferences.instance.isVisible) {
    showAppSnackBar(context, 'Hidden in settings');
    return false;
  }
  if (!AdsBridge.isSupportedPlatform) {
    showAppSnackBar(context, 'Available on mobile only');
    return false;
  }

  try {
    final result = await AdsBridge.showRewarded();
    if (!context.mounted) return false;
    if (!result.rewardEarned) {
      showAppSnackBar(
        context,
        result.shown
            ? 'Watch the full video to support PreConnect'
            : 'Support video is not ready yet',
      );
      return false;
    }

    final count = await RewardSupportController.instance.recordReward();
    if (!context.mounted) return false;
    await AdsBridge.showInterstitial();
    if (!context.mounted) return false;
    HapticFeedback.lightImpact();
    showAppSnackBar(context, 'Thanks! Support #$count added.');
    return true;
  } catch (_) {
    if (context.mounted) {
      showAppSnackBar(context, 'Support video could not be shown');
    }
    return false;
  }
}

void copyToClipboard(BuildContext context, String text) {
  final value = text.trim();
  if (value.isEmpty) return;
  Clipboard.setData(ClipboardData(text: value));
  showAppSnackBar(context, 'Copied to clipboard');
}

Future<bool> openExternalUrl(
  BuildContext context,
  String rawUrl, {
  String failureMessage = 'Unable to open link.',
  LaunchMode mobilePreferredMode = LaunchMode.inAppBrowserView,
  LaunchMode mobileFallbackMode = LaunchMode.externalApplication,
}) async {
  var url = rawUrl.trim();
  url = url.replaceAll(RegExp(r'\s+'), '');
  if (url.startsWith('www.')) {
    url = 'https://$url';
  }
  if (url.isEmpty) {
    if (context.mounted) showAppSnackBar(context, failureMessage);
    return false;
  }
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
    if (context.mounted) showAppSnackBar(context, failureMessage);
    return false;
  }
  final platform = Theme.of(context).platform;
  final isMobilePlatform =
      !kIsWeb &&
      (platform == TargetPlatform.android || platform == TargetPlatform.iOS);
  final mode = isMobilePlatform
      ? mobilePreferredMode
      : LaunchMode.platformDefault;
  var launched = await launchUrl(uri, mode: mode);
  if (!launched && isMobilePlatform) {
    launched = await launchUrl(uri, mode: mobileFallbackMode);
  }
  if (!launched && context.mounted) {
    showAppSnackBar(context, failureMessage);
  }
  return launched;
}

Future<bool> openMailComposer(
  BuildContext context,
  String email, {
  String failureMessage = 'Unable to open email compose',
}) async {
  final cleaned = email.trim();
  if (cleaned.isEmpty) {
    if (context.mounted) showAppSnackBar(context, failureMessage);
    return false;
  }
  final mailtoUri = Uri(scheme: 'mailto', path: cleaned);
  final openedMail = await launchUrl(
    mailtoUri,
    mode: LaunchMode.platformDefault,
  );
  if (!openedMail && context.mounted) {
    showAppSnackBar(context, failureMessage);
  }
  return openedMail;
}

Future<bool> openPhoneDialer(
  BuildContext context,
  String phone, {
  String failureMessage = 'Unable to open phone dialer',
}) async {
  final cleaned = phone.trim();
  if (cleaned.isEmpty) {
    if (context.mounted) showAppSnackBar(context, failureMessage);
    return false;
  }
  final normalized = cleaned.replaceAll(RegExp(r'[^\d+]'), '');
  if (normalized.isEmpty) {
    if (context.mounted) showAppSnackBar(context, failureMessage);
    return false;
  }
  final telUri = Uri(scheme: 'tel', path: normalized);
  final opened = await launchUrl(telUri, mode: LaunchMode.platformDefault);
  if (!opened && context.mounted) {
    showAppSnackBar(context, failureMessage);
  }
  return opened;
}

Widget buildCenteredOutlinedActionButton({
  required String label,
  required VoidCallback onPressed,
  EdgeInsetsGeometry padding = const EdgeInsets.only(top: 2, bottom: 8),
}) {
  return Padding(
    padding: padding,
    child: Center(
      child: BracuActionButton(
        onPressed: onPressed,
        label: label,
      ),
    ),
  );
}

class BracuImageCarousel extends StatefulWidget {
  const BracuImageCarousel({
    super.key,
    required this.imageUrls,
    this.aspectRatio = 16 / 9,
    this.borderRadius = 14,
    this.imageFit = BoxFit.cover,
    this.maxBytesInPrefs = 8 * 1024 * 1024,
  });

  final List<String> imageUrls;
  final double aspectRatio;
  final double borderRadius;
  final BoxFit imageFit;
  final int maxBytesInPrefs;

  @override
  State<BracuImageCarousel> createState() => _BracuImageCarouselState();
}

class _BracuImageCarouselState extends State<BracuImageCarousel> {
  late final PageController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void didUpdateWidget(covariant BracuImageCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrls.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.imageUrls.length == 1)
              CachedImage(
                url: widget.imageUrls.first,
                fit: widget.imageFit,
                placeholder: const BracuSkeletonBox(height: 220, radius: 8),
                error: const _BracuImageErrorFallback(),
              )
            else
              PageView.builder(
                controller: _controller,
                itemCount: widget.imageUrls.length,
                onPageChanged: (value) {
                  if (!mounted) return;
                  setState(() {
                    _index = value;
                  });
                },
                itemBuilder: (context, idx) {
                  return CachedImage(
                    url: widget.imageUrls[idx],
                    fit: widget.imageFit,
                    placeholder: const BracuSkeletonBox(height: 220, radius: 8),
                    error: const _BracuImageErrorFallback(),
                  );
                },
              ),
            if (widget.imageUrls.length >= 2)
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(widget.imageUrls.length, (i) {
                          final active = i == _index;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            width: active ? 14 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: active
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BracuImageErrorFallback extends StatelessWidget {
  const _BracuImageErrorFallback();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? const Color(0xFF1B2430) : const Color(0xFFF2F6FC),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            color: isDark ? Colors.white70 : const Color(0xFF60738A),
          ),
        ],
      ),
    );
  }
}

DateTime? _lastSnackAt;
String? _lastSnackMessage;
Timer? _snackAutoTimer;

void showAppSnackBar(
  BuildContext context,
  String message, {
  String actionLabel = 'Close',
  VoidCallback? onAction,
}) {
  if (kIsWeb) return;
  final trimmed = message.trim();
  if (trimmed.isEmpty) return;
  final now = DateTime.now();
  if (_lastSnackMessage == trimmed &&
      _lastSnackAt != null &&
      now.difference(_lastSnackAt!) < const Duration(milliseconds: 1200)) {
    return;
  }
  _lastSnackMessage = trimmed;
  _lastSnackAt = now;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final messenger = ScaffoldMessenger.of(context);
  _snackAutoTimer?.cancel();
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(trimmed, style: const TextStyle(color: Colors.white)),
      backgroundColor: isDark ? const Color(0xFF1E6BE3) : BracuPalette.primary,
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      action: SnackBarAction(
        label: actionLabel,
        textColor: Colors.white,
        onPressed: () {
          if (onAction != null) {
            onAction();
            messenger.hideCurrentSnackBar();
            return;
          }
          messenger.hideCurrentSnackBar();
        },
      ),
    ),
  );
  _snackAutoTimer = Timer(const Duration(seconds: 3), () {
    messenger.hideCurrentSnackBar();
  });
}

Future<void> openGradeSheet(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  try {
    if (kIsWeb) {
      final bytes = await GradeSheetService().fetchGradeSheetBytes(
        fromGet: true,
      );
      if (!context.mounted) return;
      if (bytes == null || bytes.isEmpty) {
        _showPdfSnackBar(
          messenger,
          'Could not fetch the latest grade sheet',
          isDark: isDark,
        );
        return;
      }
      final fileName = await GradeSheetService().gradeSheetFileName();
      await openPdfInBrowser(bytes: bytes, fileName: '$fileName.pdf');
      return;
    }

    final gradeSheet = await GradeSheetService().fetchGradeSheet(fromGet: true);
    if (!context.mounted) return;
    if (gradeSheet == null) {
      _showPdfSnackBar(
        messenger,
        'Could not fetch the latest grade sheet',
        isDark: isDark,
      );
      return;
    }
    final opened = await _openPdfNativelyOrFallback(gradeSheet.file.path);
    if (opened) return;
    _showPdfSnackBar(
      messenger,
      'No app found to open this PDF.',
      isDark: isDark,
    );
  } on PlatformException catch (error) {
    final message = switch (error.code) {
      'NO_APP_FOUND' => 'No app found to open this PDF.',
      'FILE_NOT_FOUND' => 'The PDF file was not found.',
      _ => error.message ?? 'Could not open the PDF.',
    };
    _showPdfSnackBar(messenger, message, isDark: isDark);
  } catch (_) {
    _showPdfSnackBar(messenger, 'Could not open the PDF.', isDark: isDark);
  }
}

void _showPdfSnackBar(
  ScaffoldMessengerState messenger,
  String message, {
  required bool isDark,
}) {
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: isDark ? const Color(0xFF1E6BE3) : BracuPalette.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
  );
}

Future<bool> _openPdfNativelyOrFallback(String filePath) async {
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    try {
      return await _pdfOpenChannel.invokeMethod<bool>(
            'openPdf',
            <String, Object?>{'filePath': filePath},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  final opened = await launchUrl(
    Uri.file(filePath),
    mode: LaunchMode.externalApplication,
  );
  return opened;
}

List<section.Section> buildCurrentSectionsForCalculator(
  ProgressInfo info,
  String? scheduleJson,
) {
  final sections = section.parseSectionsFromScheduleJson(scheduleJson);
  final courseTitleByCode = <String, String>{};
  for (final course in info.curriculumCourses) {
    final code = course.code.trim().toUpperCase();
    final title = course.title.trim();
    if (code.isEmpty || title.isEmpty) continue;
    courseTitleByCode[code] = title;
  }
  for (final course in info.completedCourses) {
    final code = course.code.trim().toUpperCase();
    final title = course.title.trim();
    if (code.isEmpty || title.isEmpty) continue;
    courseTitleByCode.putIfAbsent(code, () => title);
  }
  return sections.where((current) {
    final resolvedTitle =
        (courseTitleByCode[current.courseCode.trim().toUpperCase()] ??
                (current.name ?? ''))
            .trim();
    final hasNoRealName =
        resolvedTitle.isEmpty ||
        resolvedTitle.toUpperCase() == current.courseCode.trim().toUpperCase();
    return !(current.courseCredit <= 0 && hasNoRealName);
  }).toList();
}

Future<void> openCgpaCalculatorPage(BuildContext context) async {
  try {
    final info = await ProgressService().getProgress();
    final profile = await ProfileService().getProfile();
    final semesterSessionId = await resolveCurrentSessionSemesterId();
    final scheduleJson = await ScheduleService().getStudentScheduleForSemester(
      semesterSessionId: semesterSessionId,
    );
    if (!context.mounted) return;

    if (info == null) {
      showAppSnackBar(
        context,
        'No progress data available for CGPA calculator',
      );
      return;
    }

    final currentCgpa = (profile?['cgpa'] ?? '').trim();
    final sections = buildCurrentSectionsForCalculator(info, scheduleJson);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CgpaCalculatorPage(
          info: info,
          currentSections: sections,
          currentCgpa: currentCgpa,
        ),
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    showAppSnackBar(context, 'Could not open CGPA calculator');
  }
}

class BracuActionBannerCard extends StatelessWidget {
  const BracuActionBannerCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor = BracuPalette.primary,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: BracuPalette.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: BracuPalette.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: BracuPalette.textSecondary(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showBracuFundingSupportSheet(BuildContext context) async {
  await showBracuBottomSheet<void>(
    context,
    title: 'Support PreConnect',
    subtitle: 'Choose how you want to help',
    builder: (sheetContext, textPrimary, textSecondary) {
      final sheetScroll = bracuBottomSheetScrollController(sheetContext);
      return ListView(
        controller: sheetScroll,
        children: [
          Text(
            'PreConnect is built by BRACU students. We keep it free, maintain the app, and add new features from community feedback. Your support helps keep it running.',
            style: TextStyle(
              color: textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          const BracuRewardVideoSection(),
          const SizedBox(height: 14),
          const BracuFundingSupportContent(),
        ],
      );
    },
  );
}

class BracuRewardVideoSection extends StatefulWidget {
  const BracuRewardVideoSection({
    super.key,
    this.activeTitle = 'Support PreConnect',
    this.activeSubtitle = 'Watch short video to support',
    this.inactiveTitle = 'Support PreConnect',
    this.inactiveSubtitle = 'Watch short video to support',
    this.buttonLabel = 'Watch',
    this.padding = const EdgeInsets.symmetric(vertical: 2),
  });

  final String activeTitle;
  final String activeSubtitle;
  final String inactiveTitle;
  final String inactiveSubtitle;
  final String buttonLabel;
  final EdgeInsetsGeometry padding;

  @override
  State<BracuRewardVideoSection> createState() =>
      _BracuRewardVideoSectionState();
}

class _BracuRewardVideoSectionState extends State<BracuRewardVideoSection> {
  bool _isLoading = false;

  Future<void> _watchRewardAd() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      if (!mounted) return;
      final earned = await showRewardSupportFlow(context);
      if (earned && mounted) {
        setState(() {});
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);

    return ValueListenableBuilder<bool>(
      valueListenable: AdsPreferences.instance.adsVisible,
      builder: (context, adsVisible, _) {
        if (!adsVisible) return const SizedBox.shrink();
        return ValueListenableBuilder<int>(
          valueListenable: RewardSupportController.instance.supportCount,
          builder: (context, supportCount, _) {
            return Padding(
              padding: widget.padding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          supportCount > 0
                              ? widget.activeTitle
                              : widget.inactiveTitle,
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          supportCount > 0
                              ? widget.activeSubtitle
                              : widget.inactiveSubtitle,
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 118),
                child: BracuActionButton(
                  onPressed: _isLoading ? null : _watchRewardAd,
                  label: supportCount > 0
                      ? '${widget.buttonLabel} #$supportCount'
                      : widget.buttonLabel,
                  borderRadius: 10,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class BracuInterstitialAdSection extends StatefulWidget {
  const BracuInterstitialAdSection({super.key});

  @override
  State<BracuInterstitialAdSection> createState() =>
      _BracuInterstitialAdSectionState();
}

class _BracuInterstitialAdSectionState
    extends State<BracuInterstitialAdSection> {
  bool _isLoading = false;

  Future<void> _showInterstitial() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final shown = await AdsBridge.showInterstitial();
      if (!mounted) return;
      showAppSnackBar(context, shown ? 'Shown' : 'Not ready');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AdsPreferences.instance.adsVisible,
      builder: (context, adsVisible, _) {
        if (!adsVisible) return const SizedBox.shrink();
        final textPrimary = BracuPalette.textPrimary(context);
        final textSecondary = BracuPalette.textSecondary(context);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Interstitial',
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Show a full-screen ad before support actions',
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 118),
                child: BracuActionButton(
                  onPressed: _isLoading ? null : _showInterstitial,
                  label: 'Show',
                  borderRadius: 10,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class BracuAdRewardSupportContent extends StatelessWidget {
  const BracuAdRewardSupportContent({super.key});

  @override
  Widget build(BuildContext context) {
    return const BracuRewardVideoSection();
  }
}

class BracuCountdownDigital extends StatelessWidget {
  const BracuCountdownDigital({super.key, required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final totalMinutes = remaining.inMinutes;
    final safeMinutes = totalMinutes < 0 ? 0 : totalMinutes;
    final days = safeMinutes ~/ 1440;
    final hours = (safeMinutes ~/ 60) % 24;
    final minutes = safeMinutes % 60;

    final units = <({String value, String label})>[
      if (days > 0) (value: days.toString(), label: 'Days'),
      if (hours > 0) (value: hours.toString().padLeft(2, '0'), label: 'Hours'),
      (value: minutes.toString().padLeft(2, '0'), label: 'Minutes'),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < units.length; i++) ...[
          _BracuCountdownCell(value: units[i].value, label: units[i].label),
          if (i != units.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _BracuCountdownCell extends StatelessWidget {
  const _BracuCountdownCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: BracuPalette.textPrimary(context),
              fontWeight: FontWeight.w700,
              fontSize: 14,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: BracuPalette.textSecondary(context),
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

String normalizeWeekday(String? day) {
  if (day == null) return '';
  final trimmed = day.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.toUpperCase();
}

String formatWeekdayTitle(String? day) {
  final normalized = normalizeWeekday(day);
  switch (normalized) {
    case 'MONDAY':
      return 'Monday';
    case 'TUESDAY':
      return 'Tuesday';
    case 'WEDNESDAY':
      return 'Wednesday';
    case 'THURSDAY':
      return 'Thursday';
    case 'FRIDAY':
      return 'Friday';
    case 'SATURDAY':
      return 'Saturday';
    case 'SUNDAY':
      return 'Sunday';
    default:
      if (day == null || day.trim().isEmpty) return '';
      final lower = day.trim().toLowerCase();
      return lower[0].toUpperCase() + lower.substring(1);
  }
}

String formatSemesterTitle(String? raw) {
  if (raw == null) return '';
  final cleaned = raw.trim();
  if (cleaned.isEmpty || cleaned == 'N/A' || cleaned == '-') return '';
  final normalized = cleaned.replaceAll(RegExp(r'[_-]+'), ' ');
  final parts = normalized.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  final titled = parts
      .map((part) {
        if (RegExp(r'^\d+$').hasMatch(part)) return part;
        final lower = part.toLowerCase();
        return lower[0].toUpperCase() + lower.substring(1);
      })
      .join(' ');
  return titled;
}

String formatSemesterFromSessionIdInt(int semesterSessionId) {
  final year = semesterSessionId ~/ 10;
  final code = semesterSessionId % 10;
  final label = switch (code) {
    1 => 'Spring',
    2 => 'Summer',
    3 => 'Fall',
    _ => 'Session',
  };
  return '$label $year';
}

String formatSemesterFromSessionId(String raw) {
  final cleaned = raw.trim();
  if (cleaned.isEmpty || cleaned == 'N/A' || cleaned == '-') return '';
  final value = int.tryParse(cleaned);
  if (value == null) return formatSemesterTitle(cleaned);
  return formatSemesterFromSessionIdInt(value);
}

String formatTimeHour(String? input) {
  final t = formatTime(input);
  if (t.isEmpty) return '--';
  return t.split(':').first;
}

double compactPopupMenuWidth(
  BuildContext context,
  List<String> labels, {
  double minWidth = 0,
  double maxWidth = 320,
  TextStyle style = const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
  double horizontalPadding = 16,
  double screenMargin = 20,
}) {
  var maxTextWidth = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    if (painter.width > maxTextWidth) {
      maxTextWidth = painter.width;
    }
  }
  final screenMax = MediaQuery.sizeOf(context).width - screenMargin;
  final effectiveMax = math.min(maxWidth, screenMax);
  return (maxTextWidth + (horizontalPadding * 2) + 4).clamp(
    minWidth,
    effectiveMax,
  );
}

PopupMenuItem<T> compactPopupMenuItem<T>({
  required T value,
  required String label,
  double height = 42,
  EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 16),
  TextStyle textStyle = const TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
  ),
}) {
  return PopupMenuItem<T>(
    value: value,
    padding: padding,
    height: height,
    child: Text(
      label,
      style: textStyle,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.fade,
    ),
  );
}

const String _kPreconnectSupportNumber = '01865493144';
const String _kPreconnectSupportReference = 'PreConnect App';
const String _kPreconnectWhatsAppUrl =
    'https://api.whatsapp.com/send?phone=8801865493144&text=Hi%20PreConnect%2C%20I%20want%20to%20support%20the%20app.';
const String kPreconnectRepositoryUrl =
    'https://github.com/sabbirba/preconnect';

class BracuFundingSupportContent extends StatelessWidget {
  const BracuFundingSupportContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: BracuPalette.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: BracuPalette.primary.withValues(alpha: 0.12),
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.volunteer_activism_rounded,
                color: BracuPalette.primary,
                size: 34,
              ),
              const SizedBox(height: 8),
              Text(
                'Support via bKash, Nagad, or Upay',
                style: TextStyle(
                  color: BracuPalette.textPrimary(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const BracuSupportNumberRow(number: _kPreconnectSupportNumber),
        const SizedBox(height: 4),
        Text(
          'Send money with reference',
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontSize: 11,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _kPreconnectSupportReference,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: () async {
                await Clipboard.setData(
                  const ClipboardData(text: _kPreconnectSupportReference),
                );
                if (context.mounted) {
                  showAppSnackBar(context, 'Reference copied');
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(
                  Icons.copy_rounded,
                  size: 14,
                  color: BracuPalette.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Your support helps cover server costs, ongoing development, and app releases so PreConnect can stay reliable.',
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontSize: 13,
            height: 1.45,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _BracuSponsorActionChip(
              icon: Icons.call_outlined,
              label: _kPreconnectSupportNumber,
              onTap: () => openPhoneDialer(context, _kPreconnectSupportNumber),
            ),
            _BracuSponsorActionChip(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'WhatsApp',
              onTap: () => openExternalUrl(
                context,
                _kPreconnectWhatsAppUrl,
                failureMessage: 'Unable to open WhatsApp.',
              ),
            ),
            _BracuSponsorActionChip(
              icon: Icons.open_in_new_rounded,
              label: 'GitHub Repository',
              onTap: () => openExternalUrl(context, kPreconnectRepositoryUrl),
            ),
          ],
        ),
      ],
    );
  }
}

class _BracuSponsorActionChip extends StatelessWidget {
  const _BracuSponsorActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BracuActionButton(
      onPressed: onTap,
      icon: icon,
      label: label,
      borderRadius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }
}

class BracuSupportNumberRow extends StatelessWidget {
  const BracuSupportNumberRow({super.key, required this.number});

  final String number;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: number));
        if (!context.mounted) return;
        showAppSnackBar(context, 'Copied to clipboard');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  number,
                  style: TextStyle(
                    color: BracuPalette.textPrimary(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.content_copy_rounded,
                  size: 14,
                  color: textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Tap to copy',
              style: TextStyle(
                color: textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
