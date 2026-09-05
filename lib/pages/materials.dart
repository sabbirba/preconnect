import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/materials.dart';
import 'package:preconnect/model/materials.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:url_launcher/url_launcher.dart';

class MaterialsPage extends StatefulWidget {
  const MaterialsPage({super.key});

  @override
  State<MaterialsPage> createState() => _MaterialsPageState();
}

class _MaterialsPageState extends State<MaterialsPage> {
  final MaterialsService _service = MaterialsService();
  final TextEditingController _searchController = TextEditingController();

  String? _selectedSource;
  MaterialCollection? _selectedCollection;
  MaterialSources? _sources;
  List<MaterialCollection>? _collections;
  MaterialDetail? _detail;
  Object? _error;
  bool _loading = true;
  final Set<String> _expandedCategories = <String>{};

  @override
  void initState() {
    super.initState();
    HomeTabRegistry.registerBackHandler(HomeTab.materials, _handleBack);
    _searchController.addListener(_onSearchChanged);
    unawaited(_loadSources());
  }

  @override
  void dispose() {
    HomeTabRegistry.unregisterBackHandler(HomeTab.materials, _handleBack);
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  bool _handleBack() {
    if (_selectedCollection != null) {
      _searchController.clear();
      setState(() {
        _selectedCollection = null;
        _detail = null;
        _error = null;
        _loading = false;
        _expandedCategories.clear();
      });
      return true;
    }
    if (_selectedSource != null) {
      _searchController.clear();
      setState(() {
        _selectedSource = null;
        _collections = null;
        _error = null;
        _loading = false;
      });
      return true;
    }
    return false;
  }

  Future<void> _loadSources({bool forceRefresh = false}) async {
    if (_sources == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final sources = await _service.loadSources(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _sources = sources;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _selectSource(String source, {bool forceRefresh = false}) async {
    if (!forceRefresh || _collections == null) {
      setState(() {
        _selectedSource = source;
        _selectedCollection = null;
        _collections = null;
        _detail = null;
        _loading = true;
        _error = null;
        _searchController.clear();
        _expandedCategories.clear();
      });
    }
    try {
      final collections = await _service.loadCollections(
        source,
        forceRefresh: forceRefresh,
      );
      if (!mounted || _selectedSource != source) return;
      setState(() {
        _collections = collections;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || _selectedSource != source) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _selectCollection(
    MaterialCollection collection, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh || _detail == null) {
      setState(() {
        _selectedCollection = collection;
        _detail = null;
        _loading = true;
        _error = null;
        _searchController.clear();
        _expandedCategories.clear();
      });
    }
    try {
      final detail = await _service.loadDetail(
        collection.code,
        source: _selectedSource ?? '',
        forceRefresh: forceRefresh,
      );
      if (!mounted || _selectedCollection?.code != collection.code) return;
      setState(() {
        _detail = detail;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || _selectedCollection?.code != collection.code) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    final collection = _selectedCollection;
    if (collection != null) {
      await _selectCollection(collection, forceRefresh: true);
      return;
    }
    final source = _selectedSource;
    if (source != null) {
      await _selectSource(source, forceRefresh: true);
      return;
    }
    await _loadSources(forceRefresh: true);
  }

  String _sourceUrl(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://github.com/$trimmed';
  }

  List<String> get _filteredSources {
    final query = _searchController.text.trim().toLowerCase();
    final sources = _sources?.all ?? const <String>[];
    if (query.isEmpty) return sources;
    return sources
        .where((s) => s.toLowerCase().contains(query))
        .toList(growable: false);
  }

  List<MaterialCollection> get _filteredCollections {
    final query = _searchController.text.trim().toLowerCase();
    final collections = _collections ?? const <MaterialCollection>[];
    if (query.isEmpty) return collections;
    return collections
        .where(
          (item) =>
              item.code.toLowerCase().contains(query) ||
              item.title.toLowerCase().contains(query) ||
              item.sources.any((s) => s.toLowerCase().contains(query)),
        )
        .toList(growable: false);
  }

  List<MaterialCategory> get _filteredCategories {
    final query = _searchController.text.trim().toLowerCase();
    final categories = _detail?.categories ?? const <MaterialCategory>[];
    if (query.isEmpty) return categories;
    return categories
        .map((category) {
          final categoryMatches = category.name.toLowerCase().contains(query);
          final files = categoryMatches
              ? category.files
              : category.files
                    .where(
                      (file) =>
                          file.name.toLowerCase().contains(query) ||
                          file.path.toLowerCase().contains(query) ||
                          file.source.toLowerCase().contains(query),
                    )
                    .toList(growable: false);
          return MaterialCategory(name: category.name, files: files);
        })
        .where((category) => category.files.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final selectedCol = _selectedCollection;
    final selectedSrc = _selectedSource;
    final String title;
    final String subtitle;
    if (selectedCol != null) {
      title = selectedCol.code;
      subtitle = selectedSrc ?? 'Materials';
    } else if (selectedSrc != null) {
      title = selectedSrc;
      subtitle = 'Materials';
    } else {
      title = 'Course';
      subtitle = 'Materials';
    }
    return BracuBackScope(
      canGoBack: true,
      onBack: () {
        if (!_handleBack()) HomeTabRegistry.setActive(HomeTab.dashboard);
      },
      child: BracuPageScaffold(
        title: title,
        subtitle: subtitle,
        icon: Icons.folder_copy_outlined,
        showBack: true,
        actions: [
          if (selectedSrc != null)
            IconButton(
              tooltip: 'Source',
              onPressed: () {
                final sourceLink = _sourceUrl(
                  selectedCol?.sources.firstOrNull ?? selectedSrc,
                );
                if (sourceLink.isNotEmpty) {
                  openExternalUrl(
                    context,
                    sourceLink,
                    failureMessage: 'Unable to open source.',
                  );
                }
              },
              icon: const PreConnectGitHubIcon(
                size: 22,
                color: BracuPalette.primary,
              ),
            ),
          BracuRefreshButton(onPressed: _refresh, isLoading: _loading),
        ],
        body: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            children: [
              BracuSearchField(
                controller: _searchController,
                hintText: 'Search...',
              ),
              const Gap(12),
              _buildBody(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Expanded(child: BracuLoading());
    }
    if (_error != null) {
      return Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Unable to load files. Please try again.'),
              const Gap(16),
              BracuActionButton(label: 'Retry', onPressed: _refresh),
            ],
          ),
        ),
      );
    }
    if (_selectedSource == null) {
      final sources = _filteredSources;
      return Expanded(
        child: sources.isEmpty
            ? const BracuEmptyState(message: 'No sources found.')
            : BracuRefreshScroll(
                onRefresh: _refresh,
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  children: sources
                      .map(
                        (source) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: BracuActionCard(
                            title: source,
                            leadingIcon: Icons.source_outlined,
                            trailing: Icon(
                              Icons.chevron_right_rounded,
                              color: BracuPalette.textSecondary(context),
                            ),
                            onTap: () => _selectSource(source),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
      );
    }
    if (_selectedCollection == null) {
      final collections = _filteredCollections;
      return Expanded(
        child: collections.isEmpty
            ? const BracuEmptyState(message: 'No materials found.')
            : BracuRefreshScroll(
                onRefresh: _refresh,
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  children: collections
                      .map(
                        (collection) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: BracuActionCard(
                            title: collection.code,
                            subtitle: collection.title,
                            leadingIcon: Icons.folder_outlined,
                            trailing: Icon(
                              Icons.chevron_right_rounded,
                              color: BracuPalette.textSecondary(context),
                            ),
                            onTap: () => _selectCollection(collection),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
      );
    }
    final categories = _filteredCategories;
    return Expanded(
      child: categories.isEmpty
          ? const BracuEmptyState(message: 'No file found.')
          : BracuRefreshScroll(
              onRefresh: _refresh,
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: categories
                    .map((category) {
                      final isExpanded =
                          _searchController.text.trim().isNotEmpty ||
                          _expandedCategories.contains(category.name);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                setState(() {
                                  if (!_expandedCategories.add(category.name)) {
                                    _expandedCategories.remove(category.name);
                                  }
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        category.name,
                                        style: TextStyle(
                                          color: BracuPalette.textPrimary(
                                            context,
                                          ),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    AnimatedRotation(
                                      turns: isExpanded ? 0.5 : 0,
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      child: Icon(
                                        Icons.expand_more_rounded,
                                        color: BracuPalette.textSecondary(
                                          context,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 200),
                              alignment: Alignment.topCenter,
                              child: isExpanded
                                  ? Column(
                                      children: [
                                        const Gap(4),
                                        ...category.files.map(
                                          (file) => Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 12,
                                            ),
                                            child: BracuActionCard(
                                              title: file.name,
                                              leadingIcon: _fileIcon(file.path),
                                              trailing: Icon(
                                                Icons.open_in_new_rounded,
                                                size: 19,
                                                color:
                                                    BracuPalette.textSecondary(
                                                      context,
                                                    ),
                                              ),
                                              onTap: () => launchUrl(
                                                Uri.parse(file.url),
                                                mode: LaunchMode
                                                    .externalApplication,
                                                webOnlyWindowName: '_blank',
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
    );
  }
}

IconData _fileIcon(String path) {
  final extension = path.split('.').last.toLowerCase();
  return switch (extension) {
    'pdf' => Icons.picture_as_pdf_outlined,
    'ppt' || 'pptx' => Icons.slideshow_outlined,
    'xls' || 'xlsx' || 'csv' => Icons.table_chart_outlined,
    'doc' || 'docx' || 'gdoc' => Icons.description_outlined,
    'md' || 'txt' || 'typ' => Icons.article_outlined,
    'java' ||
    'py' ||
    'dart' ||
    'js' ||
    'ts' ||
    'c' ||
    'cpp' ||
    'h' ||
    'html' ||
    'css' ||
    'gradle' => Icons.code_rounded,
    'ipynb' => Icons.developer_board_outlined,
    'json' ||
    'xml' ||
    'yaml' ||
    'yml' ||
    'sql' ||
    'db' => Icons.data_object_outlined,
    'png' ||
    'jpg' ||
    'jpeg' ||
    'gif' ||
    'webp' ||
    'svg' => Icons.image_outlined,
    'mp3' || 'wav' || 'aac' || 'm4a' || 'flac' => Icons.audio_file_outlined,
    'mp4' || 'mov' || 'avi' || 'mkv' || 'webm' => Icons.video_file_outlined,
    'ttf' ||
    'ttc' ||
    'otf' ||
    'woff' ||
    'woff2' => Icons.font_download_outlined,
    'excalidraw' => Icons.draw_outlined,
    'zip' || '7z' || 'rar' || 'tar' || 'gz' || 'bz2' => Icons.archive_outlined,
    'apk' => Icons.android_rounded,
    'gitignore' || 'gitkeep' || 'ini' => Icons.settings_outlined,
    'epub' || 'mobi' => Icons.menu_book_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}
