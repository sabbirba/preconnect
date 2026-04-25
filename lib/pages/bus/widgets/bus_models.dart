part of 'package:preconnect/pages/bus.dart';

class BusRouteVehicle {
  const BusRouteVehicle({required this.name, required this.code});

  final String name;
  final String code;

  String get displayLabel {
    if (code.isNotEmpty) return code;
    if (name.isNotEmpty) return name;
    return 'Bus';
  }

  factory BusRouteVehicle.fromJson(Map<String, dynamic> json) {
    return BusRouteVehicle(
      name: _pick(json, <String>['name', 'vehicle_name']),
      code: _pick(json, <String>['code', 'vehicle_code']),
    );
  }
}

class BusTransportRoute {
  const BusTransportRoute({
    required this.id,
    required this.name,
    required this.code,
    required this.routeVehicle,
    required this.from,
    required this.to,
    required this.attendantPhone,
    required this.stops,
    required this.live,
  });

  final String id;
  final String name;
  final String code;
  final BusRouteVehicle routeVehicle;
  final String from;
  final String to;
  final String attendantPhone;
  final List<BusTransportStop> stops;
  final BusRouteLiveSnapshot live;

  String get displayTitle {
    if (name.isNotEmpty) return _cleanRouteName(name);
    if (from.isNotEmpty) return _cleanRouteName(from);
    if (id.isNotEmpty) return _cleanRouteName(id);
    return 'Bus Route';
  }

  factory BusTransportRoute.fromJson(Map<String, dynamic> json) {
    final stopsRaw = json['stops'];
    final stops = <BusTransportStop>[];
    if (stopsRaw is List) {
      for (final rawStop in stopsRaw.whereType<Map>()) {
        final stop = BusTransportStop.fromJson(rawStop.cast<String, dynamic>());
        if (stop.name.isNotEmpty) stops.add(stop);
      }
    }

    final rawPhone = _pick(json, <String>[
      'service_attendant',
      'attendant_phone',
      'phone',
      'contact',
    ]);
    final routeVehicleRaw = json['route_vehicles'];

    return BusTransportRoute(
      id: _pick(json, <String>['id', 'name', 'route_name', 'title']),
      name: _pick(json, <String>['name', 'route_name', 'title']),
      code: _pick(json, <String>['code', 'tracking_code']),
      routeVehicle: routeVehicleRaw is Map
          ? BusRouteVehicle.fromJson(routeVehicleRaw.cast<String, dynamic>())
          : const BusRouteVehicle(name: '', code: ''),
      from: _pick(json, <String>['from', 'start', 'origin']),
      to: _pick(json, <String>['to', 'destination', 'end']),
      attendantPhone: normalizeCampusPhoneValue(rawPhone),
      stops: stops,
      live: BusRouteLiveSnapshot.fromJson(json),
    );
  }
}

String _cleanRouteName(String value) {
  var cleaned = value.trim();
  cleaned = cleaned.replaceAll(
    RegExp(r'^\s*Route\s*[-:]?\s*\d+\s*[:\-]?\s*', caseSensitive: false),
    '',
  );
  cleaned = cleaned.replaceAll(
    RegExp(r'\s+to\s+BRAC University\s*$', caseSensitive: false),
    '',
  );
  return cleaned.trim();
}

class BusRouteLiveSnapshot {
  const BusRouteLiveSnapshot({
    required this.assetId,
    required this.status,
    required this.time,
    required this.statusTime,
    required this.ignition,
    required this.gpsPositioned,
    required this.engineSensor,
    required this.charging,
    required this.gsmSignal,
    required this.speed,
    required this.bearing,
    required this.heading,
    required this.locationDescription,
    required this.latitude,
    required this.longitude,
    required this.deviceType,
    required this.speedLimit,
    required this.validTill,
    required this.validTillCredit,
    required this.powercutAlert,
    required this.engineAlert,
    required this.nearestLandmarks,
  });

