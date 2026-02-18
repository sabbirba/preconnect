import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/api_client.dart';

class PaymentService {
  static final PaymentService _instance = PaymentService._internal();
  factory PaymentService() => _instance;
  PaymentService._internal();

  final ApiClient _client = ApiClient();

  static const String _cacheKey = 'SemesterPaymentInfo';

  Future<String?> fetchPaymentInfo({bool fromGet = false}) async {
    final asyncPrefs = SharedPreferencesAsync();
    final String? id = await asyncPrefs.getString('id');
    if (id == null || id.isEmpty) {
      if (fromGet) return null;
      return getPaymentInfo(fromFetch: true);
    }

    final url = ApiConfig.paymentUrl(id);

    return _client.fetchWithFallback<String>(
      url: url,
      fromGet: fromGet,
      cacheResponse: (response) async {
        await asyncPrefs.setString(_cacheKey, response.body);
      },
      readCache: ({required bool fromFetch}) =>
          getPaymentInfo(fromFetch: fromFetch),
    );
  }

  Future<String?> getPaymentInfo({bool fromFetch = false}) async {
    final prefsWithCache = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: <String>{_cacheKey},
      ),
    );

    if (fromFetch) await prefsWithCache.reloadCache();

    final String paymentInfo = prefsWithCache.getString(_cacheKey) ?? '';
    if (paymentInfo == '') {
      if (fromFetch) return null;
      return await fetchPaymentInfo(fromGet: true);
    }
    return paymentInfo;
  }
}
