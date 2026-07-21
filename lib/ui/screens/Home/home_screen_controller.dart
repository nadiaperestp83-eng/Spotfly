import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/media_Item_builder.dart';
import '/ui/player/player_controller.dart';
import '../../../core/models/podcast_episode.dart';
import '../../../core/riverpod/app_provider_container.dart';
import '../../../features/home/state/home_notifier.dart';
import '../../../utils/update_check_flag_file.dart';
import '../../../utils/helper.dart';
import '/models/album.dart';
import '/models/playlist.dart';
import '/models/quick_picks.dart';
import '/services/music_service.dart';
import '../../../features/search/data/sources/audio_content_service.dart';
import '../../../features/search/data/sources/jamendo_source.dart';
import '../../../features/search/data/track_media_item_mapper.dart';
import '../Settings/settings_screen_controller.dart';
import '/ui/widgets/new_version_dialog.dart';

class HomeScreenController extends GetxController {
  final MusicServices _musicServices = Get.find<MusicServices>();
  final isContentFetched = false.obs;
  final tabIndex = 0.obs;
  final networkError = false.obs;
  final quickPicks = QuickPicks([]).obs;
  final middleContent = [].obs;
  final fixedContent = [].obs;

  /// "Recommended for you": semente = música mais recente do histórico
  /// local (Hive box "LIBRP", já mantida por PlayerController._addToRP),
  /// relacionados buscados via API (getContentRelatedToSong). Não duplica
  /// nenhuma fonte de dados nova — só combina as duas que já existem.
  final recommendedForYou = QuickPicks([]).obs;
  final isRecommendedForYouLoading = false.obs;

  /// "Estações de Rádio Popular": seção ISOLADA, não passa pelo
  /// Orquestrador (musicSourcesProvider/searchCoordinatorProvider) — o
  /// Jamendo foi removido de propósito de lá (ver comentário em
  /// providers.dart) e essa decisão continua valendo para busca/fallback
  /// normal. Aqui é uma chamada direta e exclusiva ao JamendoSource, só
  /// pra essa seção da Home, usando o client_id que já está configurado
  /// via --dart-define=JAMENDO_CLIENT_ID (ver .github/workflows).
  final popularRadioStations = <MediaItem>[].obs;
  final isPopularRadioStationsLoading = false.obs;

  /// "Mais tocadas" (Trending/YouTube): seção FIXA na Home, sempre
  /// visível pra todo mundo — independente do seletor "Discover" nas
  /// Configurações. Antes, a busca de "Trending" só rodava quando o
  /// usuário tinha esse seletor em "Trending" (contentType == "TR");
  /// quem estava em "Quick Picks" (padrão) nunca via essa seção, e por
  /// isso ela "sumia". Usa getCharts() do Orquestrador (mesma fonte já
  /// usada pelo seletor), com cache local próprio (chave
  /// "trendingSongsCache" em Hive "AppPrefs") pra mostrar algo na hora
  /// enquanto a rede não responde — mesmo padrão de
  /// loadRecommendedForYou logo acima.
  final trendingSongs = QuickPicks([]).obs;
  final isTrendingSongsLoading = false.obs;

  /// 3 seções narrativas (Minutos de Reflexão, Contos da Noite, Poesia
  /// Sonora), no mesmo padrão ISOLADO da "Estações de Rádio Popular"
  /// acima: não passam pelo orquestrador de busca normal
  /// (musicSourcesProvider). A fonte é o AudioContentService
  /// ("Fallback Híbrido": iTunes Search API + RSS primeiro,
  /// Internet Archive como fallback automático se o iTunes falhar ou
  /// não achar nada) — ver
  /// lib/features/search/data/sources/audio_content_service.dart.
  /// ItunesSource e InternetArchiveSource são registradas à parte em
  /// playbackResolverProvider (ver core/providers/providers.dart) pra
  /// essas faixas conseguirem tocar no player normal do app.
  final AudioContentService _audioContentService = AudioContentService();

  /// Faixas de duração (em segundos) fáceis de ajustar depois:
  static const _reflectionMinSeconds = 150; // 2:30
  static const _reflectionMaxSeconds = 330; // 5:30
  static const _nightTalesMinSeconds = 150; // 2:30
  static const _nightTalesMaxSeconds = 330; // 5:30
  static const _soundPoetryMinSeconds = 150; // 2:30
  static const _soundPoetryMaxSeconds = 450; // 7:30

