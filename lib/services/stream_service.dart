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

  /// Ponto de entrada público. Mantém o nome antigo `fetch` para não quebrar
  /// quem já chama esse método, mas agora delega para o fallback automático.
  static Future<StreamProvider> fetch(String videoId) => fetchWithFallback(videoId);

  /// Tenta buscar o manifesto via proxy; se falhar por motivo de rede
  /// (SocketException, TimeoutException ou HTTP 403), tenta de novo
  /// imediatamente com conexão direta. Só propaga erro pra UI se as
  /// duas tentativas falharem.
  static Future<StreamProvider> fetchWithFallback(String videoId) async {
    // 1ª tentativa: via proxy
    final proxyYt = YtClientProvider.createProxyClient();
    final proxyAttempt = await _tryFetch(
      proxyYt,
      videoId,
      timeout: ProxyConfigTimeout.proxy,
    );

    if (proxyAttempt.result != null) {
      return proxyAttempt.result!;
    }

    if (!proxyAttempt.shouldFallback) {
      // Erro "definitivo" (ex: vídeo indisponível) — não faz sentido
      // tentar de novo, o problema não é o proxy.
      return proxyAttempt.errorResult!;
    }

    // 2ª tentativa: conexão direta (sem proxy)
    final directYt = YtClientProvider.createDefaultClient();
    final directAttempt = await _tryFetch(
      directYt,
      videoId,
      timeout: ProxyConfigTimeout.direct,
    );

    if (directAttempt.result != null) {
      return directAttempt.result!;
    }

    // Falhou nas duas — devolve o erro da tentativa direta para a UI.
    return directAttempt.errorResult ??
        StreamProvider(playable: false, statusMSG: "networkError");
  }

  /// Executa uma tentativa de busca do manifesto num client específico.
  /// Retorna um `_FetchAttempt` indicando sucesso, ou se deve/não deve
  /// cair no fallback.
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
                audioCodec: e.audioCodec == AudioCodec.aac ? Codec.mp4a : Codec.opus,
                bitrate: e.bitrate.bitsPerSecond,
                duration: 0,
                loudnessDb: 0.0,
                url: e.url.toString(),
                size: e.size.totalBytes))
            .toList(),
      );

      return _FetchAttempt.success(streamProvider);
    } on TimeoutException {
      // Timeout -> aciona fallback
      return _FetchAttempt.error(
        StreamProvider(playable: false, statusMSG: "Network timeout"),
        shouldFallback: true,
      );
    } on SocketException {
      // Sem conexão / proxy caiu -> aciona fallback
      return _FetchAttempt.error(
        StreamProvider(playable: false, statusMSG: "networkError"),
        shouldFallback: true,
      );
    } catch (e) {
      if (_is403Forbidden(e)) {
        // Proxy bloqueado/banido pelo YouTube -> aciona fallback
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
        // Erro genérico da lib: não necessariamente é o proxy,
        // mas por segurança tentamos o fallback direto também.
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

  /// Detecta erro HTTP 403 dentro da mensagem/exception lançada
  /// pelo youtube_explode_dart (a lib nem sempre expõe um tipo dedicado).
  static bool _is403Forbidden(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains("403") || msg.contains("forbidden");
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

/// Resultado interno de uma tentativa de fetch, usado só dentro
/// desta classe para decidir se cai no fallback ou não.
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

/// Pequeno wrapper para deixar explícito qual timeout é usado em
/// cada tentativa (proxy vs direto), lendo de ProxyConfig.
class ProxyConfigTimeout {
  static Duration get proxy =>
      _ProxyConfigTimeoutHelper.proxyTimeout;
  static Duration get direct =>
      _ProxyConfigTimeoutHelper.directTimeout;
}

class _ProxyConfigTimeoutHelper {
  static const Duration proxyTimeout = Duration(seconds: 8);
  static const Duration directTimeout = Duration(seconds: 12);
}
