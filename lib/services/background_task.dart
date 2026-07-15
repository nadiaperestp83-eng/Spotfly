import 'package:flutter/services.dart';
import 'package:harmonymusic/services/stream_service.dart';

/// Ponto único de resolução de URL de streaming — 100% on-device via
/// `youtube_explode_dart`. O app extrai a URL direto do googlevideo.com
/// (usando o proxy configurado no YtClientProvider, se estiver ativado).
Future<Map<String, dynamic>> getStreamInfo(
  String songId,
  dynamic token,
) async {
  if (songId.substring(0, 4) == "MPED") {
    songId = songId.substring(4);
  }
  
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);

  final playerResponse = await StreamProvider.fetch(songId);
  
  return playerResponse.hmStreamingData;
}
