import 'dart:io';
import 'package:hive/hive.dart';
import 'package:http/io_client.dart' as io_client;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Cria instâncias de YoutubeExplode com suporte a proxy configurável.
/// Atualizado para compatibilidade com a versão 3.1.0+ do youtube_explode_dart.
class YtClientProvider {
  static String get _proxyAddress =>
      (Hive.box("AppPrefs").get("proxyAddress") ?? "") as String;

  static bool get _proxyEnabled =>
      (Hive.box("AppPrefs").get("proxyEnabled") ?? false) as bool;

  static YoutubeExplode create() {
    final bool enabled = _proxyEnabled;
    final String address = _proxyAddress.trim();

    // Se o proxy não estiver ativo, retornamos o cliente padrão
    if (!enabled || address.isEmpty) {
      return YoutubeExplode();
    }

    try {
      final httpClient = HttpClient();
      
      // Configuração do proxy
      httpClient.findProxy = (uri) => "PROXY $address";
      httpClient.badCertificateCallback = (cert, host, port) => true;

      final baseClient = io_client.IOClient(httpClient);

      // CORREÇÃO: Na versão 3.1.0, o construtor exige o parâmetro nomeado 'httpClient'
      return YoutubeExplode(httpClient: YoutubeHttpClient(baseClient));
    } catch (_) {
      // Segurança extra em caso de erro na configuração
      return YoutubeExplode();
    }
  }
}
