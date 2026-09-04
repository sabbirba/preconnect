import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/bracu_leaks.dart';
import 'package:preconnect/model/bracu_leaks.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:url_launcher/url_launcher.dart';

class BracuLeaksPage extends StatefulWidget {
  const BracuLeaksPage({super.key});

  @override
  State<BracuLeaksPage> createState() => _BracuLeaksPageState();
}

class _BracuLeaksPageState extends State<BracuLeaksPage> {
  final BracuLeaksService _service = BracuLeaksService();
  final TextEditingController _searchController = TextEditingController();

  BracuLeaksCollection? _selectedCollection;
  List<BracuLeaksCollection>? _collections;
  BracuLeaksDetail? _detail;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    HomeTabRegistry.registerBackHandler(HomeTab.bracuLeaks, _handleBack);
    _searchController.addListener(_onSearchChanged);
    unawaited(_loadCollections());
  }

  @override
  void dispose() {
    HomeTabRegistry.unregisterBackHandler(HomeTab.bracuLeaks, _handleBack);
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  bool _handleBack() {
    if (_selectedCollection == null) return false;
    _searchController.clear();
    setState(() {
      _selectedCollection = null;
      _detail = null;
      _error = null;
      _loading = false;
    });
    return true;
  }

  Future<void> _loadCollections({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final collections = await _service.loadCollections(
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _collections = collections;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _selectCollection(
    BracuLeaksCollection collection, {
    bool forceRefresh = false,
  }) async {
    setState(() {
      _selectedCollection = collection;
      _detail = null;
      _loading = true;
      _error = null;
      _searchController.clear();
    });
    try {
      final detail = await _service.loadDetail(
        collection.code,
        forceRefresh: forceRefresh,
      );
      if (!mounted || _selectedCollection?.code != collection.code) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || _selectedCollection?.code != collection.code) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _refresh() {
    final selected = _selectedCollection;
    return selected == null
        ? _loadCollections(forceRefresh: true)
        : _selectCollection(selected, forceRefresh: true);
  }

  List<BracuLeaksCollection> get _filteredCollections {
    final query = _searchController.text.trim().toLowerCase();
    final collections = _collections ?? const <BracuLeaksCollection>[];
    if (query.isEmpty) return collections;
    return collections
        .where(
          (item) =>
              item.code.toLowerCase().contains(query) ||
              item.title.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  List<BracuLeaksCategory> get _filteredCategories {
    final query = _searchController.text.trim().toLowerCase();
    final categories = _detail?.categories ?? const <BracuLeaksCategory>[];
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
                          file.path.toLowerCase().contains(query),
                    )
                    .toList(growable: false);
          return BracuLeaksCategory(name: category.name, files: files);
        })
        .where((category) => category.files.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedCollection;
    return BracuBackScope(
      canGoBack: true,
      onBack: () {
        if (!_handleBack()) HomeTabRegistry.setActive(HomeTab.dashboard);
      },
      child: BracuPageScaffold(
        title: 'Leaks',
        subtitle: 'Course',
        icon: Icons.folder_copy_outlined,
        showBack: true,
        actions: [
          if (selected == null)
            IconButton(
              tooltip: 'Source',
              onPressed: () => openExternalUrl(
                context,
                'https://github.com/braculeaks',
                failureMessage: 'Unable to open source.',
              ),
              icon: const PreConnectGitHubIcon(
                size: 22,
                color: BracuPalette.primary,
              ),
            )
          else
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
    if (_selectedCollection == null) {
      final collections = _filteredCollections;
      return Expanded(
        child: collections.isEmpty
            ? const BracuEmptyState(message: 'No collection found.')
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
                    .map(
                      (category) => Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              category.name,
                              style: TextStyle(
                                color: BracuPalette.textPrimary(context),
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Gap(12),
                            ...category.files.map(
                              (file) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: BracuActionCard(
                                  title: file.name,
                                  leadingIcon: _fileIcon(file.path),
                                  trailing: Icon(
                                    Icons.open_in_new_rounded,
                                    size: 19,
                                    color: BracuPalette.textSecondary(context),
                                  ),
                                  onTap: () => launchUrl(
                                    Uri.parse(file.url),
                                    mode: LaunchMode.externalApplication,
                                    webOnlyWindowName: '_blank',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
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
