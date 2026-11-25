/*
 * Controlador de teclado PS/2 completo para ARGOS OS
 *  - Distribuciones intercambiables: Latinoamerica (latam), Espana (es) e Ingles (us)
 *  - Caracteres especiales: ñ/Ñ, á/é/í/ó/ú/Á/É/Í/Ó/Ú, ü/Ü, ¿/¡, °/º/ª/¬, < >, @, \, ~, |, {, }, [, ]
 *  - Teclas muertas (tildes ´ y dieresis ¨), teclado numerico (NumLock), AltGr, Ctrl, Shift
 *  - Edicion completa de linea: Flechas Izq/Der, Inicio/Fin, Supr, Seleccion Shift+Flechas
 *  - Portapapeles global del SO: Ctrl+C (copiar), Ctrl+X (cortar), Ctrl+V (pegar), Ctrl+A (todo)
 */
#include <stdint.h>
#include "teclado.h"
#include "reloj.h"

#define HIST_MAX   20
#define CMD_MAX    128

#define DEAD_ACUTE  0xF0
#define DEAD_UMLAUT 0xF1

/* Codigos VGA/CP437 de 1 byte para caracteres en espanol (coinciden con kernel.c) */
#define CH_a_AC  0xA0
#define CH_e_AC  0x82
#define CH_i_AC  0xA1
#define CH_o_AC  0xA2
#define CH_u_AC  0xA3
#define CH_A_AC  0x9B
#define CH_E_AC  0x90
#define CH_I_AC  0x9C
#define CH_O_AC  0x9D
#define CH_U_AC  0x9E
#define CH_u_UM  0x81
#define CH_U_UM  0x9A
#define CH_enie  0xA4
#define CH_ENIE  0xA5
#define CH_IQUEST 0xA8
#define CH_IEXCL  0xAD
#define CH_DEG    0xF8
#define CH_ORDM   0xA7
#define CH_ORDF   0xA6
#define CH_NOT    0xAA
#define CH_MDOT   0xFA
#define CH_cced   0x87
#define CH_CCED   0x80

static inline uint8_t inb(uint16_t port) {
    uint8_t result;
    __asm__ volatile("inb %1, %0" : "=a"(result) : "Nd"(port));
    return result;
}

/* ---------- Tablas base (US) ---------- */
static const uint8_t us_norm[128] = {
    0,  27, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', '\b',
    '\t', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', '\n',
    0, 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', '`',
    0, '\\', 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', 0,
    '*', 0, ' '
};

static const uint8_t us_shift[128] = {
    0,  27, '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+', '\b',
    '\t', 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', '\n',
    0, 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '~',
    0, '|', 'Z', 'X', 'C', 'V', 'B', 'N', 'M', '<', '>', '?', 0,
    '*', 0, ' '
};

/* ---------- Distribucion Espanol Latinoamerica (LATAM) ---------- */
static const uint8_t latam_norm[128] = {
    0,  27, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '\'', CH_IQUEST, '\b',
    '\t', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', DEAD_ACUTE, '+', '\n',
    0, 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', CH_enie, '{', '|',
    0, '}', 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '-', 0,
    '*', 0, ' '
};

static const uint8_t latam_shift[128] = {
    0,  27, '!', '"', '#', '$', '%', '&', '/', '(', ')', '=', '?', CH_IEXCL, '\b',
    '\t', 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', DEAD_UMLAUT, '*', '\n',
    0, 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', CH_ENIE, '[', CH_DEG,
    0, ']', 'Z', 'X', 'C', 'V', 'B', 'N', 'M', ';', ':', '_', 0,
    '*', 0, ' '
};

/* ---------- Distribucion Espanol Espana (ES) ---------- */
static const uint8_t es_norm[128] = {
    0,  27, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '\'', CH_IEXCL, '\b',
    '\t', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '`', '+', '\n',
    0, 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', CH_enie, DEAD_ACUTE, CH_ORDM,
    0, CH_cced, 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '-', 0,
    '*', 0, ' '
};

static const uint8_t es_shift[128] = {
    0,  27, '!', '"', CH_MDOT, '$', '%', '&', '/', '(', ')', '=', '?', CH_IQUEST, '\b',
    '\t', 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '^', '*', '\n',
    0, 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', CH_ENIE, DEAD_UMLAUT, CH_ORDF,
    0, CH_CCED, 'Z', 'X', 'C', 'V', 'B', 'N', 'M', ';', ':', '_', 0,
    '*', 0, ' '
};

