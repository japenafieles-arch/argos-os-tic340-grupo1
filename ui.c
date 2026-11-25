/*
 * Modulo 8 (Bloque 1): Gestion de Archivos Completa en Modo Facil + Temas y Preferencias
 *  - Menu Principal con opcion "Crear Archivo o Carpeta"
 *  - Explorador Visual completo: Abrir, Nuevo archivo (N), Nueva carpeta (C/K),
 *    Renombrar (R), Copiar (P), Mover con selector de carpetas (M),
 *    Buscar texto interactivo (B), Eliminar (D) y Guardar en disco (G)
 *  - Ajustes persistentes en disco ATA: Teclado, Zona Horaria, Tema Visual e Internet
 */
#include <stdint.h>
#include "ui.h"
#include "fs.h"
#include "teclado.h"
#include "net.h"
#include "scholar.h"
#include "reloj.h"
#include "mem.h"
#include "proc.h"
#include "audit.h"
#include "apps.h"
#include "juegos.h"

#define COLS 80
#define MAX_HITS_UI 32

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
extern const char *kernel_usuario_nombre_completo(void);
extern const char *kernel_usuario_desc_permisos(void);
extern void kernel_mostrar_sysinfo(void);
extern void kernel_guardar_prefs(void);

extern int         kernel_get_tema(void);
extern void        kernel_set_tema(int t);
extern const char *kernel_tema_nombre(void);
extern uint8_t     kcol_fondo(void);
extern uint8_t     kcol_barra(void);
extern uint8_t     kcol_caja(void);
extern uint8_t     kcol_borde(void);
extern uint8_t     kcol_caja_tit(void);
extern uint8_t     kcol_caja_ten(void);
extern uint8_t     kcol_sel(void);
extern uint8_t     kcol_acento(void);
extern uint8_t     kcol_titulo(void);
extern uint8_t     kcol_ok(void);
extern uint8_t     kcol_aviso(void);
extern uint8_t     kcol_tenue(void);
extern uint8_t     kcol_dato(void);

static fs_item_t     exp_items[MAX_NODOS];
static fs_find_hit_t find_hits[MAX_HITS_UI];
static char          visor_buf[MAX_DATOS];

static int u_slen(const char *s) { int n = 0; while (s[n]) n++; return n; }

static void u_scpy(char *d, const char *s, int max) {
    int i = 0;
    while (i < max - 1 && s && s[i]) { d[i] = s[i]; i++; }
    d[i] = '\0';
}

static void u_uint_str(uint32_t v, char *out) {
    char tmp[12];
    int n = 0;
    do { tmp[n++] = (char)('0' + (v % 10)); v /= 10; } while (v);
    for (int i = 0; i < n; i++) out[i] = tmp[n - 1 - i];
    out[n] = '\0';
}

