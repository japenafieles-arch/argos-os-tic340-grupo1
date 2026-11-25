/*
 * Modulo 6: Motor de Busqueda Academico vinculado con Google Academico
 *  - Utiliza la pila TCP/IP + HTTP/1.1 real de ARGOS OS (net_http_get)
 *  - Se conecta a la pasarela HTTP->HTTPS del host (por defecto 10.0.2.2:8080 en VirtualBox NAT)
 *  - Interfaz interactiva 80x25: navegar resultados, ver resumen/enlace/APA,
 *    copiar cita al portapapeles (Ctrl+V) y guardar citas en TIC340FS
 */
#include "scholar.h"
#include "net.h"
#include "fs.h"
#include "teclado.h"
#include "audit.h"
#include "reloj.h"

#define COLS 80
#define MAX_SCHOLAR_RES 6
#define SCHOLAR_RX_SZ   12288

typedef struct {
    char title[144];
    char authors[104];
    char year[8];
    char cites[12];
    char url[144];
    char snippet[224];
    char apa[264];
} scholar_item_t;

extern void kprint(const char *s);
extern void kputc(char c);
extern void kset_color(uint8_t c);
extern void kprint_dec(uint32_t v);
extern void kclear(void);
extern void kvga_texto_en(int x, int y, uint8_t color, const char *s);
extern void kvga_dibujar_caja(int x0, int y0, int ancho, int alto, uint8_t fondo, uint8_t borde);
extern void kvga_barra_titulo(const char *t);
extern void kvga_limpiar_area(int y_ini, int y_fin, uint8_t color);
extern void kset_cursor(int x, int y);
extern const char *kernel_usuario_corto(void);

#ifndef SCHOLAR_DEFAULT_HOST
#define SCHOLAR_DEFAULT_HOST "auto"
#endif
#ifndef SCHOLAR_DEFAULT_PORT
#define SCHOLAR_DEFAULT_PORT 8080
#endif

static char     gw_host[64] = "10.0.2.2";
static uint16_t gw_port     = 8080;
static char     gw_label[80] = "10.0.2.2:8080";
static int      gw_en_nube  = 0;

static char           rx_buf[SCHOLAR_RX_SZ];
static scholar_item_t resultados[MAX_SCHOLAR_RES];
static int            num_resultados = 0;
static char           fuente_actual[52] = "";
static char           ultima_consulta[96] = "";

static int s_slen(const char *s) { int n = 0; while (s[n]) n++; return n; }

static int s_igual(const char *a, const char *b) {
    while (*a && *a == *b) { a++; b++; }
    return *a == *b;
}

static int s_empieza(const char *s, const char *pre) {
    while (*pre) { if (*s++ != *pre++) return 0; }
    return 1;
}

static void s_scpy(char *d, const char *s, int max) {
    int i = 0;
    while (i < max - 1 && s && s[i]) { d[i] = s[i]; i++; }
    d[i] = '\0';
}

static void actualizar_gw_label(void) {
    int p = 0;
    for (int i = 0; gw_host[i] && p < 68; i++) gw_label[p++] = gw_host[i];
    gw_label[p++] = ':';
    char tmp[8];
    uint32_t v = gw_port;
    int n = 0;
    do { tmp[n++] = (char)('0' + (v % 10)); v /= 10; } while (v);
    while (n-- && p < 79) gw_label[p++] = tmp[n];
    gw_label[p] = '\0';
}

static void ip_a_str(uint32_t ip, char *out) {
    int p = 0;
    for (int k = 3; k >= 0; k--) {
        uint32_t oct = (ip >> (k * 8)) & 0xFFu;
        char tmp[4]; int n = 0;
        do { tmp[n++] = (char)('0' + (oct % 10)); oct /= 10; } while (oct);
        while (n--) out[p++] = tmp[n];
        if (k > 0) out[p++] = '.';
    }
    out[p] = '\0';
}

void scholar_init(void) {
    if (!s_igual(SCHOLAR_DEFAULT_HOST, "auto") && SCHOLAR_DEFAULT_HOST[0] != '\0') {
        s_scpy(gw_host, SCHOLAR_DEFAULT_HOST, sizeof(gw_host));
        gw_port = (uint16_t)SCHOLAR_DEFAULT_PORT;
        gw_en_nube = 1;
    } else {
        uint32_t gw = net_mi_gw();
        if (gw != 0) ip_a_str(gw, gw_host);
        gw_port = 8080;
        gw_en_nube = 0;
    }
    actualizar_gw_label();
}

