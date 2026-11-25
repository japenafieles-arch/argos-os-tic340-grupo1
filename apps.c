/*
 * Modulo 8 (Bloque 2): Aplicaciones Cotidianas en Consola (80x25 VGA)
 *  1. Calculadora (calc): aritmetica con parentesis, potencias, porcentajes,
 *     decimales en punto fijo (x10000 sin FPU/libgcc), historial y conversor DEC/HEX/BIN.
 *  2. Calendario y Agenda de Tareas (agenda): calendario mensual real (CMOS/RTC)
 *     + lista de pendientes interactiva guardada en /agenda.txt (TIC340FS).
 *  3. Temporizador Pomodoro y Cronometro (timer): reloj gigante en modo texto
 *     impulsado por el timer hardware PIT 100 Hz (IRQ0) con CPU en reposo (hlt).
 */
#include <stdint.h>
#include "apps.h"
#include "fs.h"
#include "teclado.h"
#include "reloj.h"
#include "audit.h"

#define COLS 80
#define CALC_SCALE 10000LL

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

extern int     kernel_get_tema(void);
extern uint8_t kcol_fondo(void);
extern uint8_t kcol_barra(void);
extern uint8_t kcol_caja(void);
extern uint8_t kcol_borde(void);
extern uint8_t kcol_caja_tit(void);
extern uint8_t kcol_caja_ten(void);
extern uint8_t kcol_sel(void);
extern uint8_t kcol_acento(void);
extern uint8_t kcol_titulo(void);
extern uint8_t kcol_ok(void);
extern uint8_t kcol_aviso(void);
extern uint8_t kcol_tenue(void);
extern uint8_t kcol_dato(void);

/* ==================== UTILIDADES SIN LIBGCC ==================== */
static int ap_slen(const char *s) { int n = 0; while (s[n]) n++; return n; }

static void ap_scpy(char *d, const char *s, int max) {
    int i = 0;
    while (i < max - 1 && s && s[i]) { d[i] = s[i]; i++; }
    d[i] = '\0';
}

static uint64_t udivmod64(uint64_t num, uint64_t den, uint64_t *rem_out) {
    uint64_t q = 0, r = 0;
    if (den == 0) { if (rem_out) *rem_out = 0; return 0; }
    for (int i = 63; i >= 0; i--) {
        r = (r << 1) | ((num >> i) & 1ULL);
        if (r >= den) {
            r -= den;
            q |= (1ULL << i);
        }
    }
    if (rem_out) *rem_out = r;
    return q;
}

static int64_t sdiv64(int64_t a, int64_t b) {
    if (b == 0) return 0;
    int neg = 0;
    uint64_t ua, ub;
    if (a < 0) { neg = !neg; ua = (uint64_t)(-a); } else ua = (uint64_t)a;
    if (b < 0) { neg = !neg; ub = (uint64_t)(-b); } else ub = (uint64_t)b;
    uint64_t q = udivmod64(ua, ub, 0);
    return neg ? -(int64_t)q : (int64_t)q;
}

static void barra_inf(const char *texto, int es_aviso) {
    uint8_t bg = kcol_barra();
    uint8_t fg = es_aviso ? (uint8_t)((bg & 0xF0) | 0x0E) : bg;
    if (kernel_get_tema() == 2 && es_aviso) fg = 0x2F;
    char vacio[81];
    for (int i = 0; i < COLS; i++) vacio[i] = ' ';
    vacio[COLS] = '\0';
    kvga_texto_en(0, 24, bg, vacio);
    kvga_texto_en(1, 24, fg, texto);
}

static void u32_str(uint32_t v, char *out) {
    char tmp[12];
    int n = 0;
    do { tmp[n++] = (char)('0' + (v % 10)); v /= 10; } while (v);
    for (int i = 0; i < n; i++) out[i] = tmp[n - 1 - i];
    out[n] = '\0';
}

static void i64_u_str(uint64_t v, char *out) {
    char tmp[24];
    int n = 0;
    do {
        uint64_t rem = 0;
        v = udivmod64(v, 10ULL, &rem);
        tmp[n++] = (char)('0' + (int)rem);
    } while (v != 0 && n < 22);
    for (int i = 0; i < n; i++) out[i] = tmp[n - 1 - i];
    out[n] = '\0';
}

static void fixed_a_str(int64_t val, char *out, int max_len) {
    int p = 0;
    uint64_t u;
    if (val < 0) {
        if (p < max_len - 1) out[p++] = '-';
        u = (uint64_t)(-val);
    } else {
        u = (uint64_t)val;
    }
    uint64_t frac = 0;
    uint64_t ent = udivmod64(u, (uint64_t)CALC_SCALE, &frac);
    char ebuf[24];
    i64_u_str(ent, ebuf);
    for (int i = 0; ebuf[i] && p < max_len - 1; i++) out[p++] = ebuf[i];

    if (frac != 0) {
        char fbuf[5];
        uint64_t f = frac;
        for (int i = 3; i >= 0; i--) {
            uint64_t rem = 0;
            f = udivmod64(f, 10ULL, &rem);
            fbuf[i] = (char)('0' + (int)rem);
        }
        int flen = 4;
        while (flen > 0 && fbuf[flen - 1] == '0') flen--;
        if (flen > 0 && p < max_len - 1) {
            out[p++] = '.';
            for (int i = 0; i < flen && p < max_len - 1; i++) out[p++] = fbuf[i];
        }
    }
    out[p] = '\0';
}

static void u32_hex_str(uint32_t v, char *out) {
    static const char hx[] = "0123456789ABCDEF";
    out[0] = '0'; out[1] = 'x';
    char tmp[10];
    int n = 0;
    do { tmp[n++] = hx[v & 0xF]; v >>= 4; } while (v);
    for (int i = 0; i < n; i++) out[2 + i] = tmp[n - 1 - i];
    out[2 + n] = '\0';
}

