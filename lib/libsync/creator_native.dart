import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client createLibSyncClient() => IOClient(
  HttpClient()
    ..badCertificateCallback = (X509Certificate cert, String host, int port) =>
        true,
);
