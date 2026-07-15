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

      // Aplica o proxy HTTP e ignora certificados inválidos (útil para proxies)
      httpClient.findProxy = (uri) => "PROXY $address";
      httpClient.badCertificateCallback = (cert, host, port) => true;

      // Cria um IOClient a partir do HttpClient configurado
      final baseClient = io_client.IOClient(httpClient);

      // Converte para um YoutubeHttpClient, que é o tipo esperado pelo YoutubeExplode
      final ytHttpClient = YoutubeHttpClient.fromClient(baseClient);

      // Retorna o YoutubeExplode com o cliente personalizado
      return YoutubeExplode(ytHttpClient);
    } catch (_) {
      // Em caso de erro, fallback para o cliente padrão (sem proxy)
      return YoutubeExplode();
    }
  }
}