static void u32_bin_str(uint32_t v, char *out) {
    out[0] = '0'; out[1] = 'b';
    int msb = 0;
    for (int b = 31; b >= 0; b--) {
        if ((v >> b) & 1u) { msb = b; break; }
    }
    int p = 2;
    for (int b = msb; b >= 0; b--) {
        out[p++] = ((v >> b) & 1u) ? '1' : '0';
        if (b > 0 && (b % 4) == 0 && p < 44) out[p++] = ' ';
    }
    out[p] = '\0';
}

static int popup_texto_app(const char *titulo, const char *etiqueta, char *buf, int max_len) {
    int len = ap_slen(buf);
    int cur = len;
    const int x0 = 9, y0 = 9, ancho = 62, alto = 7;

    while (1) {
        kvga_dibujar_caja(x0, y0, ancho, alto, kcol_caja(), kcol_borde());
        kvga_texto_en(x0 + 3, y0 + 1, kcol_caja_tit(), titulo);
        kvga_texto_en(x0 + 3, y0 + 3, kcol_caja(), etiqueta);

        int fx = x0 + 3 + ap_slen(etiqueta);
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
        } else if (k >= 32 && k < 0x100 && len < max_len - 1) {
            for (int j = len; j >= cur; j--) buf[j + 1] = buf[j];
            buf[cur++] = (char)k;
            len++;
        }
    }
}

/* ==================== 1. CALCULADORA (calc) ==================== */
static const char *cp_ptr = 0;
static const char *cp_err = 0;
static int64_t     calc_ans = 0;

static void cp_skip(void) { while (*cp_ptr == ' ' || *cp_ptr == '\t') cp_ptr++; }

static int64_t cp_expr(void);

static int64_t cp_primary(void) {
    cp_skip();
    if (cp_err) return 0;

    if (*cp_ptr == '(') {
        cp_ptr++;
        int64_t v = cp_expr();
        cp_skip();
        if (*cp_ptr != ')') { cp_err = "Falta paréntesis de cierre ')'"; return 0; }
        cp_ptr++;
        return v;
    }

    /* Palabra clave 'ans' (ultimo resultado) */
    if ((cp_ptr[0] == 'a' || cp_ptr[0] == 'A') &&
        (cp_ptr[1] == 'n' || cp_ptr[1] == 'N') &&
        (cp_ptr[2] == 's' || cp_ptr[2] == 'S')) {
        cp_ptr += 3;
        return calc_ans;
    }

    /* Hexadecimal 0x... */
    if (cp_ptr[0] == '0' && (cp_ptr[1] == 'x' || cp_ptr[1] == 'X')) {
        cp_ptr += 2;
        uint64_t v = 0;
        int dig = 0;
        while (1) {
            char c = *cp_ptr;
            int d = -1;
            if (c >= '0' && c <= '9') d = c - '0';
            else if (c >= 'a' && c <= 'f') d = 10 + (c - 'a');
            else if (c >= 'A' && c <= 'F') d = 10 + (c - 'A');
            else break;
            v = (v << 4) | (uint64_t)d;
            dig++; cp_ptr++;
        }
        if (dig == 0) { cp_err = "Número hexadecimal inválido"; return 0; }
        return (int64_t)v * CALC_SCALE;
    }

    /* Binario 0b... */
    if (cp_ptr[0] == '0' && (cp_ptr[1] == 'b' || cp_ptr[1] == 'B')) {
        cp_ptr += 2;
        uint64_t v = 0;
        int dig = 0;
        while (*cp_ptr == '0' || *cp_ptr == '1') {
            v = (v << 1) | (uint64_t)(*cp_ptr - '0');
            dig++; cp_ptr++;
        }
        if (dig == 0) { cp_err = "Número binario inválido"; return 0; }
        return (int64_t)v * CALC_SCALE;
    }

    /* Numero decimal (admite punto o coma decimal) */
    if ((*cp_ptr >= '0' && *cp_ptr <= '9') || *cp_ptr == '.' || *cp_ptr == ',') {
        int64_t ent = 0;
        int dig = 0;
        while (*cp_ptr >= '0' && *cp_ptr <= '9') {
            if (ent < 100000000000LL) ent = ent * 10 + (*cp_ptr - '0');
            dig++; cp_ptr++;
        }
        int64_t frac = 0;
        int fscale = 1000;
        if (*cp_ptr == '.' || *cp_ptr == ',') {
            cp_ptr++;
            while (*cp_ptr >= '0' && *cp_ptr <= '9') {
                if (fscale >= 1) {
                    frac += (int64_t)(*cp_ptr - '0') * fscale;
                    fscale /= 10;
                }
                dig++; cp_ptr++;
            }
        }
        if (dig == 0) { cp_err = "Número inválido"; return 0; }
        return ent * CALC_SCALE + frac;
    }

    cp_err = "Expresión incompleta o carácter no válido";
    return 0;
}

static int64_t cp_postfix(void) {
    int64_t v = cp_primary();
    while (!cp_err) {
        cp_skip();
        if (*cp_ptr == '%') {
            cp_ptr++;
            v = sdiv64(v, 100LL);
        } else {
            break;
        }
    }
    return v;
}

static int64_t cp_unary(void);

static int64_t cp_power(void) {
    int64_t base = cp_postfix();
    cp_skip();
    if (!cp_err && *cp_ptr == '^') {
        cp_ptr++;
        int64_t exp_fx = cp_unary();
        if (cp_err) return 0;
        int64_t exp_i = sdiv64(exp_fx, CALC_SCALE);
        if (exp_i < 0 || exp_i > 12) {
            cp_err = "Exponente entero admitido: 0 a 12";
            return 0;
        }
        int64_t res = CALC_SCALE;
        for (int64_t k = 0; k < exp_i; k++) {
            res = sdiv64(res * base, CALC_SCALE);
        }
        return res;
    }
    return base;
}

