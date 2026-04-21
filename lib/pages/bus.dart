import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:preconnect/pages/shared_widgets/campus_map_shared.dart';
import 'package:preconnect/pages/ui_kit.dart';

class BusPage extends StatefulWidget {
  const BusPage({super.key});

  @override
  State<BusPage> createState() => _BusPageState();
}

class _BusPageState extends State<BusPage> {
  bool _loading = true;
  String? _error;
  _BusDataPackage? _data;
  String _schedulePdfUrl = '';
  final Set<String> _expandedRouteIds = <String>{};

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
      if (mounted) {
        setState(() {
          _schedulePdfUrl = resolvedUrl ?? '';
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch schedule URL: $e');
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
      final jsonText = await rootBundle.loadString(
        'assets/data/bus_routes.json',
      );
      final decoded = jsonDecode(jsonText);
      final package = decoded is Map<String, dynamic>
          ? _BusDataPackage.fromJson(decoded)
          : decoded is Map
          ? _BusDataPackage.fromJson(decoded.cast<String, dynamic>())
          : const _BusDataPackage.empty();
      if (!mounted) return;
      setState(() {
        _data = package;
        _loading = false;
        _expandedRouteIds.clear();
      });
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
    final routes = _data?.routes ?? const <_TransportRoute>[];
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
            )
          else if (routes.isEmpty)
            const BracuEmptyState(message: 'No bus route data available')
          else
            ...routes.map(
              (route) => _TransportRouteCard(
                route: route,
                expanded: _expandedRouteIds.contains(route.id),
                onToggle: () {
                  setState(() {
                    if (_expandedRouteIds.contains(route.id)) {
                      _expandedRouteIds.remove(route.id);
                    } else {
                      _expandedRouteIds.add(route.id);
                    }
                  });
                },
              ),
            ),
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
}

class _TransportRouteCard extends StatelessWidget {
  const _TransportRouteCard({
    required this.route,
    required this.expanded,
    required this.onToggle,
  });

  final _TransportRoute route;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: BracuCard(
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          route.displayTitle,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      Icon(
                        expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 18,
                        color: BracuPalette.primary,
                      ),
                    ],
                  ),
                ),
              ),
              if (expanded) ...[
                const SizedBox(height: 10),
                if (route.stops.isEmpty)
                  Text(
                    'Stop details are unavailable for this route.',
                    style: TextStyle(color: textSecondary),
                  )
                else
                  ...route.stops.asMap().entries.map(
                    (entry) => _RouteStopTile(
                      stop: entry.value,
                      isLast: entry.key == route.stops.length - 1,
                    ),
                  ),
                if (route.attendantPhone.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: InkWell(
                      onTap: () =>
                          openPhoneDialer(context, route.attendantPhone),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.call_rounded,
                              size: 16,
                              color: BracuPalette.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Call Attendant (${route.attendantPhone})',
                              style: TextStyle(
                                color: BracuPalette.primary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteStopTile extends StatelessWidget {
  const _RouteStopTile({required this.stop, required this.isLast});

  final _TransportStop stop;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: BracuPalette.primary,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 44,
                    margin: const EdgeInsets.only(top: 2),
                    color: BracuPalette.primary.withValues(alpha: 0.35),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stop.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                if (stop.times.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: stop.times
                          .map(
                            (time) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: BracuPalette.primary.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 12,
                                    color: BracuPalette.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    time,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: BracuPalette.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(growable: false),
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

class _OutboundTripsCard extends StatelessWidget {
  const _OutboundTripsCard({required this.outbound});

  final _BusOutbound outbound;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.directions_bus_filled_rounded,
            title: 'Outbound Drop-offs',
          ),
          const SizedBox(height: 8),
          if (outbound.firstOutbound.isNotEmpty) ...[
            _TripGroupPanel(
              title: '1st Outbound',
              entries: outbound.firstOutbound,
            ),
            const SizedBox(height: 10),
          ],
          if (outbound.secondOutbound.isNotEmpty) ...[
            _TripGroupPanel(
              title: '2nd Outbound',
              entries: outbound.secondOutbound,
            ),
          ],
          if (outbound.firstOutbound.isEmpty && outbound.secondOutbound.isEmpty)
            Text(
              'No outbound drop-off data available.',
              style: TextStyle(color: BracuPalette.textSecondary(context)),
            ),
        ],
      ),
    );
  }
}

class _FareCard extends StatelessWidget {
  const _FareCard({required this.fares});

  final List<_BusFare> fares;

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(icon: Icons.payments_rounded, title: 'Fare'),
          const SizedBox(height: 8),
          ...fares.asMap().entries.map(
            (entry) => Container(
              margin: EdgeInsets.only(
                bottom: entry.key == fares.length - 1 ? 0 : 8,
              ),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: BracuPalette.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fareLabel(entry.value.routeGroup),
                    style: TextStyle(
                      color: textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _InfoChip(
                        icon: Icons.login_rounded,
                        text: 'Per trip: ${entry.value.amountPerTrip}',
                      ),
                      _InfoChip(
                        icon: Icons.repeat_rounded,
                        text: 'Round trip: ${entry.value.roundTrip}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (fares.isEmpty)
            Text(
              'No fare data available.',
              style: TextStyle(color: textSecondary),
            ),
        ],
      ),
    );
  }
}

class _ContactsCard extends StatelessWidget {
  const _ContactsCard({required this.contacts});

  final List<_BusContact> contacts;

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.support_agent_rounded,
            title: 'Transport Contacts',
          ),
          const SizedBox(height: 8),
          ...contacts.asMap().entries.map(
            (entry) => Container(
              margin: EdgeInsets.only(
                bottom: entry.key == contacts.length - 1 ? 0 : 8,
              ),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: BracuPalette.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: BracuPalette.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.person_rounded,
                      size: 16,
                      color: BracuPalette.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.value.name,
                          style: TextStyle(
                            color: textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (entry.value.role.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              entry.value.role,
                              style: TextStyle(color: textSecondary),
                            ),
                          ),
                        if (entry.value.email.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: InkWell(
                              onTap: () =>
                                  openMailComposer(context, entry.value.email),
                              borderRadius: BorderRadius.circular(999),
                              child: _InfoChip(
                                icon: Icons.mail_outline_rounded,
                                text: entry.value.email,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (contacts.isEmpty)
            Text(
              'No contact data available.',
              style: TextStyle(color: textSecondary),
            ),
        ],
      ),
    );
  }
}

class _GeneralInstructionsCard extends StatelessWidget {
  const _GeneralInstructionsCard({required this.instructions});

  final List<String> instructions;

  @override
  Widget build(BuildContext context) {
    final textSecondary = BracuPalette.textSecondary(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.rule_rounded,
            title: 'General Instructions',
          ),
          const SizedBox(height: 8),
          ...instructions.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: BracuPalette.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: BracuPalette.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${entry.key + 1}',
                        style: TextStyle(
                          color: BracuPalette.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: TextStyle(color: textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (instructions.isEmpty)
            Text(
              'No instruction data available.',
              style: TextStyle(color: textSecondary),
            ),
        ],
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

class _TripGroupPanel extends StatelessWidget {
  const _TripGroupPanel({required this.title, required this.entries});

  final String title;
  final List<_BusDropoffEntry> entries;

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BracuPalette.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
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
          const SizedBox(height: 8),
          ...entries.asMap().entries.map(
            (entry) => Padding(
              padding: EdgeInsets.only(
                bottom: entry.key == entries.length - 1 ? 0 : 8,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      '${entry.value.route} (${entry.value.code})',
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _InfoChip(
                    icon: Icons.schedule_outlined,
                    text: entry.value.time,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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

class _TransportRoute {
  const _TransportRoute({
    required this.id,
    required this.name,
    required this.code,
    required this.from,
    required this.to,
    required this.attendantPhone,
    required this.stops,
  });

  final String id;
  final String name;
  final String code;
  final String from;
  final String to;
  final String attendantPhone;
  final List<_TransportStop> stops;

  String get displayTitle {
    if (name.isNotEmpty) {
      return name.replaceAll(RegExp(r'\s+to\s+BRAC University\s*$'), '');
    }
    if (from.isNotEmpty && to.isNotEmpty) return '$from -> $to';
    return 'Bus Route';
  }

  factory _TransportRoute.fromJson(Map<String, dynamic> json) {
    final stopsRaw = json['stops'];
    final stops = <_TransportStop>[];
    if (stopsRaw is List) {
      for (final rawStop in stopsRaw.whereType<Map>()) {
        final stop = _TransportStop.fromJson(rawStop.cast<String, dynamic>());
        if (stop.name.isNotEmpty) stops.add(stop);
      }
    }

    final rawPhone = _pick(json, <String>[
      'service_attendant',
      'attendant_phone',
      'phone',
      'contact',
    ]);

    return _TransportRoute(
      id: _pick(json, <String>['id', 'name', 'route_name', 'title']),
      name: _pick(json, <String>['name', 'route_name', 'title']),
      code: _pick(json, <String>['code', 'tracking_code']),
      from: _pick(json, <String>['from', 'start', 'origin']),
      to: _pick(json, <String>['to', 'destination', 'end']),
      attendantPhone: normalizeCampusPhoneValue(rawPhone),
      stops: stops,
    );
  }
}

class _TransportStop {
  const _TransportStop({required this.name, required this.times});

  final String name;
  final List<String> times;

  factory _TransportStop.fromJson(Map<String, dynamic> json) {
    final timesRaw = json['time'];
    final altTimesRaw = json['times'];
    final listRaw = timesRaw is List ? timesRaw : altTimesRaw;
    final times = listRaw is List
        ? listRaw
              .map((item) => '$item'.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : <String>[];

    return _TransportStop(
      name: _pick(json, <String>['name', 'stop', 'location']),
      times: times,
    );
  }
}

class _BusDataPackage {
  const _BusDataPackage({
    required this.title,
    required this.routes,
    required this.outbound,
    required this.fares,
    required this.contacts,
    required this.instructions,
  });

  const _BusDataPackage.empty()
    : title = '',
      routes = const <_TransportRoute>[],
      outbound = null,
      fares = const <_BusFare>[],
      contacts = const <_BusContact>[],
      instructions = const <String>[];

  final String title;
  final List<_TransportRoute> routes;
  final _BusOutbound? outbound;
  final List<_BusFare> fares;
  final List<_BusContact> contacts;
  final List<String> instructions;

  factory _BusDataPackage.fromJson(Map<String, dynamic> json) {
    final routesRaw = json['routes'];
    final faresRaw = json['fares'];
    final contactsRaw = json['contacts'];
    final instructionsRaw = json['general_instructions'];
    final outboundRaw = json['outbound_dropoffs'];

    return _BusDataPackage(
      title: _pick(json, <String>['title']),
      routes: routesRaw is List
          ? routesRaw
                .whereType<Map>()
                .map(
                  (item) =>
                      _TransportRoute.fromJson(item.cast<String, dynamic>()),
                )
                .toList(growable: false)
          : const <_TransportRoute>[],
      outbound: outboundRaw is Map
          ? _BusOutbound.fromJson(outboundRaw.cast<String, dynamic>())
          : null,
      fares: faresRaw is List
          ? faresRaw
                .whereType<Map>()
                .map((item) => _BusFare.fromJson(item.cast<String, dynamic>()))
                .toList(growable: false)
          : const <_BusFare>[],
      contacts: contactsRaw is List
          ? contactsRaw
                .whereType<Map>()
                .map(
                  (item) => _BusContact.fromJson(item.cast<String, dynamic>()),
                )
                .toList(growable: false)
          : const <_BusContact>[],
      instructions: instructionsRaw is List
          ? instructionsRaw
                .map((item) => '$item'.trim())
                .where((item) => item.isNotEmpty)
                .toList(growable: false)
          : const <String>[],
    );
  }
}

class _BusOutbound {
  const _BusOutbound({
    required this.from,
    required this.firstOutbound,
    required this.secondOutbound,
  });

  final String from;
  final List<_BusDropoffEntry> firstOutbound;
  final List<_BusDropoffEntry> secondOutbound;

  factory _BusOutbound.fromJson(Map<String, dynamic> json) {
    final firstRaw = json['first_outbound'];
    final secondRaw = json['second_outbound'];
    return _BusOutbound(
      from: _pick(json, <String>['from']),
      firstOutbound: firstRaw is List
          ? firstRaw
                .whereType<Map>()
                .map(
                  (item) =>
                      _BusDropoffEntry.fromJson(item.cast<String, dynamic>()),
                )
                .toList(growable: false)
          : const <_BusDropoffEntry>[],
      secondOutbound: secondRaw is List
          ? secondRaw
                .whereType<Map>()
                .map(
                  (item) =>
                      _BusDropoffEntry.fromJson(item.cast<String, dynamic>()),
                )
                .toList(growable: false)
          : const <_BusDropoffEntry>[],
    );
  }
}

class _BusDropoffEntry {
  const _BusDropoffEntry({
    required this.route,
    required this.code,
    required this.time,
  });

  final String route;
  final String code;
  final String time;

  factory _BusDropoffEntry.fromJson(Map<String, dynamic> json) {
    return _BusDropoffEntry(
      route: _pick(json, <String>['route', 'name']),
      code: _pick(json, <String>['code']),
      time: _pick(json, <String>['time']),
    );
  }
}

class _BusFare {
  const _BusFare({
    required this.routeGroup,
    required this.amountPerTrip,
    required this.roundTrip,
  });

  final String routeGroup;
  final String amountPerTrip;
  final String roundTrip;

  factory _BusFare.fromJson(Map<String, dynamic> json) {
    return _BusFare(
      routeGroup: _pick(json, <String>['route_group']),
      amountPerTrip: _pick(json, <String>['amount_per_trip']),
      roundTrip: _pick(json, <String>['round_trip']),
    );
  }
}

class _BusContact {
  const _BusContact({
    required this.name,
    required this.role,
    required this.email,
  });

  final String name;
  final String role;
  final String email;

  factory _BusContact.fromJson(Map<String, dynamic> json) {
    return _BusContact(
      name: _pick(json, <String>['name']),
      role: _pick(json, <String>['role']),
      email: _pick(json, <String>['email']),
    );
  }
}

String _pick(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = '${json[key] ?? ''}'.trim();
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}
