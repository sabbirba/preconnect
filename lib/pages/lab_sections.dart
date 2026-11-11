import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/model/advising_phase.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/pages/section_loader.dart';
import 'package:preconnect/pages/ui_kit.dart';

class _LabPhaseTab {
  const _LabPhaseTab({required this.label, required this.queryValue});

  final String label;
  final String queryValue;
}

final List<_LabPhaseTab> _labPhaseTabs = <_LabPhaseTab>[
  for (final phase in AdvisingPhase.values)
    _LabPhaseTab(label: phase.label, queryValue: phase.queryValue),
  const _LabPhaseTab(label: 'Wishlist', queryValue: 'WISH_LIST'),
];

Future<List<Section>> _loadLabSections(
  String phase, {
  bool forceRefresh = false,
}) {
  return ScheduleService().fetchRelatedLabSections(
    phase,
    forceRefresh: forceRefresh,
  );
}

class LabSectionsPage extends StatefulWidget {
  const LabSectionsPage({super.key, this.loadSections});

  final SectionLoader<String>? loadSections;

  @override
  State<LabSectionsPage> createState() => _LabSectionsPageState();
}

class _LabSectionsPageState extends State<LabSectionsPage> {
  late final List<SectionLoadController<String>> _controllers;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    final loader = widget.loadSections ?? _loadLabSections;
    _controllers = <SectionLoadController<String>>[
      for (final tab in _labPhaseTabs)
        SectionLoadController<String>(key: tab.queryValue, loader: loader),
    ];
    unawaited(_controllers.first.load());
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _select(int index) {
    if (index == _selected) return;
    setState(() => _selected = index);
    final controller = _controllers[index];
    if (!controller.isLoaded) unawaited(controller.load());
  }

  @override
  Widget build(BuildContext context) {
    final tab = _labPhaseTabs[_selected];
    return AppPageScaffold(
      title: 'Lab Sections',
      subtitle: 'Advising',
      icon: Icons.science_outlined,
      actions: [
        AppSelectDropdownChip<int>(
          title: 'Select Phase',
          label: tab.label,
          selected: true,
          selectedValue: _selected,
          compact: true,
          showBorder: false,
          options: [
            for (var index = 0; index < _labPhaseTabs.length; index++)
              AppSelectOption<int>(
                value: index,
                label: _labPhaseTabs[index].label,
                icon: Icons.science_outlined,
              ),
          ],
          onSelected: _select,
        ),
      ],
      body: _LabSectionsTab(
        key: ValueKey<String>(tab.queryValue),
        tab: tab,
        controller: _controllers[_selected],
      ),
    );
  }
}

class _LabSectionsTab extends StatelessWidget {
  const _LabSectionsTab({
    super.key,
    required this.tab,
    required this.controller,
  });

  final _LabPhaseTab tab;
  final SectionLoadController<String> controller;

  @override
  Widget build(BuildContext context) {
    return SectionLoadView<String>(
      controller: controller,
      errorTitle: 'Could not load ${tab.label} lab sections.',
      label: 'Related Lab Sections',
      emptyMessage: 'No related lab sections found for ${tab.label}.',
    );
  }
}
