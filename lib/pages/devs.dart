import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/app_preferences_store.dart';
import 'package:preconnect/pages/api_test.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/build_info.dart';
import 'package:preconnect/tools/cached_image.dart';

class DevsPage extends StatefulWidget {
  const DevsPage({super.key});

  static Future<void> preload() async {
    await _DevsPageState.preloadData();
  }

  @override
  State<DevsPage> createState() => _DevsPageState();
}

class _DevsPageState extends State<DevsPage> {
  late Future<String> _subtitleFuture;
  List<_ContributorProfile> _contributors = const <_ContributorProfile>[];
  bool _contributorsLoading = false;
  int _secretTapCount = 0;
  bool _showAllContributors = false;
  static List<_ContributorProfile>? _cachedContributors;
  static Future<List<_ContributorProfile>>? _preloadFuture;

  @override
  void initState() {
    super.initState();
    _subtitleFuture = _buildVersionSubtitle();
    if (_cachedContributors != null) {
      _contributors = _cachedContributors!;
    }
    _loadContributors();
  }

  static Future<List<_ContributorProfile>> preloadData({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedContributors != null) {
      return _cachedContributors!;
    }
    if (!forceRefresh) {
      final inFlight = _preloadFuture;
      if (inFlight != null) {
        return inFlight;
      }
    }

    final future = _loadContributorsStatic(forceRefresh: forceRefresh);
    _preloadFuture = future;
    try {
      final contributors = await future;
      _cachedContributors = contributors;
      return contributors;
    } finally {
      if (identical(_preloadFuture, future)) {
        _preloadFuture = null;
      }
    }
  }

  Future<String> _buildVersionSubtitle() async {
    return BuildInfo.displayVersion();
  }

  Future<void> _loadContributors({bool forceRefresh = false}) async {
    if (_contributorsLoading) return;
    _contributorsLoading = true;
    try {
      final fresh = await preloadData(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _contributors = fresh;
      });
    } finally {
      _contributorsLoading = false;
    }
  }

  Future<void> _refreshContributors() async {
    await _loadContributors(forceRefresh: true);
  }

  static Future<List<_ContributorProfile>> _loadContributorsStatic({
    bool forceRefresh = false,
  }) async {
    try {
      if (!forceRefresh) {
        final cached = await _readCachedContributorsStatic();
        if (cached.isNotEmpty) {
          return _withPinnedAndManualContributorsStatic(cached);
        }
      }

      final uri = Uri.parse(
        'https://api.github.com/repos/sabbirba/preconnect/contributors',
      );
      final response = await http.get(
        uri,
        headers: <String, String>{
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          ...compressionHeaders(),
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _withPinnedAndManualContributorsStatic(
          const <_ContributorProfile>[],
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return _withPinnedAndManualContributorsStatic(
          const <_ContributorProfile>[],
        );
      }
      final contributors = decoded
          .whereType<Map>()
          .map((raw) {
            final contributor = _ContributorProfile.fromGitHubContributor(
              raw.cast<String, dynamic>(),
            );
            return contributor;
          })
          .where((item) => item.name.isNotEmpty && item.avatarUrl.isNotEmpty)
          .where((item) => !item.key.endsWith('[bot]'))
          .toList();
      final merged = _withPinnedAndManualContributorsStatic(contributors);
      if (contributors.isNotEmpty) {
        await AppPreferencesStore()
            .setJson(_contributorsCacheKey, <String, dynamic>{
              'ts': DateTime.now().millisecondsSinceEpoch,
              'items': contributors.map((item) => item.toJson()).toList(),
            });
      }
      return merged;
    } catch (_) {
      return _withPinnedAndManualContributorsStatic(
        const <_ContributorProfile>[],
      );
    }
  }

  static Future<List<_ContributorProfile>>
  _readCachedContributorsStatic() async {
    final raw = await AppPreferencesStore().getJsonMap(_contributorsCacheKey);
    if (raw == null) return const <_ContributorProfile>[];
    final items = raw['items'];
    if (items is! List || items.isEmpty) {
      return const <_ContributorProfile>[];
    }
    return items
        .whereType<Map>()
        .map((entry) => _ContributorProfile.fromJson(entry.cast()))
        .where((item) => item.name.isNotEmpty && item.avatarUrl.isNotEmpty)
        .toList();
  }

  static List<_ContributorProfile> _withPinnedAndManualContributorsStatic(
    List<_ContributorProfile> items,
  ) {
    return _dedupeContributors([
      ..._pinnedGitHubContributors,
      ..._manualContributors,
      ...items,
    ]);
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
          body: RefreshIndicator(
            onRefresh: _refreshContributors,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const _IntroCard(),
                const SizedBox(height: 14),
                const BracuSectionTitle(title: 'People Behind It'),
                const SizedBox(height: 10),
                if (_contributors.isEmpty && _contributorsLoading)
                  const BracuLoading()
                else
                  _ContributorsGrid(
                    contributors: _contributors,
                    showAll: _showAllContributors,
                    onToggle: () => setState(
                      () => _showAllContributors = !_showAllContributors,
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.only(top: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BracuSectionTitle(title: 'Sponsored'),
                      SizedBox(height: 10),
                      _SponsoredStrip(),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const BracuSectionTitle(title: 'Funding & Support'),
                const SizedBox(height: 10),
                const _FundingCard(),
              ],
            ),
          ),
        );
      },
    );
  }
}

