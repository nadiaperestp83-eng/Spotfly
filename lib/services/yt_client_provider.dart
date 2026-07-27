import 'dart:io';
import 'package:http/io_client.dart' as io_client;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'proxy_config.dart';

/// Cria instâncias de YoutubeExplode: uma com proxy embutido (fixo, via
/// ProxyConfig, OU um endereço dinâmico vindo de FreeProxyService),
/// outra "limpa" (conexão direta) para uso como fallback.
class YtClientProvider {
  /// Cliente configurado com o proxy fixo definido em ProxyConfig.
  /// Se nenhum proxy real estiver configurado (ProxyConfig.isConfigured
  /// == false), devolve direto o cliente sem proxy — evita perder
  /// tempo tentando resolver um host placeholder que nunca vai existir.
  static YoutubeExplode createProxyClient() {
    if (!ProxyConfig.isConfigured) {
      return createDefaultClient();
    }
    return createProxyClientFor(ProxyConfig.proxyAddress);
  }

  /// Cliente configurado com um proxy ESPECÍFICO, no formato
  /// "ip:porta" — usado tanto pelo proxy fixo (ProxyConfig) quanto pela
  /// lista de proxies públicos gratuitos (FreeProxyService), que muda a
  /// cada tentativa.
  ///
  /// CORRIGIDO: confirmado no código-fonte real do Musify
  /// (ProxyManager.dart) que o parâmetro é NOMEADO —
  /// `YoutubeExplode(httpClient: YoutubeHttpClient(ioClient))` — e não
  /// posicional como numa tentativa anterior aqui.
  static YoutubeExplode createProxyClientFor(String proxyAddress,
      {Duration? timeout}) {
    try {
      final HttpClient httpClient = HttpClient();
      httpClient.findProxy = (Uri uri) => "PROXY $proxyAddress; DIRECT";
      httpClient.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
      httpClient.connectionTimeout =
          timeout ?? ProxyConfig.proxyTimeout;

      final ioClient = io_client.IOClient(httpClient);
      return YoutubeExplode(httpClient: YoutubeHttpClient(ioClient));
    } catch (_) {
      return createDefaultClient();
    }
  }

  /// Cliente "limpo", sem proxy — usado no fallback.
  static YoutubeExplode createDefaultClient() {
    return YoutubeExplode();
  }

  /// Alias de compatibilidade com chamadas antigas.
  /// Mantém o comportamento anterior: tenta o proxy por padrão
  /// (que, sem proxy configurado, já é equivalente ao direto).
  static YoutubeExplode create() {
    return createProxyClient();
  }
}
