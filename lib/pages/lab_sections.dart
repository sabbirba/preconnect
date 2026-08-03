import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:preconnect/api/schedule.dart';
import 'package:preconnect/model/advising_phase.dart';
import 'package:preconnect/model/section_info.dart';
import 'package:preconnect/pages/ui_kit.dart';

class _LabPhaseTab {
  const _LabPhaseTab({required this.label, required this.queryValue});

  final String label;
  final String queryValue;
}

final List<_LabPhaseTab> _labPhaseTabs = [
  for (final phase in AdvisingPhase.values)
    _LabPhaseTab(label: phase.label, queryValue: phase.queryValue),
  const _LabPhaseTab(label: 'Wishlist', queryValue: 'WISH_LIST'),
];

class LabSectionsPage extends StatefulWidget {
  const LabSectionsPage({super.key});

  @override
  State<LabSectionsPage> createState() => _LabSectionsPageState();
}

class _LabSectionsPageState extends State<LabSectionsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final Map<int, bool> _isLoading = {
    for (var i = 0; i < _labPhaseTabs.length; i++) i: true,
  };
  final Map<int, String?> _errors = {
    for (var i = 0; i < _labPhaseTabs.length; i++) i: null,
  };
  final Map<int, List<Section>> _sections = {
    for (var i = 0; i < _labPhaseTabs.length; i++) i: const [],
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _labPhaseTabs.length, vsync: this);
    for (var i = 0; i < _labPhaseTabs.length; i++) {
      unawaited(_load(i));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load(int index) async {
    if (!mounted) return;
    setState(() {
      _isLoading[index] = true;
      _errors[index] = null;
    });
    try {
      final sections = await ScheduleService().fetchRelatedLabSections(
        _labPhaseTabs[index].queryValue,
      );
      if (!mounted) return;
      setState(() {
        _sections[index] = sections;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errors[index] = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading[index] = false;
        });
      }
    }
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
                for (var i = 0; i < _labPhaseTabs.length; i++)
                  _buildPhaseTab(context, i),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseTab(BuildContext context, int index) {
    final tab = _labPhaseTabs[index];
    final isLoading = _isLoading[index] ?? false;
    final error = _errors[index];
    final sections = _sections[index] ?? const <Section>[];

    if (isLoading && sections.isEmpty && error == null) {
      return const Center(child: BracuLoading());
    }

    if (error != null && sections.isEmpty) {
      return SectionsErrorState(
        title: 'Could not load ${tab.label} lab sections.',
        message: error,
        onRetry: () => _load(index),
      );
    }

    return BracuRefreshList(
      onRefresh: () => _load(index),
      children: [
        SectionListCard(
          label: 'Related Lab Sections',
          sections: sections,
          emptyMessage: 'No related lab sections found for ${tab.label}.',
        ),
      ],
    );
  }
}
