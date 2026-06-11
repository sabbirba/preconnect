import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart'
    show ValueListenable, TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/notification.dart';
import 'package:preconnect/api/progress.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/api/grade_sheet.dart';
import 'package:preconnect/model/progress_info.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/cgpa_calculator.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/cached_image.dart';
import 'package:preconnect/tools/token_storage.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/time_utils.dart';
import 'package:preconnect/tools/web_shared.dart';
import 'package:preconnect/pages/shared_widgets/current_session_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:io';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:share_plus/share_plus.dart';
import 'package:preconnect/tools/app_paths.dart';
import 'package:flutter/rendering.dart';

export 'package:preconnect/tools/web_shared.dart';

part 'shared_widgets/ui_kit_core.dart';
part 'shared_widgets/ui_kit_dialogs.dart';
part 'shared_widgets/ui_kit_selects.dart';
part 'shared_widgets/ui_kit_refresh.dart';
part 'shared_widgets/ui_kit_chrome.dart';
part 'shared_widgets/ui_kit_launchers.dart';

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

String formatDateTimeRange(
  DateTime start,
  DateTime end, {
  bool includeYear = true,
}) {
  final startLocal = start.toLocal();
  final endLocal = end.toLocal();
  final sameDay =
      startLocal.year == endLocal.year &&
      startLocal.month == endLocal.month &&
      startLocal.day == endLocal.day;

  final startLabel = formatDateTimeLabel(start, includeYear: includeYear);
  if (sameDay) {
    return '$startLabel – ${BracuTime.formatDateTime(endLocal)}';
  } else {
    return '$startLabel – ${formatDateTimeLabel(end, includeYear: includeYear)}';
  }
}

