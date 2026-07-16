import 'dart:async';
import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'yt_client_provider.dart';
import 'proxy_config.dart';
import 'package:harmonymusic/models/audio_model.dart';

class StreamProvider {
  final bool playable;
  final List<Audio>? audioFormats;
  final String statusMSG;

  StreamProvider({required this.playable, this.audioFormats, this.statusMSG = ""});

  /// Ponto de entrada público. Mantém o nome antigo `fetch` para não quebrar
  /// quem já chama esse método, mas agora delega para o fallback automático.
  static Future<StreamProvider> fetch(String videoId) => fetchWithFallback(videoId);

  /// Tenta buscar o manifesto via proxy (se houver um configurado); se
  /// falhar por motivo de rede (SocketException, TimeoutException ou
  /// HTTP 403), tenta de novo imediatamente com conexão direta. Só
  /// propaga erro pra UI se as duas tentativas falharem.
  ///
  /// Sem proxy configurado (ProxyConfig.isConfigured == false), pula
  /// direto pra UMA ÚNICA tentativa direta com o timeout mais longo —
  /// evita gastar 8s à toa numa "tentativa de proxy" que na prática já
  /// é idêntica à tentativa direta que viria a seguir.
  static Future<StreamProvider> fetchWithFallback(String videoId) async {
    if (!ProxyConfig.isConfigured) {
      final directYt = YtClientProvider.createDefaultClient();
      final directAttempt = await _tryFetch(
        directYt,
        videoId,
        timeout: ProxyConfig.directTimeout,
      );
      return directAttempt.result ??
          directAttempt.errorResult ??
          StreamProvider(playable: false, statusMSG: "networkError");
    }

    // 1ª tentativa: via proxy
    final proxyYt = YtClientProvider.createProxyClient();
    final proxyAttempt = await _tryFetch(
      proxyYt,
      videoId,
      timeout: ProxyConfig.proxyTimeout,
    );

    if (proxyAttempt.result != null) {
      return proxyAttempt.result!;
    }

    if (!proxyAttempt.shouldFallback) {
      // Erro "definitivo" (ex: vídeo indisponível) — não faz sentido
      // tentar de novo sem proxy, o problema não é o proxy.
      return proxyAttempt.errorResult!;
    }

    // 2ª tentativa: conexão direta (sem proxy)
    final directYt = YtClientProvider.createDefaultClient();
    final directAttempt = await _tryFetch(
      directYt,
      videoId,
      timeout: ProxyConfig.directTimeout,
    );

    if (directAttempt.result != null) {
      return directAttempt.result!;
    }

    // Falhou nas duas — devolve o erro da tentativa direta para a UI.
    return directAttempt.errorResult ??
        StreamProvider(playable: false, statusMSG: "networkError");
  }

  /// Executa uma tentativa de busca do manifesto num client específico.
  static Future<_FetchAttempt> _tryFetch(
    YoutubeExplode yt,
    String videoId, {
    required Duration timeout,
  }) async {
    try {
      final res = await yt.videos.streamsClient
          .getManifest(videoId)
          .timeout(timeout);

      final audio = res.audioOnly;

      if (audio.isEmpty) {
        return _FetchAttempt.error(
          StreamProvider(playable: false, statusMSG: "No audio streams found"),
          shouldFallback: false,
        );
      }

      final streamProvider = StreamProvider(
        playable: true,
        statusMSG: "OK",
        audioFormats: audio
            .map((e) => Audio(
                itag: e.tag,
                audioCodec: _isAacContainer(e) ? Codec.mp4a : Codec.opus,
                bitrate: e.bitrate.bitsPerSecond,
                duration: 0,
                loudnessDb: 0.0,
                url: e.url.toString(),
                size: e.size.totalBytes))
            .toList(),
      );

      return _FetchAttempt.success(streamProvider);
    } on TimeoutException {
      return _FetchAttempt.error(
        StreamProvider(playable: false, statusMSG: "Network timeout"),
        shouldFallback: true,
      );
    } on SocketException {
      return _FetchAttempt.error(
        StreamProvider(playable: false, statusMSG: "networkError"),
        shouldFallback: true,
      );
    } catch (e) {
      if (_is403Forbidden(e)) {
        return _FetchAttempt.error(
          StreamProvider(playable: false, statusMSG: "networkError"),
          shouldFallback: true,
        );
      } else if (e is VideoUnplayableException) {
        return _FetchAttempt.error(
          StreamProvider(playable: false, statusMSG: "Song is unplayable"),
          shouldFallback: false,
        );
      } else if (e is VideoRequiresPurchaseException) {
        return _FetchAttempt.error(
          StreamProvider(playable: false, statusMSG: "Song requires purchase"),
          shouldFallback: false,
        );
      } else if (e is VideoUnavailableException) {
        return _FetchAttempt.error(
          StreamProvider(playable: false, statusMSG: "Song is unavailable"),
          shouldFallback: false,
        );
      } else if (e is YoutubeExplodeException) {
        return _FetchAttempt.error(
          StreamProvider(playable: false, statusMSG: e.message),
          shouldFallback: true,
        );
      } else {
        return _FetchAttempt.error(
          StreamProvider(playable: false, statusMSG: "Error: ${e.toString()}"),
          shouldFallback: true,
        );
      }
    } finally {
      yt.close();
    }
  }

  /// Detecta erro HTTP 403 na mensagem/exception lançada pela lib
  /// (nem sempre exposta como um tipo dedicado).
  static bool _is403Forbidden(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains("403") || msg.contains("forbidden");
  }

  /// Infere se o stream é AAC (container mp4/m4a) em vez de Opus (webm),
  /// já que a lib não expõe mais uma classe/enum `AudioCodec`.
  static bool _isAacContainer(AudioOnlyStreamInfo e) {
    final containerName = e.container.name.toLowerCase();
    return containerName.contains('mp4') || containerName.contains('m4a');
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

class _FetchAttempt {
  final StreamProvider? result;
  final StreamProvider? errorResult;
  final bool shouldFallback;

  _FetchAttempt.success(this.result)
      : errorResult = null,
        shouldFallback = false;

  _FetchAttempt.error(this.errorResult, {required this.shouldFallback})
      : result = null;
}
