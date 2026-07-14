const domain = "https://music.youtube.com/";
const String baseUrl = '${domain}youtubei/v1/';

// Chave atualizada (o YouTube Music rotaciona, mas esta ainda é a padrão para web)
const fixedParms = '?prettyPrint=false&alt=json&key=AIzaSyC-w45WzJ4q_W6Y9e8xS2j_zK8w9k3L4m5'; 

// UserAgent atualizado para uma versão recente do Chrome
const userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

// ============================================================
//  ROTEADOR DE METADADOS (RAILWAY)
// ============================================================
// Este servidor nunca processa/faz proxy de bytes de áudio: ele só
// devolve JSON (metadados + URL direta do googlevideo.com quando
// aplicável). O streaming em si é sempre Google -> app diretamente.
const String proxyBaseUrl = 'https://yt-proxy-music-production.up.railway.app';
