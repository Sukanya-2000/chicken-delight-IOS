import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

const _trustedRmsHosts = {'rms-backend-v1.vercel.app'};

http.Client createRmsHttpClient() {
  final client = HttpClient()
    ..badCertificateCallback = (certificate, host, port) {
      return _trustedRmsHosts.contains(host);
    };

  return IOClient(client);
}
