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

  Future<void> _loadSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? encodedList = prefs.getStringList("friendSchedules");

    // Load metadata
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
      } catch (e) {
        // Sabbir
      }
    }

    await prefs.setStringList("friendSchedules", validEntries);
    await prefs.setStringList("friendSchedules_seen", validEntries);

    // Sort: favorites first, then alphabetically by display name
    allSchedules.sort((a, b) {
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });

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

  Future<void> _saveMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(
      _metadata.map((key, value) => MapEntry(key, value.toJson())),
    );
    await prefs.setString('friendMetadata', json);
  }

  Future<void> _toggleFavorite(FriendScheduleItem item) async {
    final friendId = item.friend.id;
    final currentMetadata = _metadata[friendId];
    final newMetadata = (currentMetadata ?? FriendMetadata(friendId: friendId))
        .copyWith(isFavorite: !(currentMetadata?.isFavorite ?? false));

    setState(() {
      _metadata[friendId] = newMetadata;
    });

    await _saveMetadata();
    await _loadSchedules();
  }

  Future<void> _editNickname(FriendScheduleItem item) async {
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
                        Icons.edit_outlined,
                        color: BracuPalette.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Edit Nickname',
                        style: TextStyle(
                          color: BracuPalette.textPrimary(context),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
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

    if (result == null) return;

    final friendId = item.friend.id;
    final currentMetadata = _metadata[friendId];
    final newMetadata = (currentMetadata ?? FriendMetadata(friendId: friendId))
        .copyWith(nickname: result.isEmpty ? null : result);

    setState(() {
      _metadata[friendId] = newMetadata;
    });

    await _saveMetadata();
    await _loadSchedules();
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

  Future<void> _addDummyFriends() async {
    final dummyFriends = [
      {
        "name": "Ahmed Hassan",
        "id": "21101234",
        "photoFilePath": null,
        "photoUrl": null,
        "courses": [
          {
            "courseCode": "CSE110",
            "sectionName": "1",
            "roomNumber": "NAC501",
            "faculties": "Dr. Rahman",
            "schedule": [
              {"day": "Sunday", "startTime": "08:00 AM", "endTime": "09:30 AM"},
              {"day": "Tuesday", "startTime": "08:00 AM", "endTime": "09:30 AM"},
            ]
          },
          {
            "courseCode": "CSE111",
            "sectionName": "3",
            "roomNumber": "NAC503",
            "faculties": "Ms. Khan",
            "schedule": [
              {"day": "Monday", "startTime": "11:00 AM", "endTime": "12:30 PM"},
              {"day": "Wednesday", "startTime": "11:00 AM", "endTime": "12:30 PM"},
            ]
          },
          {
            "courseCode": "MAT120",
            "sectionName": "2",
            "roomNumber": "NAC301",
            "faculties": "Dr. Ahmed",
            "schedule": [
              {"day": "Sunday", "startTime": "02:00 PM", "endTime": "03:30 PM"},
              {"day": "Thursday", "startTime": "02:00 PM", "endTime": "03:30 PM"},
            ]
          }
        ]
      },
      {
        "name": "Fatima Ali",
        "id": "21105678",
        "photoFilePath": null,
        "photoUrl": null,
        "courses": [
          {
            "courseCode": "CSE110",
            "sectionName": "2",
            "roomNumber": "NAC502",
            "faculties": "Dr. Rahman",
            "schedule": [
              {"day": "Sunday", "startTime": "09:40 AM", "endTime": "11:10 AM"},
              {"day": "Tuesday", "startTime": "09:40 AM", "endTime": "11:10 AM"},
            ]
          },
          {
            "courseCode": "ENG101",
            "sectionName": "5",
            "roomNumber": "NAC201",
            "faculties": "Ms. Begum",
            "schedule": [
              {"day": "Monday", "startTime": "08:00 AM", "endTime": "09:30 AM"},
              {"day": "Wednesday", "startTime": "08:00 AM", "endTime": "09:30 AM"},
            ]
          },
          {
            "courseCode": "PHY111",
            "sectionName": "1",
            "roomNumber": "SCI101",
            "faculties": "Dr. Hossain",
            "schedule": [
              {"day": "Saturday", "startTime": "11:20 AM", "endTime": "12:50 PM"},
              {"day": "Thursday", "startTime": "11:20 AM", "endTime": "12:50 PM"},
            ]
          }
        ]
      },
      {
        "name": "Rafiq Islam",
        "id": "21109012",
        "photoFilePath": null,
        "photoUrl": null,
        "courses": [
          {
            "courseCode": "CSE220",
            "sectionName": "4",
            "roomNumber": "NAC701",
            "faculties": "Dr. Karim",
            "schedule": [
              {"day": "Sunday", "startTime": "11:20 AM", "endTime": "12:50 PM"},
              {"day": "Tuesday", "startTime": "11:20 AM", "endTime": "12:50 PM"},
            ]
          },
          {
            "courseCode": "CSE221",
            "sectionName": "2",
            "roomNumber": "NAC702",
            "faculties": "Ms. Sultana",
            "schedule": [
              {"day": "Monday", "startTime": "02:00 PM", "endTime": "03:30 PM"},
              {"day": "Wednesday", "startTime": "02:00 PM", "endTime": "03:30 PM"},
            ]
          },
          {
            "courseCode": "MAT216",
            "sectionName": "1",
            "roomNumber": "NAC302",
            "faculties": "Dr. Alam",
            "schedule": [
              {"day": "Saturday", "startTime": "08:00 AM", "endTime": "09:30 AM"},
              {"day": "Thursday", "startTime": "08:00 AM", "endTime": "09:30 AM"},
            ]
          }
        ]
      },
    ];

    final prefs = await SharedPreferences.getInstance();
    List<String> currentList = prefs.getStringList("friendSchedules") ?? [];

    for (final friendData in dummyFriends) {
      final jsonString = jsonEncode(friendData);
      final gzipped = GZipEncoder().encode(utf8.encode(jsonString));
      final encoded = base64.encode(gzipped);

      if (!currentList.contains(encoded)) {
        currentList.add(encoded);
      }
    }

    await prefs.setStringList("friendSchedules", currentList);
    await _loadSchedules();

    if (!mounted) return;
    showAppSnackBar(context, '${dummyFriends.length} dummy friends added!');
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Scan & Share',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _addDummyFriends,
                  icon: const Icon(Icons.bug_report, size: 18),
                  label: const Text('Test Data'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 12.0;
                return GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: spacing,
                  crossAxisSpacing: spacing,
                  childAspectRatio: 1.0,
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
                if (decodedSchedules.isNotEmpty)
                  Text(
                    '${decodedSchedules.length}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: BracuPalette.textSecondary(context),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (decodedSchedules.isNotEmpty) ...[
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search friends...',
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
                  onDelete: () => _deleteFriendSchedule(item),
                  onToggleFavorite: () => _toggleFavorite(item),
                  onEditNickname: () => _editNickname(item),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FriendDetailPage(
                          friend: item.friend,
                          displayName: item.displayName,
                          isFavorite: item.isFavorite,
                          onToggleFavorite: () => _toggleFavorite(item),
                          onEditNickname: () => _editNickname(item),
                          onDelete: () {
                            _deleteFriendSchedule(item);
                            Navigator.of(context).pop();
                          },
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
