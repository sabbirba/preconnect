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
  late Future<List<_ContributorProfile>> _contributorsFuture;
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

  Future<List<_ContributorProfile>> _loadContributors() async {
    final uri = Uri.parse('$_contributorsApiUrl/contributors');
    final response = await http.get(uri, headers: _githubHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Unable to load contributors');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const <_ContributorProfile>[];
    final contributors = decoded
        .whereType<Map>()
        .map((raw) => _ContributorProfile.fromGitHubContributor(raw.cast()))
        .where((item) => item.name.isNotEmpty && item.avatarUrl.isNotEmpty)
        .where((item) => !item.key.endsWith('[bot]'))
        .toList();
    final withPinned = _dedupeContributors([
      ...contributors,
      ..._pinnedGitHubContributors,
    ]);
    return Future.wait(withPinned.map(_loadGitHubProfile));
  }

  Future<_ContributorProfile> _loadGitHubProfile(
    _ContributorProfile contributor,
  ) async {
    final login = contributor.githubLogin;
    if (login.isEmpty) return contributor;
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/users/$login'),
        headers: _githubHeaders,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return contributor;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return contributor;
      return contributor.withGitHubProfile(decoded.cast());
    } catch (_) {
      return contributor;
    }
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
              const _IntroCard(),
              const SizedBox(height: 14),
              const BracuSectionTitle(title: 'Contributors'),
              const SizedBox(height: 10),
              FutureBuilder<List<_ContributorProfile>>(
                future: _contributorsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: BracuSkeletonGrid(
                        itemCount: 6,
                        crossAxisCount: 3,
                        itemHeight: 72,
                      ),
                    );
                  }
                  final contributors =
                      snapshot.data ?? const <_ContributorProfile>[];
                  return _ContributorsGrid(
                    contributors: contributors,
                    showAll: _showAllContributors,
                    onToggle: () => setState(
                      () => _showAllContributors = !_showAllContributors,
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              const BracuSectionTitle(title: 'Funding & Support'),
              const SizedBox(height: 10),
              const _FundingCard(),
            ],
          ),
        );
      },
    );
  }
}

const _repoUrl = 'https://github.com/sabbirba/preconnect';
const _contributorsApiUrl = 'https://api.github.com/repos/sabbirba/preconnect';
const _collapsedContributorCount = 6;
const _githubHeaders = <String, String>{
  'Accept': 'application/vnd.github+json',
};

const _pinnedGitHubContributors = <_ContributorProfile>[
  _ContributorProfile.github(
    handle: 'NaiveInvestigator',
    role: 'Lead Developer',
  ),
  _ContributorProfile.github(handle: 'sabbirba', role: 'Developer & UI/UX'),
];

const _manualContributors = <_ContributorProfile>[
  _ContributorProfile(
    name: 'Mueen Ahmmed',
    handle: 'mueen-ahmmed',
    role: 'Faculty Reviews',
    avatarUrl:
        'https://media.licdn.com/dms/image/v2/D5603AQHtYo7APsdwwQ/profile-displayphoto-shrink_800_800/B56ZcH6GpoH4Ag-/0/1748184362516?e=1776902400&v=beta&t=lAxMqND2jjkT4ybK2z9zvePqMtMkCr3zEcZ4w_vfxDw',
    linkLabel: 'LinkedIn',
    url: 'https://www.linkedin.com/in/mueen-ahmmed-b337b8231/',
  ),
];

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    return BracuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PreConnect App Runs by Students',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
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
          const _RepoButton(),
        ],
      ),
    );
  }
}

class _RepoButton extends StatelessWidget {
  const _RepoButton();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openExternalUrl(context, _repoUrl),
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
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: BracuPalette.primary.withValues(alpha: 0.12),
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
              color: BracuPalette.primary.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContributorsGrid extends StatelessWidget {
  const _ContributorsGrid({
    required this.contributors,
    required this.showAll,
    required this.onToggle,
  });

  final List<_ContributorProfile> contributors;
  final bool showAll;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final all = _orderContributors(
      _dedupeContributors([...contributors, ..._manualContributors]),
    );
    final visible = showAll ? all : all.take(_collapsedContributorCount);
    return Column(
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 1.0,
          children: [
            for (final contributor in visible)
              _DevGridTile(contributor: contributor),
          ],
        ),
        if (all.length > _collapsedContributorCount)
          buildCenteredOutlinedActionButton(
            label: showAll ? 'Show Less' : 'Show More',
            onPressed: onToggle,
            padding: const EdgeInsets.only(top: 6),
          ),
      ],
    );
  }
}

class _FundingCard extends StatelessWidget {
  const _FundingCard();

  @override
  Widget build(BuildContext context) {
    return BracuCard(
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
            style: TextStyle(color: BracuPalette.textSecondary(context)),
          ),
          const SizedBox(height: 12),
          const BracuFundingSupportContent(),
        ],
      ),
    );
  }
}

