part of 'package:preconnect/pages/bus.dart';

class BusFleetMapView extends StatelessWidget {
  const BusFleetMapView({required this.markers, super.key});

  final List<BusFleetMarker> markers;

  @override
  Widget build(BuildContext context) {
    final validMarkers = markers
        .where((marker) => marker.hasPosition)
        .toList(growable: false);
    if (validMarkers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No live bus positions available.',
          textAlign: TextAlign.center,
          style: TextStyle(color: BracuPalette.textSecondary(context)),
        ),
      );
    }

    return _BusLiveMapWebView(markers: validMarkers);
  }
}

class _BusLiveMapWebView extends StatefulWidget {
  const _BusLiveMapWebView({required this.markers});

  final List<BusFleetMarker> markers;

  @override
  State<_BusLiveMapWebView> createState() => _BusLiveMapWebViewState();
}

class _BusLiveMapWebViewState extends State<_BusLiveMapWebView> {
  WebViewController? _controller;
  String? _lastHtml;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    _reloadMap();
  }

  @override
  void didUpdateWidget(covariant _BusLiveMapWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_markerSignature(oldWidget.markers) !=
        _markerSignature(widget.markers)) {
      _reloadMap();
    }
  }

  Future<void> _reloadMap() async {
    final html = _buildFleetEmbedHtml(widget.markers);
    if (_lastHtml == html) return;
    _lastHtml = html;
    await _controller?.loadHtmlString(html);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const SizedBox.shrink();
    }
    return Semantics(
      label: 'Live fleet bus map',
      child: ColoredBox(
        color: const Color(0xFFEEF5FF),
        child: WebViewWidget(controller: controller),
      ),
    );
  }

  String _markerSignature(List<BusFleetMarker> markers) {
    return markers
        .map(
          (marker) => [
            marker.code,
            marker.title,
            marker.latitude.toStringAsFixed(6),
            marker.longitude.toStringAsFixed(6),
            marker.speed,
            marker.updatedAt,
          ].join('|'),
        )
        .join('~');
  }

  String _buildFleetEmbedHtml(List<BusFleetMarker> markers) {
    final embedUrl = _buildGoogleMapsEmbedUrl(markers);
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <style>
    html, body {
      margin: 0;
      width: 100%;
      height: 100%;
      overflow: hidden;
      background: #eef5ff;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    }
    .wrap {
      position: relative;
      width: 100%;
      height: 100%;
      background: #eef5ff;
    }
    iframe {
      width: 100%;
      height: 100%;
      border: 0;
    }
  </style>
</head>
<body>
  <div class="wrap">
    <iframe
      loading="lazy"
      src="$embedUrl"
      allowfullscreen
      referrerpolicy="no-referrer-when-downgrade"
    ></iframe>
  </div>
</body>
</html>
''';
  }

  String _buildGoogleMapsEmbedUrl(List<BusFleetMarker> markers) {
    final validMarkers = markers
        .where((marker) => marker.hasPosition)
        .toList(growable: false);
    if (validMarkers.isEmpty) {
      return 'https://www.google.com/maps?q=BRAC%20University&output=embed';
    }
    if (validMarkers.length == 1) {
      final marker = validMarkers.first;
      return Uri.https('www.google.com', '/maps', <String, String>{
        'q':
            '${marker.latitude.toStringAsFixed(6)},${marker.longitude.toStringAsFixed(6)}',
        'z': '16',
        'output': 'embed',
      }).toString();
    }

    final origin = validMarkers.first;
    final destination = validMarkers.last;
    final waypoints = validMarkers
        .skip(1)
        .take(validMarkers.length - 2)
        .map(
          (marker) =>
              '${marker.latitude.toStringAsFixed(6)},${marker.longitude.toStringAsFixed(6)}',
        )
        .join('|');

    final params = <String, String>{
      'api': '1',
      'origin':
          '${origin.latitude.toStringAsFixed(6)},${origin.longitude.toStringAsFixed(6)}',
      'destination':
          '${destination.latitude.toStringAsFixed(6)},${destination.longitude.toStringAsFixed(6)}',
      'travelmode': 'driving',
    };
    if (waypoints.isNotEmpty) {
      params['waypoints'] = waypoints;
    }
    params['output'] = 'embed';
    return Uri.https('www.google.com', '/maps/dir/', params).toString();
  }
}

class BusFleetMarker {
  const BusFleetMarker({
    required this.code,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.speed,
    required this.updatedAt,
    required this.latitude,
    required this.longitude,
  });

  final String code;
  final String title;
  final String subtitle;
  final String status;
  final String speed;
  final String updatedAt;
  final double latitude;
  final double longitude;

  bool get hasPosition => latitude != 0 && longitude != 0;
  double get speedValue => double.tryParse(speed) ?? 0;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'code': code,
    'title': title,
    'subtitle': subtitle,
    'status': status,
    'speed': speed,
    'updatedAt': updatedAt,
    'latitude': latitude,
    'longitude': longitude,
  };
}

BusTrackerRouteSnapshot? snapshotForRoute(
  BusTransportRoute route,
  Map<String, BusTrackerRouteSnapshot> snapshotsByCode,
) {
  final routeVehicle = route.routeVehicle;
  final code = normalizeRouteCode(
    routeVehicle.code.isNotEmpty ? routeVehicle.code : route.code,
  );
  return snapshotsByCode[code];
}

List<BusFleetMarker> buildFleetMarkers(
  List<BusTransportRoute> routes,
  Map<String, BusTrackerRouteSnapshot> snapshotsByCode,
) {
  final seen = <String>{};
  final markers = <BusFleetMarker>[];

  for (final route in routes) {
    final routeVehicle = route.routeVehicle;
    final code = normalizeRouteCode(
      routeVehicle.code.isNotEmpty ? routeVehicle.code : route.code,
    );
    if (code.isEmpty || !seen.add(code)) continue;
    final snapshot = snapshotsByCode[code];
    if (snapshot == null || !snapshot.hasPosition) continue;

    markers.add(
      BusFleetMarker(
        code: code,
        title: route.displayTitle,
        subtitle: (() {
          final vehicleLabel = routeVehicle.displayLabel;
          return vehicleLabel.isNotEmpty ? vehicleLabel : snapshot.assetName;
        })(),
        status: snapshot.status,
        speed: snapshot.speed,
        updatedAt: snapshot.updatedAt,
        latitude: snapshot.latitudeValue ?? 0,
        longitude: snapshot.longitudeValue ?? 0,
      ),
    );
  }

  return markers;
}

String normalizeRouteCode(String value) {
  return value.trim().toUpperCase();
}