/* Estado de modificadores */
static int lshift = 0, rshift = 0;
static int lctrl  = 0, rctrl  = 0;
static int lalt   = 0, altgr  = 0;
static int bloq_mayus = 0;
static int num_lock   = 1;
static int caps_down  = 0;
static int num_down   = 0;
static int prefijo_e0 = 0;
static int saltar_e1  = 0;
static int dead_key   = 0;
static int layout_actual = KBD_LATAM;

/* Historial de comandos */
static char historial[HIST_MAX][CMD_MAX];
static int hist_total = 0;

/* Portapapeles global de ARGOS OS */
static char portapapeles[CLIP_MAX];
static int  clip_len = 0;

extern void kputc(char c);
extern void kprint(const char *s);
extern void kset_color(uint8_t c);
extern void kclear(void);
extern void kget_cursor(int *x, int *y);
extern void krender_linea_input(int *start_x, int *start_y, const char *buf,
                                int len, int cur, int sel_a, int sel_b, int *prev_len);
extern void kernel_imprimir_prompt(void);
extern int  shell_autocompletar(char *destino, int *len, int *cur, int max_len);
extern void kernel_guardar_prefs(void);

static int t_slen(const char *s) {
    int n = 0;
    while (s[n]) n++;
    return n;
}

static int t_scmp(const char *a, const char *b) {
    while (*a && (*a == *b)) { a++; b++; }
    return *(const unsigned char *)a - *(const unsigned char *)b;
}

static void t_scpy(char *d, const char *s, int max) {
    int i = 0;
    while (i < max - 1 && s[i]) { d[i] = s[i]; i++; }
    d[i] = '\0';
}

/* ---------- Portapapeles ---------- */
void clip_copiar(const char *src, int len) {
    if (!src || len <= 0) return;
    if (len >= CLIP_MAX) len = CLIP_MAX - 1;
    for (int i = 0; i < len; i++) portapapeles[i] = src[i];
    portapapeles[len] = '\0';
    clip_len = len;
}

const char *clip_obtener(void) {
    return portapapeles;
}

int clip_largo(void) {
    return clip_len;
}

void clip_limpiar(void) {
    portapapeles[0] = '\0';
    clip_len = 0;
}

/* ---------- Distribucion de teclado ---------- */
void teclado_set_layout(int layout) {
    if (layout >= KBD_LATAM && layout <= KBD_US) {
        layout_actual = layout;
        dead_key = 0;
    }
}

int teclado_get_layout(void) {
    return layout_actual;
}

const char *teclado_layout_nombre(void) {
    if (layout_actual == KBD_ES) return "es (Español España)";
    if (layout_actual == KBD_US) return "us (Inglés US)";
    return "latam (Español Latinoamérica)";
}

static uint8_t traducir_altgr(uint8_t sc, int shift) {
    if (layout_actual == KBD_LATAM) {
        switch (sc) {
            case 0x29: return CH_NOT;  /* ¬ */
            case 0x02: return '|';
            case 0x03: return '@';
            case 0x04: return '#';
            case 0x05: return '~';
            case 0x07: return '^';
            case 0x0C: return '\\';
            case 0x0D: return '\\';
            case 0x10: return '@';     /* AltGr+Q = @ */
            case 0x1A: return '[';
            case 0x1B: return '~';
            case 0x28: return '^';
            case 0x2B: return '`';
            case 0x56: return '|';
        }
    } else if (layout_actual == KBD_ES) {
        switch (sc) {
            case 0x29: return '\\';
            case 0x02: return '|';
            case 0x03: return '@';
            case 0x04: return '#';
            case 0x05: return '~';
            case 0x07: return CH_NOT;
            case 0x0C: return '\\';
            case 0x1A: return '[';
            case 0x1B: return ']';
            case 0x28: return '{';
            case 0x2B: return '}';
            case 0x56: return '|';
        }
    } else {
        /* En US, AltGr permite escribir tildes, ñ, ¿, ¡ y ° comodamente */
        int may = shift ^ bloq_mayus;
        switch (sc) {
            case 0x1E: return may ? CH_A_AC : CH_a_AC; /* a -> á */
            case 0x12: return may ? CH_E_AC : CH_e_AC; /* e -> é */
            case 0x17: return may ? CH_I_AC : CH_i_AC; /* i -> í */
            case 0x18: return may ? CH_O_AC : CH_o_AC; /* o -> ó */
            case 0x16: return may ? CH_U_AC : CH_u_AC; /* u -> ú */
            case 0x31: return may ? CH_ENIE : CH_enie; /* n -> ñ */
            case 0x35: return CH_IQUEST;               /* / -> ¿ */
            case 0x02: return CH_IEXCL;                /* 1 -> ¡ */
            case 0x0B: return CH_DEG;                  /* 0 -> ° */
        }
    }
    return 0;
}

