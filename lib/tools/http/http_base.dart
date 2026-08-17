import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:preconnect/tools/http/doh_resolver.dart';

class DelegatingHttpClient extends http.BaseClient {
  DelegatingHttpClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final host = request.url.host;
    if (host.contains('preconnect.app') ||
        host.contains('bracu.ac.bd') ||
        host.contains('github.com') ||
        host.contains('githubusercontent.com')) {
      unawaited(DohResolver.resolve(host));
    }
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
  }
}

final http.Client _sharedHttpClient = http.Client();
final http.Client _sharedDelegatingClient = DelegatingHttpClient(
  _sharedHttpClient,
);

http.Client createSharedHttpClient() {
  return _sharedDelegatingClient;
}
