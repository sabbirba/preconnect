import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

final http.Client _sharedLibSyncClient = IOClient(
  HttpClient()
    ..badCertificateCallback = (X509Certificate cert, String host, int port) =>
        true,
);

http.Client createLibSyncClient() => _sharedLibSyncClient;
