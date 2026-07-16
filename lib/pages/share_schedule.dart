import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:flutter/rendering.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:archive/archive.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/pages/shared_widgets/session_helper.dart';
import 'package:preconnect/tools/app_storage.dart';
import 'package:preconnect/tools/app_paths.dart';
import 'package:preconnect/tools/storage_keys.dart';
import 'package:share_plus/share_plus.dart';
import 'package:preconnect/tools/refresh_bus.dart';

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
    if (reason == 'auth' || reason == 'friend_schedule') {
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

      final courses = sections.map((section) {
        final schedules = section.sectionSchedule.classSchedules.map((c) {
          return {"day": c.day, "startTime": c.startTime, "endTime": c.endTime};
        }).toList();

        return {
          "courseCode": section.courseCode,
          "sectionName": section.sectionName,
          "roomNumber": section.roomNumber,
          "roomName": section.roomName,
          "faculties": section.faculties,
          "schedule": schedules,
        };
      }).toList();

      final finalJson = {
        "name": fullName,
        "id": studentId,
        "photoFilePath": photoFilePath,
        "courses": courses,
        "shortCode": shortCode,
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
    final listContent = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isLoading || _base64Data == null)
            const _ShareScheduleLoadingState()
          else if (errorMessage != null)
            BracuEmptyState(message: "Error: $errorMessage")
          else ...[
            RepaintBoundary(
              key: _qrKey,
              child: Container(
                decoration: const BoxDecoration(color: Colors.white),
                padding: const EdgeInsets.all(12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.maxWidth;
                    return SizedBox(
                      width: size,
                      height: size,
                      child: BarcodeWidget(
                        barcode: Barcode.qrCode(),
                        data: _base64Data!,
                        color: const Color(0xFF000000),
                        backgroundColor: const Color(0xFFFFFFFF),
                        errorBuilder: (context, error) => Center(
                          child: Text(
                            'Unable to generate QR',
                            style: TextStyle(
                              color: BracuPalette.textSecondary(context),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const Gap(12),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _shareQrCode,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: BracuPalette.primary.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.qr_code_scanner,
                              size: 16,
                              color: BracuPalette.primary,
                            ),
                          ),
                          const Gap(10),
                          const Expanded(
                            child: Text(
                              'Share via QR',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: BracuPalette.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    return listContent;
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
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
      ),
    );
  }
}