static void u_ip_str(uint32_t ip, char *out) {
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

static void barra_inferior(const char *texto, int es_aviso) {
    uint8_t col_bg = kcol_barra();
    uint8_t col_fg = es_aviso ? ((uint8_t)((col_bg & 0xF0) | 0x0E)) : col_bg;
    if (kernel_get_tema() == 2 && es_aviso) col_fg = 0x2F;
    char vacio[81];
    for (int i = 0; i < COLS; i++) vacio[i] = ' ';
    vacio[COLS] = '\0';
    kvga_texto_en(0, 24, col_bg, vacio);
    kvga_texto_en(1, 24, col_fg, texto);
}

static int popup_entrada(const char *titulo, const char *etiqueta, char *buf, int max_len) {
    int len = u_slen(buf);
    int cur = len;
    const int x0 = 9, y0 = 9, ancho = 62, alto = 7;

    while (1) {
        kvga_dibujar_caja(x0, y0, ancho, alto, kcol_caja(), kcol_borde());
        kvga_texto_en(x0 + 3, y0 + 1, kcol_caja_tit(), titulo);
        kvga_texto_en(x0 + 3, y0 + 3, kcol_caja(), etiqueta);

        int fx = x0 + 3 + u_slen(etiqueta);
        int fw = (x0 + ancho - 3) - fx;
        if (fw > 40) fw = 40;
        char vacio[42];
        for (int i = 0; i < fw; i++) vacio[i] = ' ';
        vacio[fw] = '\0';
        kvga_texto_en(fx, y0 + 3, 0x0F, vacio);

        int vs = (cur >= fw) ? (cur - fw + 1) : 0;
        char vis[42];
        int vn = 0;
        for (int i = vs; i < len && vn < fw; i++) vis[vn++] = buf[i];
        vis[vn] = '\0';
        kvga_texto_en(fx, y0 + 3, 0x0F, vis);

        kvga_texto_en(x0 + 3, y0 + 5, kcol_caja_ten(), "Enter: aceptar  |  ESC: cancelar");
        kset_cursor(fx + (cur - vs), y0 + 3);

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

static int popup_confirmar(const char *pregunta, const char *detalle) {
    int op = 0; /* 0 = No (seguro por defecto), 1 = Si */
    const int x0 = 13, y0 = 8, ancho = 54, alto = 9;

    while (1) {
        kvga_dibujar_caja(x0, y0, ancho, alto, kcol_caja(), kcol_borde());
        kvga_texto_en(x0 + 4, y0 + 2, kcol_caja_tit(), pregunta);
        kvga_texto_en(x0 + 4, y0 + 3, kcol_caja(), detalle);

        kvga_texto_en(x0 + 12, y0 + 5, op == 1 ? kcol_sel() : kcol_caja_ten(), "  [  Sí  ]  ");
        kvga_texto_en(x0 + 28, y0 + 5, op == 0 ? kcol_sel() : kcol_caja_ten(), "  [  No  ]  ");
        kvga_texto_en(x0 + 5, y0 + 7, kcol_caja_ten(), "Flechas Izq/Der: elegir | Enter: aceptar");
        kset_cursor(op == 1 ? x0 + 17 : x0 + 33, y0 + 5);

        int k = teclado_getkey();
        if (k == KEY_LEFT || k == KEY_RIGHT || k == KEY_TAB) op = !op;
        else if (k == KEY_ENTER) return op;
        else if (k == KEY_ESC) return 0;
    }
}

/* Selector simple de 2 opciones para "Crear Archivo o Carpeta"
 * Devuelve: 1 = Archivo, 2 = Carpeta, 0 = Cancelar
 */
static int popup_elegir_crear(void) {
    int op = 0;
    const int x0 = 12, y0 = 8, ancho = 56, alto = 9;

    while (1) {
        kvga_dibujar_caja(x0, y0, ancho, alto, kcol_caja(), kcol_borde());
        kvga_texto_en(x0 + 16, y0 + 2, kcol_caja_tit(), "¿QUÉ DESEAS CREAR?");
        kvga_texto_en(x0 + 6, y0 + 3, kcol_caja(), "Elige si quieres escribir una nota o hacer carpeta:");

        kvga_texto_en(x0 + 6,  y0 + 5, op == 0 ? kcol_sel() : kcol_caja_ten(), " [ 1. Archivo .txt ] ");
        kvga_texto_en(x0 + 31, y0 + 5, op == 1 ? kcol_sel() : kcol_caja_ten(), " [ 2. Nueva Carpeta ] ");
        kvga_texto_en(x0 + 7, y0 + 7, kcol_caja_ten(), "Flechas Izq/Der o 1/2 | Enter: elegir | ESC");
        kset_cursor(op == 0 ? x0 + 9 : x0 + 34, y0 + 5);

        int k = teclado_getkey();
        if (k == KEY_LEFT || k == KEY_RIGHT || k == KEY_TAB) op = !op;
        else if (k == '1') return 1;
        else if (k == '2') return 2;
        else if (k == KEY_ENTER) return op + 1;
        else if (k == KEY_ESC) return 0;
    }
}

/* ---------- Visor de solo lectura (para Invitado o archivos protegidos) ---------- */
static void visor_archivo_lectura(const char *nombre) {
    int n = fs_leer_archivo_buf(nombre, visor_buf, sizeof(visor_buf));
    if (n < 0) return;

    int scroll = 0;
    const char *aviso = "";
    while (1) {
        kvga_barra_titulo("VISOR DE DOCUMENTO (SOLO LECTURA)");
        kvga_limpiar_area(1, 23, kcol_fondo());

        kvga_texto_en(1, 1, kcol_acento(), "Archivo: ");
        kvga_texto_en(10, 1, kcol_dato(), nombre);
        char bstr[16];
        u_uint_str((uint32_t)n, bstr);
        kvga_texto_en(44, 1, kcol_tenue(), "| Tamaño: ");
        kvga_texto_en(54, 1, kcol_fondo(), bstr);
        kvga_texto_en(54 + u_slen(bstr), 1, kcol_fondo(), " bytes");

        int r = 0, c = 0;
        for (int i = 0; i < n; i++) {
            char ch = visor_buf[i];
            if (ch == '\n') { r++; c = 0; continue; }
            if (r >= scroll && r < scroll + 20) {
                char s2[2] = { ch, '\0' };
                kvga_texto_en(1 + c, 3 + (r - scroll), kcol_fondo(), s2);
            }
            c++;
            if (c >= 78) { r++; c = 0; }
        }
        int total_lineas = r + 1;

        if (aviso[0]) {
            barra_inferior(aviso, 1);
            aviso = "";
        } else {
            barra_inferior("Arr/Abj/RePág/AvPág: Desplazar | C: Copiar todo | ESC: Volver", 0);
        }
        kset_cursor(1, 1);

        int k = teclado_getkey();
        if (k == KEY_ESC || k == 'q' || k == 'Q') break;
        else if (k == KEY_UP && scroll > 0) scroll--;
        else if (k == KEY_DOWN && scroll + 20 < total_lineas) scroll++;
        else if (k == KEY_PGUP) { scroll -= 10; if (scroll < 0) scroll = 0; }
        else if (k == KEY_PGDN) {
            scroll += 10;
            if (scroll + 20 >= total_lineas) scroll = (total_lineas > 20) ? (total_lineas - 20) : 0;
        }
        else if (k == 'c' || k == 'C' || k == KEY_CTRL_C) {
            if (n > 0) {
                clip_copiar(visor_buf, n);
                aviso = "Contenido copiado al portapapeles (usa Ctrl+V)";
            }
        }
    }
}

/* ---------- Selector visual de carpeta destino para Mover (M) ---------- */
static int popup_elegir_destino_mover(const char *origen, int en_raiz,
                                      const fs_item_t *items, int cnt,
                                      char *dest_out, int max_out) {
    const char *dests[34];
    const char *etiquetas[34];
    char lbl_sub[32][42];
    int n = 0;

    if (!en_raiz) {
        dests[n] = "..";
        etiquetas[n] = "..  (Carpeta superior)";
        n++;
        dests[n] = "/";
        etiquetas[n] = "/   (Carpeta raíz principal)";
        n++;
    }
    for (int i = 0; i < cnt && n < 34; i++) {
        if (items[i].tipo == NODO_DIR) {
            /* No ofrecer la misma carpeta que se esta moviendo */
            int mismo = 1;
            for (int k = 0; origen[k] || items[i].nombre[k]; k++) {
                if (origen[k] != items[i].nombre[k]) { mismo = 0; break; }
            }
            if (mismo) continue;
            int li = n < 32 ? n : 31;
            int p = 0;
            const char *pre = "[CARPETA] ";
            for (int k = 0; pre[k]; k++) lbl_sub[li][p++] = pre[k];
            for (int k = 0; items[i].nombre[k] && p < 40; k++) lbl_sub[li][p++] = items[i].nombre[k];
            lbl_sub[li][p] = '\0';
            dests[n] = items[i].nombre;
            etiquetas[n] = lbl_sub[li];
            n++;
        }
    }

    if (n == 0) return -1; /* no hay carpetas destino disponibles */

    int sel = 0, scr = 0;
    const int x0 = 13, y0 = 6, ancho = 54, alto = 13;

    while (1) {
        if (sel < scr) scr = sel;
        if (sel >= scr + 7) scr = sel - 6;

        kvga_dibujar_caja(x0, y0, ancho, alto, kcol_caja(), kcol_borde());
        kvga_texto_en(x0 + 3, y0 + 1, kcol_caja_tit(), "Mover a qué carpeta:");
        kvga_texto_en(x0 + 25, y0 + 1, kcol_caja(), origen);

        for (int r = 0; r < 7 && (scr + r) < n; r++) {
            int idx = scr + r;
            int y = y0 + 3 + r;
            uint8_t col = (idx == sel) ? kcol_sel() : kcol_caja();
            char bg[51];
            for (int c = 0; c < 50; c++) bg[c] = ' ';
            bg[50] = '\0';
            kvga_texto_en(x0 + 2, y, col, bg);
            kvga_texto_en(x0 + 3, y, col, idx == sel ? "> " : "  ");
            kvga_texto_en(x0 + 5, y, col, etiquetas[idx]);
        }

        kvga_texto_en(x0 + 4, y0 + 11, kcol_caja_ten(), "Arr/Abj: elegir | Enter: mover | ESC: cancelar");
        kset_cursor(x0 + 3, y0 + 3 + (sel - scr));

        int k = teclado_getkey();
        if (k == KEY_ESC) return 0;
        else if (k == KEY_UP) sel = (sel + n - 1) % n;
        else if (k == KEY_DOWN) sel = (sel + 1) % n;
        else if (k == KEY_ENTER) {
            u_scpy(dest_out, dests[sel], max_out);
            return 1;
        }
    }
}

/* ---------- Buscador Visual Interactivo (B) ---------- */
static void ui_buscar_archivos(void) {
    char patron[48] = "";
    if (!popup_entrada("Buscar en mis Archivos y Carpetas", "Texto a buscar: ", patron, 44) || !patron[0]) {
        return;
    }

    int total = fs_buscar_resultados(patron, find_hits, MAX_HITS_UI);
    int sel = 0, scroll = 0;

    while (1) {
        kvga_barra_titulo("ARGOS - RESULTADOS DE BÚSQUEDA");
        kvga_limpiar_area(1, 23, kcol_fondo());

        kvga_texto_en(2, 2, kcol_acento(), "Búsqueda: ");
        kvga_texto_en(12, 2, kcol_dato(), patron);

        char nstr[12];
        u_uint_str((uint32_t)total, nstr);
        kvga_texto_en(52, 2, kcol_tenue(), "Encontrados: ");
        kvga_texto_en(65, 2, total > 0 ? kcol_ok() : kcol_aviso(), nstr);

        kvga_dibujar_caja(2, 4, 76, 18, kcol_fondo(), kcol_acento());
        kvga_texto_en(4, 5, kcol_acento(), "COINCIDENCIA   TIPO        RUTA COMPLETA");

        if (total == 0) {
            kvga_texto_en(20, 11, kcol_tenue(), "No se encontraron archivos ni carpetas.");
            kvga_texto_en(18, 13, kcol_fondo(), "Pulsa N para otra búsqueda o ESC para volver.");
        } else {
            if (sel < scroll) scroll = sel;
            if (sel >= scroll + 14) scroll = sel - 13;

            for (int r = 0; r < 14 && (scroll + r) < total; r++) {
                int idx = scroll + r;
                int y = 6 + r;
                int is_sel = (idx == sel);
                uint8_t col = is_sel ? kcol_sel() : kcol_fondo();

                char bg[75];
                for (int c = 0; c < 74; c++) bg[c] = ' ';
                bg[74] = '\0';
                kvga_texto_en(3, y, col, bg);

                kvga_texto_en(4, y, is_sel ? col : (find_hits[idx].por_contenido ? kcol_aviso() : kcol_ok()),
                              find_hits[idx].por_contenido ? "[CONTENIDO]" : "[NOMBRE]   ");
                kvga_texto_en(19, y, is_sel ? col : kcol_acento(),
                              find_hits[idx].tipo == NODO_DIR ? "[CARPETA]" : "[ARCHIVO]");
                kvga_texto_en(31, y, is_sel ? col : kcol_dato(), find_hits[idx].ruta);
            }
        }

        barra_inferior(total > 0 ? "Arr/Abj: Elegir | Enter: Ir y abrir | N: Nueva búsqueda | ESC: Volver"
                                 : "N: Nueva búsqueda | ESC: Volver al explorador", 0);
        kset_cursor(3, total > 0 ? (6 + (sel - scroll)) : 11);

        int k = teclado_getkey();
        if (k == KEY_ESC || k == 'q' || k == 'Q') break;
        else if (k == KEY_UP && total > 0) sel = (sel + total - 1) % total;
        else if (k == KEY_DOWN && total > 0) sel = (sel + 1) % total;
        else if (k == 'n' || k == 'N') {
            patron[0] = '\0';
            if (popup_entrada("Nueva búsqueda", "Texto a buscar: ", patron, 44) && patron[0]) {
                total = fs_buscar_resultados(patron, find_hits, MAX_HITS_UI);
                sel = 0; scroll = 0;
            }
        } else if (k == KEY_ENTER && total > 0) {
            fs_find_hit_t *h = &find_hits[sel];
            if (h->tipo == NODO_DIR) {
                fs_ir_a_dir(h->id);
                break;
            } else {
                if (fs_ir_a_dir(h->padre) == 0) {
                    if (fs_get_rol() == ROL_INVITADO) visor_archivo_lectura(h->nombre);
                    else fs_edit(h->nombre);
                }
                break;
            }
        }
    }
}

/* ---------- Explorador Visual de Archivos y Carpetas ---------- */
void ui_explorador_archivos(void) {
    int sel = 0;
    int scroll = 0;
    char aviso[76];
    aviso[0] = '\0';

    while (1) {
        int en_raiz = fs_en_raiz();
        int cnt = fs_listar_dir_actual(exp_items, MAX_NODOS);
        if (cnt < 0) cnt = 0;
        int total = cnt + (en_raiz ? 0 : 1);
        if (total == 0) sel = 0;
        else if (sel >= total) sel = total - 1;

        if (sel < scroll) scroll = sel;
        if (sel >= scroll + 13) scroll = sel - 12;

        kvga_barra_titulo("ARGOS - MIS ARCHIVOS Y CARPETAS");
        kvga_limpiar_area(1, 23, kcol_fondo());

        char ruta[64];
        fs_ruta_actual_str(ruta, sizeof(ruta));
        int usados = 0, archs = 0, dirs = 0;
        uint32_t bytes_fs = 0;
        fs_contar_nodos(&usados, &archs, &dirs, &bytes_fs);

        kvga_texto_en(2, 2, kcol_acento(), "Carpeta actual: ");
        kvga_texto_en(18, 2, kcol_dato(), ruta);

        char nstr[16];
        u_uint_str((uint32_t)usados, nstr);
        kvga_texto_en(51, 2, kcol_tenue(), "Espacio: ");
        kvga_texto_en(60, 2, kcol_ok(), nstr);
        kvga_texto_en(60 + u_slen(nstr), 2, kcol_tenue(), "/128 (4KB)");

        if (fs_hay_cambios()) {
            kvga_texto_en(2, 3, kcol_aviso(), "Aviso: tienes cambios sin guardar (pulsa G para guardar en el disco).");
        } else {
            kvga_texto_en(2, 3, kcol_ok(), "Estado: todos tus archivos están guardados en el disco.");
        }

        kvga_dibujar_caja(2, 4, 76, 17, kcol_fondo(), kcol_acento());
        kvga_texto_en(4, 5, kcol_acento(), "TIPO        NOMBRE                            DETALLE");

        if (total == 0) {
            kvga_texto_en(22, 11, kcol_tenue(), "(Esta carpeta está vacía)");
            kvga_texto_en(13, 13, kcol_fondo(), "Pulsa N para crear un archivo o C para crear una carpeta.");
        } else {
            for (int row = 0; row < 13 && (scroll + row) < total; row++) {
                int idx = scroll + row;
                int y = 6 + row;
                int is_sel = (idx == sel);
                uint8_t col_base = is_sel ? kcol_sel() : kcol_fondo();

                char bg[75];
                for (int c = 0; c < 74; c++) bg[c] = ' ';
                bg[74] = '\0';
                kvga_texto_en(3, y, col_base, bg);

                if (!en_raiz && idx == 0) {
                    kvga_texto_en(4, y, is_sel ? kcol_sel() : kcol_aviso(), "[SUBIR]     ..  (Volver a carpeta anterior)");
                } else {
                    int fi = en_raiz ? idx : (idx - 1);
                    fs_item_t *it = &exp_items[fi];
                    if (it->tipo == NODO_DIR) {
                        kvga_texto_en(4, y, is_sel ? kcol_sel() : kcol_acento(), "[CARPETA]");
                        kvga_texto_en(16, y, is_sel ? kcol_sel() : kcol_dato(), it->nombre);
                        kvga_texto_en(50, y, is_sel ? kcol_sel() : kcol_tenue(), "Enter para abrir");
                    } else {
                        kvga_texto_en(4, y, is_sel ? kcol_sel() : kcol_ok(), "[ARCHIVO]");
                        kvga_texto_en(16, y, is_sel ? kcol_sel() : kcol_fondo(), it->nombre);
                        char tbuf[16];
                        u_uint_str(it->tam, tbuf);
                        kvga_texto_en(50, y, is_sel ? kcol_sel() : kcol_tenue(), tbuf);
                        kvga_texto_en(50 + u_slen(tbuf), y, is_sel ? kcol_sel() : kcol_tenue(), " B");
                        if (fs_get_rol() == ROL_INVITADO || !(it->permisos & PERM_W)) {
                            kvga_texto_en(62, y, is_sel ? kcol_sel() : kcol_aviso(), "(Solo lect.)");
                        }
                    }
                }
            }
        }

        /* Leyenda clara de dos filas encima de la barra de estado */
        if (fs_get_rol() == ROL_INVITADO) {
            kvga_texto_en(3, 22, kcol_acento(), "Enter: Abrir / Leer  |  B: Buscar texto  |  ESC: Volver al Menú");
            kvga_texto_en(3, 23, kcol_tenue(),  "Modo Invitado: solo lectura (no puedes crear, mover ni borrar).");
        } else {
            kvga_texto_en(3, 22, kcol_acento(), "Enter: Abrir  |  N: Archivo  |  C: Carpeta  |  B: Buscar  |  G: Guardar");
            kvga_texto_en(3, 23, kcol_tenue(),
                fs_get_rol() == ROL_ADMIN
                    ? "R: Renombrar  |  P: Copiar   |  M: Mover    |  D: Borrar  |  ESC: Menú"
                    : "R: Renombrar  |  P: Copiar   |  M: Mover    |  ESC: Volver al Menú");
        }

        if (aviso[0]) {
            barra_inferior(aviso, 1);
            aviso[0] = '\0';
        } else {
            barra_inferior("Flechas Arr/Abj: Elegir | Retroceso: Subir carpeta | ESC: Menú Principal", 0);
        }
        kset_cursor(3, total > 0 ? (6 + (sel - scroll)) : 11);

        int k = teclado_getkey();
        if (k == KEY_ESC || k == 'q' || k == 'Q') {
            break;
        } else if (k == KEY_UP && total > 0) {
            sel = (sel + total - 1) % total;
        } else if (k == KEY_DOWN && total > 0) {
            sel = (sel + 1) % total;
        } else if (k == KEY_BS && !en_raiz) {
            fs_cd("..");
            sel = 0; scroll = 0;
        } else if (k == KEY_ENTER && total > 0) {
            if (!en_raiz && sel == 0) {
                fs_cd("..");
                sel = 0; scroll = 0;
            } else {
                int fi = en_raiz ? sel : (sel - 1);
                fs_item_t *it = &exp_items[fi];
                if (it->tipo == NODO_DIR) {
                    if (fs_cd(it->nombre) == 0) {
                        sel = 0; scroll = 0;
                    } else {
                        u_scpy(aviso, "No tienes permiso de acceso a esa carpeta.", sizeof(aviso));
                    }
                } else {
                    if (fs_get_rol() == ROL_INVITADO || !(it->permisos & PERM_W)) {
                        if (it->permisos & PERM_R) visor_archivo_lectura(it->nombre);
                        else u_scpy(aviso, "Este archivo no tiene permiso de lectura.", sizeof(aviso));
                    } else {
                        fs_edit(it->nombre);
                    }
                }
            }
        } else if (k == 'n' || k == 'N') {
            if (fs_get_rol() == ROL_INVITADO) {
                u_scpy(aviso, "Modo Invitado: solo puedes leer archivos.", sizeof(aviso));
            } else {
                char nom[33] = "";
                if (popup_entrada("Crear nuevo archivo", "Nombre (ej. nota.txt): ", nom, 32) && nom[0]) {
                    fs_edit(nom);
                }
            }
        } else if (k == 'c' || k == 'C' || k == 'k' || k == 'K') {
            char nom[33] = "";
            if (popup_entrada("Crear nueva carpeta", "Nombre de la carpeta: ", nom, 32) && nom[0]) {
                const char *err = 0;
                if (fs_mkdir_silencioso(nom, &err) >= 0) {
                    u_scpy(aviso, "Carpeta creada. Recuerda pulsar G para guardar en disco.", sizeof(aviso));
                } else {
                    u_scpy(aviso, err ? err : "No se pudo crear la carpeta.", sizeof(aviso));
                }
            }
        } else if (k == 'b' || k == 'B') {
            ui_buscar_archivos();
            sel = 0; scroll = 0;
        } else if (k == 'r' || k == 'R') {
            if (total == 0 || (!en_raiz && sel == 0)) continue;
            if (fs_get_rol() == ROL_INVITADO) {
                u_scpy(aviso, "Modo Invitado: no puedes renombrar elementos.", sizeof(aviso));
                continue;
            }
            int fi = en_raiz ? sel : (sel - 1);
            fs_item_t *it = &exp_items[fi];
            char nuevo[33];
            u_scpy(nuevo, it->nombre, sizeof(nuevo));
            if (popup_entrada("Renombrar elemento", "Nuevo nombre: ", nuevo, 32) && nuevo[0]) {
                const char *err = 0;
                if (fs_renombrar_silencioso(it->nombre, nuevo, &err) == 0) {
                    u_scpy(aviso, "Renombrado correctamente. Pulsa G para guardar en disco.", sizeof(aviso));
                } else {
                    u_scpy(aviso, err ? err : "No se pudo renombrar.", sizeof(aviso));
                }
            }
        } else if (k == 'p' || k == 'P') {
            if (total == 0 || (!en_raiz && sel == 0)) continue;
            if (fs_get_rol() == ROL_INVITADO) {
                u_scpy(aviso, "Modo Invitado: no puedes copiar archivos.", sizeof(aviso));
                continue;
            }
            int fi = en_raiz ? sel : (sel - 1);
            fs_item_t *it = &exp_items[fi];
            if (it->tipo != NODO_ARCH) {
                u_scpy(aviso, "Solo se pueden copiar archivos (selecciona un archivo).", sizeof(aviso));
                continue;
            }
            char dest[33];
            int dp = 0;
            const char *pre = "copia_";
            for (int i = 0; pre[i] && dp < 31; i++) dest[dp++] = pre[i];
            for (int i = 0; it->nombre[i] && dp < 31; i++) dest[dp++] = it->nombre[i];
            dest[dp] = '\0';
            if (popup_entrada("Copiar archivo (nombre o carpeta)", "Destino: ", dest, 32) && dest[0]) {
                const char *err = 0;
                if (fs_copiar_silencioso(it->nombre, dest, &err) == 0) {
                    u_scpy(aviso, "Archivo copiado. Pulsa G para guardar en disco.", sizeof(aviso));
                } else {
                    u_scpy(aviso, err ? err : "No se pudo copiar.", sizeof(aviso));
                }
            }
        } else if (k == 'm' || k == 'M') {
            if (total == 0 || (!en_raiz && sel == 0)) continue;
            if (fs_get_rol() == ROL_INVITADO) {
                u_scpy(aviso, "Modo Invitado: no puedes mover elementos.", sizeof(aviso));
                continue;
            }
            int fi = en_raiz ? sel : (sel - 1);
            fs_item_t *it = &exp_items[fi];
            char dest[33] = "";
            int r = popup_elegir_destino_mover(it->nombre, en_raiz, exp_items, cnt, dest, sizeof(dest));
            if (r == -1) {
                u_scpy(aviso, "Crea primero una carpeta (pulsa C) para poder mover elementos.", sizeof(aviso));
            } else if (r == 1 && dest[0]) {
                const char *err = 0;
                if (fs_mover_silencioso(it->nombre, dest, &err) == 0) {
                    u_scpy(aviso, "Elemento movido correctamente. Pulsa G para guardar.", sizeof(aviso));
                } else {
                    u_scpy(aviso, err ? err : "No se pudo mover.", sizeof(aviso));
                }
            }
        } else if (k == 'd' || k == 'D' || k == KEY_DEL) {
            if (total == 0 || (!en_raiz && sel == 0)) continue;
            int fi = en_raiz ? sel : (sel - 1);
            fs_item_t *it = &exp_items[fi];
            if (fs_get_rol() != ROL_ADMIN) {
                const char *err = 0;
                fs_eliminar_silencioso(it->nombre, &err);
                u_scpy(aviso, err ? err : "Sin permiso para eliminar.", sizeof(aviso));
            } else if (popup_confirmar("¿Seguro que deseas eliminar este elemento?", it->nombre)) {
                const char *err = 0;
                if (fs_eliminar_silencioso(it->nombre, &err) == 0) {
                    u_scpy(aviso, "Elemento eliminado. Pulsa G para guardar en disco.", sizeof(aviso));
                } else {
                    u_scpy(aviso, err ? err : "No se pudo eliminar.", sizeof(aviso));
                }
            }
        } else if (k == 'g' || k == 'G') {
            const char *err = 0;
            if (fs_save_silencioso(&err) == 0) {
                u_scpy(aviso, "¡Listo! Todos tus archivos y ajustes fueron guardados en el disco.", sizeof(aviso));
            } else {
                u_scpy(aviso, err ? err : "No se pudo guardar en el disco.", sizeof(aviso));
            }
        }
    }
}

/* ---------- Panel de Ajustes Sencillos (con persistencia en disco) ---------- */
static void ui_ajustes(void) {
    int sel = 0;
    char aviso[76];
    aviso[0] = '\0';

    while (1) {
        kvga_barra_titulo("ARGOS - AJUSTES DEL SISTEMA");
        kvga_limpiar_area(1, 23, kcol_fondo());

        kvga_dibujar_caja(7, 3, 66, 17, kcol_caja(), kcol_borde());
        kvga_texto_en(21, 4, kcol_caja_tit(), "AJUSTES RÁPIDOS DE ARGOS OS");

        char ip_txt[20];
        if (net_tiene_ip()) u_ip_str(net_mi_ip(), ip_txt);
        else u_scpy(ip_txt, "Sin IP", sizeof(ip_txt));

        int tz = reloj_get_tz();
        char tz_txt[16];
        int p = 0;
        if (tz == 0) u_scpy(tz_txt, "Sistema (0h)", sizeof(tz_txt));
        else {
            tz_txt[p++] = (tz > 0) ? '+' : '-';
            char nt[6];
            u_uint_str((uint32_t)(tz > 0 ? tz : -tz), nt);
            for (int i = 0; nt[i]; i++) tz_txt[p++] = nt[i];
            tz_txt[p++] = ' '; tz_txt[p++] = 'h'; tz_txt[p] = '\0';
        }

        const char *items[6] = {
            "1. Cambiar idioma de teclado  ->",
            "2. Ajustar hora local (UTC)   ->",
            "3. Cambiar tema visual        ->",
            "4. Reconectar Internet (DHCP) ->",
            "5. Ver información del equipo ->",
            "6. Volver al Menú Principal"
        };
        const char *vals[6] = {
            teclado_layout_nombre(),
            tz_txt,
            kernel_tema_nombre(),
            ip_txt,
            "RAM, CPU, Disco y Red",
            ""
        };

        for (int i = 0; i < 6; i++) {
            int y = 7 + i * 2;
            uint8_t col = (i == sel) ? kcol_sel() : kcol_caja();
            char bg[63];
            for (int c = 0; c < 62; c++) bg[c] = ' ';
            bg[62] = '\0';
            kvga_texto_en(9, y, col, bg);
            kvga_texto_en(10, y, col, i == sel ? "> " : "  ");
            kvga_texto_en(12, y, col, items[i]);
            if (vals[i][0]) kvga_texto_en(45, y, i == sel ? kcol_sel() : kcol_borde(), vals[i]);
        }

        kvga_texto_en(9, 21, kcol_tenue(),
            "Teclado, hora y tema se guardan automáticamente para próximos reinicios.");

        if (aviso[0]) {
            barra_inferior(aviso, 1);
            aviso[0] = '\0';
        } else {
            barra_inferior("Arr/Abj o 1-6: Elegir | Enter: Cambiar ajuste | ESC: Volver al Menú", 0);
        }
        kset_cursor(10, 7 + sel * 2);

        int k = teclado_getkey();
        if (k == KEY_ESC) break;
        else if (k == KEY_UP) sel = (sel + 5) % 6;
        else if (k == KEY_DOWN) sel = (sel + 1) % 6;
        else if (k >= '1' && k <= '6') { sel = k - '1'; k = KEY_ENTER; }

        if (k == KEY_ENTER) {
            if (sel == 0) {
                int nl = (teclado_get_layout() + 1) % 3;
                teclado_set_layout(nl);
                kernel_guardar_prefs();
                u_scpy(aviso, "Teclado cambiado y guardado en preferencias.", sizeof(aviso));
            } else if (sel == 1) {
                int ntz = (tz == 0) ? -5 : (tz == -5 ? -3 : (tz == -3 ? 1 : 0));
                reloj_set_tz(ntz);
                kernel_guardar_prefs();
                u_scpy(aviso, "Hora local actualizada y guardada en preferencias.", sizeof(aviso));
            } else if (sel == 2) {
                int nt = (kernel_get_tema() + 1) % 3;
                kernel_set_tema(nt);
                kernel_guardar_prefs();
                u_scpy(aviso, "Tema visual aplicado y guardado en preferencias.", sizeof(aviso));
            } else if (sel == 3) {
                barra_inferior("Conectando a la red por DHCP y probando servidor académico...", 1);
                if (net_dhcp(1) == 0) {
                    scholar_init();
                    if (scholar_probar_salud() == 0)
                        u_scpy(aviso, "¡Conectado! Internet y Google Académico en línea.", sizeof(aviso));
                    else
                        u_scpy(aviso, "IP obtenida, pero el servidor académico no responde.", sizeof(aviso));
                } else {
                    u_scpy(aviso, "No se pudo obtener IP. Revisa VirtualBox -> Red -> NAT.", sizeof(aviso));
                }
            } else if (sel == 4) {
                kernel_mostrar_sysinfo();
                kvga_texto_en(2, 22, kcol_aviso(), "Pulsa cualquier tecla para volver a Ajustes...");
                teclado_getkey();
            } else if (sel == 5) {
                break;
            }
        }
    }
}

/* ---------- Submenu de Salir / Apagar ---------- */
static int ui_menu_salir(void) {
    int sel = 0;
    const int x0 = 16, y0 = 7, ancho = 48, alto = 11;
    const char *ops[4] = {
        "1. Cambiar de usuario (Cerrar sesión)",
        "2. Reiniciar computadora",
        "3. Apagar de forma segura",
        "4. Cancelar y volver al menú"
    };

    while (1) {
        kvga_dibujar_caja(x0, y0, ancho, alto, kcol_caja(), kcol_borde());
        kvga_texto_en(x0 + 11, y0 + 1, kcol_caja_tit(), "OPCIONES DE SESIÓN Y ENERGÍA");
        for (int i = 0; i < 4; i++) {
            int y = y0 + 3 + i;
            uint8_t col = (i == sel) ? kcol_sel() : kcol_caja();
            char bg[45];
            for (int c = 0; c < 44; c++) bg[c] = ' ';
            bg[44] = '\0';
            kvga_texto_en(x0 + 2, y, col, bg);
            kvga_texto_en(x0 + 3, y, col, i == sel ? "> " : "  ");
            kvga_texto_en(x0 + 5, y, col, ops[i]);
        }
        kvga_texto_en(x0 + 6, y0 + 9, kcol_caja_ten(), "Arr/Abj: elegir | Enter: aceptar");
        kset_cursor(x0 + 3, y0 + 3 + sel);

        int k = teclado_getkey();
        if (k == KEY_ESC) return -1;
        else if (k == KEY_UP) sel = (sel + 3) % 4;
        else if (k == KEY_DOWN) sel = (sel + 1) % 4;
        else if (k >= '1' && k <= '4') { sel = k - '1'; k = KEY_ENTER; }

        if (k == KEY_ENTER) {
            if (sel == 0) return 1; /* logout */
            if (sel == 1) return 2; /* reboot */
            if (sel == 2) return 3; /* shutdown */
            return -1;
        }
    }
}

/* ==================== MENU PRINCIPAL INTERACTIVO ==================== */
int ui_menu_principal(void) {
    int sel = 0;
    char aviso[76];
    aviso[0] = '\0';

    if (fs_fue_migrado_v1()) {
        u_scpy(aviso, "Disco actualizado a TIC340FS v2 (128 nodos x 4KB). Pulsa 6 para guardar.", sizeof(aviso));
    }

    static const char * const titulos[9] = {
        "1. Buscar en Google Académico",
        "2. Mis Archivos y Carpetas",
        "3. Crear Archivo o Carpeta",
        "4. Aplicaciones (Calculadora, Agenda y Timer)",
        "5. Juegos (Snake, 2048 y Ahorcado)",
        "6. Guardar mis Cambios en el Disco",
        "7. Ajustes (Teclado, Hora, Tema e Internet)",
        "8. Consola de Comandos (Modo Avanzado)",
        "9. Cambiar Usuario / Apagar Equipo"
    };
    static const char * const descs[9] = {
        "Investiga artículos, lee resúmenes y guarda citas APA",
        "Explora, renombra, copia, mueve y busca tus documentos",
        "Crea una nueva carpeta o empieza un archivo de texto",
        "Calculadora con conversor, calendario con tareas y Pomodoro",
        "Diviértete con Snake, 2048 y Ahorcado con récords guardados",
        "Guarda tus archivos y ajustes en el disco (hasta 4 KB/arch)",
        "Cambia teclado, zona horaria, tema visual o red",
        "Terminal completa para comandos técnicos de TIC340",
        "Cierra tu sesión, reinicia o apaga con seguridad"
    };

    while (1) {
        kvga_barra_titulo("ARGOS OS - MENÚ PRINCIPAL");
        kvga_limpiar_area(1, 23, kcol_fondo());

        kvga_texto_en(3, 2, kcol_titulo(), "TECNOLÓGICO UNIVERSITARIO ARGOS");

        kvga_texto_en(3, 3, kcol_acento(), "Usuario: ");
        kvga_texto_en(12, 3, kcol_aviso(), kernel_usuario_nombre_completo());
        kvga_texto_en(36, 3, kcol_tenue(), "|  Red: ");
        if (net_tiene_ip()) {
            char ip_s[20];
            u_ip_str(net_mi_ip(), ip_s);
            kvga_texto_en(44, 3, kcol_ok(), "Conectado (");
            kvga_texto_en(55, 3, kcol_dato(), ip_s);
            kvga_texto_en(55 + u_slen(ip_s), 3, kcol_ok(), ")");
        } else {
            kvga_texto_en(44, 3, kcol_aviso(), "Desconectada (Ajustes)");
        }

        const int x0 = 5, y0 = 4, ancho = 70, alto = 16;
        kvga_dibujar_caja(x0, y0, ancho, alto, kcol_caja(), kcol_borde());
        kvga_texto_en(x0 + 21, y0 + 1, kcol_caja_tit(), "¿QUÉ DESEAS HACER HOY?");

        for (int i = 0; i < 9; i++) {
            int y = y0 + 3 + i;
            uint8_t col = (i == sel) ? kcol_sel() : kcol_caja();
            char bg[67];
            for (int c = 0; c < 66; c++) bg[c] = ' ';
            bg[66] = '\0';
            kvga_texto_en(x0 + 2, y, col, bg);
            kvga_texto_en(x0 + 4, y, col, i == sel ? "> " : "  ");
            kvga_texto_en(x0 + 6, y, col, titulos[i]);

            if (i == 5 && fs_hay_cambios()) {
                kvga_texto_en(x0 + 45, y, i == sel ? kcol_sel() : kcol_caja_tit(), "[Cambios pendientes]");
            } else if ((i == 2 || i == 5) && fs_get_rol() == ROL_INVITADO) {
                kvga_texto_en(x0 + 49, y, i == sel ? kcol_sel() : kcol_caja_ten(), "(Solo lectura)");
            }
        }

        kvga_texto_en(x0 + 4, y0 + 13, kcol_borde(), "Ayuda: ");
        kvga_texto_en(x0 + 11, y0 + 13, kcol_caja_ten(), descs[sel]);

        int usados = 0, a = 0, d = 0;
        fs_contar_nodos(&usados, &a, &d, 0);
        char ram_s[12], k_s[12], u_s[12];
        u_uint_str(mem_ram_mb(), ram_s);
        u_uint_str(mem_kernel_kb(), k_s);
        u_uint_str((uint32_t)usados, u_s);
        kvga_texto_en(5, 21, kcol_tenue(), "Recursos: Kernel ");
        kvga_texto_en(22, 21, kcol_ok(), k_s);
        kvga_texto_en(22 + u_slen(k_s), 21, kcol_tenue(), " KB | RAM ");
        int px = 22 + u_slen(k_s) + 10;
        kvga_texto_en(px, 21, kcol_fondo(), ram_s);
        kvga_texto_en(px + u_slen(ram_s), 21, kcol_tenue(), " MB | Archivos: ");
        px += u_slen(ram_s) + 16;
        kvga_texto_en(px, 21, kcol_dato(), u_s);
        kvga_texto_en(px + u_slen(u_s), 21, kcol_tenue(), "/128 (4KB)");

        if (aviso[0]) {
            barra_inferior(aviso, 1);
            aviso[0] = '\0';
        } else {
            barra_inferior("Flechas Arr/Abj o teclas 1-9: Elegir opción | Enter: Abrir", 0);
        }
        kset_cursor(x0 + 4, y0 + 3 + sel);

        int k = teclado_getkey();
        if (k == KEY_UP) sel = (sel + 8) % 9;
        else if (k == KEY_DOWN) sel = (sel + 1) % 9;
        else if (k >= '1' && k <= '9') { sel = k - '1'; k = KEY_ENTER; }

        if (k == KEY_ENTER) {
            if (sel == 0) {
                scholar_abrir_desde_menu();
            } else if (sel == 1) {
                ui_explorador_archivos();
            } else if (sel == 2) {
                if (fs_get_rol() == ROL_INVITADO) {
                    u_scpy(aviso, "Modo Invitado: solo tienes permiso de lectura.", sizeof(aviso));
                } else {
                    int tipo = popup_elegir_crear();
                    if (tipo == 1) {
                        char nom[33] = "";
                        if (popup_entrada("Crear o Editar Archivo", "Nombre (ej. tarea.txt): ", nom, 32) && nom[0]) {
                            fs_edit(nom);
                        }
                    } else if (tipo == 2) {
                        char nom[33] = "";
                        if (popup_entrada("Crear Nueva Carpeta", "Nombre de la carpeta: ", nom, 32) && nom[0]) {
                            const char *err = 0;
                            if (fs_mkdir_silencioso(nom, &err) >= 0) {
                                u_scpy(aviso, "Carpeta creada. Ábrela en opción 2 o guarda con opción 6.", sizeof(aviso));
                            } else {
                                u_scpy(aviso, err ? err : "No se pudo crear la carpeta.", sizeof(aviso));
                            }
                        }
                    }
                }
            } else if (sel == 3) {
                apps_menu();
            } else if (sel == 4) {
                juegos_menu();
            } else if (sel == 5) {
                const char *err = 0;
                if (fs_save_silencioso(&err) == 0) {
                    u_scpy(aviso, "¡Listo! Tus archivos y ajustes quedaron guardados en el disco.", sizeof(aviso));
                } else {
                    u_scpy(aviso, err ? err : "No se pudo guardar en el disco.", sizeof(aviso));
                }
            } else if (sel == 6) {
                ui_ajustes();
            } else if (sel == 7) {
                return 0; /* ir a consola avanzada */
            } else if (sel == 8) {
                int r = ui_menu_salir();
                if (r > 0) return r;
            }
        }
    }
}