  // Filtro de idioma reaproveitado nas 3 buscas: aceita as variações
  // mais comuns de metadado de idioma português no Internet Archive
  // (não exige ser produção brasileira — qualquer lusofonia serve).
  static const _portugueseFilter =
      'language:(por OR Portuguese OR "Português" OR pt)';

  final reflectionMinutes = <MediaItem>[].obs;
  final isReflectionMinutesLoading = true.obs;
  final nightTales = <MediaItem>[].obs;
  final isNightTalesLoading = true.obs;
  final soundPoetry = <MediaItem>[].obs;
  final isSoundPoetryLoading = true.obs;

  final showVersionDialog = true.obs;
  //isHomeScreenOnTop var only useful if bottom nav enabled
  final isHomeSreenOnTop = true.obs;
  final List<ScrollController> contentScrollControllers = [];
  bool reverseAnimationtransiton = false;

  bool _narrativeSectionsStarted = false;

  @override
  onInit() {
    super.onInit();
    loadContent();
    loadRecommendedForYou();
    loadPopularRadioStations();
    loadTrendingSongs();

    // IMPORTANTE: loadContent() NÃO pode ser usado como sinal de "Home
    // principal pronta" — dentro dele, loadContentFromNetwork() é
    // disparado SEM `await` nas 3 ramificações (fire-and-forget), então
    // o Future de loadContent() resolve quase na hora, bem antes dos
    // dados do YouTube chegarem de verdade. Foi por isso que o
    // `.then()` usado antes não resolvia a disputa de rede: as seções
    // narrativas ainda começavam cedo demais.
    //
    // O sinal de verdade é isContentFetched virando `true` (só isso
    // indica que quickPicks/middleContent/fixedContent já têm dados).
    // `once` garante que isso dispare só 1 vez. Um fallback de 15s
    // garante que as seções narrativas apareçam mesmo se a Home
    // principal falhar (ex.: YouTube fora do ar, mas Internet Archive
    // ok) — sem essa rede de segurança, elas ficariam esperando pra
    // sempre.
    once(isContentFetched, (_) => _startNarrativeSectionsOnce());
    Future.delayed(const Duration(seconds: 15), _startNarrativeSectionsOnce);

    if (updateCheckFlag) _checkNewVersion();
  }

  void _startNarrativeSectionsOnce() {
    if (_narrativeSectionsStarted) return;
    _narrativeSectionsStarted = true;
    _loadNarrativeSectionsSequentially();
  }

  /// Carrega as 3 seções narrativas uma de cada vez (não em paralelo
  /// entre si) — reduz ainda mais o pico de requisições simultâneas ao
  /// Internet Archive numa conexão móvel.
  Future<void> _loadNarrativeSectionsSequentially() async {
    await loadReflectionMinutes();
    await loadNightTales();
    await loadSoundPoetry();
  }

  /// Monta a seção "Recommended for you" a partir do histórico local:
  /// 1. Lê a Hive box "LIBRP" (sem duplicatas, mais recente por último).
  /// 2. Usa a música mais recente como "semente" pra API de relacionados.
  /// 3. Filtra fora qualquer música que já esteja no próprio histórico,
  ///    pra não recomendar o que o usuário acabou de ouvir.
  ///
  /// "Fixa" (não deve desaparecer a cada abertura do app):
  /// - Ao iniciar, primeiro mostra o que foi salvo em cache na última vez
  ///   que a busca deu certo (Hive "AppPrefs" -> "recommendedForYouCache"),
  ///   então atualiza em segundo plano.
  /// - Se a chamada de rede falhar ou vier vazia, o cache anterior é
  ///   mantido na tela (nunca sobrescreve com uma lista vazia).
  /// - Se não houver cache nenhum (primeiro uso) e a rede falhar, cai de
  ///   volta pro próprio histórico local como recomendação, pra sempre
  ///   ter algo pra mostrar quando já existe alguma música tocada.
  Future<void> loadRecommendedForYou() async {
    final appPrefs = Hive.isBoxOpen("AppPrefs")
        ? Hive.box("AppPrefs")
        : await Hive.openBox("AppPrefs");

    // 1) Mostra imediatamente o último resultado salvo, sem esperar rede.
    final cached = appPrefs.get("recommendedForYouCache") as List?;
    if (cached != null && cached.isNotEmpty) {
      try {
        final cachedItems = cached
            .map((e) => MediaItemBuilder.fromJson(Map.from(e as Map)))
            .toList();
        recommendedForYou.value =
            QuickPicks(cachedItems, title: "recommendedForYou".tr);
      } catch (_) {}
    }

    try {
      isRecommendedForYouLoading.value = true;
      final box = Hive.isBoxOpen("LIBRP")
          ? Hive.box("LIBRP")
          : await Hive.openBox("LIBRP");
      if (box.isEmpty) return; // nunca tocou nada ainda: nada a recomendar

      final historyValues = box.values
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final seedSongId = historyValues.last['videoId'] as String?;
      if (seedSongId == null) return;

      final historyIds = historyValues.map((e) => e['videoId']).toSet();
      List<Map<String, dynamic>> freshTracks = [];

      try {
        final related = await _musicServices.getContentRelatedToSong(
            seedSongId, getContentHlCode());
        freshTracks = related
            .where((track) =>
                track['videoId'] != null &&
                !historyIds.contains(track['videoId']))
            .take(10)
            .toList();
      } catch (e) {
        printERROR("getContentRelatedToSong falhou: $e");
      }

      // 2) API não trouxe nada novo (offline, erro, ou tudo já visto):
      //    cai pro próprio histórico local em vez de deixar a seção vazia.
      if (freshTracks.isEmpty) {
        if (recommendedForYou.value.songList.isNotEmpty) {
          return; // já tem cache/valor na tela, não sobrescreve com vazio
        }
        freshTracks = historyValues.reversed
            .where((track) => track['videoId'] != seedSongId)
            .take(10)
            .toList();
      }

      if (freshTracks.isEmpty) return;

      final mediaItems = freshTracks
          .map((track) => MediaItemBuilder.fromJson(track))
          .toList();

      recommendedForYou.value =
          QuickPicks(mediaItems, title: "recommendedForYou".tr);
      await appPrefs.put("recommendedForYouCache", freshTracks);
    } catch (e) {
      printERROR("Recommended for you not loaded due to: $e");
    } finally {
      isRecommendedForYouLoading.value = false;
    }
  }