const char *scholar_gateway_str(void) {
    return gw_label;
}

/* Convierte UTF-8 del servidor a glifos 1-byte VGA de ARGOS (para TUI, edit y clip) */
static uint8_t s_utf8_vga(uint8_t a, uint8_t b) {
    if (a == 0xC3) {
        switch (b) {
            case 0x81: return 0x9B; /* Á */
            case 0x89: return 0x90; /* É */
            case 0x8D: return 0x9C; /* Í */
            case 0x93: return 0x9D; /* Ó */
            case 0x9A: return 0x9E; /* Ú */
            case 0x91: return 0xA5; /* Ñ */
            case 0x9C: return 0x9A; /* Ü */
            case 0xA1: return 0xA0; /* á */
            case 0xA9: return 0x82; /* é */
            case 0xAD: return 0xA1; /* í */
            case 0xB3: return 0xA2; /* ó */
            case 0xBA: return 0xA3; /* ú */
            case 0xB1: return 0xA4; /* ñ */
            case 0xBC: return 0x81; /* ü */
        }
    } else if (a == 0xC2) {
        switch (b) {
            case 0xBF: return 0xA8; /* ¿ */
            case 0xA1: return 0xAD; /* ¡ */
            case 0xBA: return 0xA7; /* º */
            case 0xB0: return 0xF8; /* ° */
        }
    }
    return '?';
}

static void copiar_utf8_a_vga(char *dst, int max_len, const char *src, int src_len) {
    int o = 0;
    for (int i = 0; i < src_len && o < max_len - 1; ) {
        uint8_t c = (uint8_t)src[i];
        if ((c == 0xC3 || c == 0xC2) && i + 1 < src_len && ((uint8_t)src[i + 1] & 0xC0) == 0x80) {
            dst[o++] = (char)s_utf8_vga(c, (uint8_t)src[i + 1]);
            i += 2;
        } else if (c >= 0x80) {
            i++;
            while (i < src_len && ((uint8_t)src[i] & 0xC0) == 0x80) i++;
            dst[o++] = ' ';
        } else if (c >= 32) {
            dst[o++] = (char)c;
            i++;
        } else {
            i++;
        }
    }
    dst[o] = '\0';
}

/* Codifica la consulta (que puede contener glifos 1-byte VGA en español) a UTF-8 URL-encoded */
static void url_append_pct(char *out, int *pos, int max_len, uint8_t b) {
    static const char hx[] = "0123456789ABCDEF";
    if (*pos + 3 >= max_len) return;
    out[(*pos)++] = '%';
    out[(*pos)++] = hx[(b >> 4) & 0xF];
    out[(*pos)++] = hx[b & 0xF];
}

static void vga_a_utf8_url(const char *in, char *out, int max_len) {
    int p = 0;
    for (int i = 0; in[i] && p < max_len - 7; i++) {
        uint8_t c = (uint8_t)in[i];
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.') {
            out[p++] = (char)c;
        } else if (c == ' ') {
            out[p++] = '+';
        } else if (c < 0x80) {
            url_append_pct(out, &p, max_len, c);
        } else {
            /* Mapear glifo VGA español a UTF-8 2 bytes */
            uint8_t b1 = 0xC3, b2 = 0;
            switch (c) {
                case 0xA0: b2 = 0xA1; break; /* á */
                case 0x82: b2 = 0xA9; break; /* é */
                case 0xA1: b2 = 0xAD; break; /* í */
                case 0xA2: b2 = 0xB3; break; /* ó */
                case 0xA3: b2 = 0xBA; break; /* ú */
                case 0xA4: b2 = 0xB1; break; /* ñ */
                case 0x81: b2 = 0xBC; break; /* ü */
                case 0x9B: b2 = 0x81; break; /* Á */
                case 0x90: b2 = 0x89; break; /* É */
                case 0x9C: b2 = 0x8D; break; /* Í */
                case 0x9D: b2 = 0x93; break; /* Ó */
                case 0x9E: b2 = 0x9A; break; /* Ú */
                case 0xA5: b2 = 0x91; break; /* Ñ */
                case 0x9A: b2 = 0x9C; break; /* Ü */
                default: b1 = 0; break;
            }
            if (b1 && b2) {
                url_append_pct(out, &p, max_len, b1);
                url_append_pct(out, &p, max_len, b2);
            }
        }
    }
    out[p] = '\0';
}

