import 'dart:io';

import 'package:hive/hive.dart';
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
      httpClient.findProxy = (uri) => "PROXY $address";
      httpClient.badCertificateCallback = (cert, host, port) => true;

      final baseClient = io_client.IOClient(httpClient);

      // Cria um YoutubeHttpClient com o client personalizado
      // (youtube_explode_dart 2.5.3: parâmetro posicional, não nomeado)
      final ytHttpClient = YoutubeHttpClient(baseClient);
      return YoutubeExplode(ytHttpClient);
    } catch (_) {
      // Fallback para cliente padrão (sem proxy)
      return YoutubeExplode();
    }
  }
}
