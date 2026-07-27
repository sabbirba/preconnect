import 'package:http/http.dart' as http;

final http.Client _sharedStubClient = http.Client();

http.Client createLibSyncClient() => _sharedStubClient;
