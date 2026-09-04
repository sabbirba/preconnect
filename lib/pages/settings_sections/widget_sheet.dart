import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/features/schedule/application/today_widget.dart';
import 'package:preconnect/pages/home.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/refresh_bus.dart';

class WidgetSetupSheet extends StatefulWidget {
  const WidgetSetupSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showBracuBottomSheet<void>(
      context,
      title: 'Home Screen Widget',
      initialChildSize: 0.72,
      builder: (sheetContext, textPrimary, textSecondary) {
        return const WidgetSetupSheet();
      },
    );
  }

  @override
  State<WidgetSetupSheet> createState() => _WidgetSetupSheetState();
}

class _WidgetSetupSheetState extends State<WidgetSetupSheet> {
  bool _isPinSupported = false;
  bool _isSyncing = false;
  TodayWidgetData? _widgetData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final supported = await TodayWidget.isPinWidgetSupported();
    var data = await TodayWidget.loadCurrent();
    if (data == null || (data.title.isEmpty && data.items.isEmpty)) {
      try {
        await syncTodayWidgetInBackground(
          Uri.parse('preconnect://refresh'),
          forceRefresh: true,
        );
        data = await TodayWidget.loadCurrent();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _isPinSupported = supported;
        _widgetData = data;
        _isLoading = false;
      });
    }
  }

  Future<void> _pinWidget() async {
    final success = await TodayWidget.requestPinWidget();
    if (!mounted) return;
    if (success) {
      showAppSnackBar(context, 'Home screen widget prompt opened.');
    } else {
      showAppSnackBar(
        context,
        'Automatic pinning not supported on this launcher.',
      );
    }
  }

  Future<void> _syncWidget() async {
    setState(() => _isSyncing = true);
    try {
      ApiClient().clearTransientCaches();
      await syncTodayWidgetInBackground(
        Uri.parse('preconnect://refresh'),
        forceRefresh: true,
      );
    } catch (_) {}
    RefreshBus.instance.notify(reason: 'cache_cleared');
    final data = await TodayWidget.loadCurrent();
    if (!mounted) return;
    setState(() {
      _widgetData = data;
      _isSyncing = false;
    });
    showAppSnackBar(context, 'Widget schedule synced.');
  }

  @override
  Widget build(BuildContext context) {
    final dragController = bracuBottomSheetScrollController(context);
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;

    return ListView(
      controller: dragController,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _buildPreviewCard(context, textPrimary, textSecondary),
        const Gap(16),
        if (isAndroid && _isPinSupported) ...[
          BracuActionButton(
            onPressed: _pinWidget,
            label: 'Add to Home Screen',
            icon: Icons.add_to_home_screen_rounded,
            outlined: false,
            backgroundColor: BracuPalette.primary,
            foregroundColor: Colors.white,
          ),
          const Gap(12),
        ],
        Row(
          children: [
            Expanded(
              child: BracuActionButton(
                onPressed: _isSyncing ? null : _syncWidget,
                isLoading: _isSyncing,
                label: 'Sync Widget Data',
                icon: Icons.sync_rounded,
                outlined: true,
              ),
            ),
          ],
        ),
        const Gap(16),
        Text(
          'How to Add Manually',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
        const Gap(10),
        if (isAndroid) ...[
          _buildInstructionStep(
            context,
            step: '1',
            title: 'Touch & Hold Home Screen',
            body: 'Long press any empty area on your home screen.',
          ),
          const Gap(10),
          _buildInstructionStep(
            context,
            step: '2',
            title: 'Select Widgets',
            body: 'Tap Widgets from the popup menu.',
          ),
          const Gap(10),
          _buildInstructionStep(
            context,
            step: '3',
            title: 'Choose PreConnect',
            body:
                'Scroll to PreConnect and drag Today\'s Schedule to your home screen.',
          ),
        ] else ...[
          _buildInstructionStep(
            context,
            step: '1',
            title: 'Touch & Hold Home Screen',
            body:
                'Long press an empty area on your home screen until apps jiggle.',
          ),
          const Gap(10),
          _buildInstructionStep(
            context,
            step: '2',
            title: 'Tap the (+) Plus Button',
            body: 'Tap the + button in the top corner of your screen.',
          ),
          const Gap(10),
          _buildInstructionStep(
            context,
            step: '3',
            title: 'Add PreConnect Widget',
            body:
                'Search for PreConnect, select your preferred size, and tap Add Widget.',
          ),
        ],
      ],
    );
  }

  Widget _buildPreviewCard(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
  ) {
    final now = DateTime.now();
    final title = _widgetData?.title.isNotEmpty == true
        ? _widgetData!.title
        : 'Today is ${DateFormat('EEEE').format(now)}';
    final dateText = _widgetData?.date.isNotEmpty == true
        ? _widgetData!.date
        : DateFormat('d MMMM, yyyy').format(now);
    final items = _widgetData?.items ?? const <TodayItem>[];
    const emptyStatus = BracuTodayScheduleStatus.noClasses();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Gap(8),
            if (dateText.isNotEmpty)
              Text(
                dateText,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const Gap(12),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: BracuSpinner(size: 22, strokeWidth: 2.4)),
          )
        else if (items.isEmpty)
          BracuScheduleTile(
            badge: emptyStatus.badge,
            title: emptyStatus.title,
            subtitle: emptyStatus.subtitle,
            color: BracuPalette.primary,
          )
        else
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Gap(12),
            BracuScheduleTile(
              badge: items[i].badge,
              title: items[i].title,
              subtitle: items[i].subtitle,
              trailing: items[i].trailing,
              trailingSub: items[i].trailingSub,
              color: BracuPalette.primary,
            ),
          ],
      ],
    );
  }

  Widget _buildInstructionStep(
    BuildContext context, {
    required String step,
    required String title,
    required String body,
  }) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: BracuPalette.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            step,
            style: const TextStyle(
              color: BracuPalette.primary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const Gap(10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Gap(2),
              Text(
                body,
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 11.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
