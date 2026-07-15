import 'package:flutter/services.dart';
import 'package:harmonymusic/services/stream_service.dart';
import 'package:harmonymusic/services/yt_client_provider.dart';
import 'package:harmonymusic/utils/helper.dart';

/// Ponto único de resolução de URL de streaming — 100% on-device via
/// `youtube_explode_dart`, mesma técnica usada pela Musify. Não há mais
/// nenhum backend/proxy fixo no caminho do áudio: o app extrai a URL
/// direto do googlevideo.com (opcionalmente através do proxy configurado
/// pelo usuário nas Settings) e o `just_audio` baixa direto do Google.
///
/// Roda dentro de uma Isolate separada (Isolate.run), então [proxyConfig]
/// precisa ser passado já pronto pelo chamador (que tem acesso ao Hive na
/// isolate principal) — não dá pra ler o Hive aqui dentro.
Future<Map<String, dynamic>> getStreamInfo(
  String songId,
  dynamic token, {
  ProxyConfig proxyConfig = const ProxyConfig(),
}) async {
  if (songId.substring(0, 4) == "MPED") {
    songId = songId.substring(4);
  }
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);

  printINFO(
      "🎧 Extraindo stream on-device para $songId (proxy: ${proxyConfig.enabled ? '${proxyConfig.host}:${proxyConfig.port}' : 'desativado'})");
  final playerResponse =
      await StreamProvider.fetch(songId, proxyConfig: proxyConfig);
  return playerResponse.hmStreamingData;
}
