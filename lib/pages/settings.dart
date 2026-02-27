import 'package:flutter/material.dart';
import 'package:preconnect/pages/campus_wifi_login.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_lock_service.dart';
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
  bool _showExamCountdownDaysOnly = false;
  bool _showTodaySchedule = true;
  bool _showStudentContactCards = true;
  bool _appLockEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final visibility = await HomeCardPreferences.load();
    final appLockEnabled = await AppLockService().isEnabled();
    if (!mounted) return;
    setState(() {
      _showQuickAccessSection = visibility.showQuickAccessSection;
      _showRamadanCard = visibility.showRamadanCard;
      _showExamCountdownCard = visibility.showExamCountdownCard;
      _showExamCountdownDaysOnly = visibility.showExamCountdownDaysOnly;
      _showTodaySchedule = visibility.showTodaySchedule;
      _showStudentContactCards = visibility.showStudentContactCards;
      _appLockEnabled = appLockEnabled;
      _isLoading = false;
    });
  }

  Future<void> _setShowRamadanCard(bool value) async {
    await _setVisibility(
      label: 'Ramadan & Prayer Times',
      value: value,
      applyLocal: () => _showRamadanCard = value,
      persist: HomeCardPreferences.setShowRamadanCard,
    );
  }

  Future<void> _setShowExamCountdownCard(bool value) async {
    await _setVisibility(
      label: 'Exam Countdown',
      value: value,
      applyLocal: () => _showExamCountdownCard = value,
      persist: HomeCardPreferences.setShowExamCountdownCard,
    );
  }

  Future<void> _setShowQuickAccessSection(bool value) async {
    await _setVisibility(
      label: 'Quick Access',
      value: value,
      applyLocal: () => _showQuickAccessSection = value,
      persist: HomeCardPreferences.setShowQuickAccessSection,
    );
  }

  Future<void> _setShowExamCountdownDaysOnly(bool value) async {
    await _setVisibility(
      label: 'Exam Days Only',
      value: value,
      applyLocal: () => _showExamCountdownDaysOnly = value,
      persist: HomeCardPreferences.setShowExamCountdownDaysOnly,
    );
  }

  Future<void> _setShowTodaySchedule(bool value) async {
    await _setVisibility(
      label: 'Today\'s Schedule',
      value: value,
      applyLocal: () => _showTodaySchedule = value,
      persist: HomeCardPreferences.setShowTodaySchedule,
    );
  }

  Future<void> _setShowStudentContactCards(bool value) async {
    await _setVisibility(
      label: 'Student Info',
      value: value,
      applyLocal: () => _showStudentContactCards = value,
      persist: HomeCardPreferences.setShowStudentContactCards,
    );
  }

  Future<void> _setVisibility({
    required String label,
    required bool value,
    required void Function() applyLocal,
    required Future<void> Function(bool) persist,
  }) async {
    setState(() {
      applyLocal();
    });
    await persist(value);
    RefreshBus.instance.notify(reason: 'home_card_settings_changed');
    if (!mounted) return;
    showAppSnackBar(context, '$label ${value ? 'enabled' : 'disabled'}');
  }

  Future<void> _setAppLockEnabled(bool value) async {
    if (value) {
      final confirmed = await AppLockService().authenticate(
        reason: 'Confirm to enable app lock',
      );
      if (!confirmed) {
        if (!mounted) return;
        showAppSnackBar(context, 'Verification failed. App lock not enabled');
        return;
      }
    }
    await AppLockService().setEnabled(value);
    if (!mounted) return;
    setState(() {
      _appLockEnabled = value;
    });
    RefreshBus.instance.notify(reason: 'app_lock_settings_changed');
    showAppSnackBar(context, value ? 'App lock enabled' : 'App lock disabled');
  }

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Settings',
      subtitle: 'Customize',
      icon: Icons.settings_outlined,
      body: BracuRefreshList(
        onRefresh: _load,
        children: [
          if (_isLoading)
            const BracuLoading(label: 'Loading settings...')
          else ...[
            const BracuSectionTitle(title: 'Visibility'),
            const SizedBox(height: 10),
            BracuCard(
              child: Column(
                children: [
                  _ToggleRow(
                    title: 'Exam Countdown',
                    subtitle: 'Show upcoming exam countdown',
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
                    title: 'Exam Days Only',
                    subtitle: 'Show only days in countdown',
                    value: _showExamCountdownDaysOnly,
                    onChanged: _showExamCountdownCard
                        ? _setShowExamCountdownDaysOnly
                        : null,
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
                    title: 'Ramadan & Prayer Times',
                    subtitle: 'Show Ramadan and prayer times',
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
                    title: 'Today\'s Schedule',
                    subtitle: 'Show today heading and class list',
                    value: _showTodaySchedule,
                    onChanged: _setShowTodaySchedule,
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
                    title: 'Student Info',
                    subtitle: 'Show student info and phone number',
                    value: _showStudentContactCards,
                    onChanged: _setShowStudentContactCards,
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
                    title: 'Quick Access',
                    subtitle: 'Show quick shortcuts section',
                    value: _showQuickAccessSection,
                    onChanged: _setShowQuickAccessSection,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const BracuSectionTitle(title: 'Security'),
            const SizedBox(height: 10),
            BracuCard(
              child: _ToggleRow(
                title: 'App Lock',
                subtitle: 'Use system authentication to lock the app',
                value: _appLockEnabled,
                onChanged: _setAppLockEnabled,
              ),
            ),
            const SizedBox(height: 10),
            const BracuSectionTitle(title: 'Campus Wi-Fi'),
            const SizedBox(height: 6),
            BracuCard(
              child: ListTile(
                dense: true,
                minVerticalPadding: 0,
                horizontalTitleGap: 10,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 2,
                  vertical: 0,
                ),
                visualDensity: const VisualDensity(
                  vertical: -3,
                  horizontal: -2,
                ),
                leading: const Icon(Icons.wifi_rounded, size: 20),
                title: Text(
                  'Wi-Fi Login Assistant',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: BracuPalette.textPrimary(context),
                  ),
                ),
                subtitle: Text(
                  'Credentials for one-tap captive login',
                  style: TextStyle(
                    fontSize: 11,
                    color: BracuPalette.textSecondary(context),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () {
                  showAppSnackBar(context, 'Opening Wi-Fi Login Assistant');
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CampusWifiLoginPage(),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
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
  final ValueChanged<bool>? onChanged;

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