static uint8_t aplicar_tecla_muerta(int dead, uint8_t ch) {
    if (dead == 1) { /* tilde aguda ´ */
        switch (ch) {
            case 'a': return CH_a_AC;
            case 'e': return CH_e_AC;
            case 'i': return CH_i_AC;
            case 'o': return CH_o_AC;
            case 'u': return CH_u_AC;
            case 'A': return CH_A_AC;
            case 'E': return CH_E_AC;
            case 'I': return CH_I_AC;
            case 'O': return CH_O_AC;
            case 'U': return CH_U_AC;
            case ' ': return '\'';
        }
    } else if (dead == 2) { /* dieresis ¨ */
        switch (ch) {
            case 'u': return CH_u_UM;
            case 'U': return CH_U_UM;
            case ' ': return '"';
        }
    }
    return ch;
}

static int traducir_numpad(uint8_t sc, int shift) {
    if (sc == 0x37) return '*';
    if (sc == 0x4A) return '-';
    if (sc == 0x4E) return '+';
    if (sc < 0x47 || sc > 0x53) return 0;

    if (num_lock && !shift) {
        switch (sc) {
            case 0x47: return '7';
            case 0x48: return '8';
            case 0x49: return '9';
            case 0x4B: return '4';
            case 0x4C: return '5';
            case 0x4D: return '6';
            case 0x4F: return '1';
            case 0x50: return '2';
            case 0x51: return '3';
            case 0x52: return '0';
            case 0x53: return '.';
        }
    } else {
        switch (sc) {
            case 0x47: return shift ? KEY_S_HOME  : KEY_HOME;
            case 0x48: return shift ? KEY_S_UP    : KEY_UP;
            case 0x49: return KEY_PGUP;
            case 0x4B: return shift ? KEY_S_LEFT  : KEY_LEFT;
            case 0x4D: return shift ? KEY_S_RIGHT : KEY_RIGHT;
            case 0x4F: return shift ? KEY_S_END   : KEY_END;
            case 0x50: return shift ? KEY_S_DOWN  : KEY_DOWN;
            case 0x51: return KEY_PGDN;
            case 0x52: return KEY_INS;
            case 0x53: return KEY_DEL;
        }
    }
    return 0;
}

