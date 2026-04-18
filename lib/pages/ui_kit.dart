import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:native_file_preview/native_file_preview.dart';
import 'package:preconnect/api/notification_service.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/progress_service.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:preconnect/api/grade_sheet_service.dart';
import 'package:preconnect/model/progress_info.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/cgpa_calculator.dart';
import 'package:preconnect/tools/cached_image.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/time_utils.dart';
import 'package:preconnect/tools/web_pdf_opener.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

part 'shared_widgets/ui_kit_components_part.dart';

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
  if (context.mounted) {
    showAppSnackBar(context, 'Support videos are no longer available.');
  }
  return false;
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
      child: OutlinedButton(onPressed: onPressed, child: Text(label)),
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
    this.autoPlay = false,
    this.autoPlayInterval = const Duration(seconds: 4),
  });

  final List<String> imageUrls;
  final double aspectRatio;
  final double borderRadius;
  final BoxFit imageFit;
  final int maxBytesInPrefs;
  final bool autoPlay;
  final Duration autoPlayInterval;

  @override
  State<BracuImageCarousel> createState() => _BracuImageCarouselState();
}

class _BracuImageCarouselState extends State<BracuImageCarousel> {
  late final PageController _controller;
  Timer? _autoPlayTimer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _restartAutoPlay();
  }

  @override
  void didUpdateWidget(covariant BracuImageCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldRestart =
        oldWidget.autoPlay != widget.autoPlay ||
        oldWidget.autoPlayInterval != widget.autoPlayInterval ||
        oldWidget.imageUrls.length != widget.imageUrls.length;
    if (!shouldRestart) return;
    _autoPlayTimer?.cancel();
    _index = 0;
    _restartAutoPlay();
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _restartAutoPlay() {
    if (!widget.autoPlay || widget.imageUrls.length < 2) return;
    _autoPlayTimer = Timer.periodic(widget.autoPlayInterval, (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_index + 1) % widget.imageUrls.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeInOut,
      );
    });
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
                placeholder: const BracuShimmer(
                  child: BracuSkeletonBox(height: 220, radius: 8),
                ),
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
                    placeholder: const BracuShimmer(
                      child: BracuSkeletonBox(height: 220, radius: 8),
                    ),
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
final NativeFilePreview _nativeFilePreview = NativeFilePreview();

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
  try {
    if (kIsWeb) {
      final bytes = await GradeSheetService().fetchGradeSheetBytes(
        fromGet: true,
      );
      if (!context.mounted) return;
      if (bytes == null || bytes.isEmpty) {
        showAppSnackBar(context, 'Could not fetch the latest grade sheet');
        return;
      }
      final fileName = await GradeSheetService().gradeSheetFileName();
      await openPdfInBrowser(bytes: bytes, fileName: '$fileName.pdf');
      return;
    }

    final gradeSheet = await GradeSheetService().fetchGradeSheet(fromGet: true);
    if (!context.mounted) return;
    if (gradeSheet == null) {
      showAppSnackBar(context, 'Could not fetch the latest grade sheet');
      return;
    }
    await _nativeFilePreview.previewFile(gradeSheet.file.path);
  } on PlatformException catch (error) {
    if (!context.mounted) return;
    final message = switch (error.code) {
      'NO_APP_FOUND' => 'No app found to open this PDF.',
      'FILE_NOT_FOUND' => 'The PDF file was not found.',
      _ => error.message ?? 'Could not open the PDF.',
    };
    showAppSnackBar(context, message);
  } catch (_) {
    if (!context.mounted) return;
    showAppSnackBar(context, 'Could not open the PDF.');
  }
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
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: const Text('Loading...', style: TextStyle(color: Colors.white)),
      backgroundColor: BracuPalette.primary,
      duration: const Duration(seconds: 20),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
  );

  try {
    final info = await ProgressService().getProgress();
    final profile = await ProfileService().getProfile();
    final scheduleJson = await ScheduleService().getStudentSchedule();
    if (!context.mounted) return;

    if (info == null) {
      messenger.hideCurrentSnackBar();
      showAppSnackBar(
        context,
        'No progress data available for CGPA calculator',
      );
      return;
    }

    final currentCgpa = (profile?['cgpa'] ?? '').trim();
    final sections = buildCurrentSectionsForCalculator(info, scheduleJson);
    messenger.hideCurrentSnackBar();
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
    messenger.hideCurrentSnackBar();
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
  if (context.mounted) {
    showAppSnackBar(context, 'Support options are no longer available.');
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
