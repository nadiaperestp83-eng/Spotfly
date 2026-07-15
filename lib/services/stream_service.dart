import 'dart:async';
import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'yt_client_provider.dart';
import 'package:harmonymusic/models/audio_model.dart';

class StreamProvider {
  final bool playable;
  final List<Audio>? audioFormats;
  final String statusMSG;

  StreamProvider({required this.playable, this.audioFormats, this.statusMSG = ""});

  static Future<StreamProvider> fetch(String videoId) async {
    final yt = YtClientProvider.create();
    
    try {
      final res = await yt.videos.streamsClient.getManifest(videoId)
          .timeout(const Duration(seconds: 10));
      
      final audio = res.audioOnly;
      
      if (audio.isEmpty) {
        return StreamProvider(playable: false, statusMSG: "No audio streams found");
      }

      return StreamProvider(
          playable: true,
          statusMSG: "OK",
          audioFormats: audio
              .map((e) => Audio(
                  // CORREÇÃO 1: e.tag já é o int (itag), não precisa de .value
                  itag: e.tag, 
                  // CORREÇÃO 2: Comparação direta com o tipo da biblioteca (AudioCodec.aac)
                  audioCodec: e.audioCodec == AudioCodec.aac ? Codec.mp4a : Codec.opus,
                  bitrate: e.bitrate.bitsPerSecond,
                  duration: 0,
                  loudnessDb: 0.0,
                  url: e.url.toString(),
                  size: e.size.totalBytes))
              .toList());
    } on TimeoutException {
      return StreamProvider(playable: false, statusMSG: "Network timeout");
    } catch (e) {
      if (e is SocketException) {
        return StreamProvider(playable: false, statusMSG: "networkError");
      } else if (e is VideoUnplayableException) {
        return StreamProvider(playable: false, statusMSG: "Song is unplayable");
      } else if (e is VideoRequiresPurchaseException) {
        return StreamProvider(playable: false, statusMSG: "Song requires purchase");
      } else if (e is VideoUnavailableException) {
        return StreamProvider(playable: false, statusMSG: "Song is unavailable");
      } else if (e is YoutubeExplodeException) {
        return StreamProvider(playable: false, statusMSG: e.message);
      } else {
        return StreamProvider(playable: false, statusMSG: "Error: ${e.toString()}");
      }
    }
  }

  Audio? get highestQualityAudio =>
      audioFormats?.firstWhere((item) => item.itag == 251 || item.itag == 140,
          orElse: () => audioFormats!.first);

  Audio? get highestBitrateMp4aAudio =>
      audioFormats?.firstWhere((item) => item.itag == 140 || item.itag == 139,
          orElse: () => audioFormats!.first);

  Audio? get highestBitrateOpusAudio =>
      audioFormats?.firstWhere((item) => item.itag == 251 || item.itag == 250,
          orElse: () => audioFormats!.first);

  Audio? get lowQualityAudio =>
      audioFormats?.firstWhere((item) => item.itag == 249 || item.itag == 139,
          orElse: () => audioFormats!.first);

  Map<String, dynamic> get hmStreamingData {
    return {
      "playable": playable,
      "statusMSG": statusMSG,
      "lowQualityAudio": lowQualityAudio?.toJson(),
      "highQualityAudio": highestQualityAudio?.toJson()
    };
  }
}