  /// Busca só no Jamendo (order: popularity_month = "mais tocadas"),
  /// direto, sem passar pelo orquestrador YT->Piped->Jamendo — decisão
  /// explícita do usuário de manter essa seção isolada. Se JAMENDO_CLIENT_ID
  /// não estiver configurado no build (--dart-define), getHomeContent()
  /// já devolve lista vazia sozinho, então a seção simplesmente não aparece.
  Future<void> loadPopularRadioStations() async {
    try {
      isPopularRadioStationsLoading.value = true;
      final jamendoSource = JamendoSource(
        clientId: const String.fromEnvironment('JAMENDO_CLIENT_ID'),
      );
      final result = await jamendoSource.getHomeContent();
      if (result.isEmpty) return;
      final contents = (result.first['contents'] as List).cast<MediaItem>();
      popularRadioStations.value = contents;
    } catch (e) {
      printERROR("Popular radio stations (Jamendo) not loaded due to: $e");
    } finally {
      isPopularRadioStationsLoading.value = false;
    }
  }

  /// Busca o chart "Trending" via getCharts() do Orquestrador e mantém
  /// atualizado. Mostra o cache local imediatamente (sem esperar rede),
  /// atualiza em segundo plano, e nunca sobrescreve com lista vazia —
  /// se a rede falhar ou o chart não vier, o que já estava na tela
  /// continua lá.
  Future<void> loadTrendingSongs() async {
    final appPrefs = Hive.isBoxOpen("AppPrefs")
        ? Hive.box("AppPrefs")
        : await Hive.openBox("AppPrefs");

    final cached = appPrefs.get("trendingSongsCache") as List?;
    if (cached != null && cached.isNotEmpty) {
      try {
        final cachedItems = cached
            .map((e) => MediaItemBuilder.fromJson(Map.from(e as Map)))
            .toList();
        trendingSongs.value = QuickPicks(cachedItems, title: "trending".tr);
      } catch (_) {}
    }

    try {
      isTrendingSongsLoading.value = trendingSongs.value.songList.isEmpty;
      final charts = await appProviderContainer
          .read(homeNotifierProvider.notifier)
          .getCharts();
      final index =
          charts.indexWhere((element) => element['title'] == "Trending");
      if (index == -1) return; // mantém cache/valor atual na tela

      final mediaItems = _extractMediaItems(charts[index]["contents"]);
      if (mediaItems.isEmpty) return;

      trendingSongs.value = QuickPicks(mediaItems, title: "trending".tr);
      await appPrefs.put("trendingSongsCache",
          mediaItems.map((e) => MediaItemBuilder.toJson(e)).toList());
    } catch (e) {
      printERROR("Mais tocadas (Trending) not loaded due to: $e");
    } finally {
      isTrendingSongsLoading.value = false;
    }
  }

