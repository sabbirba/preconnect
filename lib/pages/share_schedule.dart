import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:flutter/rendering.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:archive/archive.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/features/schedule/application/session_resolver.dart';
import 'package:preconnect/pages/shared_widgets/qr_card.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/app_paths.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:share_plus/share_plus.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/pages/shared_widgets/online_guard.dart';

class ShareSchedulePage extends StatefulWidget {
  const ShareSchedulePage({super.key});

  @override
  State<ShareSchedulePage> createState() => _ShareSchedulePageState();
}

class _ShareSchedulePageState extends State<ShareSchedulePage>
    with RefreshBusState {
  static const int _qrPayloadVersion = 4;
  String? _base64Data;
  bool isLoading = false;
  String? errorMessage;
  final GlobalKey _qrKey = GlobalKey();
  bool _isRefreshing = false;
  bool _copied = false;

  Future<void> _copyToClipboard() async {
    if (_base64Data == null) return;
    await Clipboard.setData(ClipboardData(text: _base64Data!));
    if (!mounted) return;
    setState(() {
      _copied = true;
    });
    showAppSnackBar(context, 'Schedule code copied.');
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    unawaited(ProfileService().fetchProfile());
    unawaited(_primeCurrentSemesterSchedule());
    _loadCachedAndRefresh();
    bindRefreshBus(_onRefreshSignal);
  }

  @override
  void dispose() {
    unbindRefreshBus(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    final reason = refreshBusReason;
    if (reason == 'share_schedule') {
      return;
    }
    if (reason == 'auth' ||
        reason == 'friend_schedule' ||
        reason == 'cache_cleared') {
      unawaited(_refreshIfOnline());
    }
  }

  Future<void> _primeCurrentSemesterSchedule() async {
    final semesterSessionId = await resolveCurrentSessionSemesterIdWithRetry();
    if (semesterSessionId == null) return;
    await ScheduleService().fetchStudentScheduleForSemester(
      semesterSessionId: semesterSessionId,
    );
  }

  Future<void> _refreshIfOnline({bool notify = false}) async {
    if (!await ensureOnline(context, notify: notify)) {
      return;
    }
    if (!mounted) return;
    await _fetchAndConvertSchedule(forceRefresh: true);
  }

  Future<void> _loadCachedAndRefresh() async {
    _safeSetState(() {
      errorMessage = null;
    });

    if (kIsWeb) {
      await _fetchAndConvertSchedule();
      return;
    }

    final cachedBase64 = await AppStorage.instance.getString(
      StorageKeys.qrBase64,
    );
    final cachedHash = await AppStorage.instance.getString(StorageKeys.qrHash);
    final cachedVersion = await AppStorage.instance.getInt(
      StorageKeys.qrPayloadVersion,
    );

    if (cachedBase64 != null &&
        cachedBase64.isNotEmpty &&
        cachedVersion == _qrPayloadVersion) {
      _safeSetState(() {
        _base64Data = cachedBase64;
        isLoading = false;
      });
      unawaited(_refreshIfOnline(notify: false));
      return;
    }

    await _fetchAndConvertSchedule(
      cachedHash: cachedHash,
      cachedBase64: cachedBase64,
      cachedVersion: cachedVersion,
    );
  }

  Future<void> _fetchAndConvertSchedule({
    String? cachedHash,
    String? cachedBase64,
    int? cachedVersion,
    bool forceRefresh = false,
  }) async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    _safeSetState(() {
      errorMessage = null;
    });

    try {
      final cachedProfile = await ProfileService().getProfile();
      final profile = forceRefresh
          ? await ProfileService().fetchProfile()
          : (cachedProfile ?? await ProfileService().fetchProfile());
      final fullName = profile?['fullName'] ?? '';
      final studentId = profile?['studentId'] ?? '';
      final photoFilePath = profile?['photoFilePath'] ?? '';

      final semesterSessionId =
          await resolveCurrentSessionSemesterIdWithRetry();
      if (semesterSessionId == null) {
        if (_base64Data == null) {
          _safeSetState(() {
            errorMessage = 'No schedule data available offline.';
          });
        }
        return;
      }
      final cachedSchedule = await ScheduleService()
          .getStudentScheduleForSemester(semesterSessionId: semesterSessionId);
      final jsonString = forceRefresh
          ? await ScheduleService().fetchStudentScheduleForSemester(
              semesterSessionId: semesterSessionId,
            )
          : (cachedSchedule ??
                await ScheduleService().fetchStudentScheduleForSemester(
                  semesterSessionId: semesterSessionId,
                ));
      if (jsonString == null || jsonString.trim().isEmpty) {
        if (_base64Data == null) {
          _safeSetState(() {
            errorMessage = 'No schedule data available offline.';
          });
        }
        return;
      }

      final currentSemester = profile?['currentSemester'] ?? '';
      final shortCode = profile?['shortCode'] ?? '';

      final fingerprint = _fastHash(
        'v$_qrPayloadVersion|$studentId|$fullName|$photoFilePath|$shortCode|$currentSemester|$jsonString',
      );
      if (!forceRefresh &&
          cachedBase64 != null &&
          cachedHash == fingerprint &&
          cachedVersion == _qrPayloadVersion) {
        _safeSetState(() {
          isLoading = false;
        });
        return;
      }

      final sections = ScheduleService().parseStudentSections(
        jsonString,
        semesterSessionId: semesterSessionId,
      );

      final courses = sections.map((section) => section.toJson()).toList();

      final finalJson = {
        "name": fullName,
        "id": studentId,
        "photoFilePath": photoFilePath,
        "courses": courses,
        "semester": currentSemester,
      };

      final jsonStr = jsonEncode(finalJson);
      final utf8Bytes = utf8.encode(jsonStr);
      final gzipBytes = GZipEncoder().encode(utf8Bytes);
      final base64Str = base64.encode(gzipBytes);

      if (!kIsWeb) {
        await AppStorage.instance.setString(StorageKeys.qrBase64, base64Str);
        await AppStorage.instance.setString(StorageKeys.qrHash, fingerprint);
        await AppStorage.instance.setInt(
          StorageKeys.qrPayloadVersion,
          _qrPayloadVersion,
        );
      }

      _safeSetState(() {
        _base64Data = base64Str;
      });
    } catch (e) {
      _safeSetState(() {
        errorMessage = 'Failed to generate. Please try again.';
      });
    } finally {
      _isRefreshing = false;
      _safeSetState(() {
        isLoading = false;
      });
    }
  }

  String _fastHash(String input) {
    int hash = 5381;
    for (final codeUnit in input.codeUnits) {
      hash = ((hash << 5) + hash) ^ codeUnit;
      hash &= 0x7fffffff;
    }
    return hash.toString();
  }

  Future<void> _shareQrCode() async {
    if (_base64Data == null) {
      if (!mounted) return;
      showAppSnackBar(context, 'No QR data available to share');
      return;
    }

    try {
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        if (!mounted) return;
        showAppSnackBar(context, 'Unable to capture QR code');
        return;
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ImageByteFormat.png);
      if (byteData == null) {
        if (!mounted) return;
        showAppSnackBar(context, 'Unable to capture QR code');
        return;
      }

      final bytes = byteData.buffer.asUint8List();
      const fileName = 'preconnect_schedule_qr.png';

      const shareText =
          "Scan my schedule QR to import in PreConnect's Friends Schedule.\n"
          'App link: https://play.google.com/store/apps/details?id=com.sabbirba.preconnect';

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
          subject: 'Share Schedule QR',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, 'Unable to share QR code');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading || _base64Data == null) {
      return const _ShareScheduleLoadingState();
    }

    if (errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: BracuEmptyState(message: 'Error: $errorMessage'),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: RepaintBoundary(
            key: _qrKey,
            child: BracuQrCard(data: _base64Data!),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BracuActionButton(
                onPressed: _copyToClipboard,
                label: _copied ? 'Copied' : 'Copy Code',
                icon: _copied ? Icons.check_circle_rounded : Icons.copy_rounded,
                outlined: false,
                backgroundColor: _copied
                    ? BracuPalette.accent
                    : BracuPalette.primary,
                foregroundColor: Colors.white,
              ),
              const Gap(12),
              BracuActionButton(
                onPressed: _shareQrCode,
                label: 'Share via QR',
                icon: Icons.qr_code_scanner,
                outlined: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShareScheduleLoadingState extends StatelessWidget {
  const _ShareScheduleLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: SizedBox(
          width: 28,
          height: 28,
          child: BracuSpinner(size: 28, strokeWidth: 2.6),
        ),
      ),
    );
  }
}
