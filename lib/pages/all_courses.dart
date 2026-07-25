import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/model/progress_info.dart';
import 'package:preconnect/pages/shared_widgets/course_tile.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/string_utils.dart';
import 'package:preconnect/tools/token_storage.dart';

class AllCoursesPage extends StatefulWidget {
  const AllCoursesPage({super.key, required this.info});

  final ProgressInfo info;

  @override
  State<AllCoursesPage> createState() => _AllCoursesPageState();
}

class _AllCoursesPageState extends State<AllCoursesPage> {
  late final TextEditingController _searchController;
  String _selectedHeader = 'All';
  bool _mandatoryOnly = false;
  bool _optionalOnly = false;
  Set<String> _pinnedCodes = {};

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
    _searchController = TextEditingController();
    _searchController.addListener(_onSearchChanged);
    _loadPins();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {});
  }

  Future<void> _loadPins() async {
    final pins = await CoursePinStore.load('all_courses');
    if (mounted) {
      setState(() {
        _pinnedCodes = pins.toSet();
      });
    }
  }

  Future<void> _togglePin(String code) async {
    final key = code.trim().toUpperCase();
    if (key.isEmpty) return;
    final current = Set<String>.from(_pinnedCodes);
    final willPin = !current.contains(key);
    if (willPin) {
      current.add(key);
    } else {
      current.remove(key);
    }
    setState(() {
      _pinnedCodes = current;
    });
    await CoursePinStore.save('all_courses', current);
    if (mounted) {
      showAppSnackBar(
        context,
        willPin ? '$key pinned to top' : '$key unpinned',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();

    final filtered = widget.info.curriculumCourses.where((course) {
      if (_selectedHeader != 'All' && course.headerName != _selectedHeader) {
        return false;
      }
      if (_mandatoryOnly && !_optionalOnly && !course.isMandatory) {
        return false;
      }
      if (_optionalOnly && !_mandatoryOnly && course.isMandatory) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      final code = course.code.toLowerCase();
      final title = course.title.toLowerCase();
      final subHeader = course.subHeaderName.toLowerCase();
      return code.contains(query) ||
          title.contains(query) ||
          subHeader.contains(query);
    }).toList();

    filtered.sort((a, b) {
      final ap = _pinnedCodes.contains(a.code.toUpperCase()) ? 0 : 1;
      final bp = _pinnedCodes.contains(b.code.toUpperCase()) ? 0 : 1;
      if (ap != bp) return ap.compareTo(bp);
      return compareNaturalText(a.code, b.code);
    });

    return BracuPageScaffold(
      title: 'All Courses',
      subtitle: 'Search & Filter',
      icon: Icons.menu_book_outlined,
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        itemCount: 1 + (filtered.isEmpty ? 1 : filtered.length),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildHeader(context, query);
          }
          if (filtered.isEmpty) {
            return const BracuCard(
              child: BracuEmptyState(message: 'No course found.'),
            );
          }
          final course = filtered[index - 1];
          final isPinned = _pinnedCodes.contains(course.code.toUpperCase());
          return CourseTile(
            code: course.code,
            title: course.title,
            credit: course.credit,
            isMandatory: course.isMandatory,
            isPinned: isPinned,
            onTogglePin: () => _togglePin(course.code),
            codeFontFamily: 'Outfit',
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String query) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BracuSearchField(
          controller: _searchController,
          hintText: 'Search by course code or title',
          query: query,
          keySuffix: 'all-courses',
        ),
        const Gap(12),
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
                backgroundColor: Colors.transparent,
                selectedColor: Colors.transparent,
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
        const Gap(12),
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              FilterChip(
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
                backgroundColor: Colors.transparent,
                selectedColor: Colors.transparent,
                selected: _mandatoryOnly,
                onSelected: (value) {
                  setState(() {
                    _mandatoryOnly = value;
                    if (value) {
                      _optionalOnly = false;
                    }
                  });
                },
              ),
              FilterChip(
                label: const Text('Optional'),
                showCheckmark: false,
                labelStyle: TextStyle(
                  color: _optionalOnly
                      ? BracuPalette.primary
                      : BracuPalette.textPrimary(context),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                side: BorderSide(
                  color: _optionalOnly
                      ? BracuPalette.primary.withValues(alpha: 0.8)
                      : BracuPalette.textSecondary(
                          context,
                        ).withValues(alpha: 0.24),
                ),
                backgroundColor: Colors.transparent,
                selectedColor: Colors.transparent,
                selected: _optionalOnly,
                onSelected: (value) {
                  setState(() {
                    _optionalOnly = value;
                    if (value) {
                      _mandatoryOnly = false;
                    }
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
