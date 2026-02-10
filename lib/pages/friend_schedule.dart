import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/model/friend_schedule.dart';
import 'package:archive/archive.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/pages/friend_schedule_sections/friend_action_card.dart';
import 'package:preconnect/pages/friend_schedule_sections/schedule_list.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/local_notifications.dart';
import 'package:preconnect/tools/notification_store.dart';
import 'package:preconnect/model/notification_item.dart';
import 'package:preconnect/tools/refresh_bus.dart';

class FriendSchedulePage extends StatefulWidget {
  const FriendSchedulePage({super.key, required this.onNavigate});

  final void Function(HomeTab tab) onNavigate;

  @override
  State<FriendSchedulePage> createState() => _FriendSchedulePageState();
}

class _FriendSchedulePageState extends State<FriendSchedulePage> {
  List<FriendScheduleItem> decodedSchedules = [];
  final MobileScannerController _galleryScanner = MobileScannerController();
  bool _isPicking = false;

  @override
  void initState() {
    super.initState();
    _loadSchedules();
    RefreshBus.instance.addListener(_onRefreshSignal);
  }

  @override
  void dispose() {
    RefreshBus.instance.removeListener(_onRefreshSignal);
    _galleryScanner.dispose();
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (RefreshBus.instance.reason == 'friend_schedule') {
      return;
    }
    unawaited(_loadSchedules());
  }

  Future<void> _loadSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? encodedList = prefs.getStringList("friendSchedules");

    if (encodedList == null) return;

    List<FriendScheduleItem> allSchedules = [];
    List<String> validEntries = [];
    final seenEntries = prefs.getStringList('friendSchedules_seen') ?? [];
    final List<FriendScheduleItem> newSchedules = [];

    for (final base64Json in encodedList) {
      try {
        final Uint8List decodeBase64Json = base64.decode(base64Json);
        final List<int> decodeGzipJson = GZipDecoder().decodeBytes(
          decodeBase64Json,
        );
        final String originalJson = utf8.decode(decodeGzipJson);

        final parsed = jsonDecode(originalJson);
        allSchedules.add(
          FriendScheduleItem(
            encoded: base64Json,
            friend: FriendSchedule.fromJson(parsed),
          ),
        );
        validEntries.add(base64Json);
        if (!seenEntries.contains(base64Json)) {
          newSchedules.add(
            FriendScheduleItem(
              encoded: base64Json,
              friend: FriendSchedule.fromJson(parsed),
            ),
          );
        }
      } catch (e) {
        // Sabbir
      }
    }

    await prefs.setStringList("friendSchedules", validEntries);
    await prefs.setStringList("friendSchedules_seen", validEntries);

    setState(() {
      decodedSchedules = allSchedules;
    });

