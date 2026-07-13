import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/pages/home_tab.dart';
import 'package:preconnect/pages/ui_kit.dart';

class DSpaceCategory {
  const DSpaceCategory({
    required this.category,
    required this.url,
    required this.count,
  });

  final String category;
  final String url;
  final int count;

  factory DSpaceCategory.fromJson(Map<String, dynamic> json) {
    return DSpaceCategory(
      category: json['category']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      count: json['count'] is int ? json['count'] as int : 0,
    );
  }
}

class DSpaceFile {
  const DSpaceFile({
    required this.name,
    required this.url,
    required this.sizeBytes,
  });

  final String name;
  final String url;
  final int sizeBytes;

  factory DSpaceFile.fromJson(Map<String, dynamic> json) {
    return DSpaceFile(
      name: json['name']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      sizeBytes: json['sizeBytes'] is int ? json['sizeBytes'] as int : 0,
    );
  }

  String get sizeLabel {
    if (sizeBytes <= 0) return '0 KB';
    final kb = sizeBytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class DSpaceItem {
  const DSpaceItem({
    required this.uuid,
    required this.name,
    required this.handle,
    required this.author,
    required this.date,
    required this.category,
    required this.abstractText,
    required this.files,
  });

  final String uuid;
  final String name;
  final String handle;
  final String author;
  final String date;
  final String category;
  final String abstractText;
  final List<DSpaceFile> files;

  factory DSpaceItem.fromJson(Map<String, dynamic> json) {
    final filesList = json['files'] is List
        ? (json['files'] as List)
              .whereType<Map>()
              .map((f) => DSpaceFile.fromJson(f.cast<String, dynamic>()))
              .toList()
        : const <DSpaceFile>[];

    return DSpaceItem(
      uuid: json['uuid']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      handle: json['handle']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      abstractText: json['abstract']?.toString() ?? '',
      files: filesList,
    );
  }
}

class DSpaceBrowserPage extends StatefulWidget {
  const DSpaceBrowserPage({super.key});

  @override
  State<DSpaceBrowserPage> createState() => _DSpaceBrowserPageState();
}

class _DSpaceBrowserPageState extends State<DSpaceBrowserPage> {
  final ApiClient _client = ApiClient();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _itemsScrollController = ScrollController();

  static const int _pageSize = 32;
  int _visibleItemCount = _pageSize;

  List<DSpaceCategory>? _categories;
  List<DSpaceCategory> _filteredCategories = [];
  bool _isLoadingCategories = false;
  String _categorySearchQuery = '';
  String? _categoriesError;

  DSpaceCategory? _selectedCategory;
  List<DSpaceItem>? _items;
  List<DSpaceItem> _filteredItems = [];
  bool _isLoadingItems = false;
  String _itemSearchQuery = '';
  String? _itemsError;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final val = _searchController.text;
      setState(() {
        if (_selectedCategory == null) {
          _categorySearchQuery = val;
          _filterCategories();
        } else {
          _itemSearchQuery = val;
          _filterItems();
        }
      });
    });
    _loadCategories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _itemsScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    if (mounted) {
      setState(() {
        _isLoadingCategories = true;
        _categoriesError = null;
      });
    }

