import 'dart:convert';

import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';

class BusTrackerService {
  BusTrackerService._internal();
  static final BusTrackerService _instance = BusTrackerService._internal();
  factory BusTrackerService() => _instance;

  final ApiClient _client = ApiClient();

  Future<Map<String, dynamic>?> fetchLastData() async {
    try {
      final url = ApiConfig.busTrackerLastDataUrl;
      if (url.isEmpty) return null;
      final response = await _client.publicGet(
        url,
        acceptedStatusCodes: <int>{200},
      );
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    } catch (_) {}
    return null;
  }
}
