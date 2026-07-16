import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../features/search/data/sources/piped_instances.dart';
import '../models/audio_model.dart';
import '../utils/helper.dart';

/// Fallback de streaming via instâncias públicas do Piped, usado pelo
/// player quando a extração direta via youtube_explode_dart falha
/// (rate limit, 403, timeout — os mesmos erros que apareciam na tela).
///
/// Independente do PipedSource usado pela busca/Home (lib/features/
/// search/data/sources/piped_source.dart) — implementado à parte de
/// propósito, pra não arriscar nada que já está funcionando na Search
/// (SearchCoordinator/PipedSource não são tocados aqui).
///
/// Como funciona: recebe o mesmo videoId que já ia pro
/// youtube_explode_dart, pergunta pra cada instância pública do Piped
/// (mesma lista da busca) até uma responder, e monta um mapa no MESMO
/// formato que StreamProvider.hmStreamingData já produzia — assim o
/// resto do pipeline (audio_handler.dart, cache, seleção de qualidade)
/// funciona sem precisar saber de onde a música veio.
///
/// O endpoint /streams/:videoId do Piped é público e não-autenticado —
/// a própria documentação oficial (docs.piped.video/docs/api-
/// documentation) desaconselha explicitamente mandar header
/// Authorization nesses endpoints, então nenhuma chave é usada aqui.
class PipedStreamResolver {
  static const _timeout = Duration(seconds: 8);

  /// Retorna um mapa no formato de StreamProvider.hmStreamingData, ou
  /// `null` se nenhuma instância do Piped conseguiu resolver o áudio.
  static Future<Map<String, dynamic>?> resolveAudio(String videoId) async {
    for (final instance in pipedInstances) {
      try {
        final uri = Uri.parse('$instance/streams/$videoId');
        final response = await http.get(uri).timeout(_timeout);
        if (response.statusCode != 200) continue;

        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final audioStreams = body['audioStreams'] as List<dynamic>? ?? [];
        if (audioStreams.isEmpty) continue;

        final audios = audioStreams
            .map(_audioFromPipedStream)
            .whereType<Audio>()
            .toList()
          ..sort((a, b) => b.bitrate.compareTo(a.bitrate));

        if (audios.isEmpty) continue;

        printINFO("🎵 Stream resolvido via Piped ($instance) para $videoId");

        return {
          "playable": true,
          "statusMSG": "OK",
          "lowQualityAudio": audios.last.toJson(),
          "highQualityAudio": audios.first.toJson(),
        };
      } catch (e) {
        printERROR("⚠️ Instância Piped falhou ($instance): $e");
        continue;
      }
    }
    return null;
  }

  static Audio? _audioFromPipedStream(dynamic item) {
    try {
      final map = item as Map<String, dynamic>;
      final url = map['url'] as String?;
      if (url == null || url.isEmpty) return null;

      final mimeType = (map['mimeType'] as String? ?? '').toLowerCase();
      final codecField = (map['codec'] as String? ?? '').toLowerCase();
      final isAac = mimeType.contains('mp4') ||
          mimeType.contains('m4a') ||
          codecField.contains('mp4a');

      return Audio(
        itag: (map['itag'] as num?)?.toInt() ?? 0,
        audioCodec: isAac ? Codec.mp4a : Codec.opus,
        bitrate: (map['bitrate'] as num?)?.toInt() ?? 0,
        duration: 0,
        loudnessDb: 0.0,
        url: url,
        size: (map['contentLength'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}
