import 'package:http/http.dart' as http;

class DelegatingHttpClient extends http.BaseClient {
  DelegatingHttpClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
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
