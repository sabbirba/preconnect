import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:preconnect/api/bracu_auth_manager.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/tools/qrpainter.dart';
import 'package:archive/archive.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/refresh_guard.dart';

class ShareSchedulePage extends StatefulWidget {
  const ShareSchedulePage({super.key});

  @override
  State<ShareSchedulePage> createState() => _ShareSchedulePageState();
}

class _ShareSchedulePageState extends State<ShareSchedulePage> {
  static const int _qrPayloadVersion = 4;
  String? _base64Data;
  bool isLoading = false;
  String? errorMessage;
  final GlobalKey _qrKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    unawaited(BracuAuthManager().fetchProfile());
    unawaited(BracuAuthManager().fetchStudentSchedule());
    _loadCachedAndRefresh();
    RefreshBus.instance.addListener(_onRefreshSignal);
  }

  @override
  void dispose() {
    RefreshBus.instance.removeListener(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (RefreshBus.instance.reason == 'share_schedule') {
      return;
    }
    unawaited(_refreshIfOnline());
  }

  Future<void> _refreshIfOnline({bool notify = false}) async {
    if (!await ensureOnline(context, notify: notify)) {
      return;
    }
    await _fetchAndConvertSchedule(forceRefresh: true);
  }

  Future<void> _loadCachedAndRefresh() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    final prefs = await SharedPreferences.getInstance();
    final cachedBase64 = prefs.getString('qr_base64');
    final cachedHash = prefs.getString('qr_hash');
    final cachedVersion = prefs.getInt('qr_payload_version');

    if (cachedBase64 != null &&
        cachedBase64.isNotEmpty &&
        cachedVersion == _qrPayloadVersion) {
      setState(() {
        _base64Data = cachedBase64;
        isLoading = false;
      });
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
    if (_base64Data == null) {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
    }

    try {
      if (!forceRefresh) {
        unawaited(BracuAuthManager().fetchProfile());
      }
      final cachedProfile = await BracuAuthManager().getProfile();
      final profile = forceRefresh
          ? await BracuAuthManager().fetchProfile()
          : (cachedProfile ?? await BracuAuthManager().fetchProfile());
      final fullName = profile?['fullName'] ?? 'N/A';
      final studentId = profile?['studentId'] ?? 'N/A';
      final photoFilePath = profile?['photoFilePath'] ?? '';

      if (!forceRefresh) {
        unawaited(BracuAuthManager().fetchStudentSchedule());
      }
      final cachedSchedule = await BracuAuthManager().getStudentSchedule();
      final jsonString = forceRefresh
          ? await BracuAuthManager().fetchStudentSchedule()
          : (cachedSchedule ?? await BracuAuthManager().fetchStudentSchedule());
      if (jsonString == null || jsonString.trim().isEmpty) {
        if (_base64Data == null) {
          setState(() {
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
        setState(() {
          isLoading = false;
        });
        return;
      }

      final decoded = jsonDecode(jsonString) as List<dynamic>;
      final sections = decoded.map((e) => Section.fromJson(e)).toList();

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

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('qr_base64', base64Str);
      await prefs.setString('qr_hash', fingerprint);
      await prefs.setInt('qr_payload_version', _qrPayloadVersion);

      setState(() {
        _base64Data = base64Str;
      });
    } catch (e) {
      if (_base64Data == null) {
        setState(() {
          errorMessage = e.toString();
        });
      }
    } finally {
      setState(() {
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('qr_base64');
    await prefs.remove('qr_hash');
    await prefs.remove('qr_payload_version');
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
        await Share.shareXFiles([
          XFile.fromData(bytes, mimeType: 'image/png', name: fileName),
        ], text: shareText);
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles([XFile(file.path)], text: shareText);
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
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (isLoading)
              const BracuLoading(label: 'Preparing QR...')
            else if (errorMessage != null)
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
                                  color: BracuPalette.textSecondary(context),
                                ),
                              ),
                            ),
                          );
                        }

                        return SizedBox(
                          width: size,
                          height: size,
                          child: CustomPaint(
                            size: Size.square(size),
                            painter: QrPainter(
                              _base64Data!,
                              fgColor: const Color(0xFF000000),
                              bgColor: const Color(0xFFFFFFFF),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _shareQrCode,
                borderRadius: BorderRadius.circular(18),
                child: BracuCard(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: BracuPalette.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.share_outlined,
                          color: BracuPalette.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Share QR Code',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward,
                        color: BracuPalette.textSecondary(context),
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const BracuSectionTitle(title: 'How to use'),
              const SizedBox(height: 10),
              BracuCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ask your friend to scan this QR code. It shares your schedule '
                      'for quick import to their app.',
                      style: TextStyle(
                        color: BracuPalette.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
