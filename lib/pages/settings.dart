import 'package:flutter/material.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/home_card_preferences.dart';
import 'package:preconnect/tools/refresh_bus.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isLoading = true;
  bool _showQuickAccessSection = true;
  bool _showRamadanCard = true;
  bool _showExamCountdownCard = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final visibility = await HomeCardPreferences.load();
    if (!mounted) return;
    setState(() {
      _showQuickAccessSection = visibility.showQuickAccessSection;
      _showRamadanCard = visibility.showRamadanCard;
      _showExamCountdownCard = visibility.showExamCountdownCard;
      _isLoading = false;
    });
  }

  Future<void> _setShowRamadanCard(bool value) async {
    setState(() {
      _showRamadanCard = value;
    });
    await HomeCardPreferences.setShowRamadanCard(value);
    RefreshBus.instance.notify(reason: 'home_card_settings_changed');
  }

  Future<void> _setShowExamCountdownCard(bool value) async {
    setState(() {
      _showExamCountdownCard = value;
    });
    await HomeCardPreferences.setShowExamCountdownCard(value);
    RefreshBus.instance.notify(reason: 'home_card_settings_changed');
  }

  Future<void> _setShowQuickAccessSection(bool value) async {
    setState(() {
      _showQuickAccessSection = value;
    });
    await HomeCardPreferences.setShowQuickAccessSection(value);
    RefreshBus.instance.notify(reason: 'home_card_settings_changed');
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Settings',
      subtitle: 'Customize',
      icon: Icons.settings_outlined,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (_isLoading)
              const BracuLoading(label: 'Loading settings...')
            else ...[
              const BracuSectionTitle(title: 'Card Visibility'),
              const SizedBox(height: 10),
              BracuCard(
                child: Column(
                  children: [
                    _ToggleRow(
                      title: 'Exam Countdown Card',
                      subtitle: 'Show upcoming exam countdown card',
                      value: _showExamCountdownCard,
                      onChanged: _setShowExamCountdownCard,
                    ),
                    Divider(
                      height: 12,
                      thickness: 1,
                      color: BracuPalette.textSecondary(context).withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark
                            ? 0.20
                            : 0.12,
                      ),
                    ),
                    _ToggleRow(
                      title: 'Ramadan Card',
                      subtitle: 'Show Ramadan countdown and prayer times',
                      value: _showRamadanCard,
                      onChanged: _setShowRamadanCard,
                    ),
                    Divider(
                      height: 12,
                      thickness: 1,
                      color: BracuPalette.textSecondary(context).withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark
                            ? 0.20
                            : 0.12,
                      ),
                    ),
                    _ToggleRow(
                      title: 'Quick Access Section',
                      subtitle: 'Show quick shortcuts section',
                      value: _showQuickAccessSection,
                      onChanged: _setShowQuickAccessSection,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: BracuPalette.textPrimary(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: BracuPalette.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: BracuPalette.primary,
        ),
      ],
    );
  }
}
