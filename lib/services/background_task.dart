import 'dart:async';
import 'dart:convert';
import 'dart:core';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:harmonymusic/services/constant.dart';
import 'package:harmonymusic/services/stream_service.dart';
import 'package:harmonymusic/utils/helper.dart';

//Not in use for now
// Future<List<String>?> getSongUrlFromPiped(String songId,
//     {String defaultUrl = "https://pipedapi.kavin.rocks"}) async {
//   try {
//     if (songId.substring(0, 4) == "MPED") {
//       songId = songId.substring(4);
//     }
//     final response = await Dio().get("$defaultUrl/streams/$songId");
//     if (response.statusCode == 200) {
//       final audioStream = response.data["audioStreams"] as List;
//       final x =
//           audioStream.firstWhere((item) => (item['itag'].toString() == "251"));

//       final y =
//           audioStream.firstWhere((item) => (item['itag'].toString() == "251"));

//       return [y['url'], x['url']];
//     } else {
//       return null;
//     }
//   } catch (e) {
//     return null;
//   }
// }

/// Ponto único de resolução de URL de streaming.
///
/// Estratégia:
///   1) Tenta o endpoint leve `/get_song_url` no Railway (rápido, baixo
///      custo de CPU no servidor, mas não decifra `signatureCipher`).
///   2) Se o Railway estiver fora do ar, retornar erro de rede, ou
///      informar que a música precisa de decifragem (`cipher_required...`
///      / `playable: false`), cai automaticamente para a extração local
///      via `youtube_explode_dart` (que sabe decifrar assinaturas).
///
/// Em nenhum dos dois caminhos o Railway chega a transportar bytes de
/// áudio: ele só devolve a URL final do googlevideo.com.
Future<Map<String, dynamic>> getStreamInfo(String songId, dynamic token) async {
  if (songId.substring(0, 4) == "MPED") {
    songId = songId.substring(4);
  }
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);

  final fromProxy = await _getStreamInfoFromProxy(songId);
  if (fromProxy != null) {
    printINFO("✅ URL de streaming obtida via proxy Railway ($songId)");
    return fromProxy;
  }

  printINFO("↩️ Fallback: extraindo stream localmente via youtube_explode_dart ($songId)");
  final playerResponse = await StreamProvider.fetch(songId);
  return playerResponse.hmStreamingData;
}

Future<Map<String, dynamic>?> _getStreamInfoFromProxy(String videoId) async {
  try {
    final uri = Uri.parse('$proxyBaseUrl/get_song_url')
        .replace(queryParameters: {'videoId': videoId});
    final response = await http.get(uri).timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      printERROR("❌ Proxy get_song_url retornou ${response.statusCode}");
      return null;
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final playable = data['playable'] == true;
    final hasHighAudio = data['highQualityAudio'] != null;

    if (!playable || !hasHighAudio) {
      // Servidor sinalizou que não conseguiu extrair (ex: signatureCipher).
      // Retornar null aqui aciona o fallback local automaticamente.
      printERROR("⚠️ Proxy não conseguiu extrair URL (${data['statusMSG']}), usando fallback local.");
      return null;
    }

    return data;
  } on TimeoutException {
    printERROR("⏱️ Timeout no proxy get_song_url, usando fallback local.");
    return null;
  } catch (e) {
    printERROR("❌ Erro ao consultar proxy get_song_url: $e");
    return null;
  }
}
