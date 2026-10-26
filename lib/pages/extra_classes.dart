import 'package:flutter/material.dart';
import 'package:preconnect/api/extra_classes.dart';
import 'package:preconnect/api/seat_status.dart';
import 'package:preconnect/model/extra_class.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/pages/shared_widgets/entry_card.dart';
import 'package:preconnect/tools/refresh_bus.dart';
import 'package:preconnect/tools/time_utils.dart';

class ExtraClassesPage extends StatefulWidget {
  const ExtraClassesPage({
    super.key,
    required this.semesterSessionId,
    required this.officialSections,
    required this.isRamadan,
    this.loadSections,
    this.store,
  });

  final int semesterSessionId;
  final List<Section> officialSections;
  final bool isRamadan;
  final Future<List<Section>> Function()? loadSections;
  final ExtraClassesStore? store;

  @override
  State<ExtraClassesPage> createState() => _ExtraClassesState();
}

class _ExtraClassesState extends State<ExtraClassesPage> {
  late final _store = widget.store ?? ExtraClassesStore();
  List<ExtraClass> _extras = [];
  List<Section> _catalogue = [];
  final _search = TextEditingController();
  String get _query => _search.text.trim().toLowerCase();
  bool get _canChange => !_busy && _storageError == null;
  String? _storageError;
  String? _catalogueError;
  bool _loading = true;
  bool _catalogueLoading = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await Future.wait([
      _loadSaved().whenComplete(() {
        if (mounted) setState(() => _loading = false);
      }),
      _loadCatalogue(),
    ]);
  }

  Future<void> _loadSaved() async {
    try {
      final saved = await _store.load();
      if (!mounted) return;
      setState(() {
        _extras = saved
            .where(
              (item) =>
                  item.section.semesterSessionId == widget.semesterSessionId,
            )
            .toList();
        _storageError = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _storageError = 'Could not load extra classes.');
      }
    }
  }

  Future<void> _loadCatalogue({bool forceRefresh = false}) async {
    setState(() => _catalogueLoading = true);
    try {
      final catalogue = widget.loadSections != null
          ? await widget.loadSections!()
          : (await SeatStatusService().preloadData(
              forceRefresh: forceRefresh,
            )).values.map((item) => Section.fromJson(item.toJson())).toList();
      final sections =
          catalogue
              .where(
                (item) => item.semesterSessionId == widget.semesterSessionId,
              )
              .where(
                (item) => item.sectionSchedule.classSchedules.any(
                  (meeting) => AppTime.weekdayFromName(meeting.day) != null,
                ),
              )
              .toList()
            ..sort((a, b) {
              final course = a.courseCode.compareTo(b.courseCode);
              return course == 0
                  ? a.sectionName.compareTo(b.sectionName)
                  : course;
            });
      if (!mounted) return;
      setState(() {
        _catalogue = sections;
        _catalogueError = sections.isEmpty ? 'No sections available.' : null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _catalogueError = 'Could not load sections.');
      }
    } finally {
      if (mounted) setState(() => _catalogueLoading = false);
    }
  }

  void _showHelp() {
    showAppBottomSheet<void>(
      context,
      title: 'Extra Classes Help',
      initialChildSize: 0.65,
      builder: (sheetContext, textPrimary, textSecondary) => ListView(
        controller: bottomSheetScrollController(sheetContext),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          buildInstructionStep(
            context,
            stepNumber: '1',
            title: 'Find Classes',
            body:
                'Search by course, section or faculty. Tap Refresh to reload available sections.',
          ),
          const SizedBox(height: 12),
          buildInstructionStep(
            context,
            stepNumber: '2',
            title: 'Add Classes',
            body:
                'Tap + to add all class days from a section. Matching times share a row; different times stay separate.',
          ),
          const SizedBox(height: 12),
          buildInstructionStep(
            context,
            stepNumber: '3',
            title: 'Remove Classes',
            body:
                'Tap − to remove an added section. A divider separates your extras from available sections.',
          ),
          const SizedBox(height: 12),
          buildInstructionStep(
            context,
            stepNumber: '4',
            title: 'Overlapping Classes',
            body:
                'Time overlaps are allowed, and both classes stay in your routine. Choose which class to attend.',
          ),
          const SizedBox(height: 12),
          buildInstructionStep(
            context,
            stepNumber: '5',
            title: 'Faculty Permission',
            body:
                'Always email or contact the section’s faculty member and get their permission before attending.',
          ),
          const SizedBox(height: 12),
          buildInstructionStep(
            context,
            stepNumber: '6',
            title: 'Local Routine',
            body:
                'Extras appear in Alarms and stay on this device. They do not change Connect enrolment or exam schedules.',
          ),
        ],
      ),
    );
  }

  Future<void> _persist(Future<void> Function() save) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await save();
      await _loadSaved();
      RefreshBus.instance.notify(reason: 'extra_classes');
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'Could not save extra classes.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Iterable<Widget> _meetingCards(Section section) sync* {
    final groups = <(Object, Object), List<ClassSchedule>>{};
    for (final meeting in section.sectionSchedule.classSchedules) {
      final time = (
        AppTime.parseTime(meeting.startTime) ?? meeting.startTime,
        AppTime.parseTime(meeting.endTime) ?? meeting.endTime,
      );
      groups.putIfAbsent(time, () => []).add(meeting);
    }
    for (final (index, meetings) in groups.values.indexed) {
      yield Padding(
        padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
        child: ScheduleEntryCard(
          sectionName: section.sectionName,
          courseCode: section.courseCode,
          schedule: meetings.first,
          isRamadan: widget.isRamadan,
          weekdays: meetings
              .map((meeting) => normalizeWeekday(meeting.day))
              .toSet()
              .toList(),
          roomNumber: section.roomNumber,
          faculties: section.faculties,
          wrapInCard: false,
        ),
      );
    }
  }

  Widget _sectionCard(Section section, {ExtraClass? extra}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [..._meetingCards(extra?.selectedSection ?? section)],
            ),
          ),
          IconButton(
            tooltip: extra == null ? 'Add Classes' : 'Remove Classes',
            icon: Icon(extra == null ? Icons.add : Icons.remove),
            onPressed: _canChange
                ? () => _persist(
                    () => extra != null
                        ? _store.remove(extra.key)
                        : _store.save(
                            ExtraClass(
                              section: section,
                              days: section.sectionSchedule.classSchedules
                                  .map((meeting) => meeting.day.toUpperCase())
                                  .where(
                                    (day) =>
                                        AppTime.weekdayFromName(day) != null,
                                  )
                                  .toSet(),
                            ),
                          ),
                  )
                : null,
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final savedKeys = _extras.map((item) => item.key).toSet();
    final officialIds = widget.officialSections
        .map((item) => item.sectionId)
        .toSet();
    final results = _catalogue
        .where(
          (section) =>
              !officialIds.contains(section.sectionId) &&
              !savedKeys.contains(
                '${section.semesterSessionId}|${section.sectionId}',
              ) &&
              '${section.courseCode} ${section.sectionName} ${section.faculties}'
                  .toLowerCase()
                  .contains(_query),
        )
        .toList();
    return AppPageScaffold(
      title: 'Extra Classes',
      subtitle: 'Personal Routine',
      actions: [
        IconButton(
          tooltip: 'Help',
          onPressed: _showHelp,
          style: appCompactIconButtonStyle(
            foregroundColor: AppPalette.primary,
            borderColor: Colors.transparent,
            padding: EdgeInsets.zero,
            borderRadius: 12,
          ),
          icon: const Icon(
            Icons.help_outline_rounded,
            color: AppPalette.primary,
          ),
        ),
        AppRefreshButton(
          isLoading: _catalogueLoading,
          onPressed: () => _loadCatalogue(forceRefresh: true),
        ),
      ],
      body: _loading
          ? const Center(child: AppLoading())
          : Column(
              children: [
                Padding(
                  padding: kPageListPadding.copyWith(bottom: 12),
                  child: AppSearchField(controller: _search, query: _query),
                ),
                if (_storageError != null)
                  ListTile(
                    title: Text(_storageError!),
                    trailing: AppActionButton(
                      onPressed: _loadSaved,
                      label: 'Retry',
                    ),
                  ),
                if (_catalogueError != null)
                  Padding(
                    padding: kPageListPadding.copyWith(top: 0, bottom: 12),
                    child: Text(_catalogueError!),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: kPageListPadding.copyWith(top: 0),
                    itemCount: _extras.length + results.length,
                    itemBuilder: (context, index) {
                      if (index < _extras.length) {
                        final extra = _extras[index];
                        return _sectionCard(extra.section, extra: extra);
                      }
                      final card = _sectionCard(
                        results[index - _extras.length],
                      );
                      if (_extras.isEmpty || index != _extras.length) {
                        return card;
                      }
                      return Column(
                        children: [
                          Divider(
                            height: 1,
                            color: AppPalette.textSecondary(
                              context,
                            ).withValues(alpha: 0.14),
                          ),
                          const SizedBox(height: 12),
                          card,
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
