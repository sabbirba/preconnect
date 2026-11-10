import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/chat.dart';
import 'package:preconnect/model/chat.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_paths.dart';
import 'package:preconnect/tools/file_open.dart';
import 'package:preconnect/tools/image_cache.dart';
import 'package:preconnect/tools/time_utils.dart';

Future<void> openCachedPdf(
  BuildContext context, {
  required String url,
  required String cacheKey,
  required String fileName,
}) async {
  try {
    final file = await AppImageCache.instance.getSingleFile(url, key: cacheKey);
    if (kIsWeb) {
      await openPdfInBrowser(
        bytes: await file.readAsBytes(),
        fileName: fileName,
      );
      return;
    }
    final named = File(
      '${(await AppPaths.temporaryDirectory()).path}/$fileName',
    );
    if (!await named.exists() || await named.length() != await file.length()) {
      await file.copy(named.path);
    }
    if (!await NativeFile.open(named.path) && context.mounted) {
      showAppSnackBar(context, 'No app could open this PDF.');
    }
  } catch (_) {
    if (context.mounted) {
      showAppSnackBar(context, 'The PDF could not be opened.');
    }
  }
}

class SharedMaterialsPage extends StatefulWidget {
  const SharedMaterialsPage({super.key});

  @override
  State<SharedMaterialsPage> createState() => _SharedMaterialsPageState();
}

class _SharedMaterialsPageState extends State<SharedMaterialsPage> {
  final ChatService _chat = ChatService.instance;
  final TextEditingController _search = TextEditingController();
  List<ChatMaterial> _materials = const <ChatMaterial>[];
  Map<String, String> _votes = const <String, String>{};
  final Set<String> _opening = <String>{};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final (materials, votes) = await (
        _chat.loadMaterials(),
        _chat.loadHelpfulVotes(),
      ).wait;
      if (!mounted) return;
      setState(() {
        _materials = materials;
        _votes = votes;
        _error = null;
      });
    } on ChatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Materials could not be loaded.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Set<String> get _myCourses => <String>{
    for (final room in _chat.rooms.value)
      if (room.kind != ChatRoomKind.lounge)
        room.title.split('-').first.toUpperCase(),
  };

  Map<String, List<ChatMaterial>> get _grouped {
    final query = _search.text.trim().toLowerCase();
    final mine = _myCourses;
    final groups = <String, List<ChatMaterial>>{};
    for (final material in _materials) {
      final matches =
          query.isEmpty ||
          material.name.toLowerCase().contains(query) ||
          material.courseCode.toLowerCase().contains(query);
      if (matches) {
        (groups[material.courseCode] ??= <ChatMaterial>[]).add(material);
      }
    }
    final codes = groups.keys.toList()
      ..sort((a, b) {
        final rank = (mine.contains(a) ? 0 : 1) - (mine.contains(b) ? 0 : 1);
        return rank != 0 ? rank : a.compareTo(b);
      });
    return <String, List<ChatMaterial>>{
      for (final code in codes) code: groups[code]!,
    };
  }

  Future<void> _toggleHelpful(ChatMaterial material) async {
    final current = _votes[material.id];
    try {
      final vote = await _chat.setHelpful(material.id, current);
      if (!mounted) return;
      setState(() {
        final next = Map<String, String>.from(_votes);
        vote == null ? next.remove(material.id) : next[material.id] = vote;
        _votes = next;
        _materials = [
          for (final item in _materials)
            item.id == material.id
                ? ChatMaterial(
                    id: item.id,
                    courseCode: item.courseCode,
                    name: item.name,
                    file: item.file,
                    size: item.size,
                    helpful: item.helpful + (vote == null ? -1 : 1),
                    semesterSessionId: item.semesterSessionId,
                    created: item.created,
                  )
                : item,
        ];
      });
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Could not save your vote.');
    }
  }

  Future<void> _open(ChatMaterial material) async {
    setState(() => _opening.add(material.id));
    final url = await _chat.materialUrl(material);
    if (!mounted) return;
    await openCachedPdf(
      context,
      url: url,
      cacheKey: _chat.materialKey(material),
      fileName: material.name,
    );
    if (mounted) setState(() => _opening.remove(material.id));
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'From Classmates',
      subtitle: 'Materials',
      icon: Icons.groups_outlined,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const AppLoading();
    if (_error != null) {
      return AppErrorState(
        title: 'Materials Unavailable',
        message: _error!,
        onRetry: _load,
      );
    }
    final grouped = _grouped;
    return AppRefreshList(
      onRefresh: _load,
      children: [
        AppSearchField(controller: _search),
        const Gap(12),
        if (grouped.isEmpty)
          const AppEmptyState(
            message:
                'PDFs shared in your course and section chats appear here.',
            icon: Icons.picture_as_pdf_outlined,
          ),
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: AppSectionTitle(title: entry.key),
          ),
          for (final material in entry.value) ...[
            _MaterialTile(
              material: material,
              helpful: _votes.containsKey(material.id),
              opening: _opening.contains(material.id),
              onOpen: () => _open(material),
              onHelpful: () => _toggleHelpful(material),
            ),
            const Gap(8),
          ],
        ],
      ],
    );
  }
}

class _MaterialTile extends StatelessWidget {
  const _MaterialTile({
    required this.material,
    required this.helpful,
    required this.opening,
    required this.onOpen,
    required this.onHelpful,
  });

  final ChatMaterial material;
  final bool helpful;
  final bool opening;
  final VoidCallback onOpen;
  final VoidCallback onHelpful;

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppPalette.textSecondary(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: opening ? null : onOpen,
        child: AppCard(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppPalette.danger.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: opening
                    ? const Center(child: AppSpinner(size: 18))
                    : const Icon(
                        Icons.picture_as_pdf_outlined,
                        color: AppPalette.danger,
                      ),
              ),
              const Gap(10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      material.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.textPrimary(context),
                      ),
                    ),
                    const Gap(2),
                    Text(
                      '${(material.size / 1048576).toStringAsFixed(1)} MB · '
                      '${AppTime.formatDayMonth(material.created.toLocal())}',
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onHelpful,
                style: TextButton.styleFrom(
                  foregroundColor: helpful ? AppPalette.primary : textSecondary,
                ),
                icon: Icon(
                  helpful ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
                  size: 18,
                ),
                label: Text('${material.helpful}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