void copyToClipboard(BuildContext context, String text) {
  final value = text.trim();
  if (value.isEmpty) return;
  Clipboard.setData(ClipboardData(text: value));
  showAppSnackBar(context, 'Copied to clipboard');
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
    final count = widget.imageUrls.length;
    final initialPage = count > 0 ? (5000 ~/ count) * count : 0;
    _controller = PageController(initialPage: initialPage);
    _index = initialPage;
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
                placeholder: const SizedBox.shrink(),
                error: const _BracuImageErrorFallback(),
              )
            else
              PageView.builder(
                controller: _controller,
                onPageChanged: (value) {
                  if (!mounted) return;
                  setState(() {
                    _index = value;
                  });
                },
                itemBuilder: (context, idx) {
                  final imageIndex = idx % widget.imageUrls.length;
                  return CachedImage(
                    url: widget.imageUrls[imageIndex],
                    fit: widget.imageFit,
                    placeholder: const SizedBox.shrink(),
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
                  child: Text(
                    '${(_index % widget.imageUrls.length) + 1}/${widget.imageUrls.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
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

void showAppSnackBar(
  BuildContext context,
  String message, {
  String actionLabel = 'Close',
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 2),
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
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(trimmed, style: const TextStyle(color: Colors.white)),
      backgroundColor: isDark ? const Color(0xFF1E6BE3) : BracuPalette.primary,
      duration: duration,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      action: SnackBarAction(
        label: actionLabel,
        textColor: Colors.white,
        onPressed: () {
          try {
            messenger.hideCurrentSnackBar();
          } catch (_) {}
          if (onAction != null) {
            onAction();
          }
        },
      ),
    ),
  );
}

Future<void> openGradeSheet(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  try {
    if (kIsWeb) {
      final bytes = await GradeSheetService().fetchGradeSheetBytes();
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

    final gradeSheet = await GradeSheetService().fetchGradeSheet();
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
      action: SnackBarAction(
        label: 'Close',
        textColor: Colors.white,
        onPressed: () {
          try {
            messenger.hideCurrentSnackBar();
          } catch (_) {}
        },
      ),
    ),
  );
}

Future<bool> _openPdfNativelyOrFallback(String filePath) async {
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    try {
      final result = await OpenFilex.open(filePath);
      return result.type == ResultType.done;
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
    final semesterSessionId = await resolveCurrentSessionSemesterId();
    if (semesterSessionId == null) {
      if (!context.mounted) return;
      showAppSnackBar(context, 'No current semester schedule available.');
      return;
    }
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

    final currentCgpa =
        (await AppStorage.instance.getString(StorageKeys.cgpa) ?? '').trim();
    if (!context.mounted) return;
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
    this.icon,
    this.iconWidget,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.iconColor = BracuPalette.primary,
    this.iconDecoration = false,
    this.showTrailingIcon = true,
    this.showBorder = true,
    this.trailing,
  });

  final IconData? icon;
  final Widget? iconWidget;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color iconColor;
  final bool iconDecoration;
  final bool showTrailingIcon;
  final bool showBorder;

  /// Custom trailing widget. When provided, takes precedence over [showTrailingIcon].
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: showBorder
              ? Border.all(
                  color: BracuPalette.textSecondary(context).withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.22
                        : 0.16,
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            if (iconWidget != null) ...[
              iconWidget!,
              const SizedBox(width: 12),
            ] else if (icon != null) ...[
              if (iconDecoration)
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 18),
                )
              else
                Icon(icon, color: iconColor, size: 30),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: BracuPalette.textPrimary(context),
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: BracuPalette.textSecondary(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (showTrailingIcon)
              Icon(
                Icons.chevron_right,
                color: BracuPalette.textSecondary(context),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> showBracuFundingSupportSheet(BuildContext context) async {
  await openExternalUrl(
    context,
    'https://preconnect.app/funding',
    failureMessage: 'Unable to open funding link.',
  );
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

const String kPreconnectDiscordUrl = 'https://discord.gg/HwrgeFrvaz';
const String kPreconnectRepositoryUrl =
    'https://github.com/sabbirba/preconnect';

class PreconnectDiscordIcon extends StatelessWidget {
  const PreconnectDiscordIcon({super.key, this.size = 30, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.discord,
      size: size,
      color: color ?? const Color.fromRGBO(88, 101, 242, 1),
    );
  }
}

class PreconnectGithubIcon extends StatelessWidget {
  const PreconnectGithubIcon({super.key, this.size = 24.0, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _GithubLogoPainter(color: color ?? BracuPalette.primary),
    );
  }
}

class _GithubLogoPainter extends CustomPainter {
  _GithubLogoPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final scale = size.width / 24.0;
    canvas.scale(scale, scale);

    final path = Path()
      ..moveTo(12.0, 0.0)
      ..cubicTo(5.373, 0.0, 0.0, 5.373, 0.0, 12.0)
      ..cubicTo(0.0, 17.302, 3.438, 21.8, 8.207, 23.387)
      ..cubicTo(8.806, 23.498, 9.0, 23.126, 9.0, 22.81)
      ..cubicTo(9.0, 22.5, 8.988, 21.5, 8.982, 20.25)
      ..cubicTo(5.644, 20.976, 4.949, 18.834, 4.949, 18.834)
      ..cubicTo(4.403, 17.447, 3.616, 17.078, 3.616, 17.078)
      ..cubicTo(2.527, 16.333, 3.699, 16.349, 3.699, 16.349)
      ..cubicTo(4.904, 16.433, 5.538, 17.586, 5.538, 17.586)
      ..cubicTo(6.608, 19.42, 8.345, 18.89, 9.03, 18.583)
      ..cubicTo(9.137, 17.808, 9.448, 17.278, 9.792, 16.979)
      ..cubicTo(7.127, 16.674, 4.325, 15.645, 4.325, 11.048)
      ..cubicTo(4.325, 9.737, 4.794, 8.667, 5.561, 7.827)
      ..cubicTo(5.437, 7.524, 5.026, 6.303, 5.678, 4.651)
      ..cubicTo(5.678, 4.651, 6.686, 4.329, 8.979, 5.881)
      ..cubicTo(9.936, 5.615, 10.962, 5.482, 11.982, 5.477)
      ..cubicTo(13.002, 5.482, 14.029, 5.615, 14.988, 5.881)
      ..cubicTo(17.279, 4.329, 18.285, 4.651, 18.285, 4.651)
      ..cubicTo(18.938, 6.303, 18.527, 7.524, 18.403, 7.827)
      ..cubicTo(19.173, 8.667, 19.638, 9.737, 19.638, 11.048)
      ..cubicTo(19.638, 15.657, 16.831, 16.672, 14.159, 16.969)
      ..cubicTo(14.589, 17.341, 14.982, 18.071, 14.982, 19.191)
      ..cubicTo(14.982, 20.793, 14.968, 22.09, 14.968, 22.81)
      ..cubicTo(14.968, 23.129, 15.16, 23.504, 15.769, 23.386)
      ..cubicTo(20.535, 21.796, 23.969, 17.299, 23.969, 11.999)
      ..cubicTo(24.0, 5.373, 18.627, 0.0, 12.0, 0.0)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GithubLogoPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class BracuCommunityLink extends StatelessWidget {
  const BracuCommunityLink({super.key, this.compact = false});

  final bool compact;

  static const String _title = 'Discord Community';
  static const String _subtitle = 'Connect, share ideas, and get support.';
  static const String _label = 'Discord';

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _BracuSponsorActionChip(
        iconWidget: const PreconnectDiscordIcon(
          size: 18,
          color: BracuPalette.primary,
        ),
        label: _label,
        onTap: () => openExternalUrl(
          context,
          kPreconnectDiscordUrl,
          failureMessage: 'Unable to open Discord.',
        ),
      );
    }

    return BracuActionBannerCard(
      iconWidget: const PreconnectDiscordIcon(
        size: 24,
        color: Color.fromRGBO(88, 101, 242, 1),
      ),
      title: _title,
      subtitle: _subtitle,
      onTap: () {
        openExternalUrl(
          context,
          kPreconnectDiscordUrl,
          failureMessage: 'Unable to open Discord.',
        );
        showAppSnackBar(context, 'Opened server link.');
      },
    );
  }
}

class BracuFundingPromoDivider extends StatelessWidget {
  const BracuFundingPromoDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    final borderColor = textSecondary.withValues(alpha: 0.18);
    return InkWell(
      onTap: () => openExternalUrl(
        context,
        'https://preconnect.app/funding',
        failureMessage: 'Unable to open funding link.',
      ),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Expanded(child: Container(height: 1, color: borderColor)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'Support PreConnect iOS Funding Campaign',
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(child: Container(height: 1, color: borderColor)),
          ],
        ),
      ),
    );
  }
}

const String _kPreconnectSupportNumber = '01865493144';
const String _kPreconnectSupportReference = 'PreConnect App';
const String _kPreconnectSupportQrData =
    'https://qr.bka.sh/281014021P3BymAwed3CDD8CFE';
const String _kPreconnectWhatsAppUrl =
    'https://api.whatsapp.com/send?phone=8801865493144&text=Hi%20PreConnect%2C%20I%20want%20to%20support%20the%20app.';

class BracuFundingSupportContent extends StatelessWidget {
  const BracuFundingSupportContent({super.key});

  @override
  Widget build(BuildContext context) {
    return const _BracuFundingSupportContentBody();
  }
}

class _BracuFundingSupportContentBody extends StatefulWidget {
  const _BracuFundingSupportContentBody();

  @override
  State<_BracuFundingSupportContentBody> createState() =>
      _BracuFundingSupportContentBodyState();
}

class _BracuFundingSupportContentBodyState
    extends State<_BracuFundingSupportContentBody> {
  final GlobalKey _qrShareKey = GlobalKey();

  Future<void> _shareQrCode() async {
    final boundary =
        _qrShareKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      if (!mounted) return;
      showAppSnackBar(context, 'Unable to capture QR code');
      return;
    }

    try {
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        if (!mounted) return;
        showAppSnackBar(context, 'Unable to capture QR code');
        return;
      }

      final bytes = byteData.buffer.asUint8List();
      const fileName = 'preconnect_support_qr.png';
      const shareText =
          'Scan this QR to support PreConnect.\n'
          'Reference: $_kPreconnectSupportReference';

      if (kIsWeb) {
        await openImageInBrowser(bytes: bytes, fileName: fileName);
        if (!mounted) return;
        showAppSnackBar(context, 'Share sheet opened');
        return;
      }

      final tempDir = await AppPaths.temporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: shareText,
          subject: 'PreConnect Support QR',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Unable to share QR code');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 0.0;
        final qrSize = math.min(math.max(availableWidth * 0.54, 160.0), 260.0);
        final rightWidth = math.max(0.0, availableWidth - qrSize - 20);
        final rightTextScale = (rightWidth / 220.0).clamp(0.72, 1.0);

        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: _shareQrCode,
                  child: RepaintBoundary(
                    key: _qrShareKey,
                    child: SizedBox.square(
                      dimension: qrSize,
                      child: ColoredBox(
                        color: Colors.transparent,
                        child: BarcodeWidget(
                          barcode: Barcode.qrCode(),
                          data: _kPreconnectSupportQrData,
                          color: const Color(0xFFE91E63),
                          backgroundColor: Colors.transparent,
                          drawText: false,
                          errorBuilder: (context, error) {
                            return Container(
                              alignment: Alignment.center,
                              color: Colors.transparent,
                              child: const Icon(
                                Icons.qr_code_2_rounded,
                                color: BracuPalette.primary,
                                size: 44,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: SizedBox(
                    height: qrSize,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Align(
                              alignment: Alignment.center,
                              child: BracuSupportNumberRow(
                                number: _kPreconnectSupportNumber,
                                textScale: rightTextScale,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Align(
                              alignment: Alignment.center,
                              child: Text(
                                'Send money with reference',
                                style: TextStyle(
                                  color: BracuPalette.textSecondary(context),
                                  fontSize: 11 * rightTextScale,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Align(
                              alignment: Alignment.center,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () async {
                                  await Clipboard.setData(
                                    const ClipboardData(
                                      text: _kPreconnectSupportReference,
                                    ),
                                  );
                                  if (context.mounted) {
                                    showAppSnackBar(
                                      context,
                                      'Reference copied',
                                    );
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _kPreconnectSupportReference,
                                              style: TextStyle(
                                                color: BracuPalette.textPrimary(
                                                  context,
                                                ),
                                                fontSize: 14 * rightTextScale,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Icon(
                                              Icons.content_copy_rounded,
                                              size: 13 * rightTextScale,
                                              color: BracuPalette.textSecondary(
                                                context,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Tap to copy',
                                        style: TextStyle(
                                          color: BracuPalette.textSecondary(
                                            context,
                                          ),
                                          fontSize: 9 * rightTextScale,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            'Scan the QR code in your bKash app to support or send money manually using the number.',
                            style: TextStyle(
                              color: BracuPalette.textSecondary(context),
                              fontSize: 13 * rightTextScale,
                              fontWeight: FontWeight.w400,
                              height: 1.35,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Your support helps cover server costs, ongoing development, and app releases so PreConnect can stay reliable.',
                style: TextStyle(
                  color: BracuPalette.textSecondary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _BracuSponsorActionChip(
                    iconWidget: const Icon(
                      Icons.phone_rounded,
                      size: 18,
                      color: BracuPalette.primary,
                    ),
                    label: _kPreconnectSupportNumber,
                    onTap: () =>
                        openPhoneDialer(context, _kPreconnectSupportNumber),
                  ),
                  _BracuSponsorActionChip(
                    iconWidget: const Icon(
                      Icons.chat_rounded,
                      size: 18,
                      color: BracuPalette.primary,
                    ),
                    label: 'WhatsApp',
                    onTap: () => openExternalUrl(
                      context,
                      _kPreconnectWhatsAppUrl,
                      failureMessage: 'Unable to open WhatsApp.',
                    ),
                  ),
                  _BracuSponsorActionChip(
                    iconWidget: const PreconnectDiscordIcon(
                      size: 18,
                      color: BracuPalette.primary,
                    ),
                    label: 'Discord',
                    onTap: () => openExternalUrl(
                      context,
                      kPreconnectDiscordUrl,
                      failureMessage: 'Unable to open Discord.',
                    ),
                  ),
                  _BracuSponsorActionChip(
                    iconWidget: const PreconnectGithubIcon(
                      size: 18,
                      color: BracuPalette.primary,
                    ),
                    label: 'GitHub',
                    onTap: () =>
                        openExternalUrl(context, kPreconnectRepositoryUrl),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class BracuSupportNumberRow extends StatelessWidget {
  const BracuSupportNumberRow({
    super.key,
    required this.number,
    this.textScale = 1.0,
  });

  final String number;
  final double textScale;

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
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    number,
                    style: TextStyle(
                      color: BracuPalette.textPrimary(context),
                      fontSize: 16 * textScale,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.content_copy_rounded,
                    size: 14 * textScale,
                    color: textSecondary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'bKash / Nagad / Upay',
              style: TextStyle(color: textSecondary, fontSize: 11 * textScale),
            ),
            const SizedBox(height: 2),
            Text(
              'Tap to copy',
              style: TextStyle(color: textSecondary, fontSize: 9 * textScale),
            ),
          ],
        ),
      ),
    );
  }
}

class _BracuSponsorActionChip extends StatelessWidget {
  const _BracuSponsorActionChip({
    this.iconWidget,
    required this.label,
    required this.onTap,
  });

  final Widget? iconWidget;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (iconWidget != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: BracuPalette.textSecondary(
                context,
              ).withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconWidget!,
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: BracuPalette.primary,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return BracuActionButton(
      onPressed: onTap,
      label: label,
      borderRadius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      iconWidget: iconWidget,
    );
  }
}
