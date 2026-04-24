part of 'package:preconnect/pages/bus.dart';

class BusRouteDetailPage extends StatefulWidget {
  const BusRouteDetailPage({
    super.key,
    required this.route,
    this.vehicle,
    this.initialSnapshot,
  });

  final BusTransportRoute route;
  final BusRouteVehicle? vehicle;
  final BusTrackerRouteSnapshot? initialSnapshot;

  @override
  State<BusRouteDetailPage> createState() => _BusRouteDetailPageState();
}

class _BusRouteDetailPageState extends State<BusRouteDetailPage> {
  BusTrackerRouteSnapshot? _snapshot;
  StreamSubscription<BusTrackerRouteSnapshot?>? _snapshotSubscription;
  bool _refreshing = false;
  String? _error;

  bool get _liveTrackingEnabled {
    final routeId = widget.route.id.trim().toLowerCase();
    final routeName = widget.route.displayTitle.trim().toLowerCase();
    if (routeId == 'route-09') return false;
    return !routeName.contains('bashundhara');
  }

  @override
  void initState() {
    super.initState();
    _snapshot = widget.initialSnapshot;
    if (_liveTrackingEnabled) {
      _refreshLiveData();
    }
  }

  @override
  void dispose() {
    unawaited(_snapshotSubscription?.cancel());
    super.dispose();
  }

  String get _routeCode {
    final fromVehicle = widget.vehicle?.code.trim() ?? '';
    if (fromVehicle.isNotEmpty) return fromVehicle;
    if (widget.route.code.trim().isNotEmpty) return widget.route.code.trim();
    return widget.route.displayTitle;
  }

  Future<void> _startLiveStream({bool refreshing = false}) async {
    if (!_liveTrackingEnabled) return;
    await _snapshotSubscription?.cancel();
    if (!mounted) return;
    setState(() {
      _refreshing = refreshing;
      _error = null;
    });

    _snapshotSubscription = BusTrackerService()
        .watchFleetSnapshot(_routeCode)
        .listen(
          (snapshot) {
            if (!mounted) return;
            setState(() {
              if (snapshot != null) {
                _snapshot = snapshot;
              }
              _refreshing = false;
              _error = null;
            });
          },
          onError: (_) {
            if (!mounted) return;
            setState(() {
              _refreshing = false;
              _error = 'Unable to load.';
            });
          },
        );
  }

  void _refreshLiveData() {
    unawaited(_startLiveStream(refreshing: true));
  }

