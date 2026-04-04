import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:preconnect/pages/api_test.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/cached_image.dart';

class DevsPage extends StatefulWidget {
  const DevsPage({super.key});

  @override
  State<DevsPage> createState() => _DevsPageState();
}

class _DevsPageState extends State<DevsPage> {
  late Future<String> _subtitleFuture;
  late Future<List<_GitHubContributor>> _contributorsFuture;
  int _secretTapCount = 0;
  bool _showAllContributors = false;

  @override
  void initState() {
    super.initState();
    _subtitleFuture = _buildVersionSubtitle();
    _contributorsFuture = _loadContributors();
  }

  Future<String> _buildVersionSubtitle() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      final build = info.buildNumber.trim();
      if (version.isEmpty && build.isEmpty) return 'App Version';
      if (build.isEmpty) return 'v$version';
      return 'v$version ($build)';
    } catch (_) {
      return 'App Version';
    }
  }

  Future<List<_GitHubContributor>> _loadContributors() async {
    final uri = Uri.parse(
      'https://api.github.com/repos/sabbirba/preconnect/contributors?per_page=100',
    );
    final response = await http.get(
      uri,
      headers: const <String, String>{'Accept': 'application/vnd.github+json'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Unable to load contributors');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const <_GitHubContributor>[];
    final contributors = decoded
        .whereType<Map>()
        .map((raw) => _GitHubContributor.fromJson(raw.cast<String, dynamic>()))
        .where((item) => item.login.isNotEmpty && item.avatarUrl.isNotEmpty)
        .where((item) => !item.login.toLowerCase().endsWith('[bot]'))
        .where(
          (item) =>
              item.login.toLowerCase() != 'naiveinvestigator' &&
              item.login.toLowerCase() != 'sabbirba',
        )
        .toList();
    return contributors;
  }

  Future<void> _onHeaderSecretTap() async {
    _secretTapCount += 1;
    if (_secretTapCount < 10) return;
    _secretTapCount = 0;
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ApiTestPage()));
  }

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    return FutureBuilder<String>(
      future: _subtitleFuture,
      builder: (context, snapshot) {
        final subtitle = snapshot.data ?? 'App Version';
        return BracuPageScaffold(
          title: 'Devs & Support',
          subtitle: subtitle,
          icon: Icons.developer_mode_outlined,
          onHeaderTap: _onHeaderSecretTap,
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
            children: [
              BracuCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PreConnect App Runs by Students',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const SizedBox(height: 10),
                    Text(
                      'Community driven and free for every student.',
                      style: TextStyle(color: textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Bug reports, feature requests, and ideas are welcome. '
                      'Please create issues in our GitHub repo.',
                      style: TextStyle(color: textSecondary),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => _openRepo(context),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: BracuPalette.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: BracuPalette.primary.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: BracuPalette.primary.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.open_in_new,
                                size: 16,
                                color: BracuPalette.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'View Repository',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: BracuPalette.primary,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 14,
                              color: BracuPalette.primary.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const BracuSectionTitle(title: 'Core Team'),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.85,
                children: const [
                  _DevGridTile(
                    name: 'NaiveInvestigator',
                    role: 'Lead Developer',
                    avatarUrl: 'https://github.com/NaiveInvestigator.png',
                    primaryLabel: 'GitHub',
                    primaryUrl: 'https://github.com/NaiveInvestigator',
                  ),
                  _DevGridTile(
                    name: 'Sabbir Bin Abbas',
                    role: 'Developer & UI/UX',
                    avatarUrl: 'https://github.com/sabbirba.png',
                    primaryLabel: 'GitHub',
                    primaryUrl: 'https://github.com/sabbirba',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const BracuSectionTitle(title: 'Contributors'),
              const SizedBox(height: 10),
              FutureBuilder<List<_GitHubContributor>>(
                future: _contributorsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: BracuLoading(label: 'Loading...'),
                    );
                  }
                  final contributors =
                      snapshot.data ?? const <_GitHubContributor>[];
                  final manualTiles = const <_DevGridTile>[
                    _DevGridTile(
                      name: 'Mueen Ahmmed',
                      role: 'Faculty Reviews',
                      avatarUrl:
                          'https://media.licdn.com/dms/image/v2/D5603AQHtYo7APsdwwQ/profile-displayphoto-shrink_800_800/B56ZcH6GpoH4Ag-/0/1748184362516?e=1776902400&v=beta&t=lAxMqND2jjkT4ybK2z9zvePqMtMkCr3zEcZ4w_vfxDw',
                      primaryLabel: 'LinkedIn',
                      primaryUrl:
                          'https://www.linkedin.com/in/mueen-ahmmed-b337b8231/',
                      keepVisibleInCollapsed: true,
                    ),
                  ];
                  final autoTiles = contributors
                      .map(
                        (item) => _DevGridTile(
                          name: item.login,
                          role: 'Contributor',
                          avatarUrl: item.avatarUrl,
                          primaryLabel: 'GitHub',
                          primaryUrl: item.htmlUrl,
                        ),
                      )
                      .toList();
                  final allTiles = _dedupeContributorTiles(<_DevGridTile>[
                    ...autoTiles,
                    ...manualTiles,
                  ]);
                  if (allTiles.isEmpty) {
                    return BracuCard(
                      child: Text(
                        'Contributor list not available right now.',
                        style: TextStyle(color: textSecondary),
                      ),
                    );
                  }
                  final visibleTiles = _visibleContributorTiles(
                    allTiles,
                    showAll: _showAllContributors,
                    collapsedCount: 4,
                  );
                  return Column(
                    children: [
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.85,
                        children: visibleTiles,
                      ),
                      if (allTiles.length > 4)
                        buildCenteredOutlinedActionButton(
                          label: _showAllContributors
                              ? 'Show Less'
                              : 'Show More',
                          onPressed: () {
                            setState(() {
                              _showAllContributors = !_showAllContributors;
                            });
                          },
                          padding: const EdgeInsets.only(top: 6),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              const BracuSectionTitle(title: 'Funding & Support'),
              const SizedBox(height: 10),
              BracuCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'iOS Funding',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'App Store publishing needs the \$99/year Apple Developer '
                      'membership. Any contribution towards this funding will be highly appreciated.',
                      style: TextStyle(color: textSecondary),
                    ),
                    const SizedBox(height: 12),
                    const BracuFundingSupportContent(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

List<_DevGridTile> _dedupeContributorTiles(List<_DevGridTile> tiles) {
  final seen = <String>{};
  final output = <_DevGridTile>[];
  for (final tile in tiles) {
    final key =
        '${tile.name.trim().toLowerCase()}|'
        '${tile.primaryUrl.trim().toLowerCase()}';
    if (seen.add(key)) {
      output.add(tile);
    }
  }
  return output;
}

List<_DevGridTile> _visibleContributorTiles(
  List<_DevGridTile> all, {
  required bool showAll,
  int collapsedCount = 4,
}) {
  if (showAll || all.length <= collapsedCount) return all;
  final pinned = all
      .where((tile) => tile.keepVisibleInCollapsed)
      .take(collapsedCount)
      .toList();
  final visible = <_DevGridTile>[...pinned];
  for (final tile in all) {
    if (visible.length >= collapsedCount) break;
    if (visible.contains(tile)) continue;
    visible.add(tile);
  }
  return visible;
}

class _DevGridTile extends StatelessWidget {
  const _DevGridTile({
    required this.name,
    required this.role,
    required this.avatarUrl,
    required this.primaryLabel,
    required this.primaryUrl,
    this.keepVisibleInCollapsed = false,
  });

  final String name;
  final String role;
  final String avatarUrl;
  final String primaryLabel;
  final String primaryUrl;
  final bool keepVisibleInCollapsed;

  Future<void> _openUrl(BuildContext context, String rawUrl) async {
    await openExternalUrl(context, rawUrl);
  }

  Widget _avatarPlaceholder(BuildContext context) {
    final initial = name.trim().isNotEmpty
        ? name.trim().substring(0, 1).toUpperCase()
        : '?';
    return Container(
      color: BracuPalette.primary.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Text(initial, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    return BracuCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          InkWell(
            onTap: () => _openUrl(context, primaryUrl),
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              width: 44,
              height: 44,
              child: ClipOval(
                child: CachedImage(
                  url: avatarUrl,
                  fit: BoxFit.cover,
                  placeholder: _avatarPlaceholder(context),
                  error: _avatarPlaceholder(context),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            role,
            style: TextStyle(color: textSecondary, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              _LinkChip(
                label: primaryLabel,
                onTap: () => _openUrl(context, primaryUrl),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: BracuPalette.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: BracuPalette.primary,
          ),
        ),
      ),
    );
  }
}

Future<void> _openRepo(BuildContext context) async {
  await openExternalUrl(context, 'https://github.com/sabbirba/preconnect');
}

class _GitHubContributor {
  const _GitHubContributor({
    required this.login,
    required this.avatarUrl,
    required this.htmlUrl,
  });

  final String login;
  final String avatarUrl;
  final String htmlUrl;

  factory _GitHubContributor.fromJson(Map<String, dynamic> json) {
    return _GitHubContributor(
      login: '${json['login'] ?? ''}'.trim(),
      avatarUrl: '${json['avatar_url'] ?? ''}'.trim(),
      htmlUrl: '${json['html_url'] ?? ''}'.trim(),
    );
  }
}
