import 'package:flutter/material.dart';
import 'package:preconnect/pages/ui_kit.dart';

class SettingTile extends StatelessWidget {
  const SettingTile({
    super.key,
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
    final textSecondary = BracuPalette.textSecondary(context);
    return SwitchListTile.adaptive(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(color: textSecondary)),
      value: value,
      onChanged: onChanged,
    );
  }
}