  /// "Minutos de Reflexão": poemas/reflexões curtas (2:30-5:30) em
  /// português. Mostra cache salvo primeiro (mesmo padrão de
  /// loadRecommendedForYou), atualiza em segundo plano, e nunca
  /// sobrescreve com lista vazia. Fonte: AudioContentService
  /// (iTunes -> Internet Archive).
  Future<void> loadReflectionMinutes() => _loadNarrativeSection(
        cacheKey: "reflectionMinutesCache",
        fetchedAtKey: "reflectionMinutesFetchedAt",
        itunesTerm: "poesia reflexão meditação",
        archiveQuery:
            'mediatype:(audio) AND $_portugueseFilter AND (subject:(poesia) OR subject:(reflexão) OR subject:(reflexao) OR title:(poema) OR title:(reflexão) OR title:(reflexao) OR title:(pensamento))',
        minSeconds: _reflectionMinSeconds,
        maxSeconds: _reflectionMaxSeconds,
        currentValue: () => reflectionMinutes,
        setValue: (v) => reflectionMinutes.value = v,
        loadingFlag: isReflectionMinutesLoading,
        logLabel: "Minutos de Reflexão",
      );

  /// "Contos da Noite": contos curtos (2:30-5:30) em português.
  /// Fonte: AudioContentService (iTunes -> Internet Archive).
  Future<void> loadNightTales() => _loadNarrativeSection(
        cacheKey: "nightTalesCache",
        fetchedAtKey: "nightTalesFetchedAt",
        itunesTerm: "contos infantis histórias",
        archiveQuery:
            'mediatype:(audio) AND $_portugueseFilter AND (subject:(conto) OR subject:(contos) OR title:(conto) OR title:(contos) OR title:(historinha) OR title:(história curta))',
        minSeconds: _nightTalesMinSeconds,
        maxSeconds: _nightTalesMaxSeconds,
        currentValue: () => nightTales,
        setValue: (v) => nightTales.value = v,
        loadingFlag: isNightTalesLoading,
        logLabel: "Contos da Noite",
      );

  /// "Poesia Sonora": declamação de poesia em português (qualquer país
  /// lusófono, não só Brasil). Fonte: AudioContentService (iTunes ->
  /// Internet Archive).
  Future<void> loadSoundPoetry() => _loadNarrativeSection(
        cacheKey: "soundPoetryCache",
        fetchedAtKey: "soundPoetryFetchedAt",
        itunesTerm: "poesia declamação",
        archiveQuery:
            'mediatype:(audio) AND $_portugueseFilter AND (subject:(poesia) OR subject:(declamação) OR subject:(declamacao) OR title:(poesia) OR title:(declamação) OR title:(declamacao) OR title:(verso))',
        minSeconds: _soundPoetryMinSeconds,
        maxSeconds: _soundPoetryMaxSeconds,
        currentValue: () => soundPoetry,
        setValue: (v) => soundPoetry.value = v,
        loadingFlag: isSoundPoetryLoading,
        logLabel: "Poesia Sonora",
      );

