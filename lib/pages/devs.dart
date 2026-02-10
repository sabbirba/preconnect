import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:preconnect/pages/ui_kit.dart';

class DevsPage extends StatelessWidget {
  const DevsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    return BracuPageScaffold(
      title: 'Devs',
      subtitle: 'Devs',
      icon: Icons.developer_mode_outlined,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
        children: [
          BracuCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PreConnect - Initiative Run by Students',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
                githubUrl: 'https://github.com/NaiveInvestigator',
                facebookUrl: '',
              ),
              _DevGridTile(
                name: 'Sabbir Bin Abbas',
                role: 'Developer & UI/UX',
                avatarUrl: 'https://github.com/sabbirba.png',
                githubUrl: 'https://github.com/sabbirba',
                facebookUrl: 'https://facebook.com/Sabbirba10',
              ),
            ],
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF0B0B0B)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: BracuPalette.primary.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          color: Colors.white,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final size = constraints.maxWidth;
                              return Image.network(
                                'https://preconnect.app/bkash-qr.jpg',
                                width: size,
                                height: size,
                                fit: BoxFit.contain,
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _SupportNumberRow(number: '01865493144'),
                    ],
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

class _DevGridTile extends StatelessWidget {
  const _DevGridTile({
    required this.name,
    required this.role,
    required this.avatarUrl,
    required this.githubUrl,
    required this.facebookUrl,
  });

  final String name;
  final String role;
  final String avatarUrl;
  final String githubUrl;
  final String facebookUrl;

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
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
            onTap: () => _openUrl(githubUrl),
            borderRadius: BorderRadius.circular(24),
            child: CircleAvatar(
              radius: 22,
              backgroundColor: BracuPalette.primary.withValues(alpha: 0.12),
              backgroundImage: NetworkImage(avatarUrl),
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
              _LinkChip(label: 'GitHub', onTap: () => _openUrl(githubUrl)),
              if (facebookUrl.isNotEmpty)
                _LinkChip(
                  label: 'Facebook',
                  onTap: () => _openUrl(facebookUrl),
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
  final uri = Uri.parse('https://github.com/sabbirba/preconnect');
  await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
}

class _SupportNumberRow extends StatelessWidget {
  const _SupportNumberRow({required this.number});

  final String number;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  number,
                  style: TextStyle(
                    color: BracuPalette.textPrimary(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: number));
                    if (context.mounted) {
                      showAppSnackBar(context, 'Number copied');
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.copy_rounded,
                      size: 16,
                      color: BracuPalette.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'bKash / Nagad / Upay',
              style: TextStyle(color: textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 220,
              child: Column(
                children: [
                  Text(
                    'Send money with reference',
                    style: TextStyle(color: textSecondary, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'PreConnect App',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () async {
                          await Clipboard.setData(
                            const ClipboardData(text: 'PreConnect App'),
                          );
                          if (context.mounted) {
                            showAppSnackBar(context, 'Reference copied');
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(
                            Icons.copy_rounded,
                            size: 14,
                            color: BracuPalette.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
