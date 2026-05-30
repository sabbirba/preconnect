import 'package:flutter/material.dart';
import 'package:preconnect/pages/ui_kit.dart';

class LeaksPage extends StatelessWidget {
  const LeaksPage({super.key});

  static const _sections = [
    (
      description: 'For CS/CSE/MAT courses, you may use this:',
      title: 'BRACULeaks',
      subtitle: 'Maintained by @reynep (work-in-progress)',
      icon: Icons.import_contacts,
      iconColor: null,
      resourceUrl: 'https://github.com/braculeaks',
      maintainerUrl: 'https://github.com/reynep',
    ),
    (
      description:
          'For course dumps, potential faculty analysis and more, use this:',
      title: 'Connect Dump Analyzer',
      subtitle: 'Maintained by @itzMRZ',
      icon: Icons.web,
      iconColor: Color(0xFF4822E3),
      resourceUrl: 'https://connect-dumps.itzmrz.xyz',
      maintainerUrl: 'https://github.com/itzMRZ',
    ),
    (
      description: 'For generic, open-source resources (dept. agnostic):',
      title: 'Sharminscloud-BRACUResources',
      subtitle: 'Maintained by @Sharminscloud',
      icon: Icons.cloud,
      iconColor: Color(0xFFF26822),
      resourceUrl: 'https://github.com/Sharminscloud-BRACUResources',
      maintainerUrl: 'https://github.com/Sharminscloud-BRACUResources',
    ),
  ];

  static const _legacyRepos = [
    (label: 'iamraufu/BRACU', url: 'https://github.com/iamraufu/BRACU'),
    (
      label: 'badhon495/BRACU_Life',
      url: 'https://github.com/badhon495/BRACU_Life',
    ),
  ];

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
                ..._sections.expand(
                  (s) => [
                    _LeakSection(
                      description: s.description,
                      title: s.title,
                      subtitle: s.subtitle,
                      icon: s.icon,
                      iconColor: s.iconColor,
                      resourceUrl: s.resourceUrl,
                      maintainerUrl: s.maintainerUrl,
                    ),
                    const SizedBox(height: 15),
                  ],
                ),
                const SizedBox(height: 10),
                const BracuSectionTitle(title: 'Legacy Repositories'),
                const SizedBox(height: 12),
                ..._legacyRepos.map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: _LegacyRepoLink(label: r.label, url: r.url),
                  ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          description,
          style: TextStyle(color: BracuPalette.textSecondary(context)),
        ),
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
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.code_rounded, size: 18),
              SizedBox(width: 8),
              Text(
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

class _LegacyRepoLink extends StatelessWidget {
  const _LegacyRepoLink({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openExternalUrl(context, url),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: BracuPalette.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: BracuPalette.primary.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.bookmark, color: BracuPalette.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: BracuPalette.primary,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: BracuPalette.primary.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}
