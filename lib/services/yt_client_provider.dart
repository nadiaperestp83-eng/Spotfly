import 'dart:io';

import 'package:hive/hive.dart';
import 'package:http/io_client.dart' as io_client;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Cria instâncias de YoutubeExplode com suporte a proxy configurável.
/// Se o proxy estiver desativado ou o endereço estiver vazio, 
/// retorna uma instância padrão sem cliente HTTP customizado.
class YtClientProvider {
  static String get _proxyAddress =>
      (Hive.box("AppPrefs").get("proxyAddress") ?? "") as String;

  static bool get _proxyEnabled =>
      (Hive.box("AppPrefs").get("proxyEnabled") ?? false) as bool;

  static YoutubeExplode create() {
    // 1. Verificação rígida: Se não estiver ativado ou endereço estiver vazio,
    // retornamos o YoutubeExplode puro (cliente padrão).
    final bool enabled = _proxyEnabled;
    final String address = _proxyAddress.trim();

    if (!enabled || address.isEmpty) {
      return YoutubeExplode();
    }

    // 2. Se passamos daqui, é porque o usuário configurou manualmente.
    try {
      final httpClient = HttpClient();
      
      // Configuração do proxy
      httpClient.findProxy = (uri) => "PROXY $address";
      httpClient.badCertificateCallback = (cert, host, port) => true;

      // Conversão para o tipo esperado pelo YoutubeExplode
      final baseClient = io_client.IOClient(httpClient);

      // Instanciação usando o argumento posicional (conforme versão 2.5.3)
      return YoutubeExplode(YoutubeHttpClient(baseClient));
    } catch (_) {
      // 3. Segurança extra: se qualquer erro ocorrer na criação do proxy,
      // forçamos o retorno do cliente padrão para evitar travamentos.
      return YoutubeExplode();
    }
  }
}
