import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/app_preferences_store.dart';
import 'package:preconnect/pages/shared_widgets/campus_map_shared.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/async_preload_cache.dart';
import 'package:preconnect/tools/offline_cache_helper.dart';
import 'package:webview_flutter/webview_flutter.dart';

part 'package:preconnect/pages/bus/widgets/bus_route_detail.dart';
part 'package:preconnect/pages/bus/widgets/bus_models.dart';
part 'package:preconnect/pages/bus/widgets/bus_sections.dart';
part 'package:preconnect/pages/bus/widgets/bus_widgets.dart';

const String _busDataCacheKey = 'bus_data_v1';
const String _busScheduleUrlCacheKey = 'bus_schedule_url_v1';

class BusPage extends StatefulWidget {
  const BusPage({super.key});

  static Future<void> preload() async {
    await _BusPageState.preloadData();
  }

  @override
  State<BusPage> createState() => _BusPageState();
}

class _BusPageState extends State<BusPage> {
  static final AsyncPreloadCache<_BusDataPackage> _preloadCache =
      AsyncPreloadCache<_BusDataPackage>();

  String? _error;
  _BusDataPackage? _data;
  String _schedulePdfUrl = '';

  @override
  void initState() {
    super.initState();
    _data = _preloadCache.value;
    _load();
    _fetchSchedulePdfUrl();
    unawaited(_warmAndBind());
  }

  static Future<_BusDataPackage> preloadData({
    bool forceRefresh = false,
  }) async {
    return _preloadCache.get(
      forceRefresh: forceRefresh,
      loader: _fetchBusDataPackage,
    );
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
      if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
        await AppPreferencesStore().setString(
          _busScheduleUrlCacheKey,
          resolvedUrl,
        );
      }
      if (!mounted) return;
      setState(() {
        _schedulePdfUrl = resolvedUrl ?? '';
      });
    } catch (error) {
      final cachedUrl = await AppPreferencesStore().getString(
        _busScheduleUrlCacheKey,
      );
      if (!mounted) return;
      setState(() {
        _schedulePdfUrl = cachedUrl?.trim() ?? '';
      });
      if (kDebugMode) {
        debugPrint('Failed to fetch schedule URL: $error');
      }
    }
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
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load bus route data right now.';
      });
      if (kDebugMode) {
        debugPrint('Bus data load failed: $error');
      }
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
    final routeWidgets = _error == null && routes.isNotEmpty
        ? routes.asMap().entries.expand((entry) {
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
              if (!isLast) const SizedBox(height: 10),
            ];
          })
        : const <Widget>[];

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
            buildRefreshErrorState(
              onRefresh: () => _load(forceRefresh: true),
              error: _error,
              topSpacing: 40,
            ),
          if (_error == null && routes.isEmpty)
            buildRefreshEmptyState(
              onRefresh: () => _load(forceRefresh: true),
              message: 'No bus route data available',
              topSpacing: 40,
            ),
          ...routeWidgets,
          if (outbound != null) ...[
            const SizedBox(height: 2),
            _OutboundTripsCard(outbound: outbound),
          ],
          if (fares.isNotEmpty) ...[
            const SizedBox(height: 2),
            _FareCard(fares: fares),
          ],
          if (contacts.isNotEmpty) ...[
            const SizedBox(height: 2),
            _ContactsCard(contacts: contacts),
          ],
          if (instructions.isNotEmpty) ...[
            const SizedBox(height: 2),
            _GeneralInstructionsCard(instructions: instructions),
          ],
        ],
      ),
    );
  }
}

Future<_BusDataPackage> _fetchBusDataPackage() async {
  final raw = await OfflineCacheHelper.instance.loadJson<dynamic>(
    cacheKey: _busDataCacheKey,
    ttl: const Duration(hours: 12),
    forceRefresh: false,
    fetcher: () async {
      final response = await ApiClient().publicGet(
        ApiConfig.busDataUrl,
        acceptedStatusCodes: <int>{200},
      );
      final decoded = jsonDecode(response.body);
      final payload = decoded is Map<String, dynamic>
          ? decoded
          : decoded is Map
          ? decoded.cast<String, dynamic>()
          : null;
      if (payload == null) return const _BusDataPackage.empty();
      await OfflineCacheHelper.instance.saveJson(_busDataCacheKey, payload);
      return _BusDataPackage.fromJson(payload);
    },
    decoder: (cachedData) {
      if (cachedData is Map<String, dynamic>) {
        return _BusDataPackage.fromJson(cachedData);
      }
      if (cachedData is Map) {
        return _BusDataPackage.fromJson(cachedData.cast<String, dynamic>());
      }
      return null;
    },
  );
  return raw is _BusDataPackage ? raw : const _BusDataPackage.empty();
}

class _TransportRouteCard extends StatelessWidget {
  const _TransportRouteCard({required this.route, required this.onTap});

  final BusTransportRoute route;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: BracuPalette.textSecondary(
                context,
              ).withValues(alpha: 0.18),
            ),
          ),
          child: ListTile(
            leading: Icon(
              Icons.directions_bus_rounded,
              size: 20,
              color: BracuPalette.primary,
            ),
            title: Text(route.displayTitle),
            trailing: Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: BracuPalette.primary,
            ),
          ),
        ),
      ),
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
            color: BracuPalette.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(13),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 16, color: BracuPalette.primary),
        ),
        const SizedBox(width: 8),
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
  const _InfoChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: BracuPalette.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: BracuPalette.primary),
          const SizedBox(width: 4),
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