static int64_t cp_unary(void) {
    cp_skip();
    if (*cp_ptr == '+') { cp_ptr++; return cp_unary(); }
    if (*cp_ptr == '-') { cp_ptr++; return -cp_unary(); }
    return cp_power();
}

static int64_t cp_term(void) {
    int64_t v = cp_unary();
    while (!cp_err) {
        cp_skip();
        char op = *cp_ptr;
        if (op == '*' || op == '/') {
            cp_ptr++;
            int64_t r = cp_unary();
            if (cp_err) return 0;
            if (op == '*') {
                v = sdiv64(v * r, CALC_SCALE);
            } else {
                if (r == 0) { cp_err = "Error: división por cero"; return 0; }
                v = sdiv64(v * CALC_SCALE, r);
            }
        } else {
            break;
        }
    }
    return v;
}

static int64_t cp_expr(void) {
    int64_t v = cp_term();
    while (!cp_err) {
        cp_skip();
        char op = *cp_ptr;
        if (op == '+' || op == '-') {
            cp_ptr++;
            int64_t r = cp_term();
            if (cp_err) return 0;
            v = (op == '+') ? (v + r) : (v - r);
        } else {
            break;
        }
    }
    return v;
}

static int calc_evaluar(const char *expr, int64_t *out, const char **err_out) {
    cp_ptr = expr;
    cp_err = 0;
    int64_t val = cp_expr();
    cp_skip();
    if (!cp_err && *cp_ptr != '\0') cp_err = "Símbolo inesperado al final de la operación";
    if (cp_err) {
        if (err_out) *err_out = cp_err;
        return -1;
    }
    *out = val;
    return 0;
}

#define CALC_HIST_MAX 7
static char calc_h_expr[CALC_HIST_MAX][48];
static char calc_h_res[CALC_HIST_MAX][28];
static int  calc_h_cnt = 0;

static void calc_hist_agregar(const char *e, const char *r) {
    if (calc_h_cnt < CALC_HIST_MAX) {
        ap_scpy(calc_h_expr[calc_h_cnt], e, 48);
        ap_scpy(calc_h_res[calc_h_cnt], r, 28);
        calc_h_cnt++;
    } else {
        for (int i = 0; i < CALC_HIST_MAX - 1; i++) {
            ap_scpy(calc_h_expr[i], calc_h_expr[i + 1], 48);
            ap_scpy(calc_h_res[i],  calc_h_res[i + 1],  28);
        }
        ap_scpy(calc_h_expr[CALC_HIST_MAX - 1], e, 48);
        ap_scpy(calc_h_res[CALC_HIST_MAX - 1],  r, 28);
    }
}

