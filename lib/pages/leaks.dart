import 'package:flutter/material.dart';
import 'package:preconnect/pages/ui_kit.dart';

class LeaksPage extends StatelessWidget {
  const LeaksPage({super.key});

  static const _sections = [
    (
      description: 'For CS / CSE / MAT courses',
      title: 'BRACULeaks',
      subtitle: 'Maintained by @reynep · work-in-progress',
      icon: Icons.menu_book_rounded,
      iconBg: null,
      iconColor: null,
      resourceUrl: 'https://github.com/braculeaks',
      maintainerHandle: '@reynep',
      maintainerUrl: 'https://github.com/reynep',
    ),
    (
      description: 'For course dumps & faculty analysis',
      title: 'Connect Dump Analyzer',
      subtitle: 'Maintained by @itzMRZ',
      icon: Icons.language_rounded,
      iconBg: Color(0xFFEEE9FD),
      iconColor: Color(0xFF534AB7),
      resourceUrl: 'https://connect-dumps.itzmrz.xyz',
      maintainerHandle: '@itzMRZ',
      maintainerUrl: 'https://github.com/itzMRZ',
    ),
    (
      description: 'For generic, open-source resources (dept. agnostic)',
      title: 'Sharminscloud BRACUResources',
      subtitle: 'Maintained by @Sharminscloud',
      icon: Icons.cloud_rounded,
      iconBg: Color(0xFFFEF0E6),
      iconColor: Color(0xFF993C1D),
      resourceUrl: 'https://github.com/Sharminscloud-BRACUResources',
      maintainerHandle: '@Sharminscloud',
      maintainerUrl: 'https://github.com/Sharminscloud-BRACUResources',
    ),
  ];

  static const _legacyRepos = [
    (label: 'iamraufu/BRACU', url: 'https://github.com/iamraufu/BRACU'),
    (
      label: 'badhon495/BRACU_Life',
      url: 'https://github.com/badhon495/BRACU_Life',
    ),
    (label: 'ShababAhmedd', url: 'https://github.com/ShababAhmedd'),
    (label: 'F3uR0n', url: 'https://github.com/F3uR0n'),
    (label: 'mazidzomader', url: 'https://github.com/mazidzomader'),
    (label: 'sabbirba/bracu', url: 'https://github.com/sabbirba/bracu'),
    (label: 'Sami-HC', url: 'https://github.com/Sami-HC'),
    (
      label: 'mebmrauf/CSE111',
      url: 'https://github.com/mebmrauf/CSE111-Programming-Language-II',
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
                    _LeakCard(
                      description: s.description,
                      title: s.title,
                      subtitle: s.subtitle,
                      icon: s.icon,
                      iconBg: s.iconBg,
                      iconColor: s.iconColor,
                      resourceUrl: s.resourceUrl,
                      maintainerHandle: s.maintainerHandle,
                      maintainerUrl: s.maintainerUrl,
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'LEGACY REPOS & PROFILES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: BracuPalette.textSecondary(context),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 10),
                _LegacyRepoGrid(repos: _legacyRepos),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LeakCard extends StatelessWidget {
  const _LeakCard({
    required this.description,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.resourceUrl,
    required this.maintainerHandle,
    required this.maintainerUrl,
    this.iconBg,
    this.iconColor,
  });

  final String description;
  final String title;
  final String subtitle;
  final IconData icon;
  final String resourceUrl;
  final String maintainerHandle;
  final String maintainerUrl;
  final Color? iconBg;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = colorScheme.outline.withValues(alpha: 0.18);
    final resolvedIconBg = iconBg ?? BracuPalette.textSecondary(context);
    final resolvedIconColor = iconColor ?? BracuPalette.textPrimary(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: BracuPalette.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: resolvedIconBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 18, color: resolvedIconColor),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: BracuPalette.textSecondary(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _OpenButton(
                      onTap: () => openExternalUrl(context, resourceUrl),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 0.5, color: borderColor),
          InkWell(
            onTap: () => openExternalUrl(context, maintainerUrl),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    Icons.code_rounded,
                    size: 14,
                    color: BracuPalette.textSecondary(context),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    maintainerHandle,
                    style: TextStyle(
                      fontSize: 12,
                      color: BracuPalette.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenButton extends StatelessWidget {
  const _OpenButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Open',
              style: TextStyle(
                fontSize: 13,
                color: BracuPalette.textSecondary(context),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.open_in_new_rounded,
              size: 13,
              color: BracuPalette.textSecondary(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegacyRepoGrid extends StatelessWidget {
  const _LegacyRepoGrid({required this.repos});

  final List<({String label, String url})> repos;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width < 400
            ? 1
            : width < 640
            ? 2
            : 3;

        return GridView.count(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: crossAxisCount == 1 ? 6.0 : 4.5,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: repos
              .map((r) => _LegacyRepoTile(label: r.label, url: r.url))
              .toList(),
        );
      },
    );
  }
}

class _LegacyRepoTile extends StatelessWidget {
  const _LegacyRepoTile({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openExternalUrl(context, url),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.code_rounded,
              size: 15,
              color: BracuPalette.textSecondary(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  overflow: TextOverflow.ellipsis,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