    if (newSchedules.isNotEmpty) {
      final allEnabled = prefs.getBool('notif_all') ?? false;
      final friendEnabled = prefs.getBool('notif_friend') ?? false;
      if (allEnabled && friendEnabled) {
        for (final item in newSchedules) {
          final now = DateTime.now().toUtc();
          final id = now.millisecondsSinceEpoch.remainder(1000000000);
          final title = 'Friend Schedule Received';
          final name = item.friend.name.trim();
          final body = name.isEmpty
              ? 'A friend shared a schedule.'
              : '$name shared a schedule.';
          await LocalNotificationsService.instance.showLocalNotification(
            id: id,
            title: title,
            body: body,
          );
          await NotificationStore.add(
            NotificationItem(
              id: id,
              title: title,
              message: body,
              timeIso: now.toIso8601String(),
              category: 'friend',
            ),
          );
        }
      }
    }
  }

  Future<void> _handleRefresh() async {
    await _loadSchedules();
  }

  String? _extractFriendId(String base64Data) {
    try {
      final Uint8List decodeBase64Json = base64.decode(base64Data);
      final List<int> decodeGzipJson = GZipDecoder().decodeBytes(
        decodeBase64Json,
      );
      final String originalJson = utf8.decode(decodeGzipJson);
      final parsed = jsonDecode(originalJson);
      if (parsed is Map<String, dynamic>) {
        return parsed['id']?.toString();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _saveScannedValue(String value) async {
    final prefs = await SharedPreferences.getInstance();

    List<String> currentList = prefs.getStringList("friendSchedules") ?? [];

    if (!currentList.contains(value)) {
      final scannedId = _extractFriendId(value);
      if (scannedId != null && scannedId.trim().isNotEmpty) {
        currentList = currentList.where((entry) {
          final existingId = _extractFriendId(entry);
          if (existingId == null) return true;
          return existingId.trim() != scannedId.trim();
        }).toList();
      }
      currentList.add(value);
      await prefs.setStringList("friendSchedules", currentList);
    }

    await prefs.setStringList("friendSchedules", currentList);
  }

  Future<void> _scanFromGallery() async {
    if (_isPicking) return;
    if (kIsWeb) {
      if (!mounted) return;
      showAppSnackBar(context, 'Gallery scan is not supported on web');
      return;
    }
    setState(() => _isPicking = true);
    try {
      final granted = await _ensureGalleryPermission();
      if (!granted) {
        if (!mounted) return;
        showAppSnackBar(context, 'Gallery permission denied');
        return;
      }
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      final imagePath = await _ensureReadableImagePath(image);
      final BarcodeCapture? capture = await _galleryScanner.analyzeImage(
        imagePath,
      );
      if (capture == null || capture.barcodes.isEmpty) {
        if (!mounted) return;
        showAppSnackBar(context, 'No QR code found in image');
        return;
      }

      final value = capture.barcodes.first.rawValue;
      if (value == null || value.trim().isEmpty) {
        if (!mounted) return;
        showAppSnackBar(context, 'Invalid QR code');
        return;
      }

      await _saveScannedValue(value);
      await _loadSchedules();
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  Future<bool> _ensureGalleryPermission() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final photos = await Permission.photos.request();
      return photos.isGranted || photos.isLimited;
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return true;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final photos = await Permission.photos.request();
      if (photos.isGranted) return true;
      final storage = await Permission.storage.request();
      return storage.isGranted;
    }
    return true;
  }

  Future<String> _ensureReadableImagePath(XFile image) async {
    if (!Platform.isIOS && !Platform.isMacOS) {
      return image.path;
    }
    try {
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) return image.path;
      final ext = image.path.split('.').last;
      final safeExt = ext.isEmpty ? 'png' : ext;
      final tempFile = File(
        '${Directory.systemTemp.path}/preconnect_scan_${DateTime.now().millisecondsSinceEpoch}.$safeExt',
      );
      await tempFile.writeAsBytes(bytes, flush: true);
      return tempFile.path;
    } catch (_) {
      return image.path;
    }
  }

  Future<void> _deleteFriendSchedule(FriendScheduleItem item) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        final displayName = item.friend.name.trim().isEmpty
            ? 'this friend'
            : item.friend.name;
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: BracuPalette.card(context),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.delete_outline_rounded,
                        color: BracuPalette.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Remove Friend Schedule?',
                        style: TextStyle(
                          color: BracuPalette.textPrimary(context),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'This will remove $displayName\'s shared schedule.',
                    style: TextStyle(
                      color: BracuPalette.textSecondary(context),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: BracuPalette.primary,
                            side: BorderSide(
                              color: BracuPalette.primary.withValues(
                                alpha: 0.6,
                              ),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: BracuPalette.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Remove'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (shouldDelete != true) return;

    final prefs = await SharedPreferences.getInstance();
    final List<String> current = prefs.getStringList("friendSchedules") ?? [];
    final updated = current.where((e) => e != item.encoded).toList();
    await prefs.setStringList("friendSchedules", updated);

    setState(() {
      decodedSchedules.removeWhere((e) => e.encoded == item.encoded);
    });
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    return BracuPageScaffold(
      title: 'Friend Schedule',
      subtitle: 'Shared Schedules',
      icon: Icons.people_outline,
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Text(
              'Scan & Share',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 12.0;
                const aspect = 1.02;
                return GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: spacing,
                  crossAxisSpacing: spacing,
                  childAspectRatio: aspect,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    FriendActionCard(
                      icon: Icons.qr_code_scanner,
                      title: 'Scan',
                      subtitle: 'Schedule',
                      color: const Color(0xFF2AA8A8),
                      onTap: () => widget.onNavigate(HomeTab.scanSchedule),
                    ),
                    FriendActionCard(
                      icon: Icons.photo_library_rounded,
                      title: 'Gallery',
                      subtitle: 'Scan QR',
                      color: const Color(0xFFEF6C35),
                      onTap: _scanFromGallery,
                    ),
                    FriendActionCard(
                      icon: Icons.qr_code_2,
                      title: 'Share',
                      subtitle: 'Schedule',
                      color: const Color(0xFF22B573),
                      onTap: () {
                        widget.onNavigate(HomeTab.shareSchedule);
                      },
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 22),
            Text(
              'Friends',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            if (decodedSchedules.isEmpty)
              const BracuEmptyState(message: "No schedules found")
            else
              ...decodedSchedules.map(
                (item) => FriendScheduleSection(
                  item: item,
                  onDelete: () => _deleteFriendSchedule(item),
                ),
              ),
            if (decodedSchedules.isNotEmpty) ...[
              const SizedBox(height: 6),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}