  Future<void> _callAttendant(String phone) async {
    final normalizedPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (normalizedPhone.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.parse('tel:$normalizedPhone');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened || !mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Unable to open the dialer.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final vehicle = widget.vehicle;
    final snapshot = _snapshot;
    final title = route.displayTitle;
    final subtitle = route.to.isNotEmpty
        ? route.to
        : route.from.isNotEmpty
        ? route.from
        : '';

    return Scaffold(
      body: BracuPageScaffold(
        title: title,
        subtitle: subtitle,
        icon: Icons.directions_bus_filled_rounded,
        actions: _liveTrackingEnabled
            ? [
                IconButton(
                  tooltip: 'Refresh live bus data',
                  onPressed: _refreshing ? null : _refreshLiveData,
                  icon: _refreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ]
            : const <Widget>[],
        body: BracuRefreshList(
          onRefresh: _liveTrackingEnabled
              ? () async => _refreshLiveData()
              : () async {},
          children: [
            if (_liveTrackingEnabled && _error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
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
                      onPressed: _refreshLiveData,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            if (_liveTrackingEnabled) ...[
              _RouteLiveMapCard(
                route: route,
                vehicle: vehicle,
                snapshot: snapshot,
              ),
              const SizedBox(height: 2),
              _LiveTrackingCard(snapshot: snapshot),
              const SizedBox(height: 2),
            ],
            _RouteStopsCard(route: route),
            if (route.attendantPhone.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              _RouteAttendantFooter(
                phone: route.attendantPhone,
                onCallAttendant: _callAttendant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RouteLiveMapCard extends StatelessWidget {
  const _RouteLiveMapCard({
    required this.route,
    required this.vehicle,
    required this.snapshot,
  });

  final BusTransportRoute route;
  final BusRouteVehicle? vehicle;
  final BusTrackerRouteSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final hasLocation = snapshot?.hasPosition == true;
    final marker = snapshot == null || !snapshot!.hasPosition
        ? null
        : BusFleetMarker(
            code: snapshot!.code,
            title: route.displayTitle,
            subtitle: vehicle?.displayLabel.isNotEmpty == true
                ? vehicle!.displayLabel
                : snapshot!.assetName,
            status: snapshot!.status,
            speed: snapshot!.speed,
            updatedAt: snapshot!.updatedAt,
            latitude: snapshot!.latitudeValue ?? 0,
            longitude: snapshot!.longitudeValue ?? 0,
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: double.infinity,
              height: 280,
              child: hasLocation
                  ? Container(
                      color: const Color(0xFFEEF5FF),
                      child: BusFleetMapView(
                        markers: <BusFleetMarker>[marker!],
                      ),
                    )
                  : const _BusMapShimmerPlaceholder(),
            ),
          ),
          if (hasLocation) ...[
            const SizedBox(height: 10),
            _RouteActionButton(
              label: 'Open in Google Maps',
              onPressed: () => _openInGoogleMaps(context, snapshot!),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openInGoogleMaps(
    BuildContext context,
    BusTrackerRouteSnapshot snapshot,
  ) async {
    final latitude = snapshot.latitudeValue;
    final longitude = snapshot.longitudeValue;
    if (latitude == null || longitude == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened || !context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Unable to open Google Maps.')),
    );
  }
}

class _RouteAttendantFooter extends StatelessWidget {
  const _RouteAttendantFooter({
    required this.phone,
    required this.onCallAttendant,
  });

  final String phone;
  final Future<void> Function(String phone) onCallAttendant;

  @override
  Widget build(BuildContext context) {
    final normalizedPhone = phone.trim();
    if (normalizedPhone.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: _RouteActionButton(
        label: 'Call Attendant $normalizedPhone',
        onPressed: () => onCallAttendant(normalizedPhone),
      ),
    );
  }
}

class _RouteActionButton extends StatelessWidget {
  const _RouteActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: BracuPalette.primary.withValues(alpha: 0.35)),
          foregroundColor: BracuPalette.primary,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _BusMapShimmerPlaceholder extends StatelessWidget {
  const _BusMapShimmerPlaceholder();

  @override
  Widget build(BuildContext context) {
    return BracuShimmer(
      child: Container(
        color: BracuPalette.primary.withValues(alpha: 0.05),
        padding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            Positioned(
              top: 18,
              left: 18,
              child: BracuSkeletonBox(width: 110, height: 28, radius: 14),
            ),
            Positioned(
              right: 18,
              top: 18,
              child: BracuSkeletonBox(width: 44, height: 44, radius: 14),
            ),
            Positioned(
              right: 18,
              bottom: 18,
              child: BracuSkeletonBox(width: 86, height: 86, radius: 24),
            ),
            Positioned(
              left: 18,
              bottom: 18,
              child: BracuSkeletonBox(width: 120, height: 20, radius: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveTrackingCard extends StatelessWidget {
  const _LiveTrackingCard({required this.snapshot});

  final BusTrackerRouteSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: snapshot != null
          ? _LiveTrackerDetailsCard(snapshot: snapshot)
          : const SizedBox.shrink(),
    );
  }
}

class _LiveTrackerDetailsCard extends StatelessWidget {
  const _LiveTrackerDetailsCard({required this.snapshot});

  final BusTrackerRouteSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final liveSnapshot = snapshot;
    if (liveSnapshot == null) {
      return const SizedBox.shrink();
    }
    final data = _mergedLiveSnapshotData(liveSnapshot);
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Speed: ',
                style: TextStyle(
                  color: BracuPalette.textSecondary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
              TextSpan(
                text: _speedLabel(data),
                style: TextStyle(
                  color: BracuPalette.textPrimary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              TextSpan(
                text: '   Updated: ',
                style: TextStyle(
                  color: BracuPalette.textSecondary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
              TextSpan(
                text: _updatedLabel(data),
                style: TextStyle(
                  color: BracuPalette.textPrimary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
            ],
          ),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
        ),
      ),
    );
  }
}

String _speedLabel(Map<String, dynamic> data) {
  final speed = _parseDouble(data['speed']);
  if (speed <= 0) return '0 km/h';
  return '${speed.toStringAsFixed(speed.truncateToDouble() == speed ? 0 : 1)} km/h';
}

String _updatedLabel(Map<String, dynamic> data) {
  final raw = '${data['time'] ?? ''}'.trim();
  if (raw.isEmpty) return 'Unknown';
  try {
    final parsed = DateTime.parse(raw).toLocal();
    return DateFormat('d MMMM, h:mm a').format(parsed);
  } catch (_) {
    return raw;
  }
}

double _parseDouble(dynamic value) {
  return double.tryParse('${value ?? ''}'.trim()) ?? 0;
}

Map<String, dynamic> _mergedLiveSnapshotData(BusTrackerRouteSnapshot snapshot) {
  final merged = <String, dynamic>{};
  final assetInfo = snapshot.assetInfo;
  final lastData = snapshot.lastData;
  if (assetInfo != null) {
    merged.addAll(assetInfo);
  }
  if (lastData != null) {
    merged.addAll(lastData);
  }
  merged['code'] = snapshot.code;
  return merged;
}

class _RouteStopsCard extends StatelessWidget {
  const _RouteStopsCard({required this.route});

  final BusTransportRoute route;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (route.stops.isEmpty)
            Text(
              'Stop details are unavailable for this route.',
              style: TextStyle(color: textSecondary),
            )
          else
            ...route.stops.asMap().entries.map(
              (entry) => Padding(
                padding: EdgeInsets.only(
                  bottom: entry.key == route.stops.length - 1 ? 0 : 10,
                ),
                child: _RouteStopTimelineTile(
                  index: entry.key + 1,
                  stop: entry.value,
                  isLast: entry.key == route.stops.length - 1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RouteStopTimelineTile extends StatelessWidget {
  const _RouteStopTimelineTile({
    required this.index,
    required this.stop,
    required this.isLast,
  });

  final int index;
  final BusTransportStop stop;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BracuPalette.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stop.name,
                    style: TextStyle(
                      color: textPrimary,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                  if (stop.times.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: stop.times
                          .map(
                            (time) => _InfoChip(
                              icon: Icons.schedule_rounded,
                              text: time,
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ] else ...[
                    const SizedBox(height: 4),
                    Text(
                      'No time data available.',
                      style: TextStyle(color: textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
