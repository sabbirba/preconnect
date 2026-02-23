import 'package:geolocator/geolocator.dart';

Future<({double lat, double lon})?> tryGetLiveLocation({
  void Function(String message)? onInfo,
  void Function(String message)? onFailure,
}) async {
  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      onFailure?.call('Location off. Using default times.');
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      onInfo?.call('Need location for live prayer times.');
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      onFailure?.call('Location denied. Using default times.');
      return null;
    }
    if (permission == LocationPermission.deniedForever) {
      onFailure?.call('Location blocked. Using default times.');
      return null;
    }

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 3),
      ),
    );
    return (lat: pos.latitude, lon: pos.longitude);
  } catch (_) {
    onFailure?.call('Location failed. Using default times.');
    return null;
  }
}
