import 'package:rhttp/rhttp.dart';
import 'package:http/http.dart' as http;

class HttpService {
  static final http.Client client = RhttpCompatibleClient.createSync();
}
