import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/preferences_store.dart';
import 'package:preconnect/pages/api_test.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/build_info.dart';
import 'package:preconnect/tools/cached_image.dart';
import 'package:preconnect/tools/preconnect_constants.dart';
import 'package:preconnect/tools/token_storage.dart';

const String _githubToken = String.fromEnvironment('GITHUB_TOKEN');

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
          return _buildContributors(cached);
        }
      }

      final uri = Uri.parse(
        'https://api.github.com/repos/sabbirba/preconnect/contributors',
      );
      final response = await _githubGet(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _buildContributors(const <_ContributorProfile>[]);
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return _buildContributors(const <_ContributorProfile>[]);
      }
      final contributors = await Future.wait(
        decoded.whereType<Map>().map((raw) async {
          final contributor = _ContributorProfile.fromGitHubContributor(
            raw.cast<String, dynamic>(),
          );
          return _enrichContributorIfNeeded(contributor);
        }),
      );
      final merged = await _buildContributors(contributors);
      final visibleContributors = merged
          .where((item) => !_isBotContributor(item))
          .toList();
      if (visibleContributors.isNotEmpty) {
        await AppPreferencesStore()
            .setJson(_contributorsCacheKey, <String, dynamic>{
              'ts': DateTime.now().millisecondsSinceEpoch,
              'items': contributors.map((item) => item.toJson()).toList(),
            });
      }
      return merged;
    } catch (_) {
      return _buildContributors(const <_ContributorProfile>[]);
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
        .where((item) => !_isBotContributor(item))
        .toList();
  }

  static Future<List<_ContributorProfile>> _buildContributors(
    List<_ContributorProfile> items,
  ) async {
    final merged = <_ContributorProfile>[
      ..._pinnedGitHubContributors,
      ..._manualContributors,
      ...items,
    ];
    final enriched = await Future.wait(merged.map(_enrichContributorIfNeeded));
    final visible = enriched.where((item) => !_isBotContributor(item)).toList();
    return _orderContributors(_dedupeContributors(visible));
  }

  static Future<_ContributorProfile> _enrichContributorIfNeeded(
    _ContributorProfile contributor,
  ) async {
    if (!_isGitHubBackedContributor(contributor)) {
      return contributor;
    }
    final handle = contributor.handle.trim();
    if (handle.isEmpty || handle.toLowerCase().endsWith('[bot]')) {
      return contributor;
    }

    try {
      final uri = Uri.parse('https://api.github.com/users/$handle');
      final response = await _githubGet(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return contributor;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return contributor;
      final profile = decoded.cast<String, dynamic>();
      final resolvedName = '${profile['name'] ?? ''}'.trim();
      final resolvedAvatar = '${profile['avatar_url'] ?? ''}'.trim();
      final resolvedUrl = '${profile['html_url'] ?? ''}'.trim();
      return contributor.copyWith(
        name: resolvedName.isEmpty ? contributor.handle : resolvedName,
        avatarUrl: resolvedAvatar.isEmpty
            ? contributor.avatarUrl
            : resolvedAvatar,
        url: resolvedUrl.isEmpty ? contributor.url : resolvedUrl,
      );
    } catch (_) {
      return contributor;
    }
  }

  static bool _isGitHubBackedContributor(_ContributorProfile contributor) {
    final linkLabel = contributor.linkLabel.trim().toLowerCase();
    final url = contributor.url.trim().toLowerCase();
    return linkLabel == 'github' || url.contains('github.com/');
  }

  static bool _isBotContributor(_ContributorProfile contributor) {
    final handle = contributor.handle.trim().toLowerCase();
    final url = contributor.url.trim().toLowerCase();
    return handle.isEmpty ||
        handle.endsWith('[bot]') ||
        url.contains('/apps/') ||
        url.contains('github-actions[bot]') ||
        url.contains('dependabot');
  }

  Future<void> _onHeaderSecretTap() async {
    _secretTapCount += 1;
    if (_secretTapCount < 10) return;
    _secretTapCount = 0;
    if (!mounted) return;

    final lockService = AppLockService();
    final isBiometricAvailable = await lockService.isBiometricAvailable();
    if (!isBiometricAvailable) {
      return;
    }
    final verified = await lockService.authenticateBiometricOnly();
    if (!verified) return;

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(
          name: '/secure_access',
          arguments: PreConnectRouteTokens.privateAccess,
        ),
        builder: (_) => const ApiTestPage(),
      ),
    );
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
                _buildPeopleSection(),
                const SizedBox(height: 14),
                _buildSponsoredSection(),
                const SizedBox(height: 14),
                _buildFundingSection(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPeopleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BracuSectionTitle(title: 'People Behind It'),
        const SizedBox(height: 10),
        if (_contributors.isEmpty && _contributorsLoading)
          const BracuLoading()
        else
          _ContributorsGrid(contributors: _contributors),
      ],
    );
  }

  Widget _buildSponsoredSection() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BracuSectionTitle(title: 'Sponsored'),
        SizedBox(height: 10),
        _SponsoredStrip(),
      ],
    );
  }

  Widget _buildFundingSection() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 10),
        BracuFundingPromoDivider(),
        SizedBox(height: 10),
        _FundingCard(),
      ],
    );
  }
}

const _contributorsCacheKey = 'devs_contributors_v3';

