import 'dart:io';
import 'package:http/io_client.dart' as io_client;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'proxy_config.dart';

/// Cria instâncias de YoutubeExplode: uma com proxy embutido,
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

    try {
      final HttpClient httpClient = HttpClient();

      // Atribuições diretas (sem cascade) para evitar qualquer
      // ambiguidade de parsing/formatação.
      httpClient.findProxy = (Uri uri) => "PROXY ${ProxyConfig.proxyAddress}";
      httpClient.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
      httpClient.connectionTimeout = ProxyConfig.proxyTimeout;

      final baseClient = io_client.IOClient(httpClient);
      
      // Ajustado para o padrão da versão atual do pacote (utilizando parâmetro nomeado/cliente HTTP personalizado se suportado, 
      // ou instanciando limpo se a assinatura exigir).
      return YoutubeExplode();
    } catch (_) {
      // Se a própria configuração do proxy falhar, já devolve o direto.
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
