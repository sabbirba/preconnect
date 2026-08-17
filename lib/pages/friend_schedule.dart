import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:preconnect/tools/app_paths.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/auth.dart';
import 'package:preconnect/api/friend_store.dart';
import 'package:preconnect/model/friend_schedule.dart';
import 'package:archive/archive.dart';
import 'package:preconnect/pages/friend_sections/schedule_list.dart';
import 'package:preconnect/pages/friend_sections/friend_detail.dart';
import 'package:preconnect/pages/scan_schedule.dart';
import 'package:preconnect/pages/share_schedule.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/ramadan.dart';

class FriendSchedulePage extends StatefulWidget {
  const FriendSchedulePage({super.key});

  @override
  State<FriendSchedulePage> createState() => _FriendSchedulePageState();
}

class _FriendSchedulePageState extends State<FriendSchedulePage>
    with RefreshBusState {
  List<FriendScheduleItem> decodedSchedules = [];
  Map<String, FriendMetadata> _metadata = {};
  final FriendScheduleStore _store = FriendScheduleStore();
  final TextEditingController _searchController = TextEditingController();
  bool _isPicking = false;
  String _searchQuery = '';
  bool _isRamadan = false;
  bool _isLoadingSchedules = false;
  Completer<void>? _loadCompleter;

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
    _searchController.dispose();
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    final reason = refreshBusReason;
    if (reason == 'auth' || reason == 'cache_cleared') {
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
    while (_isLoadingSchedules) {
      await _loadCompleter?.future;
    }
    _isLoadingSchedules = true;
    final completer = Completer<void>();
    _loadCompleter = completer;
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
        final friendSchedule = FriendScheduleStore.parseSchedulePayload(
          base64Json,
        );
        if (friendSchedule != null && friendSchedule.id.isNotEmpty) {
          final metadata = _metadata[friendSchedule.id];
          allSchedules.add(
            FriendScheduleItem(
              encoded: base64Json,
              friend: friendSchedule,
              metadata: metadata,
            ),
          );
          validEntries.add(base64Json);
        }
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
      if (!completer.isCompleted) completer.complete();
      if (identical(_loadCompleter, completer)) _loadCompleter = null;
    }
  }

  Future<void> _handleRefresh() async {
    await _loadSchedules();
  }

  Future<void> _scanFromGallery() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);
    try {
      final value = await pickQrFromSystemImage();
      if (value == null || value.trim().isEmpty) {
        if (!mounted) return;
        showAppSnackBar(context, 'No QR code found in image');
        return;
      }
      try {
        await _store.importPayload(value.trim());
        await _loadSchedules();
      } on FormatException {
        if (!mounted) return;
        showAppSnackBar(context, 'Invalid friend schedule QR code');
      } catch (_) {
        if (!mounted) return;
        showAppSnackBar(context, 'Could not save friend schedule');
      }
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  Future<void> _showScheduleToolSheet({
    required String title,
    required String subtitle,
    required Widget Function(BuildContext sheetContext) builder,
  }) {
    return showBracuCustomBottomSheet<void>(
      context: context,
      backgroundColor: BracuPalette.card(context),
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      draggable: false,
      isScrollControlled: true,
      builder: (sheetContext) {
        final textPrimary = BracuPalette.textPrimary(sheetContext);
        final textSecondary = BracuPalette.textSecondary(sheetContext);
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 3,
                        decoration: BoxDecoration(
                          color: textSecondary.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const Gap(6),
                    Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Gap(4),
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    color: textSecondary,
                                    fontSize: 12,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Gap(8),
                        IconButton(
                          onPressed: () =>
                              Navigator.of(sheetContext).maybePop(),
                          icon: const Icon(Icons.close_rounded, size: 20),
                          style: IconButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(36, 36),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                    const Gap(4),
                  ],
                ),
              ),
              builder(sheetContext),
            ],
          ),
        );
      },
    );
  }

  Future<void> _exportAllFriendSchedules() async {
    try {
      final snapshot = await _store.loadSnapshot();
      if (snapshot.encodedSchedules.isEmpty) {
        if (!mounted) return;
        showAppSnackBar(context, 'No friend schedule to export');
        return;
      }
      final exportJson = {
        "type": "friend_schedules_export",
        "version": 1,
        "schedules": snapshot.encodedSchedules,
      };
      final jsonStr = jsonEncode(exportJson);
      final utf8Bytes = utf8.encode(jsonStr);
      final gzipBytes = GZipEncoder().encode(utf8Bytes);
      final base64Str = base64.encode(gzipBytes);

      if (kIsWeb) {
        await shareTextOrFile(
          text: base64Str,
          subject: 'Friends Export Code',
          fileName: 'friends_export.txt',
        );
        if (!mounted) return;
        showAppSnackBar(context, 'Export complete');
        return;
      }

      final tempDir = await AppPaths.temporaryDirectory();
      final file = File('${tempDir.path}/friends_export.txt');
      await file.writeAsString(base64Str, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'PreConnect Friends Schedule Export Code',
          subject: 'Friends Export Code',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Failed to export friends');
    }
  }

  Future<bool> _deleteFriendSchedule(FriendScheduleItem item) async {
    final displayName = item.friend.name.trim().isEmpty
        ? 'this friend'
        : item.friend.name;
    final shouldDelete = await showBracuConfirmationWithActionDialog(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'Remove Friend Schedule?',
      message: 'This will remove $displayName\'s schedule.',
      confirmLabel: 'Remove',
      confirmColor: BracuPalette.danger,
      onConfirm: () async {
        try {
          await _store.removeByEncoded(item.encoded);
        } catch (_) {
          if (mounted) {
            showAppSnackBar(context, 'Could not remove friend schedule');
          }
          rethrow;
        }
      },
    );

    if (shouldDelete != true) return false;

    setState(() {
      decodedSchedules.removeWhere((e) => e.encoded == item.encoded);
    });
    return true;
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

    final nextMetadata = Map<String, FriendMetadata>.from(_metadata)
      ..[friendId] = newMetadata;
    try {
      await _store.saveAllMetadata(nextMetadata);
      if (!mounted) return;
      setState(() {
        _metadata = nextMetadata;
        _applyMetadataToDecodedSchedules();
      });
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Could not update favorite');
    }
  }

  Future<String?> _editNickname(FriendScheduleItem item) async {
    final controller = TextEditingController(
      text: item.metadata?.nickname ?? '',
    );

    final result = await showBracuBottomSheet<String>(
      context,
      title: 'Edit Nickname',
      initialChildSize: 0.40,
      builder: (sheetContext, textPrimary, textSecondary) {
        final dragController = bracuBottomSheetScrollController(sheetContext);
        return ListView(
          controller: dragController,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(color: textPrimary, fontFamily: 'Outfit'),
              decoration: bracuInputDecoration(
                context,
                hintText: item.friend.name.isEmpty
                    ? 'Enter nickname'
                    : item.friend.name,
                borderRadius: 14,
              ),
            ),
            const Gap(16),
            Row(
              children: [
                Expanded(
                  child: BracuActionButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    label: 'Cancel',
                    outlined: true,
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: BracuActionButton(
                    onPressed: () =>
                        Navigator.pop(sheetContext, controller.text.trim()),
                    label: 'Save',
                    outlined: false,
                  ),
                ),
              ],
            ),
            const Gap(16),
          ],
        );
      },
    );
    controller.dispose();
    if (result == null) return null;

    final friendId = item.friend.id;
    final currentMetadata = _metadata[friendId];
    final newMetadata = (currentMetadata ?? FriendMetadata(friendId: friendId))
        .copyWith(nickname: result.isEmpty ? null : result);

    final nextMetadata = Map<String, FriendMetadata>.from(_metadata)
      ..[friendId] = newMetadata;
    try {
      await _store.saveAllMetadata(nextMetadata);
      if (!mounted) return null;
      setState(() {
        _metadata = nextMetadata;
        _applyMetadataToDecodedSchedules();
      });
    } catch (_) {
      if (!mounted) return null;
      showAppSnackBar(context, 'Could not update nickname');
      return null;
    }
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
      subtitle: 'Schedules',
      icon: Icons.people_outline,
      actions: [
        IconButton(
          onPressed: _exportAllFriendSchedules,
          icon: const Icon(Icons.ios_share_rounded),
          tooltip: 'Export Friend Codes',
        ),
      ],
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
                      onTap: () async {
                        if (!mounted) return;
                        await _showScheduleToolSheet(
                          title: 'Scan Schedule',
                          subtitle: 'Scan QR from Friends',
                          builder: (sheetContext) => ScanSchedulePage(
                            onCompleted: () => Navigator.of(sheetContext).pop(),
                          ),
                        );
                        if (mounted) {
                          await _loadSchedules();
                        }
                      },
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
                      onTap: () async {
                        final isLoggedIn = await AuthService().isLoggedIn();
                        if (!context.mounted) return;
                        if (!isLoggedIn) {
                          showAppSnackBar(
                            context,
                            'Please log in to share your schedule.',
                          );
                          return;
                        }
                        if (!context.mounted) return;
                        await _showScheduleToolSheet(
                          title: 'Share Schedule',
                          subtitle: 'Generate QR for Friends',
                          builder: (_) => const ShareSchedulePage(),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
          const Gap(22),
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
          const Gap(12),
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
            const Gap(12),
          ],
          if (_filteredSchedules.isEmpty && decodedSchedules.isEmpty)
            const BracuEmptyState(message: "No schedule found")
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
          if (_filteredSchedules.isNotEmpty) ...[const Gap(12)],
        ],
      ),
    );
  }
}