  /// Helper compartilhado pelas 3 seções narrativas acima. Duas coisas
  /// combinadas:
  ///
  /// 1) Fallback Híbrido (AudioContentService): tenta iTunes primeiro,
  ///    cai pro Internet Archive só se o iTunes falhar/não achar nada.
  ///    Quem chama esse helper não sabe (nem precisa saber) qual das
  ///    duas fontes respondeu.
  /// 2) Cache local "1x por dia": se já existe um resultado salvo em
  ///    Hive E ele foi buscado com sucesso HOJE (mesmo dia local do
  ///    aparelho), a seção usa só o cache e nem chama
  ///    AudioContentService — elimina o load feio que antes acontecia
  ///    (quase) toda vez que o app abria, mesmo já tendo dado certo
  ///    mais cedo no mesmo dia.
  ///
  /// Se não houver cache do dia (primeiro uso, dia mudou, ou a busca
  /// de hoje ainda não deu certo), busca normalmente e, em caso de
  /// sucesso, salva o resultado (já serializado como PodcastEpisode,
  /// preservando de qual fonte veio) + o timestamp de "buscado em" pra
  /// valer pelo resto do dia. Falha total ou resultado vazio nunca
  /// apaga o que já estava na tela.
  Future<void> _loadNarrativeSection({
    required String cacheKey,
    required String fetchedAtKey,
    required String itunesTerm,
    required String archiveQuery,
    required int minSeconds,
    required int maxSeconds,
    required List<MediaItem> Function() currentValue,
    required void Function(List<MediaItem> value) setValue,
    required RxBool loadingFlag,
    required String logLabel,
  }) async {
    final appPrefs = Hive.isBoxOpen("AppPrefs")
        ? Hive.box("AppPrefs")
        : await Hive.openBox("AppPrefs");

    final cached = appPrefs.get(cacheKey) as String?;
    if (cached != null && cached.isNotEmpty) {
      try {
        final episodes = (jsonDecode(cached) as List<dynamic>)
            .map((e) =>
                PodcastEpisode.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        setValue(episodes.map((ep) => ep.toTrack().toFallbackMediaItem()).toList());
      } catch (_) {}
    }

    final fetchedAtMillis = appPrefs.get(fetchedAtKey) as int?;
    if (currentValue().isNotEmpty &&
        fetchedAtMillis != null &&
        _isSameLocalDay(fetchedAtMillis)) {
      // Já buscamos com sucesso hoje: fica só no cache, sem rede.
      loadingFlag.value = false;
      return;
    }

    try {
      loadingFlag.value = currentValue().isEmpty;
      final episodes = await _audioContentService.fetchEpisodes(
        itunesTerm: itunesTerm,
        archiveQuery: archiveQuery,
        minSeconds: minSeconds,
        maxSeconds: maxSeconds,
        resultLimit: 10,
      );
      if (episodes.isEmpty) return; // mantém cache/valor atual na tela

      setValue(episodes.map((ep) => ep.toTrack().toFallbackMediaItem()).toList());
      await appPrefs.put(
          cacheKey, jsonEncode(episodes.map((e) => e.toJson()).toList()));
      await appPrefs.put(fetchedAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      printERROR("$logLabel (AudioContentService) not loaded due to: $e");
    } finally {
      loadingFlag.value = false;
    }
  }

  /// Compara se um timestamp (ms desde epoch) cai no mesmo dia local
  /// (ano/mês/dia) que "agora". Usado pelo cache "1x por dia" acima.
  bool _isSameLocalDay(int millis) {
    final last = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    return last.year == now.year &&
        last.month == now.month &&
        last.day == now.day;
  }

  List<MediaItem> _extractMediaItems(dynamic contents) {
    if (contents == null) return [];
    final list = contents as List;
    // Filtra apenas os itens que já são MediaItem
    final mediaItems = list.whereType<MediaItem>().toList();
    return mediaItems;
  }

  Future<void> loadContent() async {
    final box = Hive.box("AppPrefs");
    final isCachedHomeScreenDataEnabled =
        box.get("cacheHomeScreenData") ?? true;
    if (isCachedHomeScreenDataEnabled) {
      final loaded = await loadContentFromDb();

      if (loaded) {
        final currTimeSecsDiff = DateTime.now().millisecondsSinceEpoch -
            (box.get("homeScreenDataTime") ??
                DateTime.now().millisecondsSinceEpoch);
        if (currTimeSecsDiff / 1000 > 3600 * 8) {
          loadContentFromNetwork(silent: true);
        }
      } else {
        loadContentFromNetwork();
      }
    } else {
      loadContentFromNetwork();
    }
  }

  Future<bool> loadContentFromDb() async {
    final homeScreenData = await Hive.openBox("homeScreenData");
    if (homeScreenData.keys.isNotEmpty) {
      final String quickPicksType = homeScreenData.get("quickPicksType");
      final List quickPicksData = homeScreenData.get("quickPicks");
      final List middleContentData = homeScreenData.get("middleContent") ?? [];
      final List fixedContentData = homeScreenData.get("fixedContent") ?? [];
      quickPicks.value = QuickPicks(
          quickPicksData.map((e) => MediaItemBuilder.fromJson(e)).toList(),
          title: quickPicksType);
      middleContent.value = middleContentData
          .map((e) => e["type"] == "Album Content"
              ? AlbumContent.fromJson(e)
              : PlaylistContent.fromJson(e))
          .toList();
      fixedContent.value = fixedContentData
          .map((e) => e["type"] == "Album Content"
              ? AlbumContent.fromJson(e)
              : PlaylistContent.fromJson(e))
          .toList();
      isContentFetched.value = true;
      printINFO("Loaded from offline db");
      return true;
    } else {
      return false;
    }
  }

  Future<void> loadContentFromNetwork({bool silent = false}) async {
    final box = Hive.box("AppPrefs");
    String contentType = box.get("discoverContentType") ?? "QP";

    networkError.value = false;
    try {
      List middleContentTemp = [];
      // Volta a chamar _musicServices.getHome() DIRETO (sem passar pelo
      // Orquestrador/fetchHomeContent) — esse é o caminho que sempre
      // funcionou. O Orquestrador aplica um timeout de 12s em cima da
      // busca (que faz várias queries sequenciais de verdade no YT, e
      // pode facilmente passar de 12s numa conexão mais lenta),
      // cortando a busca do YouTube antes de terminar e caindo pro
      // Piped — que não tem um "Home" de verdade, só retorna
      // "trending" genérico, sem nada a ver com o conteúdo esperado
      // aqui. _musicServices.getHome() continua sem esse timeout
      // artificial, exatamente como sempre foi.
      final rawHome = await _musicServices.getHome(
          limit:
              Get.find<SettingsScreenController>().noOfHomeScreenContent.value);
      final homeContentListMap = rawHome
          .map((section) => {
                'title': section['title'],
                'contents': ((section['contents'] as List?) ?? const [])
                    .map((e) => MediaItemBuilder.fromJson(
                        Map<String, dynamic>.from(e as Map)))
                    .toList(),
              })
          .toList();
      if (contentType == "TR") {
        final index = homeContentListMap
            .indexWhere((element) => element['title'] == "Trending");
        if (index != -1 && index != 0) {
          // Usa a função segura
          final mediaItems = _extractMediaItems(homeContentListMap[index]["contents"]);
          if (mediaItems.isNotEmpty) {
            quickPicks.value = QuickPicks(mediaItems, title: "Trending");
          }
        } else if (index == -1) {
          List charts = await appProviderContainer
              .read(homeNotifierProvider.notifier)
              .getCharts();
          final index = charts.indexWhere((element) =>
              element['title'] ==
              (contentType == "TMV" ? "Top Music Videos" : "Trending"));
          if (index != -1) {
            final mediaItems = _extractMediaItems(charts[index]["contents"]);
            if (mediaItems.isNotEmpty) {
              quickPicks.value = QuickPicks(mediaItems, title: charts[index]['title']);
              middleContentTemp.addAll(charts);
            }
          }
        }
      } else if (contentType == "TMV") {
        final index = homeContentListMap
            .indexWhere((element) => element['title'] == "Top music videos");
        if (index != -1 && index != 0) {
          final con = homeContentListMap.removeAt(index);
          final mediaItems = _extractMediaItems(con["contents"]);
          if (mediaItems.isNotEmpty) {
            quickPicks.value = QuickPicks(mediaItems, title: con["title"]);
          }
        } else if (index == -1) {
          List charts = await appProviderContainer
              .read(homeNotifierProvider.notifier)
              .getCharts();
          final index = charts.indexWhere((element) =>
              element['title'] ==
              (contentType == "TMV" ? "Top Music Videos" : "Trending"));
          if (index != -1) {
            final mediaItems = _extractMediaItems(charts[index]["contents"]);
            if (mediaItems.isNotEmpty) {
              quickPicks.value = QuickPicks(mediaItems, title: charts[index]["title"]);
              middleContentTemp.addAll(charts);
            }
          }
        }
      } else if (contentType == "BOLI") {
        try {
          final songId = box.get("recentSongId");
          if (songId != null) {
            final rel = (await _musicServices.getContentRelatedToSong(
                songId, getContentHlCode()));
            final con = rel.removeAt(0);
            final mediaItems = _extractMediaItems(con["contents"]);
            if (mediaItems.isNotEmpty) {
              quickPicks.value = QuickPicks(mediaItems);
            }
            middleContentTemp.addAll(rel);
          }
        } catch (e) {
          printERROR(
              "Seems Based on last interaction content currently not available!");
        }
      }

      if (quickPicks.value.songList.isEmpty) {
        final index = homeContentListMap
            .indexWhere((element) => element['title'] == "Quick picks");
        if (index != -1) {
          final con = homeContentListMap.removeAt(index);
          final mediaItems = _extractMediaItems(con["contents"]);
          if (mediaItems.isNotEmpty) {
            quickPicks.value = QuickPicks(mediaItems, title: "Quick picks");
          }
        } else if (homeContentListMap.isNotEmpty) {
          final con = homeContentListMap.removeAt(0);
          final mediaItems = _extractMediaItems(con["contents"]);
          if (mediaItems.isNotEmpty) {
            quickPicks.value = QuickPicks(mediaItems, title: con["title"] ?? "Quick picks");
          }
        }
      }

      middleContent.value = _setContentList(middleContentTemp);
      fixedContent.value = _setContentList(homeContentListMap);

      // ===== DIAGNÓSTICO TEMPORÁRIO =====
      // printINFO/printERROR (helper.dart) são no-op em release
      // (`if (kReleaseMode) return;`), e o build que você usa
      // (build-unsigned.yml) é `flutter build apk --release` — ou
      // seja, eles NUNCA apareceriam pra você, nem via logcat. Por
      // isso uso um snackbar visível na tela mesmo, só dessa vez, pra
      // a gente ver os números reais sem precisar de adb/computador.
      // ME AVISE quando já tiver visto o resultado que eu removo isso.
      Get.snackbar(
        'DEBUG: Home content',
        'contentType=$contentType | rawHome=${rawHome.length} | '
        'quickPicks=${quickPicks.value.songList.length} | '
        'middleContent=${middleContent.length} | '
        'fixedContent=${fixedContent.length} | '
        'titles=${homeContentListMap.map((e) => e['title']).toList()}',
        duration: const Duration(seconds: 12),
        isDismissible: true,
      );
      // ===== FIM DIAGNÓSTICO TEMPORÁRIO =====

      isContentFetched.value = true;

      cachedHomeScreenData(updateAll: true);
      await Hive.box("AppPrefs")
          .put("homeScreenDataTime", DateTime.now().millisecondsSinceEpoch);
    } catch (e, st) {
      printERROR("Home Content not loaded due to: $e");
      printERROR(st.toString());
      await Future.delayed(const Duration(seconds: 1));
      networkError.value = !silent;
      if (!silent) {
        Get.snackbar(
          'Erro ao carregar a Home',
          e.toString(),
          duration: const Duration(seconds: 10),
          isDismissible: true,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
  }

  List _setContentList(
    List<dynamic> contents,
  ) {
    List contentTemp = [];
    for (var content in contents) {
      if((content["contents"]).isEmpty) continue;
      if ((content["contents"][0]).runtimeType == Playlist) {
        final tmp = PlaylistContent(
            playlistList: (content["contents"]).whereType<Playlist>().toList(),
            title: content["title"]);
        if (tmp.playlistList.length >= 2) {
          contentTemp.add(tmp);
        }
      } else if ((content["contents"][0]).runtimeType == Album) {
        final tmp = AlbumContent(
            albumList: (content["contents"]).whereType<Album>().toList(),
            title: content["title"]);
        if (tmp.albumList.length >= 2) {
          contentTemp.add(tmp);
        }
      }
    }
    return contentTemp;
  }

  Future<void> changeDiscoverContent(dynamic val, {String? songId}) async {
    QuickPicks? quickPicks_;
    if (val == 'QP') {
      final rawHome = await _musicServices.getHome(limit: 3);
      if (rawHome.isEmpty) return;
      // _extractMediaItems só aceita MediaItem — _musicServices.getHome()
      // devolve Maps crus, então precisa converter aqui antes (mesmo
      // ajuste feito em loadContentFromNetwork acima).
      final mediaItems = ((rawHome[0]["contents"] as List?) ?? const [])
          .map((e) =>
              MediaItemBuilder.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (mediaItems.isNotEmpty) {
        quickPicks_ = QuickPicks(mediaItems, title: rawHome[0]["title"]);
      }
    } else if (val == "TMV" || val == 'TR') {
      try {
        final charts =
            await appProviderContainer.read(homeNotifierProvider.notifier).getCharts();
        final index = charts.indexWhere((element) =>
            element['title'] ==
            (val == "TMV" ? "Top Music Videos" : "Trending"));
        if (index != -1) {
          final mediaItems = _extractMediaItems(charts[index]["contents"]);
          if (mediaItems.isNotEmpty) {
            quickPicks_ = QuickPicks(mediaItems, title: charts[index]["title"]);
          }
        }
      } catch (e) {
        printERROR(
            "Seems ${val == "TMV" ? "Top music videos" : "Trending songs"} currently not available!");
      }
    } else {
      songId ??= Hive.box("AppPrefs").get("recentSongId");
      if (songId != null) {
        try {
          final value = await _musicServices.getContentRelatedToSong(
              songId, getContentHlCode());
          middleContent.value = _setContentList(value);
          if (value.isNotEmpty && (value[0]['title']).contains("like")) {
            final mediaItems = _extractMediaItems(value[0]["contents"]);
            if (mediaItems.isNotEmpty) {
              quickPicks_ = QuickPicks(mediaItems);
            }
            Hive.box("AppPrefs").put("recentSongId", songId);
          }
          // ignore: empty_catches
        } catch (e) {}
      }
    }
    if (quickPicks_ == null) return;

    quickPicks.value = quickPicks_;

    cachedHomeScreenData(updateQuickPicksNMiddleContent: true);
    await Hive.box("AppPrefs")
        .put("homeScreenDataTime", DateTime.now().millisecondsSinceEpoch);
  }

  String getContentHlCode() {
    const List<String> unsupportedLangIds = ["ia", "ga", "fj", "eo"];
    final userLangId =
        Get.find<SettingsScreenController>().currentAppLanguageCode.value;
    return unsupportedLangIds.contains(userLangId) ? "en" : userLangId;
  }

  void onSideBarTabSelected(int index) {
    reverseAnimationtransiton = index > tabIndex.value;
    tabIndex.value = index;
  }

  void onBottonBarTabSelected(int index) {
    reverseAnimationtransiton = index > tabIndex.value;
    tabIndex.value = index;
  }

  void _checkNewVersion() {
    showVersionDialog.value =
        Hive.box("AppPrefs").get("newVersionVisibility") ?? true;
    if (showVersionDialog.isTrue) {
      newVersionCheck(Get.find<SettingsScreenController>().currentVersion)
          .then((value) {
        if (value) {
          showDialog(
              context: Get.context!,
              builder: (context) => const NewVersionDialog());
        }
      });
    }
  }

  void onChangeVersionVisibility(bool val) {
    Hive.box("AppPrefs").put("newVersionVisibility", !val);
    showVersionDialog.value = !val;
  }

  ///This is used to minimized bottom navigation bar by setting [isHomeSreenOnTop.value] to `true` and set mini player height.
  ///
  ///and applicable/useful if bottom nav enabled
  void whenHomeScreenOnTop() {
    if (Get.find<SettingsScreenController>().isBottomNavBarEnabled.isTrue) {
      final currentRoute = getCurrentRouteName();
      final isHomeOnTop = currentRoute == '/homeScreen';
      final isResultScreenOnTop = currentRoute == '/searchResultScreen';
      final playerCon = Get.find<PlayerController>();

      isHomeSreenOnTop.value = isHomeOnTop;

      // Set miniplayer height accordingly
      if (!playerCon.initFlagForPlayer) {
        if (isHomeOnTop) {
          playerCon.playerPanelMinHeight.value = 75.0;
        } else {
          Future.delayed(
              isResultScreenOnTop
                  ? const Duration(milliseconds: 300)
                  : Duration.zero, () {
            playerCon.playerPanelMinHeight.value =
                75.0 + Get.mediaQuery.viewPadding.bottom;
          });
        }
      }
    }
  }

  Future<void> cachedHomeScreenData({
    bool updateAll = false,
    bool updateQuickPicksNMiddleContent = false,
  }) async {
    if (Get.find<SettingsScreenController>().cacheHomeScreenData.isFalse ||
        quickPicks.value.songList.isEmpty) {
      return;
    }

    final homeScreenData = Hive.box("homeScreenData");

    if (updateQuickPicksNMiddleContent) {
      await homeScreenData.putAll({
        "quickPicksType": quickPicks.value.title,
        "quickPicks": _getContentDataInJson(quickPicks.value.songList,
            isQuickPicks: true),
        "middleContent": _getContentDataInJson(middleContent.toList()),
      });
    } else if (updateAll) {
      await homeScreenData.putAll({
        "quickPicksType": quickPicks.value.title,
        "quickPicks": _getContentDataInJson(quickPicks.value.songList,
            isQuickPicks: true),
        "middleContent": _getContentDataInJson(middleContent.toList()),
        "fixedContent": _getContentDataInJson(fixedContent.toList())
      });
    }

    printINFO("Saved Homescreen data data");
  }

  List<Map<String, dynamic>> _getContentDataInJson(List content,
      {bool isQuickPicks = false}) {
    if (isQuickPicks) {
      return content.toList().map((e) => MediaItemBuilder.toJson(e)).toList();
    } else {
      return content.map((e) {
        if (e.runtimeType == AlbumContent) {
          return (e as AlbumContent).toJson();
        } else {
          return (e as PlaylistContent).toJson();
        }
      }).toList();
    }
  }

  void disposeDetachedScrollControllers({bool disposeAll = false}) {
    final scrollControllersCopy = contentScrollControllers.toList();
    for (final contoller in scrollControllersCopy) {
      if (!contoller.hasClients || disposeAll) {
        contentScrollControllers.remove(contoller);
        contoller.dispose();
      }
    }
  }

  @override
  void dispose() {
    disposeDetachedScrollControllers(disposeAll: true);
    super.dispose();
  }
}