/* ---------- Parseo de respuesta estructurada de la pasarela ---------- */
static void limpiar_item(scholar_item_t *it) {
    it->title[0] = '\0';
    it->authors[0] = '\0';
    it->year[0] = '\0';
    it->cites[0] = '\0';
    it->url[0] = '\0';
    it->snippet[0] = '\0';
    it->apa[0] = '\0';
}

static int hdr_es_chunked(const char *hdr, int hdr_len) {
    const char *pat = "chunked";
    for (int i = 0; i + 7 <= hdr_len; i++) {
        int ok = 1;
        for (int k = 0; k < 7; k++) {
            char c = hdr[i + k];
            if (c >= 'A' && c <= 'Z') c = (char)(c + 32);
            if (c != pat[k]) { ok = 0; break; }
        }
        if (ok) return 1;
    }
    return 0;
}

static int decodificar_chunked_inplace(char *buf, int len) {
    int r = 0, w = 0;
    while (r < len) {
        while (r < len && (buf[r] == '\r' || buf[r] == '\n')) r++;
        if (r >= len) break;
        int csize = 0, dig = 0;
        while (r < len) {
            char c = buf[r];
            int v = -1;
            if (c >= '0' && c <= '9') v = c - '0';
            else if (c >= 'a' && c <= 'f') v = 10 + (c - 'a');
            else if (c >= 'A' && c <= 'F') v = 10 + (c - 'A');
            else break;
            csize = (csize << 4) | v;
            dig++;
            r++;
        }
        if (dig == 0) break;
        while (r < len && buf[r] != '\n') r++;
        if (r < len) r++; /* saltar '\n' */
        if (csize == 0) break;
        for (int k = 0; k < csize && r < len; k++) buf[w++] = buf[r++];
    }
    return w;
}

static int parsear_respuesta(char *raw, int total_len) {
    /* Saltar cabeceras HTTP (\r\n\r\n) */
    int body = -1;
    for (int i = 0; i + 3 < total_len; i++) {
        if (raw[i] == '\r' && raw[i + 1] == '\n' &&
            raw[i + 2] == '\r' && raw[i + 3] == '\n') {
            body = i + 4;
            break;
        }
    }
    if (body < 0) return -1;

    if (hdr_es_chunked(raw, body)) {
        int new_body_len = decodificar_chunked_inplace(raw + body, total_len - body);
        total_len = body + new_body_len;
    }

    num_resultados = 0;
    s_scpy(fuente_actual, "Google Scholar", sizeof(fuente_actual));
    int cur = -1;

    int i = body;
    while (i < total_len) {
        int j = i;
        while (j < total_len && raw[j] != '\n') j++;
        int llen = j - i;
        if (llen > 0 && raw[i + llen - 1] == '\r') llen--;

        const char *ln = raw + i;
        if (llen == 3 && ln[0] == '-' && ln[1] == '-' && ln[2] == '-') {
            if (num_resultados < MAX_SCHOLAR_RES) {
                cur = num_resultados++;
                limpiar_item(&resultados[cur]);
            } else {
                cur = -1;
            }
        } else if (llen == 3 && ln[0] == 'E' && ln[1] == 'N' && ln[2] == 'D') {
            break;
        } else if (llen > 8 && s_empieza(ln, "SOURCE: ")) {
            copiar_utf8_a_vga(fuente_actual, sizeof(fuente_actual), ln + 8, llen - 8);
        } else if (cur >= 0) {
            if (llen > 7 && s_empieza(ln, "TITLE: "))
                copiar_utf8_a_vga(resultados[cur].title, sizeof(resultados[cur].title), ln + 7, llen - 7);
            else if (llen > 9 && s_empieza(ln, "AUTHORS: "))
                copiar_utf8_a_vga(resultados[cur].authors, sizeof(resultados[cur].authors), ln + 9, llen - 9);
            else if (llen > 6 && s_empieza(ln, "YEAR: "))
                copiar_utf8_a_vga(resultados[cur].year, sizeof(resultados[cur].year), ln + 6, llen - 6);
            else if (llen > 7 && s_empieza(ln, "CITES: "))
                copiar_utf8_a_vga(resultados[cur].cites, sizeof(resultados[cur].cites), ln + 7, llen - 7);
            else if (llen > 5 && s_empieza(ln, "URL: "))
                copiar_utf8_a_vga(resultados[cur].url, sizeof(resultados[cur].url), ln + 5, llen - 5);
            else if (llen > 9 && s_empieza(ln, "SNIPPET: "))
                copiar_utf8_a_vga(resultados[cur].snippet, sizeof(resultados[cur].snippet), ln + 9, llen - 9);
            else if (llen > 5 && s_empieza(ln, "APA: "))
                copiar_utf8_a_vga(resultados[cur].apa, sizeof(resultados[cur].apa), ln + 5, llen - 5);
        }

        i = j + 1;
    }

    /* Descartar el ultimo si quedo vacio */
    while (num_resultados > 0 && resultados[num_resultados - 1].title[0] == '\0') {
        num_resultados--;
    }
    return num_resultados;
}

