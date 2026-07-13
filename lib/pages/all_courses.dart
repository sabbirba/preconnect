import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:signals_hooks/signals_hooks.dart';
import 'package:preconnect/model/progress_info.dart';
import 'package:preconnect/tools/string_utils.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/token_storage.dart';

class AllCoursesPage extends HookWidget {
  const AllCoursesPage({super.key, required this.info});

  final ProgressInfo info;

  List<String> get _headers {
    final values =
        info.curriculumCourses
            .map((e) => e.headerName)
            .where((e) => e.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return ['All', ...values];
  }

  @override
  Widget build(BuildContext context) {
    final searchController = useTextEditingController();
    useListenable(searchController);

    final selectedHeader = useSignal('All');
    final mandatoryOnly = useSignal(false);
    final optionalOnly = useSignal(false);
    final pinnedCodes = useSignal<Set<String>>(<String>{});

    useEffect(() {
      CoursePinStore.load('all_courses').then((pins) {
        pinnedCodes.value = pins.toSet();
      });
      return null;
    }, const []);

    Future<void> togglePin(String code) async {
      final key = code.trim().toUpperCase();
      if (key.isEmpty) return;
      final current = Set<String>.from(pinnedCodes.value);
      final willPin = !current.contains(key);
      if (willPin) {
        current.add(key);
      } else {
        current.remove(key);
      }
      pinnedCodes.value = current;
      await CoursePinStore.save('all_courses', current);
      if (context.mounted) {
        showAppSnackBar(
          context,
          willPin ? '$key pinned to top' : '$key unpinned',
        );
      }
    }

    final query = searchController.text.trim().toLowerCase();

    final filtered = info.curriculumCourses.where((course) {
      if (selectedHeader.value != 'All' &&
          course.headerName != selectedHeader.value) {
        return false;
      }
      if (mandatoryOnly.value && !optionalOnly.value && !course.isMandatory) {
        return false;
      }
      if (optionalOnly.value && !mandatoryOnly.value && course.isMandatory) {
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
      final ap = pinnedCodes.value.contains(a.code.toUpperCase()) ? 0 : 1;
      final bp = pinnedCodes.value.contains(b.code.toUpperCase()) ? 0 : 1;
      if (ap != bp) return ap.compareTo(bp);
      return compareNaturalText(a.code, b.code);
    });

    return BracuPageScaffold(
      title: 'All Courses',
      subtitle: 'Search & Filter',
      icon: Icons.menu_book_outlined,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          BracuSearchField(
            controller: searchController,
            hintText: 'Search by course code or title',
            query: query,
            keySuffix: 'all-courses',
          ),
          const Gap(10),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: _headers.map((header) {
                final selected = selectedHeader.value == header;
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
                    selectedHeader.value = header;
                  },
                );
              }).toList(),
            ),
          ),
          const Gap(8),
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
                    color: mandatoryOnly.value
                        ? BracuPalette.primary
                        : BracuPalette.textPrimary(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  side: BorderSide(
                    color: mandatoryOnly.value
                        ? BracuPalette.primary.withValues(alpha: 0.8)
                        : BracuPalette.textSecondary(
                            context,
                          ).withValues(alpha: 0.24),
                  ),
                  backgroundColor: Colors.transparent,
                  selectedColor: Colors.transparent,
                  selected: mandatoryOnly.value,
                  onSelected: (value) {
                    mandatoryOnly.value = value;
                    if (value) {
                      optionalOnly.value = false;
                    }
                  },
                ),
                FilterChip(
                  label: const Text('Optional'),
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    color: optionalOnly.value
                        ? BracuPalette.primary
                        : BracuPalette.textPrimary(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  side: BorderSide(
                    color: optionalOnly.value
                        ? BracuPalette.primary.withValues(alpha: 0.8)
                        : BracuPalette.textSecondary(
                            context,
                          ).withValues(alpha: 0.24),
                  ),
                  backgroundColor: Colors.transparent,
                  selectedColor: Colors.transparent,
                  selected: optionalOnly.value,
                  onSelected: (value) {
                    optionalOnly.value = value;
                    if (value) {
                      mandatoryOnly.value = false;
                    }
                  },
                ),
              ],
            ),
          ),
          const Gap(8),
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
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(text: course.code),
                                        WidgetSpan(
                                          alignment:
                                              PlaceholderAlignment.middle,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              left: 4,
                                            ),
                                            child: Tooltip(
                                              message:
                                                  pinnedCodes.value.contains(
                                                    course.code.toUpperCase(),
                                                  )
                                                  ? 'Unpin'
                                                  : 'Pin to top',
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                onTap: () =>
                                                    togglePin(course.code),
                                                child: Icon(
                                                  pinnedCodes.value.contains(
                                                        course.code
                                                            .toUpperCase(),
                                                      )
                                                      ? Icons.star_rounded
                                                      : Icons
                                                            .star_outline_rounded,
                                                  size: 16,
                                                  color:
                                                      pinnedCodes.value
                                                          .contains(
                                                            course.code
                                                                .toUpperCase(),
                                                          )
                                                      ? BracuPalette.favorite
                                                      : BracuPalette.textSecondary(
                                                          context,
                                                        ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    style: TextStyle(
                                      color: BracuPalette.textPrimary(context),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'Outfit',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Gap(3),
                            Text(
                              course.title.isEmpty ? '--' : course.title,
                              style: TextStyle(
                                color: BracuPalette.textSecondary(context),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Gap(10),
                      SizedBox(
                        width: 96,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${_formatCredit(course.credit)} credits',
                              style: TextStyle(
                                color: BracuPalette.textPrimary(context),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Gap(1),
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