  final String assetId;
  final String status;
  final String time;
  final String statusTime;
  final String ignition;
  final String gpsPositioned;
  final String engineSensor;
  final String charging;
  final String gsmSignal;
  final String speed;
  final String bearing;
  final String heading;
  final String locationDescription;
  final String latitude;
  final String longitude;
  final String deviceType;
  final String speedLimit;
  final String validTill;
  final String validTillCredit;
  final String powercutAlert;
  final String engineAlert;
  final List<String> nearestLandmarks;

  factory BusRouteLiveSnapshot.fromJson(Map<String, dynamic> json) {
    final loc = json['loc'];
    final coordinates = loc is Map ? loc['coordinates'] : null;
    final latitude = coordinates is List && coordinates.length > 1
        ? '${coordinates[1]}'.trim()
        : '';
    final longitude = coordinates is List && coordinates.isNotEmpty
        ? '${coordinates[0]}'.trim()
        : '';

    final landmarksRaw = json['nearest_landmarks'];
    final nearestLandmarks = landmarksRaw is List
        ? landmarksRaw
              .map((item) => '$item'.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[];

    return BusRouteLiveSnapshot(
      assetId: _pick(json, <String>['asset_id', '_id']),
      status: _pick(json, <String>['status']),
      time: _pick(json, <String>['time']),
      statusTime: _pick(json, <String>['status_time']),
      ignition: _pick(json, <String>['ignition']),
      gpsPositioned: _pick(json, <String>['gps_positioned']),
      engineSensor: _pick(json, <String>['engine_sensor']),
      charging: _pick(json, <String>['charging']),
      gsmSignal: _pick(json, <String>['gsm_signal']),
      speed: _pick(json, <String>['speed']),
      bearing: _pick(json, <String>['bearing']),
      heading: _pick(json, <String>['heading']),
      locationDescription: _pick(json, <String>['location']),
      latitude: latitude,
      longitude: longitude,
      deviceType: _pick(json, <String>['device_type']),
      speedLimit: _pick(json, <String>['speed_limit']),
      validTill: _pick(json, <String>['valid_till']),
      validTillCredit: _pick(json, <String>['valid_till_credit']),
      powercutAlert: _pick(json, <String>['powercut_alert']),
      engineAlert: _pick(json, <String>['engine_alert']),
      nearestLandmarks: nearestLandmarks,
    );
  }

  bool get hasPosition => latitude.isNotEmpty && longitude.isNotEmpty;
  double? get latitudeValue => double.tryParse(latitude);
  double? get longitudeValue => double.tryParse(longitude);
}

class BusTransportStop {
  const BusTransportStop({required this.name, required this.times});

  final String name;
  final List<String> times;

  factory BusTransportStop.fromJson(Map<String, dynamic> json) {
    final timesRaw = json['time'];
    final altTimesRaw = json['times'];
    final listRaw = timesRaw is List ? timesRaw : altTimesRaw;
    final times = listRaw is List
        ? listRaw
              .map((item) => '$item'.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : <String>[];

    return BusTransportStop(
      name: _pick(json, <String>['name', 'stop', 'location']),
      times: times,
    );
  }
}

class _BusDataPackage {
  const _BusDataPackage({
    required this.routes,
    required this.outbound,
    required this.fares,
    required this.contacts,
    required this.instructions,
  });

  const _BusDataPackage.empty()
    : routes = const <BusTransportRoute>[],
      outbound = null,
      fares = const <_BusFare>[],
      contacts = const <_BusContact>[],
      instructions = const <String>[];

  final List<BusTransportRoute> routes;
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
    final routes = routesRaw is List
        ? routesRaw
              .whereType<Map>()
              .map(
                (item) =>
                    BusTransportRoute.fromJson(item.cast<String, dynamic>()),
              )
              .toList(growable: false)
        : const <BusTransportRoute>[];

    return _BusDataPackage(
      routes: routes,
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