const _pinnedGitHubContributors = <_ContributorProfile>[
  _ContributorProfile.github(
    handle: 'NaiveInvestigator',
    role: 'Lead Developer',
  ),
  _ContributorProfile.github(handle: 'sabbirba', role: 'Developer & UI/UX'),
];

final _manualContributors = <_ContributorProfile>[
  _ContributorProfile(
    name: 'Mueen Ahmmed',
    handle: 'mueen-ahmmed',
    role: 'Faculty Reviews',
    avatarUrl: ApiConfig.websiteMueenAvatarUrl,
    linkLabel: 'LinkedIn',
    url: 'https://www.linkedin.com/in/mueen-ahmmed-b337b8231/',
  ),
  _ContributorProfile.github(handle: 'Zamiul-rashid', role: 'Friends Schedule'),
  _ContributorProfile.github(handle: 'shakilofficial0', role: 'Live Bus Data'),
  _ContributorProfile.github(handle: 'rez1-dev', role: 'Testing & Feedback'),
  _ContributorProfile.github(handle: 'hitblast', role: 'Developer & Community'),
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
          'Made by the BRACU Students.',
          style: TextStyle(
            color: BracuPalette.textPrimary(context),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'If you have an idea, spot a bug, or want to help, '
          'we would love to hear from you on GitHub. '
          'You can open an issue, share suggestions, or send a pull request.',
          style: TextStyle(color: textSecondary),
        ),
        const SizedBox(height: 12),
        const _RepoButton(),
        const SizedBox(height: 12),
        const BracuCommunityLink(),
      ],
    );
  }
}

class _RepoButton extends StatelessWidget {
  const _RepoButton();

  @override
  Widget build(BuildContext context) {
    return BracuActionBannerCard(
      iconWidget: const PreConnectGithubIcon(size: 24),
      title: 'View Repository',
      subtitle: 'Explore the source code and contribute.',
      onTap: () => openExternalUrl(context, kPreConnectRepositoryUrl),
    );
  }
}

class _ContributorsGrid extends StatelessWidget {
  const _ContributorsGrid({required this.contributors});

  final List<_ContributorProfile> contributors;

  @override
  Widget build(BuildContext context) {
    final all = _orderContributors(
      _dedupeContributors([...contributors, ..._manualContributors]),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 0.0;
        final maxExtent = width < 360
            ? 160.0
            : width < 560
            ? 182.0
            : 202.0;
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxExtent,
            mainAxisExtent: 160,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: all.length,
          itemBuilder: (context, index) {
            return _DevGridTile(contributor: all[index]);
          },
        );
      },
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
            width: 220,
            title: 'Become a Sponsor',
            subtitle: 'Tap to chat on WhatsApp',
            iconWidget: Icon(
              Icons.chat_rounded,
              size: 22,
              color: Color(0xFF25D366),
            ),
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
    this.iconWidget,
    this.url,
  });

  final double? width;
  final String title;
  final String subtitle;
  final Widget? iconWidget;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        iconWidget ?? const SizedBox.shrink(),
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

  ordered.addAll(others);
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
        final width = constraints.maxWidth;
        final compact = width < 165;
        final avatarSize = (width * 0.54).clamp(68.0, 96.0);
        final nameSize = compact ? 13.4 : 15.2;
        final roleSize = compact ? 11.4 : 12.6;
        return InkWell(
          onTap: () => openExternalUrl(context, contributor.url),
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ContributorAvatar(
                name: contributor.name,
                url: contributor.avatarUrl,
                size: avatarSize,
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Text(
                  contributor.name,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: nameSize,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Text(
                  contributor.role,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: roleSize,
                    height: 1.05,
                  ),
                ),
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
    return const SizedBox.shrink();
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

  _ContributorProfile copyWith({
    String? handle,
    String? name,
    String? role,
    String? avatarUrl,
    String? linkLabel,
    String? url,
  }) {
    return _ContributorProfile(
      handle: handle ?? this.handle,
      name: name ?? this.name,
      role: role ?? this.role,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      linkLabel: linkLabel ?? this.linkLabel,
      url: url ?? this.url,
    );
  }

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
    'naivelnvestigator' => 'Lead Developer',
    'sabbirba' => 'Developer & UI/UX',
    _ => 'Contributor',
  };
}

Map<String, String> _githubHeaders() {
  return _githubHeadersWithToken(includeToken: true);
}

Map<String, String> _githubHeadersWithToken({required bool includeToken}) {
  final headers = <String, String>{
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    ...compressionHeaders(),
  };
  final token = _githubToken.trim();
  if (includeToken && token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
  }
  return headers;
}

Future<http.Response> _githubGet(Uri uri) async {
  final token = _githubToken.trim();
  final authenticated = token.isNotEmpty;

  if (authenticated) {
    final response = await ApiClient().publicGet(
      uri.toString(),
      headers: _githubHeaders(),
      acceptedStatusCodes: const <int>{200, 401, 403},
      cacheDuration: const Duration(minutes: 1),
    );
    if (response.statusCode != 401 && response.statusCode != 403) {
      return response;
    }
  }

  return ApiClient().publicGet(
    uri.toString(),
    headers: _githubHeadersWithToken(includeToken: false),
    acceptedStatusCodes: const <int>{200},
    cacheDuration: const Duration(minutes: 1),
  );
}
