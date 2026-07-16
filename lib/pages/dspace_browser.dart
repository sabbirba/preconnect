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
    required this.lastModified,
    required this.department,
    required this.supervisor,
    required this.subject,
    required this.keywords,
    required this.language,
  });

  final String uuid;
  final String name;
  final String handle;
  final String author;
  final String date;
  final String category;
  final String abstractText;
  final List<DSpaceFile> files;
  final String lastModified;
  final String department;
  final String supervisor;
  final List<String> subject;
  final List<String> keywords;
  final String language;

  factory DSpaceItem.fromJson(Map<String, dynamic> json) {
    final filesList = json['files'] is List
        ? (json['files'] as List)
              .whereType<Map>()
              .map((f) => DSpaceFile.fromJson(f.cast<String, dynamic>()))
              .toList()
        : const <DSpaceFile>[];

    List<String> parseStringList(dynamic raw) {
      if (raw is List) return raw.map((e) => e.toString()).toList();
      if (raw is String && raw.isNotEmpty) return [raw];
      return const [];
    }

    return DSpaceItem(
      uuid: json['uuid']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      handle: json['handle']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      abstractText: json['abstract']?.toString() ?? '',
      files: filesList,
      lastModified: json['lastModified']?.toString() ?? '',
      department: json['department']?.toString() ?? '',
      supervisor: json['supervisor']?.toString() ?? '',
      subject: parseStringList(json['subject']),
      keywords: parseStringList(json['keywords']),
      language: json['language']?.toString() ?? '',
    );
  }
}

