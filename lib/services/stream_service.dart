import 'dart:async';
import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'yt_client_provider.dart';
import 'proxy_config.dart';
import 'free_proxy_service.dart';
import 'package:harmonymusic/models/audio_model.dart';

class StreamProvider {
  final bool playable;
  final List<Audio>? audioFormats;
  final String statusMSG;

  StreamProvider({required this.playable, this.audioFormats, this.statusMSG = ""});

  /// Ponto de entrada público. Mantém o nome antigo `fetch` para não quebrar
  /// quem já chama esse método, mas agora delega para o fallback automático.
  static Future<StreamProvider> fetch(String videoId) => fetchWithFallback(videoId);

  /// Ordem de tentativas (igual ao ProxyManager real do Musify:
  /// `getSongManifest` tenta `_validateDirect` primeiro, proxy só entra
  /// se o direto falhar):
  /// 1) Conexão direta, timeout curto (5s) — cobre o caso comum (rede
  ///    ok, sem bloqueio no momento), sem gastar tempo com proxy à toa.
  /// 2) Se o direto falhar por motivo de rede, tenta alguns candidatos
  ///    de uma lista pública e gratuita de proxies (ProxyScrape +
  ///    Geonode), cada um com timeout curto.
  /// 3) Se nenhum proxy funcionar (ou a lista vier vazia), cai pro
  ///    fluxo que já estava funcionando antes: proxy fixo (se
  ///    ProxyConfig.isConfigured) ou conexão direta com mais retries.
  static Future<StreamProvider> fetchWithFallback(String videoId) async {
    final quickDirectYt = YtClientProvider.createDefaultClient();
    final quickDirectAttempt = await _tryFetch(
      quickDirectYt,
      videoId,
      timeout: _quickDirectTimeout,
    );
    if (quickDirectAttempt.result != null) return quickDirectAttempt.result!;
    if (!quickDirectAttempt.shouldFallback) {
      return quickDirectAttempt.errorResult!;
    }

    final freeProxyResult = await _tryFreeProxyList(videoId);
    if (freeProxyResult != null) return freeProxyResult;

    if (!ProxyConfig.isConfigured) {
      // Antes: 1 tentativa só. Se desse timeout/erro de rede, a música
      // já falhava na hora — sem chance de um "soluço" passageiro de
      // rede se resolver sozinho. Agora tenta até
      // [ProxyConfig.directRetries] vezes (client novo a cada
      // tentativa) ANTES de desistir, só pra erros marcados como
      // shouldFallback (rede/timeout/403) — erros definitivos (vídeo
      // indisponível, exige compra etc.) continuam falhando na hora,
      // sem repetir à toa.
      _FetchAttempt directAttempt = _FetchAttempt.error(
        StreamProvider(playable: false, statusMSG: "networkError"),
        shouldFallback: true,
      );
      for (var attempt = 1; attempt <= ProxyConfig.directRetries; attempt++) {
        final directYt = YtClientProvider.createDefaultClient();
        directAttempt = await _tryFetch(
          directYt,
          videoId,
          timeout: ProxyConfig.directTimeout,
        );
        if (directAttempt.result != null || !directAttempt.shouldFallback) {
          break; // sucesso, ou erro definitivo que não adianta repetir
        }
      }
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

  /// Timeout da tentativa direta rápida inicial — igual ao
  /// `_validateDirectTimeout` do Musify (5s). Curto de propósito: se a
  /// rede/YouTube estiver ok, a resposta normal chega bem antes disso;
  /// se não chegar, não vale a pena esperar mais — já parte pro proxy.
  static const Duration _quickDirectTimeout = Duration(seconds: 5);

  /// Timeout curto por candidato — proxy público que não responde rápido
  /// não vale a pena esperar, é melhor pular pro próximo/pro modo direto.
  static const Duration _freeProxyPerAttemptTimeout = Duration(seconds: 6);

  /// Tenta alguns candidatos da lista pública de proxies gratuitos.
  /// Devolve `null` (não `StreamProvider`) se nenhum candidato existir
  /// ou nenhum funcionar — nesse caso quem chamou segue pro fallback
  /// já existente (proxy fixo / direto), sem essa tentativa ter
  /// "gastado" o resultado de erro definitivo.
  static Future<StreamProvider?> _tryFreeProxyList(String videoId) async {
    final candidates = await FreeProxyService.getCandidates(maxCandidates: 3);
    for (final proxyAddress in candidates) {
      final proxyYt = YtClientProvider.createProxyClientFor(
        proxyAddress,
        timeout: _freeProxyPerAttemptTimeout,
      );
      final attempt = await _tryFetch(
        proxyYt,
        videoId,
        timeout: _freeProxyPerAttemptTimeout,
      );
      if (attempt.result != null) {
        return attempt.result;
      }
      if (!attempt.shouldFallback) {
        // Erro definitivo (vídeo indisponível etc.) — não é culpa do
        // proxy, não faz sentido tentar outro candidato nem o direto.
        return attempt.errorResult;
      }
      // Erro de rede/timeout: marca esse candidato como morto por essa
      // sessão e tenta o próximo da lista.
      FreeProxyService.markDead(proxyAddress);
    }
    return null; // nenhum candidato disponível ou nenhum funcionou
  }

  /// Executa uma tentativa de busca do manifesto num client específico.
  static Future<_FetchAttempt> _tryFetch(
    YoutubeExplode yt,
    String videoId, {
    required Duration timeout,
  }) async {
    try {
      // Igual ao exemplo do Musify (README do youtube_explode_dart):
      // sem `ytClients`, a lib usa o client "web" por padrão, que é o
      // mais visado pelo bloqueio/rate-limit do YouTube. Os clients
      // móveis (ios/androidVr) tomam bem menos throttling — é
      // literalmente a técnica que apps como Musify e yt-dlp usam pra
      // contornar isso.
      final res = await yt.videos.streamsClient
          .getManifest(
            videoId,
            ytClients: [
              YoutubeApiClient.ios,
              YoutubeApiClient.androidVr,
            ],
          )
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
