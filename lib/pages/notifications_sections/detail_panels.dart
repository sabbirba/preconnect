import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/notification.dart';
import 'package:preconnect/pages/notifications_sections/list_widgets.dart';
import 'package:preconnect/pages/notifications_sections/text_formatter.dart';
import 'package:preconnect/pages/ui_kit.dart';

class ScraperNotificationDetailPanel extends StatelessWidget {
  const ScraperNotificationDetailPanel({super.key, required this.item});

  final NotificationListItem item;

  List<String> _resolvedImageUrls() {
    if (item.imageUrls.isNotEmpty) return item.imageUrls;
    final fallback = (item.imageUrl ?? '').trim();
    if (fallback.isEmpty) return const <String>[];
    return <String>[fallback];
  }

  @override
  Widget build(BuildContext context) {
    final dragController = bracuBottomSheetScrollController(context);
    final cleanedDetails = cleanNotificationBodyText(
      item.details,
      title: item.title,
    );
    final parts = splitNotificationBodyParts(cleanedDetails);
    final imageUrls = _resolvedImageUrls();
    final published = item.createdOn == null
        ? item.module
        : '${item.module}  •  ${DateFormat('EEEE, d MMMM yyyy, h:mm a').format(item.createdOn!.toLocal())}';
    return SingleChildScrollView(
      controller: dragController,
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            published,
            style: TextStyle(
              color: BracuPalette.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (imageUrls.isNotEmpty) ...[
            const SizedBox(height: 14),
            BracuImageCarousel(imageUrls: imageUrls, borderRadius: 14),
          ],
          const SizedBox(height: 18),
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
            const SizedBox(height: 16),
            Text(
              'Source links:',
              style: TextStyle(
                color: BracuPalette.textPrimary(context),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ...parts.links.map(
              (link) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: double.infinity,
                    child: SelectableText(
                      displayLinkLabel(link),
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        color: BracuPalette.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      onTap: () async {
                        await openExternalUrl(context, link);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
          if ((item.url ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 16),
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
      ),
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
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                const SizedBox(height: 12),
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
            ),
          );
        }

        final detail = snapshot.data!;
        final formattedDetails = cleanNotificationBodyText(
          detail.details,
          title: detail.title,
        );
        final parts = splitNotificationBodyParts(formattedDetails);
        return SingleChildScrollView(
          controller: dragController,
          padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _detailMeta(detail),
                style: TextStyle(
                  color: BracuPalette.textSecondary(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
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
                const SizedBox(height: 16),
                Text(
                  'Source links:',
                  style: TextStyle(
                    color: BracuPalette.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ...parts.links.map(
                  (link) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: double.infinity,
                        child: SelectableText(
                          displayLinkLabel(link),
                          textAlign: TextAlign.left,
                          style: TextStyle(
                            color: BracuPalette.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          onTap: () async {
                            await openExternalUrl(context, link);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
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
