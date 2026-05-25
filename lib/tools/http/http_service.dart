import 'package:http/http.dart' as http;

import 'http_client.dart';

class HttpService {
  static final http.Client client = createHttpClient();
}