/* ---------- Ejecucion de consulta por TCP/HTTP ---------- */
static int ejecutar_busqueda(const char *query, const char **err_out) {
    if (!net_tiene_ip()) {
        if (net_listo() && net_dhcp(1) == 0) {
            scholar_init();
        } else {
            if (err_out) *err_out = "Sin conexión a Internet. Revisa Red -> NAT (Intel PRO/1000).";
            return -1;
        }
    }

    char q_enc[240];
    vga_a_utf8_url(query, q_enc, sizeof(q_enc));
    if (!q_enc[0]) {
        if (err_out) *err_out = "La consulta está vacía.";
        return -1;
    }

    char ruta[280];
    int p = 0;
    const char *pre = "/search?q=";
    const char *suf = "&n=6";
    for (int i = 0; pre[i]; i++) ruta[p++] = pre[i];
    for (int i = 0; q_enc[i] && p < 268; i++) ruta[p++] = q_enc[i];
    for (int i = 0; suf[i] && p < 279; i++) ruta[p++] = suf[i];
    ruta[p] = '\0';

    int code = 0;
    int n = net_http_get(gw_host, gw_port, ruta, rx_buf, SCHOLAR_RX_SZ, &code);
    if (n < 0) {
        if (err_out) *err_out = gw_en_nube ? "No se pudo conectar al servidor académico. Revisa tu Internet." : "No responde la pasarela local (10.0.2.2:8080).";
        return -2;
    }
    if (code != 200) {
        if (err_out) *err_out = "La pasarela devolvió un error HTTP.";
        return -3;
    }

    int count = parsear_respuesta(rx_buf, n);
    if (count <= 0) {
        if (err_out) *err_out = "No se encontraron artículos académicos para esa consulta.";
        return 0;
    }

    s_scpy(ultima_consulta, query, sizeof(ultima_consulta));
    audit_registrar(LOG_INFO, kernel_usuario_corto(), "SCHOLAR", query);
    return count;
}

/* ---------- Helpers visuales de la interfaz TUI ---------- */
static void dibujar_envuelto(int x0, int y0, int ancho, int max_lineas, uint8_t color, const char *txt) {
    int len = s_slen(txt);
    int pos = 0;
    for (int l = 0; l < max_lineas && pos < len; l++) {
        while (pos < len && txt[pos] == ' ') pos++;
        if (pos >= len) break;
        int take = len - pos;
        if (take > ancho) {
            take = ancho;
            /* Intentar cortar en el ultimo espacio para no partir palabras */
            if (l < max_lineas - 1) {
                int sp = take;
                while (sp > 10 && txt[pos + sp] != ' ') sp--;
                if (txt[pos + sp] == ' ') take = sp;
            }
        }
        char linea[81];
        int k = 0;
        for (int i = 0; i < take && k < 80; i++) linea[k++] = txt[pos + i];
        if (l == max_lineas - 1 && pos + take < len && k >= 3) {
            linea[k - 3] = '.'; linea[k - 2] = '.'; linea[k - 1] = '.';
        }
        linea[k] = '\0';
        kvga_texto_en(x0, y0 + l, color, linea);
        pos += take;
    }
}

