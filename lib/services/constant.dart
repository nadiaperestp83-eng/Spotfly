// ATENÇÃO: usado como Referer/Origin nos headers de streaming em
// audio_handler.dart (_createAudioSource). Precisa bater com o
// contexto real usado pra extrair a URL do stream — hoje é o YouTube
// "normal" via youtube_explode_dart (services/stream_service.dart),
// NÃO mais o YouTube Music/WEB_REMIX de antes da migração. Mandar
// "music.youtube.com" pro CDN (googlevideo.com) numa URL assinada
// pelo contexto do YouTube normal é um descompasso clássico de
// Referer/Origin que faz o CDN travar a conexão sem nunca responder
// de verdade — a música toca metadados mas fica "carregando" pra
// sempre. Se voltar a mudar a forma de extração do stream, atualize
// aqui também.
const domain = "https://www.youtube.com/";
const String baseUrl = '${domain}youtubei/v1/';

// Chave atualizada (o YouTube Music rotaciona, mas esta ainda é a padrão para web)
const fixedParms = '?prettyPrint=false&alt=json&key=AIzaSyC-w45WzJ4q_W6Y9e8xS2j_zK8w9k3L4m5'; 

// UserAgent atualizado para uma versão recente do Chrome
const userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