int teclado_poll_key(void) {
    while (1) {
        uint8_t estado = inb(0x64);
        if (!(estado & 0x01)) {
            return 0;
        }
        uint8_t sc = inb(0x60);
        if (estado & 0x20) continue; /* dato del raton */

        if (saltar_e1 > 0) { saltar_e1--; continue; }
        if (sc == 0xE1) { saltar_e1 = 2; continue; }
        if (sc == 0xE0) { prefijo_e0 = 1; continue; }

        int shift = lshift || rshift;

        if (prefijo_e0) {
            prefijo_e0 = 0;
            /* Ignorar shifts falsos 0xE0 0x2A / 0xAA / 0x36 / 0xB6 */
            if (sc == 0x2A || sc == 0xAA || sc == 0x36 || sc == 0xB6) continue;
            if (sc == 0x1D) { rctrl = 1; continue; }
            if (sc == 0x9D) { rctrl = 0; continue; }
            if (sc == 0x38) { altgr = 1; continue; }
            if (sc == 0xB8) { altgr = 0; continue; }
            if (sc & 0x80) continue;

            dead_key = 0;
            switch (sc) {
                case 0x48: return shift ? KEY_S_UP    : KEY_UP;
                case 0x50: return shift ? KEY_S_DOWN  : KEY_DOWN;
                case 0x4B: return shift ? KEY_S_LEFT  : KEY_LEFT;
                case 0x4D: return shift ? KEY_S_RIGHT : KEY_RIGHT;
                case 0x47: return shift ? KEY_S_HOME  : KEY_HOME;
                case 0x4F: return shift ? KEY_S_END   : KEY_END;
                case 0x53: return KEY_DEL;
                case 0x49: return KEY_PGUP;
                case 0x51: return KEY_PGDN;
                case 0x52: return KEY_INS;
                case 0x1C: return KEY_ENTER;
                case 0x35: return '/';
            }
            continue;
        }

        /* Modificadores estandar */
        if (sc == 0x2A) { lshift = 1; continue; }
        if (sc == 0xAA) { lshift = 0; continue; }
        if (sc == 0x36) { rshift = 1; continue; }
        if (sc == 0xB6) { rshift = 0; continue; }
        if (sc == 0x1D) { lctrl  = 1; continue; }
        if (sc == 0x9D) { lctrl  = 0; continue; }
        if (sc == 0x38) { lalt   = 1; continue; }
        if (sc == 0xB8) { lalt   = 0; continue; }
        if (sc == 0x3A) { if (!caps_down) { bloq_mayus = !bloq_mayus; caps_down = 1; } continue; }
        if (sc == 0xBA) { caps_down = 0; continue; }
        if (sc == 0x45) { if (!num_down)  { num_lock   = !num_lock;   num_down  = 1; } continue; }
        if (sc == 0xC5) { num_down = 0; continue; }

        /* Ignorar soltado de teclas (break codes) */
        if (sc & 0x80) continue;

        shift = lshift || rshift;
        int ctrl = lctrl || rctrl;

        /* Atajos Ctrl (solo si AltGr no esta activo; evita conflicto AltGr en Windows) */
        if (ctrl && !altgr) {
            dead_key = 0;
            if (sc == 0x1E) return KEY_CTRL_A;
            if (sc == 0x2E) return KEY_CTRL_C;
            if (sc == 0x2F) return KEY_CTRL_V;
            if (sc == 0x2D) return KEY_CTRL_X;
            if (sc == 0x26) return KEY_CTRL_L;
            continue;
        }

        /* Teclado numerico (NumPad) */
        int nk = traducir_numpad(sc, shift);
        if (nk != 0) {
            dead_key = 0;
            return nk;
        }

        /* AltGr (caracteres terciarios: @, \, ~, |, [, ], {, }) */
        if (altgr) {
            uint8_t ag = traducir_altgr(sc, shift);
            if (ag != 0) {
                dead_key = 0;
                return (int)ag;
            }
            continue;
        }
        if (lalt) continue;

        /* Tecla ISO extra 0x56 (< y > entre Shift Izq y Z) */
        uint8_t ch = 0;
        if (sc == 0x56) {
            if (layout_actual == KBD_US) ch = shift ? '|' : '\\';
            else ch = shift ? '>' : '<';
        } else if (sc < 128) {
            const uint8_t *tn = (layout_actual == KBD_US) ? us_norm  :
                                (layout_actual == KBD_ES) ? es_norm  : latam_norm;
            const uint8_t *ts = (layout_actual == KBD_US) ? us_shift :
                                (layout_actual == KBD_ES) ? es_shift : latam_shift;
            uint8_t base = tn[sc];
            if (base == 0) continue;
            int es_letra = (base >= 'a' && base <= 'z') || (base == CH_enie) || (base == CH_cced);
            if (es_letra) ch = (shift ^ bloq_mayus) ? ts[sc] : base;
            else ch = shift ? ts[sc] : base;
        }

        if (ch == 0) continue;

        /* Teclas muertas (tildes ´ y dieresis ¨) */
        if (ch == DEAD_ACUTE) {
            if (dead_key == 1) { dead_key = 0; return '\''; }
            dead_key = 1;
            continue;
        }
        if (ch == DEAD_UMLAUT) {
            if (dead_key == 2) { dead_key = 0; return '"'; }
            dead_key = 2;
            continue;
        }

        if (dead_key != 0) {
            int d = dead_key;
            dead_key = 0;
            if (ch >= 32) ch = aplicar_tecla_muerta(d, ch);
        }

        return (int)ch;
    }
}

int teclado_getkey(void) {
    while (1) {
        int k = teclado_poll_key();
        if (k != 0) return k;
        if (reloj_activo()) __asm__ volatile("hlt");
    }
}

char teclado_getchar(void) {
    while (1) {
        int k = teclado_getkey();
        if (k < 0x100) return (char)k;
    }
}

void teclado_hist_clear(void) {
    hist_total = 0;
}

