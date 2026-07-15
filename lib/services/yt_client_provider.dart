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
      final httpClient = HttpClient()
        ..findProxy = (uri) => "PROXY ${ProxyConfig.proxyAddress}"
        ..badCertificateCallback = (cert, host, port) => true
        ..connectionTimeout = ProxyConfig.proxyTimeout;

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
}