static int popup_texto(const char *titulo, const char *etiqueta, char *buf, int max_len) {
    int len = s_slen(buf);
    int cur = len;
    const int x0 = 10, y0 = 9, ancho = 60, alto = 7;

    while (1) {
        kvga_dibujar_caja(x0, y0, ancho, alto, 0x1F, 0x1B);
        kvga_texto_en(x0 + 3, y0 + 1, 0x1E, titulo);
        kvga_texto_en(x0 + 3, y0 + 3, 0x1F, etiqueta);

        int fx = x0 + 3 + s_slen(etiqueta);
        int fw = (x0 + ancho - 3) - fx;
        if (fw > 42) fw = 42;
        char vacio[45];
        for (int i = 0; i < fw; i++) vacio[i] = ' ';
        vacio[fw] = '\0';
        kvga_texto_en(fx, y0 + 3, 0x0F, vacio);

        int view_start = (cur >= fw) ? (cur - fw + 1) : 0;
        char vis[45];
        int vn = 0;
        for (int i = view_start; i < len && vn < fw; i++) vis[vn++] = buf[i];
        vis[vn] = '\0';
        kvga_texto_en(fx, y0 + 3, 0x0F, vis);

        kvga_texto_en(x0 + 3, y0 + 5, 0x17, "Enter: aceptar  |  ESC: cancelar");
        kset_cursor(fx + (cur - view_start), y0 + 3);

        int k = teclado_getkey();
        if (k == KEY_ESC) return 0;
        if (k == KEY_ENTER) { buf[len] = '\0'; return 1; }
        if (k == KEY_LEFT) { if (cur > 0) cur--; }
        else if (k == KEY_RIGHT) { if (cur < len) cur++; }
        else if (k == KEY_HOME) { cur = 0; }
        else if (k == KEY_END) { cur = len; }
        else if (k == KEY_BS) {
            if (cur > 0) {
                for (int i = cur; i <= len; i++) buf[i - 1] = buf[i];
                cur--; len--;
            }
        } else if (k == KEY_DEL) {
            if (cur < len) {
                for (int i = cur + 1; i <= len; i++) buf[i - 1] = buf[i];
                len--;
            }
        } else if (k == KEY_CTRL_V) {
            const char *cl = clip_obtener();
            int clen = clip_largo();
            for (int i = 0; i < clen && len < max_len - 1; i++) {
                uint8_t ch = (uint8_t)cl[i];
                if (ch < 32) continue;
                for (int j = len; j >= cur; j--) buf[j + 1] = buf[j];
                buf[cur++] = (char)ch;
                len++;
            }
        } else if (k >= 32 && k < 0x100 && len < max_len - 1) {
            for (int j = len; j >= cur; j--) buf[j + 1] = buf[j];
            buf[cur++] = (char)k;
            len++;
        }
    }
}

static void construir_doc_cita(const scholar_item_t *it, char *out, int max_len) {
    int p = 0;
    const char *partes[18] = {
        "=== REFERENCIA ACADEMICA (ARGOS SCHOLAR) ===\n",
        "Titulo : ", it->title, "\n",
        "Autores: ", it->authors, "\n",
        "Anio   : ", it->year, " | Citas: ", it->cites, "\n",
        "Fuente : ", fuente_actual, "\n",
        "Enlace : ", it->url, "\n\nCita APA:\n"
    };
    for (int k = 0; k < 18; k++) {
        for (int i = 0; partes[k][i] && p < max_len - 1; i++) out[p++] = partes[k][i];
    }
    for (int i = 0; it->apa[i] && p < max_len - 1; i++) out[p++] = it->apa[i];
    if (p < max_len - 1) out[p++] = '\n';
    out[p] = '\0';
}

static void pantalla_buscando(const char *query) {
    kvga_barra_titulo("ARGOS SCHOLAR - BUSCANDO...");
    kvga_limpiar_area(1, 24, 0x07);
    kvga_dibujar_caja(12, 8, 56, 7, 0x1F, 0x1B);
    kvga_texto_en(15, 10, 0x1E, "Consultando Google Académico vía TCP/IP...");
    kvga_texto_en(15, 11, 0x1F, "Tema    : ");
    dibujar_envuelto(25, 11, 40, 1, 0x1B, query);
    kvga_texto_en(15, 12, 0x17, "Pasarela: ");
    kvga_texto_en(25, 12, 0x17, gw_label);
    kset_cursor(15, 13);
}