static void hist_guardar(const char *linea) {
    if (!linea[0]) return;
    if (hist_total > 0 && t_scmp(historial[hist_total - 1], linea) == 0) return;
    if (hist_total < HIST_MAX) {
        t_scpy(historial[hist_total], linea, CMD_MAX);
        hist_total++;
    } else {
        for (int i = 0; i < HIST_MAX - 1; i++) {
            t_scpy(historial[i], historial[i + 1], CMD_MAX);
        }
        t_scpy(historial[HIST_MAX - 1], linea, CMD_MAX);
    }
}

/* ---------- Edicion interactiva de linea en consola ---------- */
static void obtener_sel(int cur, int sel_ini, int *sa, int *sb) {
    if (sel_ini >= 0 && sel_ini != cur) {
        *sa = (sel_ini < cur) ? sel_ini : cur;
        *sb = (sel_ini < cur) ? cur : sel_ini;
    } else {
        *sa = 0;
        *sb = 0;
    }
}

static int borrar_sel_linea(char *buf, int *len, int *cur, int *sel_ini) {
    int sa = 0, sb = 0;
    obtener_sel(*cur, *sel_ini, &sa, &sb);
    if (sb <= sa) return 0;
    int dif = sb - sa;
    for (int i = sb; i <= *len; i++) buf[i - dif] = buf[i];
    *len -= dif;
    *cur = sa;
    *sel_ini = -1;
    return 1;
}

void teclado_readline(char *destino, int max_len) {
    char borrador[CMD_MAX];
    borrador[0] = '\0';
    int len = 0;
    int cur = 0;
    int sel_ini = -1;
    int prev_len = 0;
    int hist_pos = hist_total;
    int start_x = 0, start_y = 0;

    destino[0] = '\0';
    kget_cursor(&start_x, &start_y);

    while (1) {
        int sa = 0, sb = 0;
        obtener_sel(cur, sel_ini, &sa, &sb);
        krender_linea_input(&start_x, &start_y, destino, len, cur, sa, sb, &prev_len);

        int k = teclado_getkey();
        if (k == KEY_ENTER) {
            destino[len] = '\0';
            krender_linea_input(&start_x, &start_y, destino, len, len, 0, 0, &prev_len);
            kputc('\n');
            hist_guardar(destino);
            break;
        } else if (k == KEY_LEFT) {
            obtener_sel(cur, sel_ini, &sa, &sb);
            if (sb > sa) { cur = sa; sel_ini = -1; }
            else { sel_ini = -1; if (cur > 0) cur--; }
        } else if (k == KEY_RIGHT) {
            obtener_sel(cur, sel_ini, &sa, &sb);
            if (sb > sa) { cur = sb; sel_ini = -1; }
            else { sel_ini = -1; if (cur < len) cur++; }
        } else if (k == KEY_HOME) {
            cur = 0;
            sel_ini = -1;
        } else if (k == KEY_END) {
            cur = len;
            sel_ini = -1;
        } else if (k == KEY_S_LEFT) {
            if (sel_ini < 0) sel_ini = cur;
            if (cur > 0) cur--;
        } else if (k == KEY_S_RIGHT) {
            if (sel_ini < 0) sel_ini = cur;
            if (cur < len) cur++;
        } else if (k == KEY_S_HOME) {
            if (sel_ini < 0) sel_ini = cur;
            cur = 0;
        } else if (k == KEY_S_END) {
            if (sel_ini < 0) sel_ini = cur;
            cur = len;
        } else if (k == KEY_CTRL_A) {
            if (len > 0) { sel_ini = 0; cur = len; }
        } else if (k == KEY_CTRL_C) {
            obtener_sel(cur, sel_ini, &sa, &sb);
            if (sb > sa) clip_copiar(destino + sa, sb - sa);
            else if (len > 0) clip_copiar(destino, len);
        } else if (k == KEY_CTRL_X) {
            obtener_sel(cur, sel_ini, &sa, &sb);
            if (sb > sa) {
                clip_copiar(destino + sa, sb - sa);
                borrar_sel_linea(destino, &len, &cur, &sel_ini);
            } else if (len > 0) {
                clip_copiar(destino, len);
                len = 0; cur = 0; sel_ini = -1;
                destino[0] = '\0';
            }
        } else if (k == KEY_CTRL_V) {
            borrar_sel_linea(destino, &len, &cur, &sel_ini);
            const char *cl = clip_obtener();
            int clen = clip_largo();
            for (int i = 0; i < clen && len < max_len - 1; i++) {
                uint8_t ch = (uint8_t)cl[i];
                if (ch == '\r') continue;
                if (ch == '\n' || ch == '\t') ch = ' ';
                if (ch < 32) continue;
                for (int j = len; j >= cur; j--) destino[j + 1] = destino[j];
                destino[cur++] = (char)ch;
                len++;
            }
        } else if (k == KEY_CTRL_L) {
            kclear();
            kernel_imprimir_prompt();
            kget_cursor(&start_x, &start_y);
            prev_len = 0;
        } else if (k == KEY_BS) {
            if (!borrar_sel_linea(destino, &len, &cur, &sel_ini)) {
                if (cur > 0) {
                    for (int i = cur; i <= len; i++) destino[i - 1] = destino[i];
                    cur--;
                    len--;
                }
            }
        } else if (k == KEY_DEL) {
            if (!borrar_sel_linea(destino, &len, &cur, &sel_ini)) {
                if (cur < len) {
                    for (int i = cur + 1; i <= len; i++) destino[i - 1] = destino[i];
                    len--;
                }
            }
        } else if (k == KEY_TAB) {
            sel_ini = -1;
            destino[len] = '\0';
            if (shell_autocompletar(destino, &len, &cur, max_len)) {
                kget_cursor(&start_x, &start_y);
                prev_len = 0;
            }
        } else if (k == KEY_UP) {
            if (hist_total > 0 && hist_pos > 0) {
                if (hist_pos == hist_total) {
                    destino[len] = '\0';
                    t_scpy(borrador, destino, CMD_MAX);
                }
                hist_pos--;
                t_scpy(destino, historial[hist_pos], max_len);
                len = t_slen(destino);
                cur = len;
                sel_ini = -1;
            }
        } else if (k == KEY_DOWN) {
            if (hist_pos < hist_total) {
                hist_pos++;
                if (hist_pos == hist_total) t_scpy(destino, borrador, max_len);
                else t_scpy(destino, historial[hist_pos], max_len);
                len = t_slen(destino);
                cur = len;
                sel_ini = -1;
            }
        } else if (k >= 32 && k < 0x100) {
            borrar_sel_linea(destino, &len, &cur, &sel_ini);
            if (len < max_len - 1) {
                for (int i = len; i >= cur; i--) destino[i + 1] = destino[i];
                destino[cur++] = (char)k;
                len++;
            }
        }
    }
}