    try {
      final response = await _client.publicGet(
        ApiConfig.dspaceDataUrl,
        acceptedStatusCodes: const <int>{200},
        cacheDuration: const Duration(hours: 12),
      );
      final decoded = jsonDecode(response.body);
      if (decoded is List) {
        final parsed = decoded
            .whereType<Map>()
            .map(
              (item) => DSpaceCategory.fromJson(item.cast<String, dynamic>()),
            )
            .where((c) => c.category.isNotEmpty)
            .toList();

        parsed.sort((a, b) => b.count.compareTo(a.count));

        if (mounted) {
          setState(() {
            _categories = parsed;
            _filterCategories();
            _isLoadingCategories = false;
          });
        }
      } else {
        throw const FormatException('Expected JSON list');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _categoriesError = 'Failed to load categories: $e';
          _isLoadingCategories = false;
        });
      }
    }
  }

  Future<void> _loadCategoryItems(DSpaceCategory category) async {
    if (mounted) {
      setState(() {
        _isLoadingItems = true;
        _itemsError = null;
        _items = null;
        _filteredItems = [];
        _itemSearchQuery = '';
        _visibleItemCount = _pageSize;
      });
    }

    try {
      final response = await _client.publicGet(
        category.url,
        acceptedStatusCodes: const <int>{200},
        cacheDuration: const Duration(hours: 12),
      );

      final parsed = await compute(_parseDSpaceItems, response.body);

      if (mounted) {
        setState(() {
          _items = parsed;
          _filterItems();
          _isLoadingItems = false;
        });
      }
    } catch (e) {
      try {
        final catQuery = category.category.trim().toLowerCase();
        final fallbackResponse = await _client.publicGet(
          '${ApiConfig.realtimeApiBase}/data/dspace/search?category=$catQuery&limit=200',
          acceptedStatusCodes: const <int>{200},
          cacheDuration: const Duration(hours: 12),
        );
        final parsed = await compute(_parseDSpaceItems, fallbackResponse.body);

        if (mounted) {
          setState(() {
            _items = parsed;
            _filterItems();
            _isLoadingItems = false;
          });
          return;
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _itemsError = 'Failed to load items: $e';
          _isLoadingItems = false;
        });
      }
    }
  }

  static List<DSpaceItem> _parseDSpaceItems(String body) {
    final decoded = jsonDecode(body);
    final rawItems = decoded is Map ? decoded['items'] : null;
    if (rawItems is List) {
      return rawItems
          .whereType<Map>()
          .map((item) => DSpaceItem.fromJson(item.cast<String, dynamic>()))
          .toList();
    }
    return const <DSpaceItem>[];
  }

  void _filterCategories() {
    final query = _categorySearchQuery.trim().toLowerCase();
    final all = _categories ?? [];
    if (query.isEmpty) {
      _filteredCategories = all;
    } else {
      _filteredCategories = all
          .where((c) => c.category.toLowerCase().contains(query))
          .toList();
    }
  }

  void _filterItems() {
    final query = _itemSearchQuery.trim().toLowerCase();
    final all = _items ?? [];
    if (query.isEmpty) {
      _filteredItems = all;
    } else {
      _filteredItems = all.where((item) {
        return item.name.toLowerCase().contains(query) ||
            item.author.toLowerCase().contains(query) ||
            item.handle.toLowerCase().contains(query);
      }).toList();
    }
  }

  void _showDocumentDetails(DSpaceItem item) {
    showBracuBottomSheet<void>(
      context,
      title: item.name,
      subtitle: item.author.isNotEmpty ? item.author : 'No author listed',
      builder: (sheetContext, textPrimary, textSecondary) {
        final dragController = bracuBottomSheetScrollController(sheetContext);
        String displayDate = '';
        if (item.date.trim().isNotEmpty) {
          final trimmed = item.date.trim();
          DateTime? parsed;
          if (trimmed.length == 4) {
            parsed = DateTime.tryParse('$trimmed-01-01');
            if (parsed != null) {
              displayDate = DateFormat('yyyy').format(parsed);
            }
          } else if (trimmed.length == 7) {
            parsed = DateTime.tryParse('$trimmed-01');
            if (parsed != null) {
              displayDate = DateFormat('MMMM yyyy').format(parsed);
            }
          } else {
            parsed = DateTime.tryParse(trimmed);
            if (parsed != null) {
              displayDate = DateFormat('EEEE, d MMMM yyyy').format(parsed);
            }
          }
          if (displayDate.isEmpty) {
            displayDate = trimmed;
          }
        }

        final catLabel = _selectedCategory?.category ?? 'Document';
        final metaText = displayDate.isNotEmpty
            ? '$catLabel  •  $displayDate'
            : catLabel;

        return ListView(
          controller: dragController,
          children: [
            Text(
              metaText,
              style: TextStyle(
                color: textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Gap(18),
            if (item.abstractText.trim().isNotEmpty) ...[
              Text(
                'Abstract',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Gap(6),
              Text(
                item.abstractText.trim(),
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Gap(16),
            ],
            if (item.files.isNotEmpty) ...[
              Text(
                'Attachments',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Gap(10),
              ...item.files.map((file) {
                final ext = file.name.contains('.')
                    ? file.name.split('.').last.toUpperCase()
                    : 'DOCUMENT';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: BracuActionBannerCard(
                    title: file.name,
                    subtitle: '${file.sizeLabel} • $ext',
                    icon: Icons.description_rounded,
                    iconColor: BracuPalette.primary,
                    showTrailingIcon: true,
                    onTap: () => openExternalUrl(context, file.url),
                  ),
                );
              }),
            ],
          ],
        );
      },
    );
  }

  Widget _buildCategoriesView(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);

    if (_isLoadingCategories) {
      return const Expanded(child: BracuLoading());
    }

    if (_categoriesError != null) {
      return Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Unable to load repository categories. Please try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Gap(16),
                BracuActionButton(label: 'Retry', onPressed: _loadCategories),
              ],
            ),
          ),
        ),
      );
    }

    return Expanded(
      child: _filteredCategories.isEmpty
          ? const BracuEmptyState(message: 'No categories found.')
          : BracuRefreshScroll(
              onRefresh: _loadCategories,
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                children: _filteredCategories.map((c) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: BracuActionCard(
                      title: c.category,
                      subtitle: '${c.count.toString()} documents',
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: textSecondary,
                      ),
                      onTap: () {
                        setState(() {
                          _selectedCategory = c;
                        });
                        _loadCategoryItems(c);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
    );
  }

  Widget _buildItemsView(BuildContext context) {
    if (_isLoadingItems) {
      return const Expanded(child: BracuLoading());
    }

    if (_itemsError != null) {
      final textSecondary = BracuPalette.textSecondary(context);
      return Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Unable to load documents. Please try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Gap(16),
                BracuActionButton(
                  label: 'Retry',
                  onPressed: () => _loadCategoryItems(_selectedCategory!),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_filteredItems.isEmpty) {
      return const Expanded(
        child: BracuEmptyState(message: 'No documents found.'),
      );
    }

    final visibleCount = _filteredItems.length < _visibleItemCount
        ? _filteredItems.length
        : _visibleItemCount;
    final visibleList = _filteredItems
        .take(visibleCount)
        .toList(growable: false);
    final hasMore = visibleCount < _filteredItems.length;
    final showBackToTop = _visibleItemCount > _pageSize;

    return Expanded(
      child: BracuRefreshScroll(
        controller: _itemsScrollController,
        onRefresh: () => _loadCategoryItems(_selectedCategory!),
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          children: [
            ...visibleList.map((item) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: BracuActionCard(
                  title: item.name,
                  subtitle: item.author.isNotEmpty
                      ? (item.date.trim().isNotEmpty
                            ? '${item.author}  •  ${item.date.trim()}'
                            : item.author)
                      : (item.date.trim().isNotEmpty
                            ? 'No author listed  •  ${item.date.trim()}'
                            : 'No author listed'),
                  onTap: () => _showDocumentDetails(item),
                ),
              );
            }),
            if (hasMore)
              buildLoadMoreButton(
                onPressed: () {
                  setState(() {
                    _visibleItemCount = _visibleItemCount + _pageSize;
                  });
                },
              ),
            if (showBackToTop)
              buildScrollToTopButton(controller: _itemsScrollController),
          ],
        ),
      ),
    );
  }

  void _showHelpBottomSheet(BuildContext context) {
    showBracuBottomSheet<void>(
      context,
      title: 'DSpace Repository (BRACU IR)',
      initialChildSize: 0.65,
      builder: (sheetContext, textPrimary, textSecondary) {
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BRACU IR is the official academic repository of BRAC University.',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Gap(16),
              _buildHelpItem(
                context,
                icon: Icons.category_rounded,
                title: 'Browse Categories',
                body:
                    'Browse academic documents divided into specific collections such as Thesis, Journal, and Conference Papers.',
              ),
              const Gap(14),
              _buildHelpItem(
                context,
                icon: Icons.search_rounded,
                title: 'Search & Filter',
                body:
                    'Use the search bar at the top to filter categories or quickly locate documents matching titles or authors.',
              ),
              const Gap(14),
              _buildHelpItem(
                context,
                icon: Icons.description_rounded,
                title: 'Document Details',
                body:
                    'Tap any document card to view its metadata, read the publication abstract, and access attachments.',
              ),
              const Gap(14),
              _buildHelpItem(
                context,
                icon: Icons.download_rounded,
                title: 'Direct Downloads',
                body:
                    'Tapping any PDF attachment card will open/download the file via your external web browser.',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHelpItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: BracuPalette.primary, size: 20),
        const Gap(12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: BracuPalette.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Gap(4),
              Text(
                body,
                style: TextStyle(
                  color: BracuPalette.textSecondary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _selectedCategory == null
        ? 'DSpace'
        : _selectedCategory!.category;
    final subtitle = _selectedCategory == null ? 'Repository' : 'DSpace';

    return PopScope(
      canPop: _selectedCategory == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedCategory != null) {
          _searchController.clear();
          setState(() {
            _selectedCategory = null;
            _items = null;
            _filteredItems = [];
          });
        }
      },
      child: BracuBackScope(
        canGoBack: true,
        onBack: () {
          if (_selectedCategory != null) {
            _searchController.clear();
            setState(() {
              _selectedCategory = null;
              _items = null;
              _filteredItems = [];
            });
          } else {
            HomeTabRegistry.setActive(HomeTab.dashboard);
          }
        },
        child: BracuPageScaffold(
          title: title,
          subtitle: subtitle,
          icon: Icons.library_books_rounded,
          showBack: true,
          actions: [
            if (_selectedCategory == null)
              IconButton(
                tooltip: 'Help',
                onPressed: () => _showHelpBottomSheet(context),
                icon: const Icon(
                  Icons.help_outline_rounded,
                  color: BracuPalette.primary,
                ),
              )
            else
              IconButton(
                tooltip: 'Refresh',
                onPressed: () => _loadCategoryItems(_selectedCategory!),
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: BracuPalette.primary,
                ),
              ),
          ],
          body: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              children: [
                BracuSearchField(
                  controller: _searchController,
                  hintText: _selectedCategory == null
                      ? 'Search categories...'
                      : 'Search documents...',
                ),
                const Gap(16),
                if (_selectedCategory == null)
                  _buildCategoriesView(context)
                else
                  _buildItemsView(context),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