/* ---------- Visor interactivo 80x25 de resultados ---------- */
static void scholar_visor(void) {
    int sel = 0;
    char aviso[76];
    aviso[0] = '\0';

    while (1) {
        kvga_barra_titulo("ARGOS SCHOLAR - BUSCADOR ACADÉMICO");
        kvga_limpiar_area(1, 24, 0x07);

        /* Fila 1: Resumen de busqueda */
        kvga_texto_en(1, 1, 0x0B, "Tema: ");
        dibujar_envuelto(7, 1, 33, 1, 0x0F, ultima_consulta);
        kvga_texto_en(41, 1, 0x08, "| Fuente: ");
        dibujar_envuelto(51, 1, 28, 1, 0x0A, fuente_actual);

        /* Fila 2: Encabezado de lista */
        kvga_texto_en(1, 2, 0x0D, "Resultados (Flechas Arr/Abj):");

        /* Filas 3..8: Lista de hasta 6 articulos */
        for (int i = 0; i < num_resultados && i < 6; i++) {
            int y = 3 + i;
            uint8_t col = (i == sel) ? 0x30 : 0x07;
            if (i == sel) {
                char fila[81];
                for (int c = 0; c < COLS; c++) fila[c] = ' ';
                fila[COLS] = '\0';
                kvga_texto_en(0, y, 0x30, fila);
            }

            char pref[20];
            int p = 0;
            pref[p++] = (i == sel) ? '>' : ' ';
            pref[p++] = ' ';
            pref[p++] = (char)('1' + i);
            pref[p++] = '.';
            pref[p++] = ' ';
            pref[p++] = '[';
            for (int k = 0; resultados[i].year[k] && k < 4; k++) pref[p++] = resultados[i].year[k];
            pref[p++] = ']';
            pref[p++] = ' ';
            pref[p] = '\0';

            kvga_texto_en(0, y, (i == sel) ? 0x30 : 0x0E, pref);
            dibujar_envuelto(p, y, 56, 1, col, resultados[i].title);

            char cbuf[16];
            int cp = 0;
            cbuf[cp++] = '(';
            for (int k = 0; resultados[i].cites[k] && cp < 8; k++) cbuf[cp++] = resultados[i].cites[k];
            const char *csuf = " cit)";
            for (int k = 0; csuf[k] && cp < 15; k++) cbuf[cp++] = csuf[k];
            cbuf[cp] = '\0';
            kvga_texto_en(68, y, (i == sel) ? 0x30 : 0x08, cbuf);
        }

        /* Fila 9: Separador */
        char sep[81];
        for (int c = 0; c < COLS; c++) sep[c] = '-';
        sep[COLS] = '\0';
        kvga_texto_en(0, 9, 0x05, sep);
        kvga_texto_en(2, 9, 0x0D, " Detalle del artículo ");

        /* Filas 10..22: Tarjeta de detalle */
        const scholar_item_t *it = &resultados[sel];
        kvga_texto_en(1, 10, 0x0B, "Título : ");
        dibujar_envuelto(10, 10, 69, 2, 0x0F, it->title);

        kvga_texto_en(1, 12, 0x0B, "Autores: ");
        dibujar_envuelto(10, 12, 69, 1, 0x07, it->authors);

        kvga_texto_en(1, 13, 0x0B, "Año    : ");
        kvga_texto_en(10, 13, 0x0E, it->year);
        kvga_texto_en(17, 13, 0x0B, "| Citas: ");
        kvga_texto_en(26, 13, 0x0A, it->cites);

        kvga_texto_en(1, 15, 0x0B, "Resumen:");
        dibujar_envuelto(10, 15, 69, 3, 0x07, it->snippet);

        kvga_texto_en(1, 18, 0x0B, "Enlace : ");
        dibujar_envuelto(10, 18, 69, 2, 0x0B, it->url);

        kvga_texto_en(1, 20, 0x0E, "APA    : ");
        dibujar_envuelto(10, 20, 69, 3, 0x0E, it->apa);

        /* Fila 24: Barra inferior de atajos / aviso */
        char bar[81];
        for (int c = 0; c < COLS; c++) bar[c] = ' ';
        bar[COLS] = '\0';
        kvga_texto_en(0, 24, 0x1F, bar);
        if (aviso[0]) {
            kvga_texto_en(1, 24, 0x1E, aviso);
            aviso[0] = '\0';
        } else {
            kvga_texto_en(1, 24, 0x1F, "Arr/Abj: Elegir | G: Guardar APA | C: Copiar APA | N: Nueva | ESC: Salir");
        }
        kset_cursor(0, 3 + sel);

        int k = teclado_getkey();
        if (k == KEY_ESC || k == 'q' || k == 'Q') {
            break;
        } else if (k == KEY_UP) {
            sel = (sel + num_resultados - 1) % num_resultados;
        } else if (k == KEY_DOWN) {
            sel = (sel + 1) % num_resultados;
        } else if (k >= '1' && k <= '6') {
            int idx = k - '1';
            if (idx < num_resultados) sel = idx;
        } else if (k == 'c' || k == 'C' || k == KEY_CTRL_C) {
            clip_copiar(it->apa, s_slen(it->apa));
            s_scpy(aviso, "Cita APA copiada al portapapeles (usa Ctrl+V en consola o edit)", sizeof(aviso));
        } else if (k == 'g' || k == 'G' || k == KEY_ENTER) {
            char fname[33] = "cita_1.txt";
            fname[5] = (char)('1' + sel);
            if (popup_texto("Guardar referencia en TIC340FS", "Archivo: ", fname, 32)) {
                char doc[1536];
                construir_doc_cita(it, doc, sizeof(doc));
                const char *err = 0;
                if (fs_guardar_silencioso(fname, doc, &err) == 0) {
                    int p = 0;
                    const char *m1 = "Guardado '";
                    const char *m2 = "' en RAM (ejecuta 'save' para disco)";
                    for (int i = 0; m1[i] && p < 74; i++) aviso[p++] = m1[i];
                    for (int i = 0; fname[i] && p < 74; i++) aviso[p++] = fname[i];
                    for (int i = 0; m2[i] && p < 74; i++) aviso[p++] = m2[i];
                    aviso[p] = '\0';
                } else {
                    s_scpy(aviso, err ? err : "Error al guardar cita", sizeof(aviso));
                }
            }
        } else if (k == 'n' || k == 'N') {
            char nueva_q[96];
            nueva_q[0] = '\0';
            if (popup_texto("Nueva búsqueda en Google Académico", "Tema: ", nueva_q, 90) && nueva_q[0]) {
                pantalla_buscando(nueva_q);
                const char *err = 0;
                int r = ejecutar_busqueda(nueva_q, &err);
                if (r > 0) {
                    sel = 0;
                } else {
                    s_scpy(aviso, err ? err : "Sin resultados para la nueva búsqueda", sizeof(aviso));
                }
            }
        }
    }

    kclear();
}