void teclado_cmd_kbd(const char *args) {
    while (*args == ' ') args++;
    if (args[0] == '\0') {
        kset_color(0x0D); kprint("=== Configuración de Teclado ===\n");
        kset_color(0x0B); kprint("  Distribución : ");
        kset_color(0x0F); kprint(teclado_layout_nombre()); kprint("\n");
        kset_color(0x0B); kprint("  Cambiar con  : ");
        kset_color(0x07); kprint("kbd latam  |  kbd es  |  kbd us\n");
        kset_color(0x0B); kprint("  Cursor       : ");
        kset_color(0x07); kprint("Flechas Izq/Der, Inicio, Fin, Supr, NumPad\n");
        kset_color(0x0B); kprint("  Portapapeles : ");
        kset_color(0x07); kprint("Shift+Flechas (sel) | Ctrl+A | Ctrl+C | Ctrl+X | Ctrl+V\n");
        kset_color(0x08); kprint("  Tildes LATAM : tecla ´ (junto a P) + vocal -> á é í ó ú | AltGr+Q -> @\n");
        kset_color(0x07);
        return;
    }
    if (t_scmp(args, "latam") == 0) {
        teclado_set_layout(KBD_LATAM);
        kernel_guardar_prefs();
        kprint("Teclado configurado en: "); kprint(teclado_layout_nombre()); kprint("\n");
    } else if (t_scmp(args, "es") == 0) {
        teclado_set_layout(KBD_ES);
        kernel_guardar_prefs();
        kprint("Teclado configurado en: "); kprint(teclado_layout_nombre()); kprint("\n");
    } else if (t_scmp(args, "us") == 0) {
        teclado_set_layout(KBD_US);
        kernel_guardar_prefs();
        kprint("Teclado configurado en: "); kprint(teclado_layout_nombre()); kprint("\n");
    } else {
        kprint("Uso: kbd [latam | es | us]\n");
    }
}
