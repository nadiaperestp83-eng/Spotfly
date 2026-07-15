import 'dart:io';

import 'package:hive/hive.dart';
import 'package:http/io_client.dart' as io_client;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YtClientProvider {
  static String get _proxyAddress =>
      (Hive.box("AppPrefs").get("proxyAddress") ?? "") as String;

  static bool get _proxyEnabled =>
      (Hive.box("AppPrefs").get("proxyEnabled") ?? false) as bool;

  static YoutubeExplode create() {
    // 1. Validação: se não estiver ativado ou endereço vazio, retorna padrão
    if (!_proxyEnabled || _proxyAddress.trim().isEmpty) {
      return YoutubeExplode();
    }

    try {
      final address = _proxyAddress.trim();
      final httpClient = HttpClient();
      
      // Configuração do Proxy
      httpClient.findProxy = (uri) => "PROXY $address";
      httpClient.badCertificateCallback = (cert, host, port) => true;

      // Cria o cliente HTTP
      final baseClient = io_client.IOClient(httpClient);

      // 2. CORREÇÃO: O construtor do YoutubeExplode usa 'httpClient' como parâmetro nomeado
      return YoutubeExplode(httpClient: YoutubeHttpClient(baseClient));
    } catch (_) {
      // Fallback: se algo falhar, retorna o cliente padrão
      return YoutubeExplode();
    }
  }
}
