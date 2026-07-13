import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/pages/shared_widgets/map_shared.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/preload_cache.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

part 'package:preconnect/pages/bus/widgets/route_detail.dart';
part 'package:preconnect/pages/bus/widgets/bus_models.dart';
part 'package:preconnect/pages/bus/widgets/bus_sections.dart';
part 'package:preconnect/pages/bus/widgets/bus_widgets.dart';

class BusPage extends StatefulWidget {
  const BusPage({super.key});

  static Future<void> preload() async {
    await _BusPageState.preloadData();
  }

  @override
  State<BusPage> createState() => _BusPageState();
}

class _BusPageState extends State<BusPage> {
  static final CachedPageController<_BusDataPackage> controller =
      CachedPageController<_BusDataPackage>(
        ({bool forceRefresh = false}) => _fetchBusDataPackage(),
      );

  String? _error;
  _BusDataPackage? _data;
  String _schedulePdfUrl = '';

  @override
  void initState() {
    super.initState();
    _data = controller.value;
    _load();
    _fetchSchedulePdfUrl();
    unawaited(_warmAndBind());
  }

  static Future<_BusDataPackage> preloadData({
    bool forceRefresh = false,
  }) async {
    return controller.load(forceRefresh: forceRefresh);
  }

  Future<void> _warmAndBind() async {
    final package = await preloadData();
    if (!mounted) return;
    setState(() {
      _data = package;
    });
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

  Future<void> _load({bool forceRefresh = false}) async {
    if (mounted) {
      setState(() {
        _error = null;
      });
    }

    try {
      final package = await preloadData(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _data = package;
        controller.value = package;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load bus route data right now.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final routes = _data?.routes ?? const <BusTransportRoute>[];
    final outbound = _data?.outbound;
    final fares = _data?.fares ?? const <_BusFare>[];
    final contacts = _data?.contacts ?? const <_BusContact>[];
    final instructions = _data?.instructions ?? const <String>[];
    final schedulePdfUrl = _schedulePdfUrl;

    return BracuPageScaffold(
      title: 'Bus',
      subtitle: 'Routes',
      icon: Icons.directions_bus_filled_rounded,
      actions: [
        IconButton(
          tooltip: 'Open official schedule',
          onPressed: schedulePdfUrl.isEmpty
              ? null
              : () => openExternalUrl(context, schedulePdfUrl),
          icon: const Icon(Icons.picture_as_pdf_outlined),
        ),
      ],
      body: BracuRefreshList(
        onRefresh: () => _load(forceRefresh: true),
        children: [
          if (_error != null && _data == null)
            BracuCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _error!,
                    style: TextStyle(
                      color: BracuPalette.textPrimary(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Gap(10),
                  BracuActionButton(
                    onPressed: () => _load(forceRefresh: true),
                    icon: Icons.refresh_rounded,
                    label: 'Retry',
                  ),
                ],
              ),
            ),
          if (routes.isEmpty)
            const BracuEmptyState(message: 'No bus route data available')
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
                        builder: (_) => BusRouteDetailPage(
                          route: route,
                          vehicle: route.routeVehicle.code.isNotEmpty
                              ? route.routeVehicle
                              : null,
                        ),
                      ),
                    );
                  },
                ),
                if (!isLast) const Gap(10),
              ];
            }),
          if (outbound != null) ...[
            const Gap(2),
            _OutboundTripsCard(outbound: outbound),
          ],
          if (fares.isNotEmpty) ...[const Gap(2), _FareCard(fares: fares)],
          if (contacts.isNotEmpty) ...[
            const Gap(2),
            _ContactsCard(contacts: contacts),
          ],
          if (instructions.isNotEmpty) ...[
            const Gap(2),
            _GeneralInstructionsCard(instructions: instructions),
          ],
        ],
      ),
    );
  }
}

Future<_BusDataPackage> _fetchBusDataPackage() async {
  Future<_BusDataPackage> parseUrl(String url) async {
    final response = await ApiClient().publicGet(
      url,
      acceptedStatusCodes: <int>{200},
    );
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return _BusDataPackage.fromJson(decoded);
    }
    if (decoded is Map) {
      return _BusDataPackage.fromJson(decoded.cast<String, dynamic>());
    }
    return const _BusDataPackage.empty();
  }

  return await parseUrl(ApiConfig.busDataUrl);
}

class _TransportRouteCard extends StatelessWidget {
  const _TransportRouteCard({required this.route, required this.onTap});

  final BusTransportRoute route;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BracuActionBannerCard(
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
    final textPrimary = BracuPalette.textPrimary(context);
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
          child: Icon(icon, size: 16, color: BracuPalette.primary),
        ),
        const Gap(8),
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
            Icon(icon, size: 12, color: BracuPalette.primary),
          const Gap(4),
          Text(
            text,
            style: TextStyle(
              color: BracuPalette.primary,
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