void apps_calculadora(void) {
    char expr[64] = "";
    char res_str[32] = "0";
    char err_msg[56] = "";
    char aviso[72] = "";
    int len = 0, cur = 0;
    int hpos = calc_h_cnt;
    int tiene_res = 0;

    while (1) {
        kvga_barra_titulo("ARGOS - CALCULADORA CIENTÍFICA Y CONVERSOR");
        kvga_limpiar_area(1, 23, kcol_fondo());

        /* Caja de entrada y resultado */
        kvga_dibujar_caja(3, 2, 74, 8, kcol_caja(), kcol_borde());
        kvga_texto_en(5, 3, kcol_caja_tit(), "Operación (usa +, -, *, /, ^, %, (), ans, 0xFF, 0b1010):");

        /* Campo de texto */
        char vacio[67];
        for (int i = 0; i < 66; i++) vacio[i] = ' ';
        vacio[66] = '\0';
        kvga_texto_en(5, 5, 0x0F, vacio);
        kvga_texto_en(6, 5, 0x0F, expr);

        if (err_msg[0]) {
            kvga_texto_en(5, 7, 0x1C, err_msg);
        } else {
            kvga_texto_en(5, 7, kcol_caja_ten(), "Resultado = ");
            kvga_texto_en(17, 7, kcol_caja_tit(), res_str);
            kvga_texto_en(44, 7, kcol_caja_ten(), "(usa 'ans' para continuar)");
        }

        /* Caja conversor DEC / HEX / BIN */
        kvga_dibujar_caja(3, 11, 74, 5, kcol_fondo(), kcol_acento());
        kvga_texto_en(5, 11, kcol_acento(), " Conversor parte entera (DEC / HEX / BIN) ");
        if (tiene_res) {
            int64_t ent_s = sdiv64(calc_ans, CALC_SCALE);
            uint32_t ent_u = (ent_s < 0) ? (uint32_t)(-ent_s) : (uint32_t)ent_s;
            char s_dec[16], s_hex[16], s_bin[48];
            u32_str(ent_u, s_dec);
            u32_hex_str(ent_u, s_hex);
            u32_bin_str(ent_u, s_bin);

            kvga_texto_en(5, 13, kcol_acento(), "DEC: ");
            kvga_texto_en(10, 13, kcol_dato(), ent_s < 0 ? "-" : "");
            kvga_texto_en(ent_s < 0 ? 11 : 10, 13, kcol_dato(), s_dec);

            kvga_texto_en(26, 13, kcol_acento(), "HEX: ");
            kvga_texto_en(31, 13, kcol_ok(), s_hex);

            kvga_texto_en(5, 14, kcol_acento(), "BIN: ");
            kvga_texto_en(10, 14, kcol_aviso(), s_bin);
        } else {
            kvga_texto_en(5, 13, kcol_tenue(), "Escribe una operación como (250 + 50) * 15%  o  2^8  y pulsa Enter.");
        }

        /* Historial */
        kvga_dibujar_caja(3, 16, 74, 7, kcol_fondo(), kcol_tenue());
        kvga_texto_en(5, 16, kcol_titulo(), " Historial reciente (Arr/Abj para recuperar) ");
        if (calc_h_cnt == 0) {
            kvga_texto_en(5, 19, kcol_tenue(), "(Sin cálculos en esta sesión)");
        } else {
            int start = (calc_h_cnt > 5) ? (calc_h_cnt - 5) : 0;
            for (int i = start; i < calc_h_cnt; i++) {
                int y = 17 + (i - start);
                kvga_texto_en(5, y, kcol_fondo(), calc_h_expr[i]);
                kvga_texto_en(46, y, kcol_tenue(), "= ");
                kvga_texto_en(48, y, kcol_ok(), calc_h_res[i]);
            }
        }

        if (aviso[0]) {
            barra_inf(aviso, 1);
            aviso[0] = '\0';
        } else {
            barra_inf("Enter: Calcular | Arr/Abj: Historial | Ctrl+C: Copiar res | ESC: Salir", 0);
        }
        kset_cursor(6 + cur, 5);

        int k = teclado_getkey();
        if (k == KEY_ESC) break;
        else if (k == KEY_ENTER) {
            expr[len] = '\0';
            if (len == 0) continue;
            int64_t val = 0;
            const char *err = 0;
            if (calc_evaluar(expr, &val, &err) == 0) {
                calc_ans = val;
                tiene_res = 1;
                err_msg[0] = '\0';
                fixed_a_str(val, res_str, sizeof(res_str));
                calc_hist_agregar(expr, res_str);
                hpos = calc_h_cnt;
                len = 0; cur = 0; expr[0] = '\0';
            } else {
                ap_scpy(err_msg, err ? err : "Error de sintaxis", sizeof(err_msg));
            }
        } else if (k == KEY_LEFT) { if (cur > 0) cur--; }
        else if (k == KEY_RIGHT) { if (cur < len) cur++; }
        else if (k == KEY_HOME) { cur = 0; }
        else if (k == KEY_END) { cur = len; }
        else if (k == KEY_UP) {
            if (calc_h_cnt > 0 && hpos > 0) {
                hpos--;
                ap_scpy(expr, calc_h_expr[hpos], sizeof(expr));
                len = ap_slen(expr); cur = len;
            }
        } else if (k == KEY_DOWN) {
            if (hpos < calc_h_cnt - 1) {
                hpos++;
                ap_scpy(expr, calc_h_expr[hpos], sizeof(expr));
                len = ap_slen(expr); cur = len;
            } else {
                hpos = calc_h_cnt;
                expr[0] = '\0'; len = 0; cur = 0;
            }
        } else if (k == KEY_CTRL_C) {
            if (tiene_res) {
                clip_copiar(res_str, ap_slen(res_str));
                ap_scpy(aviso, "Resultado copiado al portapapeles (usa Ctrl+V)", sizeof(aviso));
            }
        } else if (k == KEY_CTRL_L) {
            calc_h_cnt = 0; hpos = 0;
            ap_scpy(aviso, "Historial de calculadora limpiado.", sizeof(aviso));
        } else if (k == KEY_CTRL_V) {
            const char *cl = clip_obtener();
            int clen = clip_largo();
            for (int i = 0; i < clen && len < 60; i++) {
                uint8_t ch = (uint8_t)cl[i];
                if (ch < 32 || ch >= 127) continue;
                for (int j = len; j >= cur; j--) expr[j + 1] = expr[j];
                expr[cur++] = (char)ch; len++;
            }
        } else if (k == KEY_BS) {
            if (cur > 0) {
                for (int i = cur; i <= len; i++) expr[i - 1] = expr[i];
                cur--; len--;
            }
        } else if (k == KEY_DEL) {
            if (cur < len) {
                for (int i = cur + 1; i <= len; i++) expr[i - 1] = expr[i];
                len--;
            }
        } else if (k >= 32 && k < 127 && len < 60) {
            for (int j = len; j >= cur; j--) expr[j + 1] = expr[j];
            expr[cur++] = (char)k; len++;
            err_msg[0] = '\0';
        }
    }
}

void apps_cmd_calc(const char *args) {
    while (*args == ' ') args++;
    if (!*args) {
        apps_calculadora();
        kclear();
        return;
    }
    int64_t val = 0;
    const char *err = 0;
    if (calc_evaluar(args, &val, &err) == 0) {
        calc_ans = val;
        char sres[32], shex[16];
        fixed_a_str(val, sres, sizeof(sres));
        int64_t ent = sdiv64(val, CALC_SCALE);
        u32_hex_str(ent < 0 ? (uint32_t)(-ent) : (uint32_t)ent, shex);
        kset_color(0x0A); kprint("= "); kset_color(0x0F); kprint(sres);
        kset_color(0x08); kprint("   (hex "); kprint(shex); kprint(")\n");
        kset_color(0x07);
    } else {
        kset_color(0x0C); kprint("Calculadora - "); kprint(err ? err : "Error"); kprint("\n");
        kset_color(0x07);
    }
}

/* ==================== 2. CALENDARIO Y AGENDA (agenda) ==================== */
#define MAX_TAREAS 14
#define MAX_TAREA_TXT 34

typedef struct {
    uint8_t hecha;
    char    texto[MAX_TAREA_TXT];
} tarea_t;

static tarea_t tareas[MAX_TAREAS];
static int     num_tareas = 0;
static char    agenda_io_buf[1024];

static int ag_bisiesto(uint16_t y) {
    return (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
}

static int ag_dias_mes(int m, uint16_t y) {
    static const int dm[12] = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    if (m < 1 || m > 12) return 30;
    if (m == 2 && ag_bisiesto(y)) return 29;
    return dm[m - 1];
}

/* 0=Lunes .. 6=Domingo */
static int ag_dia_sem_lunes(uint16_t y, int m, int d) {
    static const int t[12] = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 };
    if (m < 3) y--;
    int dom = (y + y / 4 - y / 100 + y / 400 + t[m - 1] + d) % 7; /* 0=Dom..6=Sab */
    return (dom + 6) % 7;
}