enum _DSpaceSort { newestFirst, oldestFirst, lastModified }

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

  _DSpaceSort _sortOrder = _DSpaceSort.newestFirst;
  int? _filterFromYear;
  int? _filterToYear;

  bool get _hasActiveFilters =>
      _sortOrder != _DSpaceSort.newestFirst ||
      _filterFromYear != null ||
      _filterToYear != null;

  List<int> get _availableYears {
    final items = _items ?? [];
    final years = <int>{};
    for (final item in items) {
      final y = _parseYear(item.date);
      if (y != null) years.add(y);
    }
    final sorted = years.toList()..sort();
    return sorted;
  }

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
        _sortOrder = _DSpaceSort.newestFirst;
        _filterFromYear = null;
        _filterToYear = null;
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

  static int? _parseYear(String date) {
    if (date.isEmpty) return null;
    final trimmed = date.trim();
    if (trimmed.contains('/')) {
      final parts = trimmed.split('/');
      if (parts.length == 3) return int.tryParse(parts[2]);
      return null;
    }
    if (trimmed.length >= 4) return int.tryParse(trimmed.substring(0, 4));
    return null;
  }

  static int _extractMonth(String date) {
    final t = date.trim();
    if (t.contains('/')) {
      return int.tryParse(t.split('/').first) ?? 0;
    }
    return t.length >= 7 ? int.tryParse(t.substring(5, 7)) ?? 0 : 0;
  }

  static int _compareDates(String a, String b) {
    final aYear = _parseYear(a) ?? 0;
    final bYear = _parseYear(b) ?? 0;
    if (aYear != bYear) return aYear.compareTo(bYear);
    return _extractMonth(a).compareTo(_extractMonth(b));
  }

  void _filterItems() {
    final query = _itemSearchQuery.trim().toLowerCase();
    final all = _items ?? [];

    final filtered = all.where((item) {
      if (query.isNotEmpty) {
        final matches =
            item.name.toLowerCase().contains(query) ||
            item.author.toLowerCase().contains(query) ||
            item.handle.toLowerCase().contains(query) ||
            item.department.toLowerCase().contains(query) ||
            item.supervisor.toLowerCase().contains(query) ||
            item.language.toLowerCase().contains(query) ||
            item.subject.any((s) => s.toLowerCase().contains(query)) ||
            item.keywords.any((k) => k.toLowerCase().contains(query));
        if (!matches) return false;
      }
      final year = _parseYear(item.date);
      if (_filterFromYear != null &&
          (year == null || year < _filterFromYear!)) {
        return false;
      }
      if (_filterToYear != null && (year == null || year > _filterToYear!)) {
        return false;
      }
      return true;
    }).toList();

    switch (_sortOrder) {
      case _DSpaceSort.newestFirst:
        filtered.sort((a, b) => _compareDates(b.date, a.date));
        break;
      case _DSpaceSort.oldestFirst:
        filtered.sort((a, b) => _compareDates(a.date, b.date));
        break;
      case _DSpaceSort.lastModified:
        filtered.sort((a, b) => b.lastModified.compareTo(a.lastModified));
        break;
    }

    _filteredItems = filtered;
  }

  void _showFilterSheet(BuildContext context) {
    var localSort = _sortOrder;
    var localFrom = _filterFromYear;
    var localTo = _filterToYear;
    final years = _availableYears;

    showBracuBottomSheet<void>(
      context,
      title: 'Filter & Sort',
      initialChildSize: 0.52,
      builder: (sheetContext, textPrimary, textSecondary) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Widget sortOption(String label, IconData icon, _DSpaceSort value) {
              final selected = localSort == value;
              return GestureDetector(
                onTap: () => setLocal(() => localSort = value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? BracuPalette.primary.withValues(alpha: 0.1)
                        : textSecondary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? BracuPalette.primary.withValues(alpha: 0.4)
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: selected ? BracuPalette.primary : textSecondary,
                      ),
                      const Gap(10),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: selected
                                ? BracuPalette.primary
                                : textPrimary,
                            fontSize: 14,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (selected)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: BracuPalette.primary,
                        ),
                    ],
                  ),
                ),
              );
            }

            List<BracuSelectOption<String>> yearOptions() => [
              const BracuSelectOption<String>(
                value: '',
                label: 'Any Year',
                icon: Icons.all_inclusive_rounded,
              ),
              ...years.reversed.map(
                (y) => BracuSelectOption<String>(value: '$y', label: '$y'),
              ),
            ];

            BracuSelectDropdownChip<String> yearChip(
              String label,
              int? value,
              void Function(int?) onChange,
            ) {
              return BracuSelectDropdownChip<String>(
                label: value != null ? '$value' : label,
                title: label,
                selected: value != null,
                borderRadius: 12,
                options: yearOptions(),
                selectedValue: value != null ? '$value' : '',
                onSelected: (s) => onChange(s.isEmpty ? null : int.tryParse(s)),
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sortOption(
                    'Last Modified',
                    Icons.update_rounded,
                    _DSpaceSort.lastModified,
                  ),
                  sortOption(
                    'Newest First',
                    Icons.arrow_downward_rounded,
                    _DSpaceSort.newestFirst,
                  ),
                  sortOption(
                    'Oldest First',
                    Icons.arrow_upward_rounded,
                    _DSpaceSort.oldestFirst,
                  ),
                  const Gap(8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      yearChip(
                        'From Year',
                        localFrom,
                        (v) => setLocal(() => localFrom = v),
                      ),
                      const Gap(12),
                      yearChip(
                        'To Year',
                        localTo,
                        (v) => setLocal(() => localTo = v),
                      ),
                    ],
                  ),
                  const Gap(12),
                  Row(
                    children: [
                      Expanded(
                        child: BracuActionButton(
                          label: 'Clear',
                          onPressed: () {
                            setLocal(() {
                              localSort = _DSpaceSort.lastModified;
                              localFrom = null;
                              localTo = null;
                            });
                          },
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: BracuActionButton(
                          label: 'Apply',
                          outlined: false,
                          backgroundColor: BracuPalette.primary,
                          foregroundColor: Colors.white,
                          onPressed: () {
                            setState(() {
                              _sortOrder = localSort;
                              _filterFromYear = localFrom;
                              _filterToYear = localTo;
                              _visibleItemCount = _pageSize;
                              _filterItems();
                            });
                            Navigator.of(sheetContext).pop();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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
          if (trimmed.contains('/')) {
            final parts = trimmed.split('/');
            if (parts.length == 3) {
              final m = parts[0].padLeft(2, '0');
              final d = parts[1].padLeft(2, '0');
              final y = parts[2];
              parsed = DateTime.tryParse('$y-$m-$d');
              if (parsed != null) {
                displayDate = DateFormat('d MMMM yyyy').format(parsed);
              }
            }
          } else if (trimmed.length == 4) {
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
              displayDate = DateFormat('d MMMM yyyy').format(parsed);
            }
          }
          if (displayDate.isEmpty) displayDate = trimmed;
        }

        String displayLastModified = '';
        if (item.lastModified.isNotEmpty) {
          final parsed = DateTime.tryParse(item.lastModified);
          if (parsed != null) {
            displayLastModified = DateFormat(
              'd MMM yyyy, h:mm a',
            ).format(parsed.toLocal());
          }
        }

        final catLabel = _selectedCategory?.category ?? 'Document';
        final metaText = displayDate.isNotEmpty
            ? '$catLabel  •  $displayDate'
            : catLabel;

        Widget metaRow(String label, String value) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label: ',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

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
            const Gap(14),
            if (item.department.isNotEmpty)
              metaRow('Department', item.department),
            if (item.supervisor.isNotEmpty) metaRow('Advisor', item.supervisor),
            if (item.language.isNotEmpty) metaRow('Language', item.language),
            if (item.subject.isNotEmpty)
              metaRow('Subject', item.subject.join(', ')),
            if (item.keywords.isNotEmpty)
              metaRow('Keywords', item.keywords.join(', ')),
            if (displayLastModified.isNotEmpty)
              metaRow('Last Modified', displayLastModified),
            if (item.abstractText.trim().isNotEmpty) ...[
              const Gap(6),
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

  Widget _buildActiveFilterBar(BuildContext context) {
    if (!_hasActiveFilters) return const SizedBox.shrink();

    final textSecondary = BracuPalette.textSecondary(context);

    final chips = <Widget>[];

    if (_sortOrder != _DSpaceSort.newestFirst) {
      final labels = {
        _DSpaceSort.newestFirst: 'Newest First',
        _DSpaceSort.oldestFirst: 'Oldest First',
        _DSpaceSort.lastModified: 'Last Modified',
      };
      chips.add(
        _FilterChip(
          label: labels[_sortOrder]!,
          onRemove: () {
            setState(() {
              _sortOrder = _DSpaceSort.newestFirst;
              _visibleItemCount = _pageSize;
              _filterItems();
            });
          },
        ),
      );
    }

    if (_filterFromYear != null || _filterToYear != null) {
      final from = _filterFromYear;
      final to = _filterToYear;
      final label = from != null && to != null
          ? '$from – $to'
          : from != null
          ? 'From $from'
          : 'Up to $to';
      chips.add(
        _FilterChip(
          label: label,
          onRemove: () {
            setState(() {
              _filterFromYear = null;
              _filterToYear = null;
              _visibleItemCount = _pageSize;
              _filterItems();
            });
          },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: chips),
            ),
          ),
          const Gap(8),
          GestureDetector(
            onTap: () {
              setState(() {
                _sortOrder = _DSpaceSort.newestFirst;
                _filterFromYear = null;
                _filterToYear = null;
                _visibleItemCount = _pageSize;
                _filterItems();
              });
            },
            child: Text(
              'Clear',
              style: TextStyle(
                color: textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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
                    'Use the search bar to filter categories or locate documents by title, author, department, subject, or keywords.',
              ),
              const Gap(14),
              _buildHelpItem(
                context,
                icon: Icons.tune_rounded,
                title: 'Sort & Date Range',
                body:
                    'Tap the filter icon to sort by date or last modified, and restrict results to a specific year range.',
              ),
              const Gap(14),
              _buildHelpItem(
                context,
                icon: Icons.description_rounded,
                title: 'Document Details',
                body:
                    'Tap any document card to view its metadata, abstract, supervisor, department, and attachments.',
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
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              HomeTabRegistry.setActive(HomeTab.dashboard);
            }
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
            else ...[
              Stack(
                children: [
                  IconButton(
                    tooltip: 'Filter & Sort',
                    onPressed: _items != null && _items!.isNotEmpty
                        ? () => _showFilterSheet(context)
                        : null,
                    icon: Icon(
                      Icons.tune_rounded,
                      color: _hasActiveFilters
                          ? BracuPalette.primary
                          : BracuPalette.primary.withValues(alpha: 0.6),
                    ),
                  ),
                  if (_hasActiveFilters)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: BracuPalette.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              BracuRefreshButton(
                onPressed: () => _loadCategoryItems(_selectedCategory!),
                isLoading: _isLoadingItems,
              ),
            ],
          ],
          body: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              children: [
                BracuSearchField(
                  controller: _searchController,
                  hintText: 'Search...',
                ),
                const Gap(10),
                if (_selectedCategory != null) _buildActiveFilterBar(context),
                if (_selectedCategory != null && !_hasActiveFilters)
                  const Gap(6),
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: BracuPalette.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: BracuPalette.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: BracuPalette.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Gap(5),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(
              Icons.close_rounded,
              size: 14,
              color: BracuPalette.primary,
            ),
          ),
        ],
      ),
    );
  }
}
