import 'package:flutter/material.dart';
import 'package:preconnect/model/progress_info.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/course_pin_store.dart';

class AllCoursesPage extends StatefulWidget {
  const AllCoursesPage({super.key, required this.info});

  final ProgressInfo info;

  @override
  State<AllCoursesPage> createState() => _AllCoursesPageState();
}

class _AllCoursesPageState extends State<AllCoursesPage> {
  late final TextEditingController _searchController;
  String _searchQuery = '';
  String _selectedHeader = 'All';
  bool _mandatoryOnly = false;
  final Set<String> _pinnedCodes = <String>{};
  static const String _pinScope = 'all_courses';

  List<String> get _headers {
    final values =
        widget.info.curriculumCourses
            .map((e) => e.headerName)
            .where((e) => e.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return ['All', ...values];
  }

  @override
  void initState() {
    super.initState();
    _loadPins();
    _searchController = TextEditingController();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPins() async {
    final pins = await CoursePinStore.load(_pinScope);
    if (!mounted) return;
    setState(() {
      _pinnedCodes
        ..clear()
        ..addAll(pins);
    });
  }

  Future<void> _togglePin(String code) async {
    final key = code.trim().toUpperCase();
    if (key.isEmpty) return;
    final willPin = !_pinnedCodes.contains(key);
    setState(() {
      if (willPin) {
        _pinnedCodes.add(key);
      } else {
        _pinnedCodes.remove(key);
      }
    });
    await CoursePinStore.save(_pinScope, _pinnedCodes);
    if (!mounted) return;
    showAppSnackBar(context, willPin ? '$key pinned to top' : '$key unpinned');
  }

  List<CurriculumCourse> get _filteredCourses {
    final list = widget.info.curriculumCourses.where((course) {
      if (_selectedHeader != 'All' && course.headerName != _selectedHeader) {
        return false;
      }
      if (_mandatoryOnly && !course.isMandatory) {
        return false;
      }
      if (_searchQuery.isEmpty) {
        return true;
      }
      final code = course.code.toLowerCase();
      final title = course.title.toLowerCase();
      final subHeader = course.subHeaderName.toLowerCase();
      return code.contains(_searchQuery) ||
          title.contains(_searchQuery) ||
          subHeader.contains(_searchQuery);
    }).toList();
    list.sort((a, b) {
      final ap = _pinnedCodes.contains(a.code.toUpperCase()) ? 0 : 1;
      final bp = _pinnedCodes.contains(b.code.toUpperCase()) ? 0 : 1;
      if (ap != bp) return ap.compareTo(bp);
      return compareNaturalText(a.code, b.code);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredCourses;
    return BracuPageScaffold(
      title: 'All Courses',
      subtitle: 'Search & Filter',
      icon: Icons.menu_book_outlined,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          TextField(
            controller: _searchController,
            style: TextStyle(color: BracuPalette.textPrimary(context)),
            decoration: InputDecoration(
              hintText: 'Search by course code or title',
              hintStyle: TextStyle(color: BracuPalette.textSecondary(context)),
              prefixIcon: Icon(
                Icons.search,
                color: BracuPalette.textSecondary(context),
              ),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => _searchController.clear(),
                      icon: Icon(
                        Icons.close,
                        color: BracuPalette.textSecondary(context),
                      ),
                    ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: BracuPalette.textSecondary(
                    context,
                  ).withValues(alpha: 0.24),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: BracuPalette.primary),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: _headers.map((header) {
                final selected = _selectedHeader == header;
                return ChoiceChip(
                  label: Text(header),
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    color: selected
                        ? BracuPalette.primary
                        : BracuPalette.textPrimary(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  side: BorderSide(
                    color: selected
                        ? BracuPalette.primary.withValues(alpha: 0.8)
                        : BracuPalette.textSecondary(
                            context,
                          ).withValues(alpha: 0.24),
                  ),
                  backgroundColor: BracuPalette.card(context),
                  selectedColor: BracuPalette.primary.withValues(alpha: 0.14),
                  selected: selected,
                  onSelected: (_) {
                    setState(() {
                      _selectedHeader = header;
                    });
                  },
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: FilterChip(
              label: const Text('Mandatory'),
              showCheckmark: false,
              labelStyle: TextStyle(
                color: _mandatoryOnly
                    ? BracuPalette.primary
                    : BracuPalette.textPrimary(context),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              side: BorderSide(
                color: _mandatoryOnly
                    ? BracuPalette.primary.withValues(alpha: 0.8)
                    : BracuPalette.textSecondary(
                        context,
                      ).withValues(alpha: 0.24),
              ),
              backgroundColor: BracuPalette.card(context),
              selectedColor: BracuPalette.primary.withValues(alpha: 0.14),
              selected: _mandatoryOnly,
              onSelected: (value) {
                setState(() {
                  _mandatoryOnly = value;
                });
              },
            ),
          ),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            const BracuCard(child: BracuEmptyState(message: 'No course found.'))
          else
            ...filtered.map((course) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: BracuCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${course.code} - ${_formatCredit(course.credit)} Credits',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: BracuPalette.textPrimary(context),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              course.title.isEmpty ? '--' : course.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: BracuPalette.textSecondary(context),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 96,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            IconButton(
                              tooltip:
                                  _pinnedCodes.contains(
                                    course.code.toUpperCase(),
                                  )
                                  ? 'Unpin'
                                  : 'Pin to top',
                              onPressed: () => _togglePin(course.code),
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              padding: EdgeInsets.zero,
                              icon: Icon(
                                _pinnedCodes.contains(course.code.toUpperCase())
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                size: 18,
                                color:
                                    _pinnedCodes.contains(
                                      course.code.toUpperCase(),
                                    )
                                    ? BracuPalette.favorite
                                    : BracuPalette.textSecondary(context),
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              course.isMandatory ? 'Required' : 'Optional',
                              style: TextStyle(
                                color: course.isMandatory
                                    ? BracuPalette.warning
                                    : BracuPalette.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  String _formatCredit(double value) {
    if (value % 1 == 0) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }
}
