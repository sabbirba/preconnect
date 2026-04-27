part of 'package:preconnect/pages/bus.dart';

class BusRouteVehicle {
  const BusRouteVehicle({required this.name, required this.code});

  final String name;
  final String code;

  String get displayLabel {
    if (code.isNotEmpty) return code;
    if (name.isNotEmpty) return name;
    return '';
  }

  factory BusRouteVehicle.fromJson(Map<String, dynamic> json) {
    return BusRouteVehicle(
      name: _stringValue(json, 'name'),
      code: _stringValue(json, 'code'),
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
    if (name.isNotEmpty) return name;
    if (from.isNotEmpty) return from;
    if (id.isNotEmpty) return id;
    return '';
  }

  factory BusTransportRoute.fromJson(Map<String, dynamic> json) {
    final stops = <BusTransportStop>[];
    final stopsRaw = json['stops'];
    if (stopsRaw is List) {
      for (final rawStop in stopsRaw.whereType<Map>()) {
        stops.add(BusTransportStop.fromJson(rawStop.cast<String, dynamic>()));
      }
    }

    final routeVehicleRaw = json['route_vehicles'];

    return BusTransportRoute(
      id: _stringValue(json, 'id'),
      name: _stringValue(json, 'name'),
      code: _stringValue(json, 'code'),
      routeVehicle: routeVehicleRaw is Map
          ? BusRouteVehicle.fromJson(routeVehicleRaw.cast<String, dynamic>())
          : const BusRouteVehicle(name: '', code: ''),
      from: _stringValue(json, 'from'),
      to: _stringValue(json, 'to'),
      attendantPhone: _stringValue(json, 'attendant_phone'),
      stops: stops,
      live: BusRouteLiveSnapshot.fromJson(json),
    );
  }
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
      assetId: _stringValue(json, 'asset_id'),
      status: _stringValue(json, 'status'),
      time: _stringValue(json, 'time'),
      statusTime: _stringValue(json, 'status_time'),
      ignition: _stringValue(json, 'ignition'),
      gpsPositioned: _stringValue(json, 'gps_positioned'),
      engineSensor: _stringValue(json, 'engine_sensor'),
      charging: _stringValue(json, 'charging'),
      gsmSignal: _stringValue(json, 'gsm_signal'),
      speed: _stringValue(json, 'speed'),
      bearing: _stringValue(json, 'bearing'),
      heading: _stringValue(json, 'heading'),
      locationDescription: _stringValue(json, 'location'),
      latitude: latitude,
      longitude: longitude,
      deviceType: _stringValue(json, 'device_type'),
      speedLimit: _stringValue(json, 'speed_limit'),
      validTill: _stringValue(json, 'valid_till'),
      validTillCredit: _stringValue(json, 'valid_till_credit'),
      powercutAlert: _stringValue(json, 'powercut_alert'),
      engineAlert: _stringValue(json, 'engine_alert'),
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
    final timesRaw = json['times'];
    final times = timesRaw is List
        ? timesRaw
              .map((item) => '$item'.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : <String>[];

    return BusTransportStop(name: _stringValue(json, 'name'), times: times);
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
      from: _stringValue(json, 'from'),
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
      route: _stringValue(json, 'route'),
      code: _stringValue(json, 'code'),
      time: _stringValue(json, 'time'),
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
      routeGroup: _stringValue(json, 'route_group'),
      amountPerTrip: _stringValue(json, 'amount_per_trip'),
      roundTrip: _stringValue(json, 'round_trip'),
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
      name: _stringValue(json, 'name'),
      role: _stringValue(json, 'role'),
      email: _stringValue(json, 'email'),
    );
  }
}

String _stringValue(Map<String, dynamic> json, String key) {
  return '${json[key] ?? ''}'.trim();
}
