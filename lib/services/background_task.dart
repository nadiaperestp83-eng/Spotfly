import 'package:flutter/services.dart';
import 'package:harmonymusic/services/stream_service.dart';
import 'package:harmonymusic/utils/helper.dart';

/// Ponto único de resolução de URL de streaming — 100% on-device via
/// `youtube_explode_dart`, mesma técnica usada pela Musify. Não há mais
/// nenhum backend/proxy no caminho do áudio: o app extrai a URL direto
/// do googlevideo.com e o `just_audio` baixa direto do Google.
Future<Map<String, dynamic>> getStreamInfo(String songId, dynamic token) async {
  if (songId.substring(0, 4) == "MPED") {
    songId = songId.substring(4);
  }
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);

  printINFO("🎧 Extraindo stream on-device para $songId");
  final playerResponse = await StreamProvider.fetch(songId);
  return playerResponse.hmStreamingData;
}