/* ---------- Comando principal: scholar ---------- */
static void cmd_scholar_status(void) {
    kset_color(0x0D); kprint("=== Estado de ARGOS Scholar (Módulo 6) ===\n");
    kset_color(0x0B); kprint("  Pasarela : ");
    kset_color(0x0F); kprint(gw_label); kprint("\n");
    kset_color(0x0B); kprint("  Red OS   : ");
    if (!net_tiene_ip() && net_listo()) {
        if (net_dhcp(1) == 0) scholar_init();
    }
    if (!net_tiene_ip()) {
        kset_color(0x0C); kprint("Sin IP (ejecuta 'net dhcp' o revisa Intel PRO/1000 en VirtualBox)\n");
        kset_color(0x07);
        return;
    }
    kset_color(0x0A); kprint("IP "); net_imprimir_ip(net_mi_ip()); kprint("\n");

    kset_color(0x0B); kprint("  Conexión : ");
    kset_color(0x07); kprint("Probando /health...\n");
    int code = 0;
    int n = net_http_get(gw_host, gw_port, "/health", rx_buf, 1024, &code);
    if (n > 0 && code == 200) {
        kset_color(0x0A); kprint("  Estado   : EN LÍNEA (HTTP 200) - Pasarela lista para Google Académico\n");
    } else {
        kset_color(0x0C); kprint("  Estado   : SIN RESPUESTA\n");
        kset_color(0x07);
        kprint("  Ejecuta en Windows/WSL: python argos_scholar_gateway.py\n");
        kprint("  Si cambiaste la IP del host usa: scholar gw <ip:puerto>\n");
    }
    kset_color(0x07);
}

