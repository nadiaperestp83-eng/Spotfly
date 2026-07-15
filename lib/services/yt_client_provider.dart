import 'dart:io';

import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as io_client;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Cria instâncias de YoutubeExplode com suporte a proxy configurável
/// pelo usuário (Settings > Proxy). Isso ajuda a contornar o
/// "rate limiting" que o YouTube aplica quando muitas requisições saem
/// do mesmo IP (erro comum em rede móvel/CGNAT) — mesma técnica que a
/// Musify oferece nas configurações dela.
class YtClientProvider {
  /// host:porta, ex: "123.45.67.89:8080". Vazio = sem proxy.
  static String get _proxyAddress =>
      (Hive.box("AppPrefs").get("proxyAddress") ?? "") as String;

  static bool get _proxyEnabled =>
      (Hive.box("AppPrefs").get("proxyEnabled") ?? false) as bool;

  /// Cria um novo YoutubeExplode. Se o proxy estiver ativado e configurado
  /// nas Settings, todas as requisições HTTP passam por ele.
  static YoutubeExplode create() {
    if (!_proxyEnabled || _proxyAddress.trim().isEmpty) {
      return YoutubeExplode();
    }

    try {
      final address = _proxyAddress.trim();
      final httpClient = HttpClient()
        ..findProxy = (uri) => "PROXY $address;"
        ..badCertificateCallback = (cert, host, port) => true;
      final baseClient = io_client.IOClient(httpClient);
      return YoutubeExplode(YoutubeHttpClient(baseClient));
    } catch (_) {
      // Proxy mal configurado: cai pro modo sem proxy em vez de travar o app.
      return YoutubeExplode();
    }
  }
}
