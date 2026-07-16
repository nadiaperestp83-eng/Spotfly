import 'package:flutter/services.dart';
import 'package:harmonymusic/services/stream_service.dart';
import 'package:harmonymusic/services/piped_stream_resolver.dart';

/// Ponto único de resolução de URL de streaming — usado por QUALQUER
/// música tocada no app (Search, Home, playlists, inclusive as
/// sincronizadas da sua conta Piped, já que todas usam o mesmo videoId
/// do YouTube por trás).
///
/// Ordem de tentativa:
/// 1) 100% on-device via `youtube_explode_dart` (já com proxy + fallback
///    direto embutidos em StreamProvider).
/// 2) Se isso falhar (rate limit, 403, timeout — os erros que apareciam
///    na tela), tenta resolver o mesmo videoId via instâncias públicas
///    do Piped.
///
/// Isso NÃO mexe na Search: a Search só lista resultados (via
/// MusicServices.search / SearchCoordinator) — este arquivo só entra em
/// ação no momento de TOCAR uma música específica, depois que ela já foi
/// encontrada e escolhida.
Future<Map<String, dynamic>> getStreamInfo(
  String songId,
  dynamic token,
) async {
  if (songId.substring(0, 4) == "MPED") {
    songId = songId.substring(4);
  }
  
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);

  final playerResponse = await StreamProvider.fetch(songId);
  if (playerResponse.playable) {
    return playerResponse.hmStreamingData;
  }

  // YouTube direto falhou (proxy + direto já tentados dentro de
  // StreamProvider) — última tentativa via Piped antes de desistir.
  final pipedResult = await PipedStreamResolver.resolveAudio(songId);
  if (pipedResult != null) {
    return pipedResult;
  }

  // Nada funcionou — devolve o erro original do YouTube pra UI, que já
  // sabe mostrar essas mensagens (networkError, Network timeout etc.).
  return playerResponse.hmStreamingData;
}
