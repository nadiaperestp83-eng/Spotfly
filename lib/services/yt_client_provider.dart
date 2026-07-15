import 'dart:io';
import 'package:http/io_client.dart' as io_client;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'proxy_config.dart';

/// Cria instâncias de YoutubeExplode: uma com proxy embutido,
/// outra "limpa" (conexão direta) para uso como fallback.
class YtClientProvider {
  /// Cliente configurado com o proxy fixo definido em ProxyConfig.
  static YoutubeExplode createProxyClient() {
    try {
      final HttpClient httpClient = HttpClient();

      // Atribuições diretas (sem cascade) para evitar qualquer
      // ambiguidade de parsing/formatação.
      httpClient.findProxy = (Uri uri) => "PROXY ${ProxyConfig.proxyAddress}";
      httpClient.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
      httpClient.connectionTimeout = ProxyConfig.proxyTimeout;

      final baseClient = io_client.IOClient(httpClient);
      return YoutubeExplode(httpClient: YoutubeHttpClient(baseClient));
    } catch (_) {
      // Se a própria configuração do proxy falhar, já devolve o direto.
      return createDefaultClient();
    }
  }

  /// Cliente "limpo", sem proxy — usado no fallback.
  static YoutubeExplode createDefaultClient() {
    return YoutubeExplode();
  }

  /// Alias de compatibilidade com chamadas antigas (ex: music_service.dart).
  /// Mantém o comportamento anterior: tenta o proxy por padrão.
  /// Se preferir que TODO o app use o fallback automático, troque os
  /// lugares que chamam `create()` para usar StreamProvider.fetchWithFallback
  /// (ou exponha aqui um client "smart" — me avise se quiser isso).
  static YoutubeExplode create() {
    return createProxyClient();
  }
}
