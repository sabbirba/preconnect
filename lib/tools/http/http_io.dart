import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:cupertino_http/cupertino_http.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:preconnect/tools/http/http_utils.dart';

final http.Client _sharedClient = _nativeClient();

http.Client createHttpClient() => _sharedClient;

http.Client _nativeClient() {
  if (!Platform.environment.containsKey('FLUTTER_TEST')) {
    try {
      if (Platform.isIOS || Platform.isMacOS) return _cupertinoClient();
      if (Platform.isAndroid) return _cronetClient();
    } catch (_) {}
  }
  return IOClient(HttpClient()..idleTimeout = const Duration(seconds: 60));
}

http.Client _cupertinoClient() {
  final config = URLSessionConfiguration.ephemeralSessionConfiguration()
    ..httpShouldSetCookies = false
    ..httpCookieAcceptPolicy =
        NSHTTPCookieAcceptPolicy.NSHTTPCookieAcceptPolicyNever
    ..requestCachePolicy =
        NSURLRequestCachePolicy.NSURLRequestReloadIgnoringLocalCacheData
    ..timeoutIntervalForRequest = const Duration(minutes: 5);
  return CupertinoClient.fromSessionConfiguration(config);
}

http.Client _cronetClient() {
  final storage = Directory('${Directory.systemTemp.path}/cronet')
    ..createSync(recursive: true);
  final engine = CronetEngine.build(
    cacheMode: CacheMode.diskNoHttp,
    cacheMaxSize: 1024 * 1024,
    storagePath: storage.path,
    enableHttp2: true,
    enableQuic: true,
    enableBrotli: true,
    quicHints: [for (final host in HttpUtils.connectionHosts) (host, 443, 443)],
    enableStaleDns: true,
    useStaleOnNameNotResolved: true,
    persistHostCache: true,
  );
  return CronetClient.fromCronetEngine(engine, closeEngine: true);
}
