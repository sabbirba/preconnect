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
import 'package:preconnect/pages/friend_schedule_sections/friend_detail.dart';
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
  Map<String, FriendMetadata> _metadata = {};
  final MobileScannerController _galleryScanner = MobileScannerController();
  final TextEditingController _searchController = TextEditingController();
  bool _isPicking = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadSchedules();
    RefreshBus.instance.addListener(_onRefreshSignal);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    RefreshBus.instance.removeListener(_onRefreshSignal);
    _galleryScanner.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    if (RefreshBus.instance.reason == 'friend_schedule') {
      return;
    }
    unawaited(_loadSchedules());
  }

  void _sortSchedules(List<FriendScheduleItem> items) {
    items.sort((a, b) {
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
  }

  Future<void> _loadSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? encodedList = prefs.getStringList("friendSchedules");

    final metadataJson = prefs.getString('friendMetadata');
    if (metadataJson != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(metadataJson);
        _metadata = decoded.map(
          (key, value) => MapEntry(
            key,
            FriendMetadata.fromJson(value as Map<String, dynamic>),
          ),
        );
      } catch (_) {
        _metadata = {};
      }
    }

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
        final friendSchedule = FriendSchedule.fromJson(parsed);
        final metadata = _metadata[friendSchedule.id];

        allSchedules.add(
          FriendScheduleItem(
            encoded: base64Json,
            friend: friendSchedule,
            metadata: metadata,
          ),
        );
        validEntries.add(base64Json);
        if (!seenEntries.contains(base64Json)) {
          newSchedules.add(
            FriendScheduleItem(
              encoded: base64Json,
              friend: friendSchedule,
              metadata: metadata,
            ),
          );
        }
      } catch (_) {}
    }

    await prefs.setStringList("friendSchedules", validEntries);
    await prefs.setStringList("friendSchedules_seen", validEntries);

    _sortSchedules(allSchedules);

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

  Future<bool> _deleteFriendSchedule(FriendScheduleItem item) async {
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
            decoration: _buildDialogDecoration(context),
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

    if (shouldDelete != true) return false;

    final prefs = await SharedPreferences.getInstance();
    final List<String> current = prefs.getStringList("friendSchedules") ?? [];
    final updated = current.where((e) => e != item.encoded).toList();
    await prefs.setStringList("friendSchedules", updated);

    setState(() {
      decodedSchedules.removeWhere((e) => e.encoded == item.encoded);
    });
    return true;
  }

  BoxDecoration _buildDialogDecoration(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      color: BracuPalette.card(context),
      border: Border.all(
        color: BracuPalette.textSecondary(
          context,
        ).withValues(alpha: isDark ? 0.35 : 0.18),
      ),
      boxShadow: isDark
          ? const []
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
    );
  }

  Future<void> _saveMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(
      _metadata.map((key, value) => MapEntry(key, value.toJson())),
    );
    await prefs.setString('friendMetadata', json);
  }

  void _applyMetadataToDecodedSchedules() {
    decodedSchedules = decodedSchedules.map((item) {
      return FriendScheduleItem(
        encoded: item.encoded,
        friend: item.friend,
        metadata: _metadata[item.friend.id],
      );
    }).toList();
    _sortSchedules(decodedSchedules);
  }

  Future<void> _toggleFavorite(FriendScheduleItem item) async {
    final friendId = item.friend.id;
    final currentMetadata = _metadata[friendId];
    final newMetadata = (currentMetadata ?? FriendMetadata(friendId: friendId))
        .copyWith(isFavorite: !(currentMetadata?.isFavorite ?? false));

    setState(() {
      _metadata[friendId] = newMetadata;
      _applyMetadataToDecodedSchedules();
    });

    await _saveMetadata();
  }

  Future<String?> _editNickname(FriendScheduleItem item) async {
    final controller = TextEditingController(
      text: item.metadata?.nickname ?? '',
    );

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            decoration: _buildDialogDecoration(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.edit_outlined,
                        color: BracuPalette.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Edit Nickname',
                          style: TextStyle(
                            color: BracuPalette.textPrimary(context),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, ''),
                        style: TextButton.styleFrom(
                          foregroundColor: BracuPalette.textSecondary(context),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 0,
                          ),
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: item.friend.name.isEmpty
                          ? 'Enter nickname'
                          : item.friend.name,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
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
                          onPressed: () =>
                              Navigator.pop(context, controller.text.trim()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: BracuPalette.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Save'),
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

    if (result == null) return null;

    final friendId = item.friend.id;
    final currentMetadata = _metadata[friendId];
    final newMetadata = (currentMetadata ?? FriendMetadata(friendId: friendId))
        .copyWith(nickname: result.isEmpty ? null : result);

    setState(() {
      _metadata[friendId] = newMetadata;
      _applyMetadataToDecodedSchedules();
    });

    await _saveMetadata();
    return newMetadata.nickname?.trim().isNotEmpty == true
        ? newMetadata.nickname!
        : item.friend.name;
  }

  List<FriendScheduleItem> get _filteredSchedules {
    if (_searchQuery.isEmpty) return decodedSchedules;

    return decodedSchedules.where((item) {
      final displayName = item.displayName.toLowerCase();
      final friendId = item.friend.id.toLowerCase();
      return displayName.contains(_searchQuery) ||
          friendId.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    final totalFriends = decodedSchedules.length;
    final scheduleWord = totalFriends == 1 ? 'Schedule' : 'Schedules';
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
                return GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: spacing,
                  crossAxisSpacing: spacing,
                  childAspectRatio: 0.95,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    FriendActionCard(
                      icon: Icons.qr_code_scanner,
                      title: 'Scan',
                      subtitle: 'Schedule',
                      color: BracuPalette.info,
                      onTap: () => widget.onNavigate(HomeTab.scanSchedule),
                    ),
                    FriendActionCard(
                      icon: Icons.photo_library_rounded,
                      title: 'Gallery',
                      subtitle: 'Scan QR',
                      color: BracuPalette.warning,
                      onTap: _scanFromGallery,
                    ),
                    FriendActionCard(
                      icon: Icons.qr_code_2,
                      title: 'Share',
                      subtitle: 'Schedule',
                      color: BracuPalette.accent,
                      onTap: () {
                        widget.onNavigate(HomeTab.shareSchedule);
                      },
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Friends',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                ),
                Text(
                  '$totalFriends $scheduleWord',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (decodedSchedules.isNotEmpty) ...[
              TextField(
                controller: _searchController,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: 'Search',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_filteredSchedules.isEmpty && decodedSchedules.isEmpty)
              const BracuEmptyState(message: "No schedules found")
            else if (_filteredSchedules.isEmpty && _searchQuery.isNotEmpty)
              BracuCard(
                child: Center(
                  child: Text(
                    'No friends match "$_searchQuery"',
                    style: TextStyle(
                      color: BracuPalette.textSecondary(context),
                    ),
                  ),
                ),
              )
            else
              ..._filteredSchedules.map(
                (item) => FriendScheduleSection(
                  item: item,
                  showActions: false,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FriendDetailPage(
                          friend: item.friend,
                          displayName: item.displayName,
                          isFavorite: item.isFavorite,
                          onToggleFavorite: () async => _toggleFavorite(item),
                          onEditNickname: () async => _editNickname(item),
                          onDelete: () async => _deleteFriendSchedule(item),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (_filteredSchedules.isNotEmpty) ...[
              const SizedBox(height: 6),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}
