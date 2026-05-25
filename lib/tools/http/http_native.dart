import 'package:http/http.dart' as http;
import 'package:rhttp/rhttp.dart';

http.Client createHttpClient() {
  return RhttpCompatibleClient.createSync();
}
