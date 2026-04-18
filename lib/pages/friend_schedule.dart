import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:preconnect/api/friend_schedule_store.dart';
import 'package:preconnect/model/friend_schedule.dart';
import 'package:archive/archive.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/pages/friend_schedule_sections/schedule_list.dart';
import 'package:preconnect/pages/friend_schedule_sections/friend_detail.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/ramadan_timing.dart';
import 'package:preconnect/tools/web_qr_image_picker_stub.dart'
    if (dart.library.html) 'package:preconnect/tools/web_qr_image_picker_web.dart';

class FriendSchedulePage extends StatefulWidget {
  const FriendSchedulePage({super.key, required this.onNavigate});

  final void Function(HomeTab tab) onNavigate;

  @override
  State<FriendSchedulePage> createState() => _FriendSchedulePageState();
}

class _FriendSchedulePageState extends State<FriendSchedulePage>
    with RefreshBusState {
  List<FriendScheduleItem> decodedSchedules = [];
  Map<String, FriendMetadata> _metadata = {};
  final FriendScheduleStore _store = FriendScheduleStore();
  final MobileScannerController _galleryScanner = MobileScannerController();
  final TextEditingController _searchController = TextEditingController();
  bool _isPicking = false;
  String _searchQuery = '';
  bool _isRamadan = false;
  bool _isLoadingSchedules = false;

  @override
  void initState() {
    super.initState();
    _loadSchedules();
    bindRefreshBus(_onRefreshSignal);
    _searchController.addListener(() {
      final next = _searchController.text.toLowerCase();
      if (next == _searchQuery) return;
      setState(() {
        _searchQuery = next;
      });
    });
  }

  @override
  void dispose() {
    unbindRefreshBus(_onRefreshSignal);
    _galleryScanner.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    final reason = refreshBusReason;
    if (reason == 'friend_schedule') {
      return;
    }
    if (reason == 'share_schedule' ||
        reason == 'scan_schedule' ||
        reason == 'auth') {
      unawaited(_loadSchedules());
    }
  }

  void _sortSchedules(List<FriendScheduleItem> items) {
    items.sort((a, b) {
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
  }

  Future<void> _loadSchedules() async {
    if (_isLoadingSchedules) return;
    _isLoadingSchedules = true;
    try {
      final ramadanFuture = RamadanTiming.isRamadan();
      final snapshot = await _store.loadSnapshot();
      final encodedList = snapshot.encodedSchedules;
      _metadata = snapshot.metadata;

      final isRamadan = await ramadanFuture;
      if (encodedList.isEmpty) {
        if (!mounted) return;
        setState(() {
          decodedSchedules = <FriendScheduleItem>[];
          _isRamadan = isRamadan;
        });
        return;
      }

      final allSchedules = <FriendScheduleItem>[];
      final validEntries = <String>[];

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
        } catch (_) {}
      }

      final invalidEntries = encodedList
          .where((entry) => !validEntries.contains(entry))
          .toList();
      for (final invalid in invalidEntries) {
        await _store.removeByEncoded(invalid);
      }

      _sortSchedules(allSchedules);

      if (!mounted) return;
      setState(() {
        decodedSchedules = allSchedules;
        _isRamadan = isRamadan;
      });
    } finally {
      _isLoadingSchedules = false;
    }
  }

  Future<void> _handleRefresh() async {
    await _loadSchedules();
  }

  Future<void> _saveScannedValue(String value) async {
    await _store.upsertEncodedSchedule(value);
  }

  Future<void> _scanFromGallery() async {
    if (_isPicking) return;
    if (kIsWeb) {
      setState(() => _isPicking = true);
      try {
        final value = await pickQrFromSystemImage();
        if (value == null || value.trim().isEmpty) {
          if (!mounted) return;
          showAppSnackBar(context, 'No QR code found in selected image');
          return;
        }
        await _saveScannedValue(value);
        await _loadSchedules();
      } catch (e) {
        if (!mounted) return;
        showAppSnackBar(
          context,
          e
              .toString()
              .replaceFirst('UnsupportedError: ', '')
              .replaceFirst('Exception: ', ''),
        );
      } finally {
        if (mounted) {
          setState(() => _isPicking = false);
        }
      }
      return;
    }
    setState(() => _isPicking = true);
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final imagePath = await _ensureReadableImagePath(picked.files.first);
      if (imagePath.isEmpty) {
        if (!mounted) return;
        showAppSnackBar(context, 'Unable to read selected image');
        return;
      }
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

  Future<String> _ensureReadableImagePath(PlatformFile file) async {
    final path = file.path?.trim() ?? '';
    if (path.isNotEmpty && (!Platform.isIOS && !Platform.isMacOS)) {
      return path;
    }
    try {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) return path;
      final ext = file.extension?.trim() ?? '';
      final safeExt = ext.isEmpty ? 'png' : ext;
      final tempFile = File(
        '${Directory.systemTemp.path}/preconnect_scan_${DateTime.now().millisecondsSinceEpoch}.$safeExt',
      );
      await tempFile.writeAsBytes(bytes, flush: true);
      return tempFile.path;
    } catch (_) {
      return path;
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
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
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

    await _store.removeByEncoded(item.encoded);

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
    await _store.saveAllMetadata(_metadata);
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
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () =>
                              Navigator.pop(context, controller.text.trim()),
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
      body: BracuRefreshList(
        onRefresh: _handleRefresh,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final layout = quickAccessGridLayout(
                constraints.maxWidth,
                targetColumns: 3,
              );
              return Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  runAlignment: WrapAlignment.center,
                  spacing: layout.spacing,
                  runSpacing: layout.spacing,
                  children: [
                    FriendActionCard(
                      width: layout.itemWidth,
                      icon: Icons.qr_code_scanner,
                      title: 'Scan',
                      subtitle: 'Schedule',
                      color: BracuPalette.info,
                      onTap: () => widget.onNavigate(HomeTab.scanSchedule),
                    ),
                    FriendActionCard(
                      width: layout.itemWidth,
                      icon: Icons.photo_library_rounded,
                      title: 'Gallery',
                      subtitle: 'Scan QR',
                      color: BracuPalette.warning,
                      onTap: _scanFromGallery,
                    ),
                    FriendActionCard(
                      width: layout.itemWidth,
                      icon: Icons.qr_code_2,
                      title: 'Share',
                      subtitle: 'Schedule',
                      color: BracuPalette.accent,
                      onTap: () {
                        widget.onNavigate(HomeTab.shareSchedule);
                      },
                    ),
                  ],
                ),
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
            BracuSearchField(
              controller: _searchController,
              hintText: 'Search',
              query: _searchQuery,
              borderRadius: 14,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              keySuffix: 'friend-schedule',
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
                  style: TextStyle(color: BracuPalette.textSecondary(context)),
                ),
              ),
            )
          else
            ..._filteredSchedules.map(
              (item) => FriendScheduleSection(
                item: item,
                isRamadan: _isRamadan,
                showActions: false,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FriendDetailPage(
                        friend: item.friend,
                        displayName: item.displayName,
                        isFavorite: item.isFavorite,
                        isRamadan: _isRamadan,
                        onToggleFavorite: () async => _toggleFavorite(item),
                        onEditNickname: () async => _editNickname(item),
                        onDelete: () async => _deleteFriendSchedule(item),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (_filteredSchedules.isNotEmpty) ...[const SizedBox(height: 12)],
        ],
      ),
    );
  }
}