const _contributorsCacheKey = 'devs_contributors_v1';
const _collapsedContributorCount = 6;

const _pinnedGitHubContributors = <_ContributorProfile>[
  _ContributorProfile.github(
    handle: 'NaiveInvestigator',
    role: 'Lead Developer',
  ),
  _ContributorProfile.github(
    handle: 'sabbirba',
    name: 'Sabbir Bin Abbas',
    role: 'Developer & UI/UX',
  ),
];

const _manualContributors = <_ContributorProfile>[
  _ContributorProfile(
    name: 'Mueen Ahmmed',
    handle: 'mueen-ahmmed',
    role: 'Faculty Reviews',
    avatarUrl: 'https://preconnect.app/Mueen-Ahmmed.jpeg',
    linkLabel: 'LinkedIn',
    url: 'https://www.linkedin.com/in/mueen-ahmmed-b337b8231/',
  ),
  _ContributorProfile.github(
    handle: 'Zamiul-rashid',
    name: 'Zamiul-rashid',
    role: 'Friends Schedule',
  ),
  _ContributorProfile(
    name: 'Shakil Ahmed',
    handle: 'shakilofficial0',
    role: 'Live Bus Data',
    avatarUrl: 'https://github.com/shakilofficial0.png',
    linkLabel: 'GitHub',
    url: 'https://github.com/shakilofficial0',
  ),
];

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Made by the BRACU student community and free for every student.',
          style: TextStyle(color: textSecondary),
        ),
        const SizedBox(height: 6),
        Text(
          'If you have an idea, spot a bug, or want to help, '
          'we would love to hear from you on GitHub.',
          style: TextStyle(color: textSecondary),
        ),
        const SizedBox(height: 12),
        const _RepoButton(),
      ],
    );
  }
}

class _RepoButton extends StatelessWidget {
  const _RepoButton();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openExternalUrl(context, kPreconnectRepositoryUrl),
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
          crossAxisCount: 1,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 0,
          childAspectRatio: 5.2,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'App Store publishing needs the \$99/year Apple Developer '
          'membership. Any contribution towards this funding will be highly appreciated.',
          style: TextStyle(color: BracuPalette.textSecondary(context)),
        ),
        const SizedBox(height: 12),
        const BracuFundingSupportContent(),
      ],
    );
  }
}

class _SponsoredStrip extends StatelessWidget {
  const _SponsoredStrip();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        children: const [
          _SponsoredTile(
            title: 'Google Admob',
            subtitle: 'Ads Support Provider',
            iconColor: BracuPalette.primary,
            leading: _AdSenseLogoImage(),
            url: 'https://admob.google.com/',
          ),
          SizedBox(width: 25),
          _SponsoredTile(
            width: 220,
            title: 'Become a Sponsor',
            subtitle: 'Tap to chat on WhatsApp',
            icon: Icons.add,
            iconColor: Color(0xFF25D366),
            url:
                'https://api.whatsapp.com/send?phone=8801865493144&text=Hi%20PreConnect%2C%20I%20want%20to%20become%20a%20sponsor%20for%20the%20app.',
          ),
        ],
      ),
    );
  }
}

class _SponsoredTile extends StatelessWidget {
  const _SponsoredTile({
    this.width,
    required this.title,
    required this.subtitle,
    this.icon,
    required this.iconColor,
    this.leading,
    this.url,
  });