static void cmd_scholar_gw(const char *arg) {
    while (*arg == ' ') arg++;
    if (!*arg) {
        kprint("Pasarela actual: "); kprint(gw_label); kprint("\n");
        kprint("Uso: scholar gw <ip[:puerto]>   (ej: scholar gw 10.0.2.2:8080)\n");
        return;
    }
    char nh[64];
    int hi = 0;
    const char *p = arg;
    while (*p && *p != ':' && *p != ' ' && hi < 63) nh[hi++] = *p++;
    nh[hi] = '\0';
    if (!nh[0]) { kprint("Error: dirección inválida.\n"); return; }

    uint16_t np = 8080;
    if (*p == ':') {
        p++;
        uint32_t v = 0;
        while (*p >= '0' && *p <= '9') { v = v * 10 + (uint32_t)(*p - '0'); p++; }
        if (v < 1 || v > 65535) { kprint("Error: puerto inválido (1..65535).\n"); return; }
        np = (uint16_t)v;
    }
    s_scpy(gw_host, nh, sizeof(gw_host));
    gw_port = np;
    actualizar_gw_label();
    kprint("Pasarela actualizada a: "); kprint(gw_label); kprint("\n");
}

void scholar_cmd(const char *args) {
    while (*args == ' ') args++;
    if (!*args) {
        kset_color(0x0D); kprint("=== ARGOS Scholar - Buscador Académico ===\n");
        kset_color(0x07);
        kprint("  scholar <tema>          : Busca artículos en Google Académico\n");
        kprint("  scholar status          : Verifica la conexión con la pasarela\n");
        kprint("  scholar gw <ip[:port]>  : Configura la pasarela (actual: ");
        kprint(gw_label); kprint(")\n");
        kset_color(0x08);
        kprint("  Ejemplo: scholar sistemas operativos paginación\n");
        kset_color(0x07);
        return;
    }

    if (s_igual(args, "status")) {
        cmd_scholar_status();
        return;
    }
    if (s_empieza(args, "gw") && (args[2] == '\0' || args[2] == ' ')) {
        cmd_scholar_gw(args + 2);
        return;
    }

    pantalla_buscando(args);
    const char *err = 0;
    int r = ejecutar_busqueda(args, &err);
    if (r > 0) {
        scholar_visor();
        kset_color(0x0A); kprint("ARGOS Scholar: ");
        kset_color(0x07); kprint("sesión finalizada (última búsqueda: \"");
        kprint(ultima_consulta); kprint("\").\n");
    } else {
        kclear();
        kset_color(0x0C); kprint("ARGOS Scholar - Error: ");
        kset_color(0x07); kprint(err ? err : "No se pudieron obtener resultados.");
        kprint("\n");
        kset_color(0x08);
        kprint("  Verifica con 'scholar status' y asegúrate de tener corriendo:\n");
        kprint("  python argos_scholar_gateway.py\n");
        kset_color(0x07);
    }
}

int scholar_probar_salud(void) {
    if (!net_tiene_ip() && net_listo()) {
        if (net_dhcp(1) == 0) scholar_init();
    }
    if (!net_tiene_ip()) return -1;
    int code = 0;
    int n = net_http_get(gw_host, gw_port, "/health", rx_buf, 1024, &code);
    return (n > 0 && code == 200) ? 0 : -2;
}

void scholar_abrir_desde_menu(void) {
    char tema[96];
    s_scpy(tema, ultima_consulta, sizeof(tema));
    if (!popup_texto("Buscador Google Académico", "Tema: ", tema, 90) || !tema[0]) {
        return;
    }
    pantalla_buscando(tema);
    const char *err = 0;
    int r = ejecutar_busqueda(tema, &err);
    if (r > 0) {
        scholar_visor();
    } else {
        kvga_barra_titulo("ARGOS SCHOLAR - AVISO");
        kvga_limpiar_area(1, 24, 0x07);
        kvga_dibujar_caja(8, 8, 64, 9, 0x1F, 0x1C);
        kvga_texto_en(11, 10, 0x1E, "No se pudo completar la búsqueda:");
        dibujar_envuelto(11, 11, 58, 2, 0x1F, err ? err : "Sin resultados.");
        kvga_texto_en(11, 14, 0x17, gw_en_nube ? "Verifica tu conexión a Internet o intenta de nuevo en unos segundos." : "Inicia la pasarela en tu PC o configura una pasarela en la nube.");
        kvga_texto_en(11, 15, 0x1B, "Pulsa cualquier tecla para volver al Menú Principal...");
        kset_cursor(11, 15);
        teclado_getkey();
    }
}
