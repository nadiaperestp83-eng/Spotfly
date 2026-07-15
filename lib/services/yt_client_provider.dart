import 'dart:io';

import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as io_client;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Cria instâncias de YoutubeExplode com suporte a proxy configurável
class YtClientProvider {
  static String get _proxyAddress =>
      (Hive.box("AppPrefs").get("proxyAddress") ?? "") as String;

  static bool get _proxyEnabled =>
      (Hive.box("AppPrefs").get("proxyEnabled") ?? false) as bool;

  static YoutubeExplode create() {
    if (!_proxyEnabled || _proxyAddress.trim().isEmpty) {
      return YoutubeExplode();
    }

    try {
      final address = _proxyAddress.trim();
      final httpClient = HttpClient();
      
      // Corrigindo a aplicação do proxy e do callback
      httpClient.findProxy = (uri) => "PROXY $address";
      httpClient.badCertificateCallback = (cert, host, port) => true;
      
      final baseClient = io_client.IOClient(httpClient);
      
      // Passando o cliente customizado corretamente
      return YoutubeExplode(baseClient);
    } catch (_) {
      return YoutubeExplode();
    }
  }
}
