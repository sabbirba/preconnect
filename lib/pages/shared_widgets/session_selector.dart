import 'package:flutter/material.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/pages/ui_kit.dart';

class SemesterSessionSelector extends StatefulWidget {
  const SemesterSessionSelector({
    super.key,
    required this.selectedSemesterSessionId,
    required this.onSessionChanged,
    this.iconOnly = true,
  });

  final int? selectedSemesterSessionId;
  final ValueChanged<SemesterSessionItem> onSessionChanged;
  final bool iconOnly;

  @override
  State<SemesterSessionSelector> createState() =>
      _SemesterSessionSelectorState();
}

class _SemesterSessionSelectorState extends State<SemesterSessionSelector> {
  List<SemesterSessionItem> _sessions = <SemesterSessionItem>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    final sessions = await ScheduleService().fetchSemesterSessions();
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _sessions.isEmpty) return const SizedBox.shrink();
    final selectedId =
        widget.selectedSemesterSessionId ?? _sessions.first.semesterSessionId;
    final current = _sessions.firstWhere(
      (s) => s.semesterSessionId == selectedId,
      orElse: () => _sessions.first,
    );

    final options = _sessions
        .map(
          (session) => BracuSelectOption<int>(
            value: session.semesterSessionId,
            label: session.description,
            icon: Icons.calendar_month_rounded,
          ),
        )
        .toList();

    if (widget.iconOnly) {
      return BracuSelectChip(
        icon: Icons.filter_list_rounded,
        selected: selectedId != _sessions.first.semesterSessionId,
        compact: true,
        showArrow: false,
        showBorder: false,
        onTap: () async {
          final value = await showBracuSelectDropdown<int>(
            context,
            title: 'Select Semester',
            options: options,
            selectedValue: selectedId,
          );
          if (value == null) return;
          final found = _sessions.firstWhere(
            (s) => s.semesterSessionId == value,
          );
          widget.onSessionChanged(found);
        },
      );
    }

    return BracuSelectDropdownChip<int>(
      title: 'Select Semester',
      label: current.description,
      options: options,
      selectedValue: selectedId,
      compact: true,
      showBorder: false,
      showArrow: true,
      selected: selectedId != _sessions.first.semesterSessionId,
      onSelected: (id) {
        final found = _sessions.firstWhere((s) => s.semesterSessionId == id);
        widget.onSessionChanged(found);
      },
    );
  }
}