static void agenda_cargar(void) {
    num_tareas = 0;
    int n = fs_leer_raiz_archivo("agenda.txt", agenda_io_buf, sizeof(agenda_io_buf));
    if (n <= 0) return;

    int i = 0;
    while (i < n && num_tareas < MAX_TAREAS) {
        int j = i;
        while (j < n && agenda_io_buf[j] != '\n') j++;
        int llen = j - i;
        if (llen > 0 && agenda_io_buf[i + llen - 1] == '\r') llen--;
        if (llen >= 4 && agenda_io_buf[i] == '[' && agenda_io_buf[i + 2] == ']' && agenda_io_buf[i + 3] == ' ') {
            tareas[num_tareas].hecha = (agenda_io_buf[i + 1] == 'x' || agenda_io_buf[i + 1] == 'X' || agenda_io_buf[i + 1] == '1') ? 1 : 0;
            int k = 0;
            for (int c = i + 4; c < i + llen && k < MAX_TAREA_TXT - 1; c++) {
                tareas[num_tareas].texto[k++] = agenda_io_buf[c];
            }
            tareas[num_tareas].texto[k] = '\0';
            if (k > 0) num_tareas++;
        }
        i = j + 1;
    }
}

static int agenda_guardar_fs(const char **err_out) {
    int p = 0;
    for (int i = 0; i < num_tareas && p < (int)sizeof(agenda_io_buf) - 42; i++) {
        agenda_io_buf[p++] = '[';
        agenda_io_buf[p++] = tareas[i].hecha ? 'x' : ' ';
        agenda_io_buf[p++] = ']';
        agenda_io_buf[p++] = ' ';
        for (int k = 0; tareas[i].texto[k] && p < (int)sizeof(agenda_io_buf) - 2; k++) {
            agenda_io_buf[p++] = tareas[i].texto[k];
        }
        agenda_io_buf[p++] = '\n';
    }
    agenda_io_buf[p] = '\0';
    return fs_guardar_raiz_archivo("agenda.txt", agenda_io_buf, err_out);
}

