import 'package:http/http.dart' as http;

final http.Client _sharedClient = http.Client();

http.Client createHttpClient() => _sharedClient;
