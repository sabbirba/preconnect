import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
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

class _LabSectionsPageState extends State<LabSectionsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final List<SectionLoadController<String>> _controllers;

  @override
  void initState() {
    super.initState();
    final loader = widget.loadSections ?? _loadLabSections;
    _controllers = <SectionLoadController<String>>[
      for (final tab in _labPhaseTabs)
        SectionLoadController<String>(key: tab.queryValue, loader: loader),
    ];
    _tabController = TabController(length: _labPhaseTabs.length, vsync: this)
      ..addListener(_loadSelectedTab);
    unawaited(_controllers.first.load());
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_loadSelectedTab)
      ..dispose();
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _loadSelectedTab() {
    final controller = _controllers[_tabController.index];
    if (!controller.isLoaded) unawaited(controller.load());
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Lab Sections',
      subtitle: 'Advising',
      icon: Icons.science_outlined,
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: BracuPalette.primary,
            unselectedLabelColor: BracuPalette.textSecondary(context),
            tabs: [for (final tab in _labPhaseTabs) Tab(text: tab.label)],
          ),
          const Gap(12),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                for (var index = 0; index < _labPhaseTabs.length; index++)
                  _LabSectionsTab(
                    tab: _labPhaseTabs[index],
                    controller: _controllers[index],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LabSectionsTab extends StatelessWidget {
  const _LabSectionsTab({required this.tab, required this.controller});

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