void apps_agenda(void) {
    static const char * const meses[12] = {
        "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
        "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"
    };

    fecha_hora_t hoy;
    reloj_leer_rtc(&hoy);
    int mes_v = hoy.mes;
    uint16_t anio_v = hoy.anio;
    int sel = 0;
    int mod = 0;
    char aviso[74] = "";

    agenda_cargar();

    while (1) {
        if (num_tareas == 0) sel = 0;
        else if (sel >= num_tareas) sel = num_tareas - 1;

        kvga_barra_titulo("ARGOS - CALENDARIO Y AGENDA DE TAREAS");
        kvga_limpiar_area(1, 23, kcol_fondo());

        /* ===== PANEL IZQUIERDO: CALENDARIO (cols 2..31, rows 2..20) ===== */
        kvga_dibujar_caja(2, 2, 30, 19, kcol_caja(), kcol_borde());

        char cab[28];
        int cp = 0;
        const char *mn = meses[(mes_v - 1) % 12];
        for (int i = 0; mn[i] && cp < 16; i++) cab[cp++] = mn[i];
        cab[cp++] = ' ';
        char ystr[8];
        u32_str(anio_v, ystr);
        for (int i = 0; ystr[i] && cp < 26; i++) cab[cp++] = ystr[i];
        cab[cp] = '\0';

        kvga_texto_en(4, 4, kcol_borde(), "<");
        kvga_texto_en(17 - (ap_slen(cab) / 2), 4, kcol_caja_tit(), cab);
        kvga_texto_en(29, 4, kcol_borde(), ">");

        kvga_texto_en(4, 6, kcol_borde(), "Lu  Ma  Mi  Ju  Vi  Sa  Do");

        int d_ini = ag_dia_sem_lunes(anio_v, mes_v, 1);
        int d_tot = ag_dias_mes(mes_v, anio_v);
        int fila = 0, col = d_ini;
        for (int d = 1; d <= d_tot; d++) {
            int px = 4 + col * 4;
            int py = 8 + fila * 2;
            char ds[3];
            ds[0] = (d < 10) ? ' ' : (char)('0' + d / 10);
            ds[1] = (char)('0' + d % 10);
            ds[2] = '\0';
            int es_hoy = (d == hoy.dia && mes_v == hoy.mes && anio_v == hoy.anio);
            kvga_texto_en(px, py, es_hoy ? kcol_sel() : kcol_caja(), ds);
            col++;
            if (col >= 7) { col = 0; fila++; }
        }

        /* Fecha de hoy al pie del calendario */
        char fh_s[24];
        fh_s[0] = 'H'; fh_s[1] = 'o'; fh_s[2] = 'y'; fh_s[3] = ':'; fh_s[4] = ' ';
        fh_s[5] = (char)('0' + hoy.dia / 10); fh_s[6] = (char)('0' + hoy.dia % 10); fh_s[7] = '/';
        fh_s[8] = (char)('0' + hoy.mes / 10); fh_s[9] = (char)('0' + hoy.mes % 10); fh_s[10] = '/';
        u32_str(hoy.anio, fh_s + 11);
        kvga_texto_en(5, 19, kcol_caja_ten(), fh_s);
        kvga_texto_en(21, 19, kcol_borde(), "(Izq/Der)");

        /* ===== PANEL DERECHO: LISTA DE TAREAS (cols 34..77, rows 2..20) ===== */
        kvga_dibujar_caja(34, 2, 44, 19, kcol_fondo(), kcol_acento());
        int hechas = 0;
        for (int i = 0; i < num_tareas; i++) if (tareas[i].hecha) hechas++;
        kvga_texto_en(36, 3, kcol_titulo(), "MIS TAREAS PENDIENTES");
        char cnt_s[16];
        u32_str((uint32_t)hechas, cnt_s);
        int sp = ap_slen(cnt_s);
        cnt_s[sp++] = '/';
        u32_str((uint32_t)num_tareas, cnt_s + sp);
        kvga_texto_en(62, 3, kcol_tenue(), "Hechas: ");
        kvga_texto_en(70, 3, kcol_ok(), cnt_s);

        if (num_tareas == 0) {
            kvga_texto_en(41, 10, kcol_tenue(), "(No tienes tareas anotadas)");
            kvga_texto_en(39, 12, kcol_fondo(), "Pulsa N para agregar tu primera tarea.");
        } else {
            for (int i = 0; i < num_tareas && i < MAX_TAREAS; i++) {
                int y = 5 + i;
                int is_sel = (i == sel);
                uint8_t c_row = is_sel ? kcol_sel() : (tareas[i].hecha ? kcol_tenue() : kcol_fondo());
                char bg[43];
                for (int c = 0; c < 42; c++) bg[c] = ' ';
                bg[42] = '\0';
                kvga_texto_en(35, y, c_row, bg);
                kvga_texto_en(36, y, is_sel ? kcol_sel() : (tareas[i].hecha ? kcol_ok() : kcol_aviso()),
                              tareas[i].hecha ? "[x] " : "[ ] ");
                kvga_texto_en(40, y, c_row, tareas[i].texto);
            }
        }

        if (mod) {
            kvga_texto_en(36, 19, kcol_aviso(), "Cambios sin guardar (pulsa G)");
        } else {
            kvga_texto_en(36, 19, kcol_tenue(), "Archivo: /agenda.txt");
        }

        kvga_texto_en(3, 22, kcol_acento(), "Arr/Abj: Tarea | Espacio/Enter: Marcar | N: Nueva | E: Editar | D: Borrar");
        kvga_texto_en(3, 23, kcol_tenue(),  "Izq/Der: Cambiar mes | H: Ir a Hoy | G: Guardar agenda | ESC: Salir");

        if (aviso[0]) {
            barra_inf(aviso, 1);
            aviso[0] = '\0';
        } else {
            barra_inf("Agenda sincronizada con el reloj CMOS/RTC y guardada en TIC340FS", 0);
        }
        kset_cursor(36, num_tareas > 0 ? (5 + sel) : 10);

        int k = teclado_getkey();
        if (k == KEY_ESC || k == 'q' || k == 'Q') {
            if (mod && fs_get_rol() != ROL_INVITADO) {
                const char *err = 0;
                agenda_guardar_fs(&err);
            }
            break;
        } else if (k == KEY_LEFT) {
            mes_v--;
            if (mes_v < 1) { mes_v = 12; if (anio_v > 2000) anio_v--; }
        } else if (k == KEY_RIGHT) {
            mes_v++;
            if (mes_v > 12) { mes_v = 1; if (anio_v < 2099) anio_v++; }
        } else if (k == 'h' || k == 'H') {
            mes_v = hoy.mes; anio_v = hoy.anio;
        } else if (k == KEY_UP && num_tareas > 0) {
            sel = (sel + num_tareas - 1) % num_tareas;
        } else if (k == KEY_DOWN && num_tareas > 0) {
            sel = (sel + 1) % num_tareas;
        } else if ((k == ' ' || k == KEY_ENTER) && num_tareas > 0) {
            if (fs_get_rol() == ROL_INVITADO) {
                ap_scpy(aviso, "Modo Invitado: solo lectura.", sizeof(aviso));
            } else {
                tareas[sel].hecha = !tareas[sel].hecha;
                mod = 1;
            }
        } else if (k == 'n' || k == 'N') {
            if (fs_get_rol() == ROL_INVITADO) {
                ap_scpy(aviso, "Modo Invitado: no puedes agregar tareas.", sizeof(aviso));
            } else if (num_tareas >= MAX_TAREAS) {
                ap_scpy(aviso, "Agenda llena (máximo 14 tareas). Elimina alguna con D.", sizeof(aviso));
            } else {
                char txt[MAX_TAREA_TXT] = "";
                if (popup_texto_app("Nueva tarea en la Agenda", "Tarea: ", txt, MAX_TAREA_TXT - 1) && txt[0]) {
                    tareas[num_tareas].hecha = 0;
                    ap_scpy(tareas[num_tareas].texto, txt, MAX_TAREA_TXT);
                    sel = num_tareas;
                    num_tareas++;
                    mod = 1;
                }
            }
        } else if ((k == 'e' || k == 'E') && num_tareas > 0) {
            if (fs_get_rol() == ROL_INVITADO) {
                ap_scpy(aviso, "Modo Invitado: no puedes editar tareas.", sizeof(aviso));
            } else {
                char txt[MAX_TAREA_TXT];
                ap_scpy(txt, tareas[sel].texto, MAX_TAREA_TXT);
                if (popup_texto_app("Editar tarea", "Tarea: ", txt, MAX_TAREA_TXT - 1) && txt[0]) {
                    ap_scpy(tareas[sel].texto, txt, MAX_TAREA_TXT);
                    mod = 1;
                }
            }
        } else if ((k == 'd' || k == 'D' || k == KEY_DEL) && num_tareas > 0) {
            if (fs_get_rol() == ROL_INVITADO) {
                ap_scpy(aviso, "Modo Invitado: no puedes eliminar tareas.", sizeof(aviso));
            } else {
                for (int i = sel; i < num_tareas - 1; i++) tareas[i] = tareas[i + 1];
                num_tareas--;
                mod = 1;
                ap_scpy(aviso, "Tarea eliminada. Pulsa G para guardar en el disco.", sizeof(aviso));
            }
        } else if (k == 'g' || k == 'G') {
            const char *err = 0;
            if (agenda_guardar_fs(&err) == 0) {
                mod = 0;
                if (fs_save_silencioso(&err) == 0) {
                    ap_scpy(aviso, "¡Agenda guardada en /agenda.txt y en el disco ATA!", sizeof(aviso));
                } else {
                    ap_scpy(aviso, "Guardada en RAM (/agenda.txt). Conecta disco ATA para persistir.", sizeof(aviso));
                }
            } else {
                ap_scpy(aviso, err ? err : "No se pudo guardar la agenda.", sizeof(aviso));
            }
        }
    }
}

