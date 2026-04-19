import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/api/schedule_service.dart';
import 'package:archive/archive.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/pages/shared_widgets/current_session_helper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:preconnect/tools/app_storage.dart';
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
    final semesterSessionId = await resolveCurrentSessionSemesterId();
    await ScheduleService().fetchStudentScheduleForSemester(
      semesterSessionId: semesterSessionId,
    );
  }

  Future<void> _refreshIfOnline({bool notify = false}) async {
    if (!await ensureOnline(context, notify: notify)) {
      return;
    }
    await _fetchAndConvertSchedule(forceRefresh: true);
  }

  Future<void> _loadCachedAndRefresh() async {
    _safeSetState(() {
      isLoading = true;
      errorMessage = null;
    });

    final cachedBase64 = await AppStorage.instance.getString('qr_base64');
    final cachedHash = await AppStorage.instance.getString('qr_hash');
    final cachedVersion = await AppStorage.instance.getInt(
      'qr_payload_version',
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
    if (_base64Data == null) {
      _safeSetState(() {
        isLoading = true;
        errorMessage = null;
      });
    }

    try {
      final cachedProfile = await ProfileService().getProfile();
      final profile = forceRefresh
          ? await ProfileService().fetchProfile()
          : (cachedProfile ?? await ProfileService().fetchProfile());
      final fullName = profile?['fullName'] ?? '';
      final studentId = profile?['studentId'] ?? '';
      final photoFilePath = profile?['photoFilePath'] ?? '';

      final semesterSessionId = await resolveCurrentSessionSemesterId();
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

      final fingerprint = _fastHash(
        'v$_qrPayloadVersion|$studentId|$fullName|$photoFilePath|$jsonString',
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
      };

      final jsonStr = jsonEncode(finalJson);
      final utf8Bytes = utf8.encode(jsonStr);
      final gzipBytes = GZipEncoder().encode(utf8Bytes);
      final base64Str = base64.encode(gzipBytes);

      await AppStorage.instance.setString('qr_base64', base64Str);
      await AppStorage.instance.setString('qr_hash', fingerprint);
      await AppStorage.instance.setInt('qr_payload_version', _qrPayloadVersion);

      _safeSetState(() {
        _base64Data = base64Str;
      });
    } catch (e) {
      if (_base64Data == null) {
        _safeSetState(() {
          errorMessage = e.toString();
        });
      }
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

  Future<void> _handleRefresh() async {
    if (!await ensureOnline(context)) {
      return;
    }
    await AppStorage.instance.remove('qr_base64');
    await AppStorage.instance.remove('qr_hash');
    await AppStorage.instance.remove('qr_payload_version');
    await _fetchAndConvertSchedule(forceRefresh: true);
    RefreshBus.instance.notify(reason: 'share_schedule');
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
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(bytes, mimeType: 'image/png', name: fileName),
            ],
            text: shareText,
          ),
        );
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: shareText),
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, 'Unable to share QR code');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Share Schedule',
      subtitle: 'Generate QR for Friends',
      icon: Icons.qr_code_2,
      body: isLoading
          ? const _ShareScheduleLoadingState()
          : BracuRefreshList(
              onRefresh: _handleRefresh,
              children: [
                if (errorMessage != null)
                  BracuEmptyState(message: "Error: $errorMessage")
                else ...[
                  const BracuSectionTitle(title: 'Your QR Code'),
                  const SizedBox(height: 10),
                  BracuCard(
                    child: RepaintBoundary(
                      key: _qrKey,
                      child: Container(
                        decoration: const BoxDecoration(color: Colors.white),
                        padding: const EdgeInsets.all(12),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final size = constraints.maxWidth;
                            if (_base64Data == null) {
                              return SizedBox(
                                height: size,
                                child: Center(
                                  child: Text(
                                    'No QR data available',
                                    style: TextStyle(
                                      color:
                                          BracuPalette.textSecondary(context),
                                    ),
                                  ),
                                ),
                              );
                            }

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
                                      color:
                                          BracuPalette.textSecondary(context),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
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
                              color: BracuPalette.primary.withValues(
                                alpha: 0.08,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: BracuPalette.primary.withValues(
                                  alpha: 0.18,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: BracuPalette.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.qr_code_scanner,
                                    size: 16,
                                    color: BracuPalette.primary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Share via QR',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: BracuPalette.primary,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: 14,
                                  color:
                                      BracuPalette.primary.withValues(alpha: 0.7),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const BracuSectionTitle(title: 'How to use'),
                  const SizedBox(height: 10),
                  BracuCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Share your schedule by showing the QR code to your friend. They scan it to add you.',
                          style: TextStyle(
                            color: BracuPalette.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }
}

class _ShareScheduleLoadingState extends StatelessWidget {
  const _ShareScheduleLoadingState();

  @override
  Widget build(BuildContext context) {
    return BracuShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < 4; index++) ...[
            if (index != 0) const SizedBox(height: 12),
            BracuCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  BracuSkeletonBox(width: 140, height: 14, radius: 7),
                  SizedBox(height: 10),
                  BracuSkeletonBox(
                    width: double.infinity,
                    height: 220,
                    radius: 14,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
