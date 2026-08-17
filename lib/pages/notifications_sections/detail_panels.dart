import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/notification.dart';
import 'package:preconnect/pages/notifications_sections/list_widgets.dart';
import 'package:preconnect/pages/notifications_sections/text_formatter.dart';
import 'package:preconnect/pages/ui_kit.dart';

class ScraperNotificationDetailPanel extends StatelessWidget {
  ScraperNotificationDetailPanel({super.key, required this.item})
    : _parts = splitNotificationBodyParts(
        cleanNotificationBodyText(item.details, title: item.title),
      ),
      _imageUrls = _resolveImageUrls(item),
      _published = item.createdOn == null
          ? item.module
          : '${item.module}  •  ${DateFormat('EEEE, d MMMM yyyy, h:mm a').format(item.createdOn!.toLocal())}';

  final NotificationListItem item;
  final NotificationBodyParts _parts;
  final List<String> _imageUrls;
  final String _published;

  static List<String> _resolveImageUrls(NotificationListItem item) {
    if (item.imageUrls.isNotEmpty) return item.imageUrls;
    final fallback = (item.imageUrl ?? '').trim();
    if (fallback.isEmpty) return const <String>[];
    return <String>[fallback];
  }

  @override
  Widget build(BuildContext context) {
    final dragController = bracuBottomSheetScrollController(context);
    return ListView(
      controller: dragController,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 16),
      children: [
        Text(
          _published,
          style: TextStyle(
            color: BracuPalette.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (_imageUrls.isNotEmpty) ...[
          const Gap(12),
          BracuImageCarousel(imageUrls: _imageUrls, borderRadius: 14),
        ],
        const Gap(16),
        Text(
          _parts.body.isEmpty
              ? 'No additional details were provided.'
              : _parts.body,
          style: TextStyle(
            color: BracuPalette.textPrimary(context),
            fontSize: 15,
            height: 1.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (_parts.links.isNotEmpty) ...[
          const Gap(16),
          Text(
            'Source links:',
            style: TextStyle(
              color: BracuPalette.textPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Gap(8),
          ..._parts.links.map(
            (link) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: () async {
                    await openExternalUrl(context, link);
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      displayLinkLabel(link),
                      style: TextStyle(
                        color: BracuPalette.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        if ((item.url ?? '').trim().isNotEmpty) ...[
          const Gap(16),
          SizedBox(
            width: double.infinity,
            child: BracuActionButton(
              onPressed: () async {
                await openExternalUrl(context, item.url!);
              },
              icon: Icons.open_in_new,
              label: 'Open Source',
            ),
          ),
        ],
      ],
    );
  }
}

class ConnectNotificationDetailPanel extends StatefulWidget {
  const ConnectNotificationDetailPanel({
    super.key,
    required this.notificationId,
  });

  final int notificationId;

  @override
  State<ConnectNotificationDetailPanel> createState() =>
      _ConnectNotificationDetailPanelState();
}

class _ConnectNotificationDetailPanelState
    extends State<ConnectNotificationDetailPanel> {
  late final Future<ConnectNotificationDetail> _future;
  NotificationBodyParts? _cachedParts;

  @override
  void initState() {
    super.initState();
    _future = NotificationService().fetchNotificationDetail(
      widget.notificationId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dragController = bracuBottomSheetScrollController(context);
    return FutureBuilder<ConnectNotificationDetail>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return ListView(
            controller: dragController,
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Unable to load notification details.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: BracuPalette.textPrimary(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Gap(12),
              Text(
                'Pull to refresh the list and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: BracuPalette.textSecondary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
        }

        final detail = snapshot.data!;
        final parts = _cachedParts ??= splitNotificationBodyParts(
          cleanNotificationBodyText(detail.details, title: detail.title),
        );
        return ListView(
          controller: dragController,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(2, 4, 2, 16),
          children: [
            Text(
              _detailMeta(detail),
              style: TextStyle(
                color: BracuPalette.textSecondary(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Gap(16),
            Text(
              parts.body.isEmpty
                  ? 'No additional details were provided.'
                  : parts.body,
              style: TextStyle(
                color: BracuPalette.textPrimary(context),
                fontSize: 15,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (parts.links.isNotEmpty) ...[
              const Gap(16),
              Text(
                'Source links:',
                style: TextStyle(
                  color: BracuPalette.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Gap(8),
              ...parts.links.map(
                (link) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: () async {
                        await openExternalUrl(context, link);
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          displayLinkLabel(link),
                          style: TextStyle(
                            color: BracuPalette.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  String _moduleLabel(String raw) {
    final cleaned = raw.trim().toLowerCase();
    switch (cleaned) {
      case 'fin':
        return 'Finance';
      case 'adv':
        return 'Advising';
      case 'reg':
        return 'Registration';
      case 'exc':
        return 'Exam & Course';
      default:
        return cleaned.isEmpty ? 'General' : cleaned.toUpperCase();
    }
  }

  String _detailMeta(ConnectNotificationDetail detail) {
    final module = _moduleLabel(detail.module);
    final createdOn = detail.createdOn;
    if (createdOn == null) return module;
    final fullTime = DateFormat(
      'EEEE, d MMMM yyyy, h:mm:ss a',
    ).format(createdOn.toLocal());
    return '$module  •  $fullTime';
  }
}