/* ==================== 3. TEMPORIZADOR / POMODORO (timer) ==================== */
static const char * const dig_art[11][5] = {
    { " ### ", "#   #", "#   #", "#   #", " ### " }, /* 0 */
    { "  #  ", " ##  ", "  #  ", "  #  ", " ### " }, /* 1 */
    { " ### ", "#   #", "  ## ", " #   ", "#####" }, /* 2 */
    { " ### ", "#   #", "  ## ", "#   #", " ### " }, /* 3 */
    { "#   #", "#   #", "#####", "    #", "    #" }, /* 4 */
    { "#####", "#    ", "#### ", "    #", "#### " }, /* 5 */
    { " ### ", "#    ", "#### ", "#   #", " ### " }, /* 6 */
    { "#####", "   # ", "  #  ", " #   ", " #   " }, /* 7 */
    { " ### ", "#   #", " ### ", "#   #", " ### " }, /* 8 */
    { " ### ", "#   #", " ####", "    #", " ### " }, /* 9 */
    { "     ", "  #  ", "     ", "  #  ", "     " }  /* : */
};

static void dibujar_reloj_grande(int x0, int y0, uint8_t col, uint32_t segs) {
    uint32_t m = segs / 60u;
    uint32_t s = segs % 60u;
    if (m > 99u) m = 99u;
    int digs[5] = { (int)(m / 10u), (int)(m % 10u), 10, (int)(s / 10u), (int)(s % 10u) };
    for (int r = 0; r < 5; r++) {
        for (int i = 0; i < 5; i++) {
            kvga_texto_en(x0 + i * 7, y0 + r, col, dig_art[digs[i]][r]);
        }
    }
}

void apps_timer(void) {
    int modo = 0; /* 0=Pomodoro 25m, 1=Descanso 5m, 2=Rapido 1m, 3=Personalizado, 4=Cronometro */
    uint32_t meta_tics = 25u * 60u * PIT_HZ;
    uint32_t trans_tics = 0;
    int corriendo = 0;
    int terminado = 0;
    uint32_t ult_tick = reloj_ticks();
    uint32_t ult_dibujo = 0xFFFFFFFFu;
    int redibujar = 1;

    static const char * const modo_nom[5] = {
        "Estudio Pomodoro (25 min)",
        "Descanso Corto (5 min)",
        "Cuenta Rápida (1 min)",
        "Tiempo Personalizado",
        "Cronómetro Ascendente"
    };

    while (1) {
        uint32_t ahora = reloj_ticks();
        if (corriendo && !terminado) {
            uint32_t delta = ahora - ult_tick;
            if (delta > 0) {
                trans_tics += delta;
                ult_tick = ahora;
                if (modo != 4 && trans_tics >= meta_tics) {
                    trans_tics = meta_tics;
                    corriendo = 0;
                    terminado = 1;
                    redibujar = 1;
                }
            }
        } else {
            ult_tick = ahora;
        }

        if (redibujar || (corriendo && (ahora - ult_dibujo) >= 10u) || (terminado && (ahora - ult_dibujo) >= 40u)) {
            redibujar = 0;
            ult_dibujo = ahora;

            kvga_barra_titulo("ARGOS - TEMPORIZADOR POMODORO Y CRONÓMETRO");
            kvga_limpiar_area(1, 23, kcol_fondo());

            kvga_texto_en(6, 2, kcol_acento(), "Modos: ");
            kvga_texto_en(13, 2, modo == 0 ? kcol_sel() : kcol_fondo(), " 1:25m ");
            kvga_texto_en(21, 2, modo == 1 ? kcol_sel() : kcol_fondo(), " 2:5m ");
            kvga_texto_en(28, 2, modo == 2 ? kcol_sel() : kcol_fondo(), " 3:1m ");
            kvga_texto_en(35, 2, modo == 3 ? kcol_sel() : kcol_fondo(), " 4:Pers ");
            kvga_texto_en(44, 2, modo == 4 ? kcol_sel() : kcol_fondo(), " 5:Cronómetro ");

            kvga_dibujar_caja(12, 4, 56, 15, kcol_caja(), kcol_borde());
            kvga_texto_en(15, 5, kcol_caja_tit(), modo_nom[modo]);

            const char *est_txt = terminado ? "[ TERMINADO ]" : (corriendo ? "[ CORRIENDO ]" : "[ PAUSADO ]");
            kvga_texto_en(52, 5, terminado ? 0x4F : (corriendo ? kcol_ok() : kcol_caja_ten()), est_txt);

            uint32_t seg_ver = (modo == 4)
                ? (trans_tics / PIT_HZ)
                : ((meta_tics > trans_tics) ? ((meta_tics - trans_tics + PIT_HZ - 1u) / PIT_HZ) : 0u);

            uint8_t col_dig = kcol_caja_tit();
            if (terminado) col_dig = ((ahora / 40u) & 1u) ? 0x4F : 0x1E;
            dibujar_reloj_grande(23, 8, col_dig, seg_ver);

            /* Barra de progreso */
            if (modo != 4) {
                uint32_t pct = (meta_tics > 0) ? ((trans_tics * 100u) / meta_tics) : 100u;
                if (pct > 100u) pct = 100u;
                int llenos = (int)((pct * 42u) / 100u);
                char bar[46];
                bar[0] = '[';
                for (int i = 0; i < 42; i++) bar[1 + i] = (i < llenos) ? '#' : '.';
                bar[43] = ']';
                bar[44] = '\0';
                kvga_texto_en(15, 15, kcol_borde(), bar);
                char ps[6];
                u32_str(pct, ps);
                kvga_texto_en(60, 15, kcol_caja_tit(), ps);
                kvga_texto_en(60 + ap_slen(ps), 15, kcol_caja_tit(), "%");
            } else {
                uint32_t decs = (trans_tics % PIT_HZ) / 10u;
                char dstr[16] = "Décimas: .0 s";
                dstr[10] = (char)('0' + decs);
                kvga_texto_en(33, 15, kcol_caja_ten(), dstr);
            }

            if (terminado) {
                uint8_t col_al = ((ahora / 40u) & 1u) ? 0x4F : 0x1E;
                kvga_texto_en(24, 17, col_al, " *** ¡TIEMPO COMPLETADO! *** ");
            } else {
                kvga_texto_en(17, 17, kcol_caja_ten(), "Temporizador de hardware PIT (100 Hz / IRQ0)");
            }

            kvga_texto_en(12, 21, kcol_acento(), "Espacio/Enter: Iniciar o Pausar  |  R: Reiniciar  |  ESC: Salir");
            barra_inf("Teclas 1-5: Cambiar duración o cronómetro | CPU en reposo (hlt) entre tics", 0);
            kset_cursor(12, 4);
        }

        int k = teclado_poll_key();
        if (k == 0) {
            if (reloj_activo()) __asm__ volatile("hlt");
            continue;
        }

        if (k == KEY_ESC || k == 'q' || k == 'Q') {
            break;
        } else if (k == ' ' || k == KEY_ENTER) {
            if (terminado) {
                trans_tics = 0; terminado = 0; corriendo = 1; ult_tick = reloj_ticks();
            } else {
                corriendo = !corriendo;
                ult_tick = reloj_ticks();
            }
            redibujar = 1;
        } else if (k == 'r' || k == 'R') {
            trans_tics = 0; corriendo = 0; terminado = 0;
            redibujar = 1;
        } else if (k == '1') {
            modo = 0; meta_tics = 25u * 60u * PIT_HZ; trans_tics = 0; corriendo = 0; terminado = 0; redibujar = 1;
        } else if (k == '2') {
            modo = 1; meta_tics = 5u * 60u * PIT_HZ;  trans_tics = 0; corriendo = 0; terminado = 0; redibujar = 1;
        } else if (k == '3') {
            modo = 2; meta_tics = 1u * 60u * PIT_HZ;  trans_tics = 0; corriendo = 0; terminado = 0; redibujar = 1;
        } else if (k == '4') {
            char mbuf[6] = "10";
            if (popup_texto_app("Duración personalizada", "Minutos (1..99): ", mbuf, 4) && mbuf[0]) {
                uint32_t m = 0;
                for (int i = 0; mbuf[i] >= '0' && mbuf[i] <= '9'; i++) m = m * 10u + (uint32_t)(mbuf[i] - '0');
                if (m >= 1u && m <= 99u) {
                    modo = 3; meta_tics = m * 60u * PIT_HZ; trans_tics = 0; corriendo = 0; terminado = 0;
                }
            }
            redibujar = 1;
        } else if (k == '5') {
            modo = 4; trans_tics = 0; corriendo = 0; terminado = 0; redibujar = 1;
        }
    }
}

