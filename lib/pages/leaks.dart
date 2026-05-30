import 'package:flutter/material.dart';
import 'package:preconnect/pages/ui_kit.dart';

class LeaksPage extends StatelessWidget {
  const LeaksPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BracuPageScaffold(
      title: 'Material Leaks',
      icon: Icons.developer_mode_outlined,
      onHeaderTap: () => {},
      subtitle: 'Useful materials to apply during class.',
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _LeakSection(
                  description: 'For CS/CSE/MAT courses, you may use this:',
                  title: 'BRACULeaks',
                  subtitle: 'Maintained by @reynep (work-in-progress)',
                  icon: Icons.import_contacts,
                  resourceUrl: 'https://github.com/braculeaks',
                  maintainerUrl: 'https://github.com/reynep',
                ),
                const SizedBox(height: 25),
                _LeakSection(
                  description:
                      'For course dumps, potential faculty analysis and more, use this:',
                  title: 'Connect Dump Analyzer',
                  subtitle: 'Maintained by @itzMRZ',
                  icon: Icons.web,
                  iconColor: const Color(0xFF4822E3),
                  resourceUrl: 'https://connect-dumps.itzmrz.xyz',
                  maintainerUrl: 'https://github.com/itzMRZ',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LeakSection extends StatelessWidget {
  const _LeakSection({
    required this.description,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.resourceUrl,
    required this.maintainerUrl,
    this.iconColor,
  });

  final String description;
  final String title;
  final String subtitle;
  final IconData icon;
  final String resourceUrl;
  final String maintainerUrl;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final textSecondaryStyle = TextStyle(
      color: BracuPalette.textSecondary(context),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(description, style: textSecondaryStyle),
        const SizedBox(height: 12),
        BracuActionBannerCard(
          title: title,
          subtitle: subtitle,
          icon: icon,
          iconColor: iconColor ?? BracuPalette.primary,
          onTap: () => openExternalUrl(context, resourceUrl),
        ),
        _MaintainerGitHub(url: maintainerUrl),
      ],
    );
  }
}

class _MaintainerGitHub extends StatelessWidget {
  const _MaintainerGitHub({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 10),
      child: InkWell(
        onTap: () => openExternalUrl(context, url),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.code_rounded, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Maintainer Handle',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