  final double? width;
  final String title;
  final String subtitle;
  final IconData? icon;
  final Color iconColor;
  final Widget? leading;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        leading ??
            (icon != null
                ? Icon(icon, color: iconColor, size: 22)
                : const SizedBox.shrink()),
        const SizedBox(width: 10),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: BracuPalette.textPrimary(context),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: BracuPalette.textSecondary(context),
              ),
            ),
          ],
        ),
      ],
    );

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0),
      child: row,
    );

    if (width != null) {
      return SizedBox(
        width: width,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: url == null ? null : () => openExternalUrl(context, url!),
          child: content,
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: url == null ? null : () => openExternalUrl(context, url!),
      child: content,
    );
  }
}

class _AdSenseLogoImage extends StatelessWidget {
  const _AdSenseLogoImage();

  static const String _logoUrl = 'https://preconnect.app/google-adsense.png';

  @override
  Widget build(BuildContext context) {
    return CachedImage(
      url: _logoUrl,
      width: 24,
      height: 24,
      fit: BoxFit.contain,
      placeholder: const SizedBox.shrink(),
      error: const SizedBox.shrink(),
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
  final zamiul = _findByHandle(items, 'zamiul-rashid');
  final mueen = _findByHandle(items, 'mueen-ahmmed');
  final shakil = _findByHandle(items, 'shakilofficial0');
  final rez1 = _findByHandle(items, 'rez1-dev');
  final reserved = <_ContributorProfile>{
    ?naive,
    ?sabbir,
    ?zamiul,
    ?mueen,
    ?shakil,
    ?rez1,
  };
  final others = items.where((item) => !reserved.contains(item)).toList();
  final ordered = <_ContributorProfile>[
    ?naive,
    ?sabbir,
    ?zamiul,
    ?mueen,
    ?shakil,
    ?rez1,
  ];

  for (final item in others) {
    if (ordered.length >= _collapsedContributorCount) break;
    ordered.add(item);
  }
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

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 150;
        final avatarSize = compact ? 46.0 : 58.0;
        final nameSize = compact ? 17.0 : 19.5;
        final roleSize = compact ? 12.0 : 14.0;
        return InkWell(
          onTap: () => openExternalUrl(context, contributor.url),
          borderRadius: BorderRadius.circular(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ContributorAvatar(
                name: contributor.name,
                url: contributor.avatarUrl,
                size: avatarSize,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        contributor.name,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: nameSize,
                          fontWeight: FontWeight.w600,
                          height: 1.05,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        contributor.role,
                        maxLines: 1,
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: roleSize,
                          height: 1.05,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _LinkChip(
                label: contributor.linkLabel,
                onTap: () => openExternalUrl(context, contributor.url),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ContributorAvatar extends StatelessWidget {
  const _ContributorAvatar({
    required this.name,
    required this.url,
    required this.size,
  });

  final String name;
  final String url;
  final double size;

  Widget _placeholder(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      color: BracuPalette.primary.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Text(initial, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fallback = _placeholder(context);
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: CachedImage(
          url: url,
          fit: BoxFit.cover,
          placeholder: fallback,
          error: fallback,
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: BracuPalette.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
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

  Map<String, dynamic> toJson() => <String, dynamic>{
    'handle': handle,
    'name': name,
    'role': role,
    'avatarUrl': avatarUrl,
    'linkLabel': linkLabel,
    'url': url,
  };

  factory _ContributorProfile.fromJson(Map<String, dynamic> json) {
    final linkLabel = '${json['linkLabel'] ?? ''}'.trim();
    return _ContributorProfile(
      handle: '${json['handle'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}'.trim(),
      role: '${json['role'] ?? ''}'.trim(),
      avatarUrl: '${json['avatarUrl'] ?? ''}'.trim(),
      linkLabel: linkLabel.isEmpty ? 'GitHub' : linkLabel,
      url: '${json['url'] ?? ''}'.trim(),
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

  String get identity {
    final normalizedUrl = url.trim().toLowerCase().replaceFirst(
      RegExp(r'/$'),
      '',
    );
    return normalizedUrl.isEmpty ? key : normalizedUrl;
  }

  bool matchesHandle(String value) => key == value.trim().toLowerCase();
}

String _githubRole(String login) {
  return switch (login.trim().toLowerCase()) {
    'naiveinvestigator' || 'naivelnvestigator' => 'Lead Developer',
    'sabbirba' => 'Developer & UI/UX',
    _ => 'Contributor',
  };
}
