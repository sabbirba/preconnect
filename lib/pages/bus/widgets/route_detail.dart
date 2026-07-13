part of 'package:preconnect/pages/bus.dart';

class BusRouteDetailPage extends StatefulWidget {
  const BusRouteDetailPage({super.key, required this.route, this.vehicle});

  final BusTransportRoute route;
  final BusRouteVehicle? vehicle;

  @override
  State<BusRouteDetailPage> createState() => _BusRouteDetailPageState();
}

class _BusRouteDetailPageState extends State<BusRouteDetailPage>
    with SingleTickerProviderStateMixin {
  late BusTransportRoute _route;
  bool _refreshing = false;
  String? _error;
  late final AnimationController _refreshController;

  @override
  void initState() {
    super.initState();
    _route = widget.route;
    _refreshController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    unawaited(_refreshRouteData());
  }

  @override
  void dispose() {
    _refreshController.dispose();
    super.dispose();
  }

  Future<void> _callAttendant(String phone) async {
    final normalizedPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (normalizedPhone.isEmpty) return;
    final uri = Uri.parse('tel:$normalizedPhone');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened || !mounted) return;
    showAppSnackBar(context, 'Unable to open the dialer.');
  }

  Future<void> _refreshRouteData() async {
    if (_refreshing) return;
    if (!mounted) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    _refreshController.repeat();

    try {
      final package = await _fetchBusDataPackage();
      final refreshedRoute = _findUpdatedRoute(package, _route);
      if (!mounted) return;
      setState(() {
        if (refreshedRoute != null) {
          _route = refreshedRoute;
        }
        _refreshing = false;
      });
      _refreshController.stop();
      _refreshController.reset();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _error = 'Unable to load bus data right now.';
      });
      _refreshController.stop();
      _refreshController.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    final vehicle = widget.vehicle;
    final hasLivePosition = route.live.hasPosition;
    final hasLiveStats =
        route.live.speed.trim().isNotEmpty ||
        route.live.time.trim().isNotEmpty ||
        route.live.status.trim().isNotEmpty;
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
        actions: [
          IconButton(
            tooltip: 'Refresh bus data',
            onPressed: _refreshing ? null : _refreshRouteData,
            icon: RotationTransition(
              turns: _refreshController,
              child: const Icon(Icons.refresh_rounded),
            ),
          ),
        ],
        body: BracuRefreshList(
          onRefresh: _refreshRouteData,
          children: [
            if (_error != null)
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
                    const Gap(10),
                    BracuActionButton(
                      onPressed: _refreshing ? null : _refreshRouteData,
                      isLoading: _refreshing,
                      icon: Icons.refresh_rounded,
                      label: 'Retry',
                    ),
                  ],
                ),
              ),
            if (hasLivePosition && !kIsWeb) ...[
              _RouteLiveMapCard(route: route, vehicle: vehicle),
              const Gap(2),
              if (hasLiveStats) _LiveTrackingCard(route: route),
              const Gap(2),
            ],
            if (hasLivePosition && kIsWeb) ...[
              _RouteGoogleMapsLink(route: route),
              const Gap(2),
            ],
            _RouteStopsCard(route: route),
            if (route.attendantPhone.trim().isNotEmpty) ...[
              const Gap(2),
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

class _RouteGoogleMapsLink extends StatelessWidget {
  const _RouteGoogleMapsLink({required this.route});

  final BusTransportRoute route;

  @override
  Widget build(BuildContext context) {
    final live = route.live;
    final latitude = live.latitudeValue;
    final longitude = live.longitudeValue;
    if (latitude == null || longitude == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: _RouteActionButton(
        label: 'Open in Google Maps',
        onPressed: () => _openRouteInGoogleMaps(context, latitude, longitude),
      ),
    );
  }
}

Future<void> _openRouteInGoogleMaps(
  BuildContext context,
  double latitude,
  double longitude,
) async {
  final uri = Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
  );
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (opened || !context.mounted) return;
  showAppSnackBar(context, 'Unable to open Google Maps.');
}

class _RouteLiveMapCard extends StatelessWidget {
  const _RouteLiveMapCard({required this.route, required this.vehicle});

