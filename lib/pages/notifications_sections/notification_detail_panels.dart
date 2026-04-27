import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/notification_service.dart';
import 'package:preconnect/pages/notifications_sections/notification_list_widgets.dart';
import 'package:preconnect/pages/notifications_sections/notification_text_formatter.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/cached_image.dart';

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
            _DirectNotificationImageGallery(imageUrls: imageUrls),
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
              child: ElevatedButton.icon(
                onPressed: () async {
                  await openExternalUrl(context, item.url!);
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Source'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DirectNotificationImageGallery extends StatefulWidget {
  const _DirectNotificationImageGallery({required this.imageUrls});

  final List<String> imageUrls;

  @override
  State<_DirectNotificationImageGallery> createState() =>
      _DirectNotificationImageGalleryState();
}

class _DirectNotificationImageGalleryState
    extends State<_DirectNotificationImageGallery> {
  late final PageController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrls.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.imageUrls.length == 1)
              CachedImage(url: widget.imageUrls.first, fit: BoxFit.cover)
            else
              PageView.builder(
                controller: _controller,
                itemCount: widget.imageUrls.length,
                onPageChanged: (value) {
                  if (!mounted) return;
                  setState(() {
                    _index = value;
                  });
                },
                itemBuilder: (context, idx) {
                  return CachedImage(
                    url: widget.imageUrls[idx],
                    fit: BoxFit.cover,
                  );
                },
              ),
            if (widget.imageUrls.length >= 2)
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Text(
                        '${_index + 1}/${widget.imageUrls.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
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
          return Padding(
            padding: const EdgeInsets.all(18),
            child: const BracuLoading(itemCount: 2),
          );
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