/* ==================== SUBMENU DE APLICACIONES ==================== */
void apps_menu(void) {
    int sel = 0;
    static const char * const ops[4] = {
        "1. Calculadora y Conversor (DEC / HEX / BIN)",
        "2. Calendario y Agenda de Tareas",
        "3. Temporizador Pomodoro y Cronómetro",
        "4. Volver al Menú Principal"
    };
    static const char * const descs[4] = {
        "Operaciones con paréntesis, porcentajes, potencias y bases numéricas",
        "Consulta el mes actual y administra tus pendientes en /agenda.txt",
        "Estudia con bloques de 25 min, descansos o cronómetro en vivo",
        "Regresa a la pantalla principal de ARGOS OS"
    };

    while (1) {
        kvga_barra_titulo("ARGOS - APLICACIONES COTIDIANAS");
        kvga_limpiar_area(1, 23, kcol_fondo());

        const int x0 = 9, y0 = 5, ancho = 62, alto = 13;
        kvga_dibujar_caja(x0, y0, ancho, alto, kcol_caja(), kcol_borde());
        kvga_texto_en(x0 + 18, y0 + 1, kcol_caja_tit(), "APLICACIONES DE ARGOS OS");

        for (int i = 0; i < 4; i++) {
            int y = y0 + 3 + i * 2;
            uint8_t col = (i == sel) ? kcol_sel() : kcol_caja();
            char bg[59];
            for (int c = 0; c < 58; c++) bg[c] = ' ';
            bg[58] = '\0';
            kvga_texto_en(x0 + 2, y, col, bg);
            kvga_texto_en(x0 + 4, y, col, i == sel ? "> " : "  ");
            kvga_texto_en(x0 + 6, y, col, ops[i]);
        }

        kvga_texto_en(6, 20, kcol_acento(), "Info: ");
        kvga_texto_en(12, 20, kcol_fondo(), descs[sel]);

        barra_inf("Flechas Arr/Abj o teclas 1-4: Elegir aplicación | Enter: Abrir | ESC: Volver", 0);
        kset_cursor(x0 + 4, y0 + 3 + sel * 2);

        int k = teclado_getkey();
        if (k == KEY_ESC) break;
        else if (k == KEY_UP) sel = (sel + 3) % 4;
        else if (k == KEY_DOWN) sel = (sel + 1) % 4;
        else if (k >= '1' && k <= '4') { sel = k - '1'; k = KEY_ENTER; }

        if (k == KEY_ENTER) {
            if (sel == 0) apps_calculadora();
            else if (sel == 1) apps_agenda();
            else if (sel == 2) apps_timer();
            else break;
        }
    }
}