List<_ContributorProfile> _dedupeContributors(List<_ContributorProfile> items) {
  final seen = <String>{};
  final output = <_ContributorProfile>[];
  for (final item in items) {
    if (seen.add(item.identity)) output.add(item);
  }
  return output;
}

List<_ContributorProfile> _orderContributors(List<_ContributorProfile> items) {
  final naive = _findByHandle(items, 'naiveinvestigator', 'naivelnvestigator');
  final sabbir = _findByHandle(items, 'sabbirba');
  final mueen = _findByHandle(items, 'mueen-ahmmed');
  final reserved = <_ContributorProfile>{?naive, ?sabbir, ?mueen};
  final others = items.where((item) => !reserved.contains(item)).toList();
  final ordered = <_ContributorProfile>[?naive, ?sabbir];

  for (final item in others) {
    if (ordered.length >= 4) break;
    ordered.add(item);
  }
  if (mueen != null) ordered.add(mueen);
  for (final item in others) {
    if (!ordered.contains(item)) ordered.add(item);
  }
  return ordered;
}

_ContributorProfile? _findByHandle(
  List<_ContributorProfile> items,
  String primary, [
  String? alternate,
]) {
  for (final item in items) {
    if (item.matchesHandle(primary) ||
        (alternate != null && item.matchesHandle(alternate))) {
      return item;
    }
  }
  return null;
}

class _DevGridTile extends StatelessWidget {
  const _DevGridTile({required this.contributor});

  final _ContributorProfile contributor;

  Widget _avatarPlaceholder(BuildContext context) {
    final initial = contributor.name.trim().isNotEmpty
        ? contributor.name.trim().substring(0, 1).toUpperCase()
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
    return InkWell(
      onTap: () => openExternalUrl(context, contributor.url),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: ClipOval(
                child: CachedImage(
                  url: contributor.avatarUrl,
                  fit: BoxFit.cover,
                  placeholder: const BracuShimmer(
                    child: BracuSkeletonBox(width: 40, height: 40, radius: 20),
                  ),
                  error: _avatarPlaceholder(context),
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  contributor.name,
                  maxLines: 1,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 1),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  contributor.role,
                  maxLines: 1,
                  style: TextStyle(color: textSecondary, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: _LinkChip(
                label: contributor.linkLabel,
                onTap: () => openExternalUrl(context, contributor.url),
              ),
            ),
          ],
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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

class _ContributorProfile {
  const _ContributorProfile({
    required this.handle,
    required this.name,
    required this.role,
    required this.avatarUrl,
    required this.linkLabel,
    required this.url,
  });

  const _ContributorProfile.github({
    required this.handle,
    required this.role,
    String? name,
    String? avatarUrl,
    String? url,
  }) : name = name ?? handle,
       avatarUrl = avatarUrl ?? 'https://github.com/$handle.png',
       linkLabel = 'GitHub',
       url = url ?? 'https://github.com/$handle';

  final String handle;
  final String name;
  final String role;
  final String avatarUrl;
  final String linkLabel;
  final String url;

  String get key => handle.trim().toLowerCase();

  String get githubLogin {
    if (key.isNotEmpty) return handle.trim();
    final uri = Uri.tryParse(url);
    final isGitHub = uri?.host.toLowerCase().contains('github.com') ?? false;
    if (!isGitHub || uri!.pathSegments.isEmpty) return '';
    return uri.pathSegments.first;
  }

  String get identity {
    final normalizedUrl = url.trim().toLowerCase().replaceFirst(
      RegExp(r'/$'),
      '',
    );
    return normalizedUrl.isEmpty ? key : normalizedUrl;
  }

  bool matchesHandle(String value) => key == value.trim().toLowerCase();

  _ContributorProfile withGitHubProfile(Map<String, dynamic> json) {
    final displayName = '${json['name'] ?? ''}'.trim();
    final profileAvatarUrl = '${json['avatar_url'] ?? ''}'.trim();
    final profileUrl = '${json['html_url'] ?? ''}'.trim();
    return _ContributorProfile(
      handle: handle,
      name: displayName.isEmpty ? name : displayName,
      role: role,
      avatarUrl: profileAvatarUrl.isEmpty ? avatarUrl : profileAvatarUrl,
      linkLabel: linkLabel,
      url: profileUrl.isEmpty ? url : profileUrl,
    );
  }

  factory _ContributorProfile.fromGitHubContributor(Map<String, dynamic> json) {
    final login = '${json['login'] ?? ''}'.trim();
    return _ContributorProfile.github(
      handle: login,
      name: login,
      role: _githubRole(login),
      avatarUrl: '${json['avatar_url'] ?? ''}'.trim(),
      url: '${json['html_url'] ?? ''}'.trim(),
    );
  }
}

String _githubRole(String login) {
  return switch (login.trim().toLowerCase()) {
    'naiveinvestigator' || 'naivelnvestigator' => 'Lead Developer',
    'sabbirba' => 'Developer & UI/UX',
    _ => 'Contributor',
  };
}
