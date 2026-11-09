import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/pages/shared_widgets/map_shared.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/app_log.dart';
import 'package:preconnect/tools/sse_client.dart';
import 'package:webview_flutter/webview_flutter.dart';

part 'package:preconnect/pages/bus/widgets/route_detail.dart';
part 'package:preconnect/pages/bus/widgets/bus_models.dart';
part 'package:preconnect/pages/bus/widgets/bus_sections.dart';
part 'package:preconnect/pages/bus/widgets/bus_widgets.dart';

class _BusLive {
  static final ValueNotifier<_BusDataPackage?> data =
      ValueNotifier<_BusDataPackage?>(null);
  static final ValueNotifier<bool> failed = ValueNotifier<bool>(false);
  static int _viewers = 0;
  static final SseClient _client = SseClient(
    name: 'Bus',
    request: () async => http.Request('GET', Uri.parse(ApiConfig.busStreamUrl)),
    onEvent: _apply,
    onFailure: () => failed.value = true,
    silence: const Duration(seconds: 20),
  );

  static void _apply(String event, String payload) {
    if (event != 'bus-snapshot' && event != 'bus-updated') return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        data.value = _BusDataPackage.fromJson(decoded.cast<String, dynamic>());
        failed.value = false;
      }
    } on FormatException catch (error) {
      unawaited(AppLog.write('Bus stream event unreadable: $error'));
    }
  }

  static void watch() {
    if (_viewers++ == 0) _client.start();
  }

  static void unwatch() {
    if (--_viewers > 0) return;
    _client.stop();
    data.value = null;
    failed.value = false;
  }

  static Future<void> reconnect() async {
    failed.value = false;
    _client.stop();
    _client.start();
  }
}

class BusPage extends StatefulWidget {
  const BusPage({super.key});

  @override
  State<BusPage> createState() => _BusPageState();
}

class _BusPageState extends State<BusPage> {
  final Listenable _live = Listenable.merge([_BusLive.data, _BusLive.failed]);
  String _schedulePdfUrl = '';

  @override
  void initState() {
    super.initState();
    _BusLive.watch();
    _live.addListener(_onLive);
    _fetchSchedulePdfUrl();
  }

  @override
  void dispose() {
    _live.removeListener(_onLive);
    _BusLive.unwatch();
    super.dispose();
  }

  void _onLive() {
    if (mounted) setState(() {});
  }

  Future<void> _fetchSchedulePdfUrl() async {
    try {
      final url = await fetchTransportScheduleUrl();
      final fallbackUrl = url == null || url.trim().isEmpty
          ? (await fetchCampusMapData())?.transportScheduleUrl
          : null;
      final resolvedUrl = (url?.trim().isNotEmpty == true ? url : fallbackUrl)
          ?.trim();
      if (!mounted) return;
      setState(() {
        _schedulePdfUrl = resolvedUrl ?? '';
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final data = _BusLive.data.value;
    final failed = _BusLive.failed.value && data == null;
    final routes = data?.routes ?? const <BusTransportRoute>[];
    final outbound = data?.outbound;
    final fares = data?.fares ?? const <_BusFare>[];
    final contacts = data?.contacts ?? const <_BusContact>[];
    final instructions = data?.instructions ?? const <String>[];
    final schedulePdfUrl = _schedulePdfUrl;

    return AppPageScaffold(
      title: 'Bus',
      subtitle: 'Routes',
      icon: Icons.directions_bus_filled_rounded,
      actions: [
        IconButton(
          tooltip: 'Open official schedule',
          onPressed: schedulePdfUrl.isEmpty
              ? null
              : () => openPdfUrl(context, schedulePdfUrl),
          icon: const Icon(Icons.picture_as_pdf_outlined),
        ),
      ],
      body: AppRefreshList(
        onRefresh: _BusLive.reconnect,
        children: [
          if (failed)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Unable to load bus route data right now.',
                    style: TextStyle(
                      color: AppPalette.textPrimary(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Gap(12),
                  AppActionButton(
                    onPressed: _BusLive.reconnect,
                    icon: Icons.sync_rounded,
                    label: 'Retry',
                  ),
                ],
              ),
            ),
          if (data == null && !failed)
            const Center(child: AppLoading())
          else if (routes.isEmpty)
            const AppEmptyState(message: 'No bus route data available')
          else
            ...routes.asMap().entries.expand((entry) {
              final route = entry.value;
              final isLast = entry.key == routes.length - 1;
              return [
                _TransportRouteCard(
                  route: route,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BusRouteDetailPage(route: route),
                      ),
                    );
                  },
                ),
                if (!isLast) const Gap(12),
              ];
            }),
          if (outbound != null) ...[
            const Gap(12),
            _OutboundTripsCard(outbound: outbound),
          ],
          if (fares.isNotEmpty) ...[const Gap(12), _FareCard(fares: fares)],
          if (contacts.isNotEmpty) ...[
            const Gap(12),
            _ContactsCard(contacts: contacts),
          ],
          if (instructions.isNotEmpty) ...[
            const Gap(12),
            _GeneralInstructionsCard(instructions: instructions),
          ],
        ],
      ),
    );
  }
}

class _TransportRouteCard extends StatelessWidget {
  const _TransportRouteCard({required this.route, required this.onTap});

  final BusTransportRoute route;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionBannerCard(
      icon: Icons.directions_bus_rounded,
      title: route.displayTitle,
      onTap: onTap,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppPalette.textPrimary(context);
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(13),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 16, color: AppPalette.primary),
        ),
        const Gap(12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({this.icon, this.iconWidget, required this.text});

  final IconData? icon;
  final Widget? iconWidget;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (iconWidget != null)
            iconWidget!
          else if (icon != null)
            Icon(icon, size: 12, color: AppPalette.primary),
          const Gap(4),
          Text(
            text,
            style: TextStyle(
              color: AppPalette.primary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

String fareLabel(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? 'Fare Group' : normalized;
}
