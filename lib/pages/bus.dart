import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:preconnect/api/bus_tracker_service.dart';
import 'package:preconnect/pages/shared_widgets/campus_map_shared.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

part 'package:preconnect/pages/bus/widgets/bus_route_detail.dart';
part 'package:preconnect/pages/bus/widgets/bus_models.dart';
part 'package:preconnect/pages/bus/widgets/bus_sections.dart';
part 'package:preconnect/pages/bus/widgets/bus_widgets.dart';

class BusPage extends StatefulWidget {
  const BusPage({super.key});

  @override
  State<BusPage> createState() => _BusPageState();
}

class _BusPageState extends State<BusPage> {
  bool _loading = true;
  String? _error;
  _BusDataPackage? _data;
  Map<String, BusTrackerRouteSnapshot> _routeSnapshots =
      <String, BusTrackerRouteSnapshot>{};
  String _schedulePdfUrl = '';

  @override
  void initState() {
    super.initState();
    _load();
    _fetchSchedulePdfUrl();
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
    } catch (error) {
      debugPrint('Failed to fetch schedule URL: $error');
    }
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final _ = forceRefresh;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final jsonTextFuture = rootBundle.loadString(
        'assets/data/bus_routes.json',
      );
      final liveAssetFuture = BusTrackerService().fetchLastData();

      final jsonText = await jsonTextFuture;
      final decoded = jsonDecode(jsonText);
      final liveAssetJson = await liveAssetFuture;
      final package = decoded is Map<String, dynamic>
          ? _BusDataPackage.fromJson(decoded)
          : decoded is Map
          ? _BusDataPackage.fromJson(decoded.cast<String, dynamic>())
          : const _BusDataPackage.empty();
      if (!mounted) return;
      setState(() {
        _data = liveAssetJson == null
            ? package
            : package.copyWith(
                liveAsset: _BusLiveAsset.fromJson(liveAssetJson),
              );
        _loading = false;
      });
      unawaited(_preloadRouteSnapshots(package.routes));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load bus route data right now.';
      });
      debugPrint('Bus data load failed: $error');
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
          if (_loading)
            const BracuLoading(itemCount: 2)
          else if (_error != null)
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
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _load(forceRefresh: true),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          if (!_loading && routes.isEmpty)
            const BracuEmptyState(message: 'No bus route data available')
          else if (!_loading)
            ...routes.asMap().entries.expand((entry) {
              final route = entry.value;
              final isLast = entry.key == routes.length - 1;
              final initialSnapshot = _routeSnapshots[_snapshotKey(route)];
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
                          initialSnapshot: initialSnapshot,
                        ),
                      ),
                    );
                  },
                ),
                if (!isLast) const SizedBox(height: 10),
              ];
            }),
          if (!_loading && outbound != null) ...[
            const SizedBox(height: 2),
            _OutboundTripsCard(outbound: outbound),
          ],
          if (!_loading && fares.isNotEmpty) ...[
            const SizedBox(height: 2),
            _FareCard(fares: fares),
          ],
          if (!_loading && contacts.isNotEmpty) ...[
            const SizedBox(height: 2),
            _ContactsCard(contacts: contacts),
          ],
          if (!_loading && instructions.isNotEmpty) ...[
            const SizedBox(height: 2),
            _GeneralInstructionsCard(instructions: instructions),
          ],
        ],
      ),
    );
  }

  Future<void> _preloadRouteSnapshots(List<BusTransportRoute> routes) async {
    final codes = <String>{
      for (final route in routes)
        if (route.routeVehicle.code.trim().isNotEmpty)
          route.routeVehicle.code.trim(),
      for (final route in routes)
        if (route.code.trim().isNotEmpty) route.code.trim(),
    }.toList(growable: false);

    if (codes.isEmpty) return;

    try {
      final snapshots = await BusTrackerService().fetchFleetSnapshots(codes);
      if (!mounted) return;

      final nextSnapshots = <String, BusTrackerRouteSnapshot>{};
      for (final snapshot in snapshots) {
        nextSnapshots[_snapshotKeyForCode(snapshot.code)] = snapshot;
      }

      setState(() {
        _routeSnapshots = nextSnapshots;
      });
    } catch (_) {}
  }

  String _snapshotKey(BusTransportRoute route) {
    final vehicleCode = route.routeVehicle.code.trim();
    if (vehicleCode.isNotEmpty) return _snapshotKeyForCode(vehicleCode);
    return _snapshotKeyForCode(route.code);
  }

  String _snapshotKeyForCode(String code) {
    return code.trim().toUpperCase();
  }
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