  final BusTransportRoute route;
  final BusRouteVehicle? vehicle;

  @override
  Widget build(BuildContext context) {
    final live = route.live;
    final hasLocation = live.hasPosition;
    final marker = !hasLocation
        ? null
        : BusFleetMarker(
            code: route.code.isNotEmpty ? route.code : route.id,
            title: route.displayTitle,
            subtitle: vehicle?.displayLabel.isNotEmpty == true
                ? vehicle!.displayLabel
                : route.routeVehicle.displayLabel,
            status: live.status,
            speed: live.speed,
            updatedAt: live.time,
            latitude: live.latitudeValue ?? 0,
            longitude: live.longitudeValue ?? 0,
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
            const Gap(10),
            _RouteActionButton(
              label: 'Open in Google Maps',
              onPressed: () {
                final latitude = live.latitudeValue;
                final longitude = live.longitudeValue;
                if (latitude == null || longitude == null) return;
                _openRouteInGoogleMaps(context, latitude, longitude);
              },
            ),
          ],
        ],
      ),
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
      child: BracuActionButton(
        onPressed: onPressed,
        label: label,
        borderRadius: 14,
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}

class _BusMapShimmerPlaceholder extends StatelessWidget {
  const _BusMapShimmerPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
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
            child: _PlaceholderPill(width: 110, height: 28, radius: 14),
          ),
          Positioned(
            right: 18,
            top: 18,
            child: _PlaceholderPill(width: 44, height: 44, radius: 14),
          ),
          Positioned(
            right: 18,
            bottom: 18,
            child: _PlaceholderPill(width: 86, height: 86, radius: 24),
          ),
          Positioned(
            left: 18,
            bottom: 18,
            child: _PlaceholderPill(width: 120, height: 20, radius: 10),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderPill extends StatelessWidget {
  const _PlaceholderPill({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _LiveTrackingCard extends StatelessWidget {
  const _LiveTrackingCard({required this.route});

  final BusTransportRoute route;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: _LiveTrackerDetailsCard(route: route),
    );
  }
}

class _LiveTrackerDetailsCard extends StatelessWidget {
  const _LiveTrackerDetailsCard({required this.route});

  final BusTransportRoute route;

  @override
  Widget build(BuildContext context) {
    final live = route.live;
    final speedLabel = _speedLabel(live);
    final updatedLabel = _updatedLabel(live);

    if (speedLabel == null && updatedLabel == null) {
      return const SizedBox.shrink();
    }

    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text.rich(
          TextSpan(
            children: [
              if (speedLabel != null) ...[
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
                  text: speedLabel,
                  style: TextStyle(
                    color: BracuPalette.textPrimary(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ],
              if (speedLabel != null && updatedLabel != null) ...[
                TextSpan(
                  text: '   ',
                  style: TextStyle(
                    color: BracuPalette.textSecondary(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ],
              if (updatedLabel != null) ...[
                TextSpan(
                  text: 'Updated: ',
                  style: TextStyle(
                    color: BracuPalette.textSecondary(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                TextSpan(
                  text: updatedLabel,
                  style: TextStyle(
                    color: BracuPalette.textPrimary(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ],
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

String? _speedLabel(BusRouteLiveSnapshot data) {
  final raw = data.speed.trim();
  if (raw.isEmpty) return null;
  final speed = _parseDouble(raw);
  if (speed <= 0) return '0 km/h';
  return '${speed.toStringAsFixed(speed.truncateToDouble() == speed ? 0 : 1)} km/h';
}

String? _updatedLabel(BusRouteLiveSnapshot data) {
  final raw = data.time.trim();
  if (raw.isEmpty) return null;
  try {
    final parsed = DateTime.parse(raw).toLocal();
    return DateFormat('d MMMM, h:mm a').format(parsed);
  } catch (_) {
    return null;
  }
}

double _parseDouble(String value) {
  return double.tryParse(value.trim()) ?? 0;
}

BusTransportRoute? _findUpdatedRoute(
  _BusDataPackage package,
  BusTransportRoute currentRoute,
) {
  final routeKeys = <String>{
    _routeMatchKey(currentRoute.id),
    _routeMatchKey(currentRoute.code),
    _routeMatchKey(currentRoute.routeVehicle.code),
    _routeMatchKey(currentRoute.displayTitle),
  }.where((key) => key.isNotEmpty).toSet();

  for (final route in package.routes) {
    final candidateKeys = <String>{
      _routeMatchKey(route.id),
      _routeMatchKey(route.code),
      _routeMatchKey(route.routeVehicle.code),
      _routeMatchKey(route.displayTitle),
    };
    if (candidateKeys.any(routeKeys.contains)) {
      return route;
    }
  }

  return null;
}

String _routeMatchKey(String value) {
  return value.trim().toLowerCase();
}

bool _isStopHighlighted(BusTransportStop stop, BusTransportRoute route) {
  final live = route.live;
  final stopName = stop.name.trim().toLowerCase();
  if (stopName.isEmpty) return false;

  final loc = live.locationDescription.trim().toLowerCase();
  if (loc.isNotEmpty) {
    if (loc.contains(stopName) || stopName.contains(loc)) {
      return true;
    }
  }

  for (final landmark in live.nearestLandmarks) {
    final land = landmark.trim().toLowerCase();
    if (land.isNotEmpty) {
      if (land.contains(stopName) || stopName.contains(land)) {
        return true;
      }
    }
  }

  return false;
}

class _NextStopHighlightCard extends StatelessWidget {
  const _NextStopHighlightCard({required this.stopName});

  final String stopName;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: BracuCard(
        isHighlighted: true,
        backgroundColor: BracuPalette.primary.withValues(
          alpha: isDark ? 0.15 : 0.08,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: BracuPalette.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.location_on_rounded,
                color: BracuPalette.primary,
                size: 22,
              ),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Next Stop (Estimated)',
                    style: TextStyle(
                      color: BracuPalette.textSecondary(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const Gap(2),
                  Text(
                    stopName,
                    style: TextStyle(
                      color: BracuPalette.textPrimary(context),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteStopsCard extends StatelessWidget {
  const _RouteStopsCard({required this.route});

  final BusTransportRoute route;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);

    int highlightedIndex = -1;
    for (int i = 0; i < route.stops.length; i++) {
      if (_isStopHighlighted(route.stops[i], route)) {
        highlightedIndex = i;
        break;
      }
    }

    final hasHighlight = highlightedIndex >= 0;
    final highlightedStopName = hasHighlight
        ? route.stops[highlightedIndex].name
        : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasHighlight)
            _NextStopHighlightCard(stopName: highlightedStopName),
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
                  isHighlighted: entry.key == highlightedIndex,
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
    required this.isHighlighted,
  });

  final int index;
  final BusTransportStop stop;
  final bool isLast;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                const Gap(14),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: isHighlighted
                        ? BracuPalette.primary
                        : Colors.grey.shade400,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isHighlighted
                          ? BracuPalette.primary.withValues(alpha: 0.25)
                          : Colors.transparent,
                      width: isHighlighted ? 3.5 : 0,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: isHighlighted
                          ? BracuPalette.primary.withValues(alpha: 0.3)
                          : Colors.grey.shade300,
                    ),
                  ),
              ],
            ),
          ),
          const Gap(8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isHighlighted
                    ? BracuPalette.primary.withValues(alpha: 0.12)
                    : BracuPalette.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: isHighlighted
                    ? Border.all(
                        color: BracuPalette.primary.withValues(alpha: 0.35),
                        width: 1.5,
                      )
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          stop.name,
                          style: TextStyle(
                            color: textPrimary,
                            fontWeight: FontWeight.w800,
                            height: 1.35,
                          ),
                        ),
                      ),
                      if (isHighlighted) ...[
                        const Gap(8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: BracuPalette.primary.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.directions_bus_rounded,
                                color: BracuPalette.primary,
                                size: 12,
                              ),
                              const Gap(4),
                              Text(
                                'LIVE',
                                style: TextStyle(
                                  color: BracuPalette.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (stop.times.isNotEmpty) ...[
                    const Gap(8),
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
                    const Gap(4),
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
