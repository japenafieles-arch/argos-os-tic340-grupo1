#include <stdint.h>
#include "fs.h"
#include "mem.h"
#include "teclado.h"
#include "reloj.h"
#include "proc.h"
#include "audit.h"
#include "net.h"
#include "scholar.h"
#include "ui.h"
#include "apps.h"
#include "juegos.h"

#define VGA_ADDR 0xB8000
#define COLS 80
#define ROWS 25
#define COLOR_BARRA   0x1F  /* blanco sobre azul */
#define COLOR_RELOJ   0x1E  /* amarillo sobre azul */
#define COLOR_MORADO  0x05
#define COLOR_CELESTE 0x0B

static volatile uint16_t * const vga = (volatile uint16_t *)VGA_ADDR;
static int cx = 0;
static int cy = 2;
static uint8_t color_actual = 0x07;

/* ==================== TEMAS VISUALES (0=Argos, 1=Claro, 2=Retro) ==================== */
static int tema_actual = 0;

int kernel_get_tema(void) { return tema_actual; }

void kernel_set_tema(int t) {
    if (t >= 0 && t <= 2) tema_actual = t;
}

const char *kernel_tema_nombre(void) {
    if (tema_actual == 1) return "Lectura Claro";
    if (tema_actual == 2) return "Retro Verde";
    return "Argos Azul";
}

uint8_t kcol_fondo(void)    { return tema_actual == 1 ? 0x70 : (tema_actual == 2 ? 0x0A : 0x07); }
uint8_t kcol_barra(void)    { return tema_actual == 2 ? 0x20 : 0x1F; }
uint8_t kcol_reloj(void)    { return tema_actual == 2 ? 0x2F : 0x1E; }
uint8_t kcol_caja(void)     { return tema_actual == 1 ? 0x70 : (tema_actual == 2 ? 0x0A : 0x1F); }
uint8_t kcol_borde(void)    { return tema_actual == 1 ? 0x71 : (tema_actual == 2 ? 0x02 : 0x1B); }
uint8_t kcol_caja_tit(void) { return tema_actual == 1 ? 0x71 : (tema_actual == 2 ? 0x0F : 0x1E); }
uint8_t kcol_caja_ten(void) { return tema_actual == 1 ? 0x78 : (tema_actual == 2 ? 0x02 : 0x17); }
uint8_t kcol_sel(void)      { return tema_actual == 1 ? 0x1F : (tema_actual == 2 ? 0x20 : 0x30); }
uint8_t kcol_acento(void)   { return tema_actual == 1 ? 0x71 : (tema_actual == 2 ? 0x0A : 0x0B); }
uint8_t kcol_titulo(void)   { return tema_actual == 1 ? 0x75 : (tema_actual == 2 ? 0x0F : 0x0D); }
uint8_t kcol_ok(void)       { return tema_actual == 1 ? 0x72 : 0x0A; }
uint8_t kcol_aviso(void)    { return tema_actual == 1 ? 0x74 : 0x0E; }
uint8_t kcol_tenue(void)    { return tema_actual == 1 ? 0x78 : (tema_actual == 2 ? 0x02 : 0x08); }
uint8_t kcol_dato(void)     { return tema_actual == 1 ? 0x70 : 0x0F; }

void kernel_guardar_prefs(void) {
    fs_guardar_prefs((uint8_t)teclado_get_layout(), (int8_t)reloj_get_tz(), (uint8_t)tema_actual);
}

typedef struct {
    const char *nombre_corto;
    const char *nombre_completo;
    const char *desc_permisos;
    const char *clave;
    int rol;
} usuario_t;

static const usuario_t usuarios[3] = {
    { "admin",    "Administrador Argos", "Todos los permisos",      "argos", ROL_ADMIN },
    { "usuario",  "Usuario Común",       "Lectura y escritura",     "1234",  ROL_USUARIO },
    { "invitado", "Invitado",            "Solo lectura",            "",      ROL_INVITADO }
};

static int usuario_activo = 0;

const char *kernel_usuario_corto(void) {
    return usuarios[usuario_activo].nombre_corto;
}

const char *kernel_usuario_nombre_completo(void) {
    return usuarios[usuario_activo].nombre_completo;
}

const char *kernel_usuario_desc_permisos(void) {
    return usuarios[usuario_activo].desc_permisos;
}

static inline void outb(uint16_t port, uint8_t val) {
    __asm__ volatile("outb %0, %1" : : "a"(val), "Nd"(port));
}
static inline void outw(uint16_t port, uint16_t val) {
    __asm__ volatile("outw %0, %1" : : "a"(val), "Nd"(port));
}
static inline uint8_t inb(uint16_t port) {
    uint8_t r;
    __asm__ volatile("inb %1, %0" : "=a"(r) : "Nd"(port));
    return r;
}

static void cursor_init(void) {
    outb(0x3D4, 0x0A); outb(0x3D5, (uint8_t)((inb(0x3D5) & 0xC0) | 13));
    outb(0x3D4, 0x0B); outb(0x3D5, (uint8_t)((inb(0x3D5) & 0xE0) | 15));
}
static void cursor_mover(void) {
    uint16_t pos = (uint16_t)(cy * COLS + cx);
    outb(0x3D4, 0x0F); outb(0x3D5, (uint8_t)(pos & 0xFF));
    outb(0x3D4, 0x0E); outb(0x3D5, (uint8_t)(pos >> 8));
}
static void cursor_pos(int x, int y) {
    cx = x;
    cy = y;
    cursor_mover();
}

static void vga_fuente_tildes(void) {
    static const uint8_t base[4] = { 'A', 'I', 'O', 'U' };
    static const uint8_t destino[4] = { 0x9B, 0x9C, 0x9D, 0x9E };
    volatile uint8_t *fuente = (volatile uint8_t *)0xA0000;

    outb(0x3C4, 0x02); outb(0x3C5, 0x04);
    outb(0x3C4, 0x04); outb(0x3C5, 0x07);
    outb(0x3CE, 0x04); outb(0x3CF, 0x02);
    outb(0x3CE, 0x05); outb(0x3CF, 0x00);
    outb(0x3CE, 0x06); outb(0x3CF, 0x04);

    for (int k = 0; k < 4; k++) {
        uint8_t g[16];
        for (int r = 0; r < 16; r++) g[r] = fuente[base[k] * 32 + r];
        volatile uint8_t *d = fuente + destino[k] * 32;
        d[0] = 0x0C;
        d[1] = 0x18;
        d[2] = 0x00;
        for (int r = 3; r < 16; r++) d[r] = g[r - 1];
    }

    outb(0x3C4, 0x02); outb(0x3C5, 0x03);
    outb(0x3C4, 0x04); outb(0x3C5, 0x03);
    outb(0x3CE, 0x04); outb(0x3CF, 0x00);
    outb(0x3CE, 0x05); outb(0x3CF, 0x10);
    outb(0x3CE, 0x06); outb(0x3CF, 0x0E);
}

void kset_color(uint8_t c) {
    color_actual = c;
}

static uint8_t utf8_a_vga(uint8_t a, uint8_t b) {
    if (a == 0xC3) {
        switch (b) {
            case 0x81: return 0x9B;
            case 0x89: return 0x90;
            case 0x8D: return 0x9C;
            case 0x93: return 0x9D;
            case 0x9A: return 0x9E;
            case 0x91: return 0xA5;
            case 0x9C: return 0x9A;
            case 0xA1: return 0xA0;
            case 0xA9: return 0x82;
            case 0xAD: return 0xA1;
            case 0xB3: return 0xA2;
            case 0xBA: return 0xA3;
            case 0xB1: return 0xA4;
            case 0xBC: return 0x81;
        }
    } else if (a == 0xC2) {
        switch (b) {
            case 0xBF: return 0xA8;
            case 0xA1: return 0xAD;
            case 0xBA: return 0xA7;
            case 0xB0: return 0xF8;
        }
    }
    return '?';
}

void kget_cursor(int *x, int *y) {
    if (x) *x = cx;
    if (y) *y = cy;
}

static int largo_visible(const char *s) {
    int n = 0;
    const uint8_t *p = (const uint8_t *)s;
    while (*p) {
        if ((*p == 0xC3 || *p == 0xC2) && (p[1] & 0xC0) == 0x80) p += 2;
        else p++;
        n++;
    }
    return n;
}

static void vga_texto_en(int x, int y, uint8_t color, const char *s) {
    const uint8_t *p = (const uint8_t *)s;
    while (*p && x < COLS) {
        uint8_t c = *p++;
        uint8_t glifo;
        if ((c == 0xC3 || c == 0xC2) && (*p & 0xC0) == 0x80) {
            glifo = utf8_a_vga(c, *p++);
        } else {
            glifo = c;
        }
        vga[y * COLS + x] = (uint16_t)((color << 8) | glifo);
        x++;
    }
}

static void vga_dibujar_caja(int x0, int y0, int ancho, int alto, uint8_t color_fondo, uint8_t color_borde) {
    for (int y = y0; y < y0 + alto; y++) {
        for (int x = x0; x < x0 + ancho; x++) {
            uint8_t ch = ' ';
            uint8_t col = color_fondo;
            if (y == y0 || y == y0 + alto - 1) {
                ch = (x == x0 || x == x0 + ancho - 1) ? '+' : '-';
                col = color_borde;
            } else if (x == x0 || x == x0 + ancho - 1) {
                ch = '|';
                col = color_borde;
            }
            vga[y * COLS + x] = (uint16_t)((col << 8) | ch);
        }
    }
}

void kdibujar_reloj_barra(uint8_t h, uint8_t m, uint8_t s) {
    char buf[9];
    buf[0] = (char)('0' + (h / 10));
    buf[1] = (char)('0' + (h % 10));
    buf[2] = ':';
    buf[3] = (char)('0' + (m / 10));
    buf[4] = (char)('0' + (m % 10));
    buf[5] = ':';
    buf[6] = (char)('0' + (s / 10));
    buf[7] = (char)('0' + (s % 10));
    buf[8] = '\0';
    for (int i = 0; i < 8; i++) {
        vga[71 + i] = (uint16_t)((kcol_reloj() << 8) | (uint8_t)buf[i]);
    }
}

static void barra_titulo(const char *t) {
    int largo = largo_visible(t);
    int ini = (COLS - largo) / 2;
    uint8_t cb = kcol_barra();
    for (int i = 0; i < COLS; i++) vga[i] = (uint16_t)((cb << 8) | ' ');
    vga_texto_en(ini, 0, cb, t);
    reloj_refrescar_barra();
}


void kvga_texto_en(int x, int y, uint8_t color, const char *s) {
    vga_texto_en(x, y, color, s);
}

void kvga_dibujar_caja(int x0, int y0, int ancho, int alto, uint8_t fondo, uint8_t borde) {
    vga_dibujar_caja(x0, y0, ancho, alto, fondo, borde);
}

void kvga_barra_titulo(const char *t) {
    barra_titulo(t);
}

void kvga_limpiar_area(int y_ini, int y_fin, uint8_t color) {
    if (y_ini < 0) y_ini = 0;
    if (y_fin >= ROWS) y_fin = ROWS - 1;
    for (int y = y_ini; y <= y_fin; y++) {
        for (int x = 0; x < COLS; x++) {
            vga[y * COLS + x] = (uint16_t)((color << 8) | ' ');
        }
    }
}

void kset_cursor(int x, int y) {
    cursor_pos(x, y);
}

void kclear(void) {
    for (int i = 0; i < COLS * ROWS; i++) vga[i] = (0x07 << 8) | ' ';
    barra_titulo("ARGOS - SISTEMA OPERATIVO");
    cx = 0;
    cy = 2;
    color_actual = 0x07;
    cursor_mover();
}

static void uint_a_str(uint32_t v, char *out) {
    char tmp[12];
    int n = 0;
    do { tmp[n++] = (char)('0' + (v % 10)); v /= 10; } while (v);
    for (int i = 0; i < n; i++) out[i] = tmp[n - 1 - i];
    out[n] = '\0';
}

static void kscroll(void);

/* Renderiza la linea de entrada del shell con cursor libre y seleccion visual */
void krender_linea_input(int *start_x, int *start_y, const char *buf,
                         int len, int cur, int sel_a, int sel_b, int *prev_len) {
    int max_i = (len > *prev_len) ? len : *prev_len;
    int max_pos = (*start_x) + max_i;
    int rows_needed = (max_pos / COLS) + 1;
    while ((*start_y) + rows_needed > ROWS && (*start_y) > 2) {
        kscroll();
        (*start_y)--;
    }

    int base = (*start_y) * COLS + (*start_x);
    for (int i = 0; i < len; i++) {
        int pos = base + i;
        if (pos >= 2 * COLS && pos < ROWS * COLS) {
            uint8_t col = (sel_a < sel_b && i >= sel_a && i < sel_b) ? 0x30 : 0x07;
            vga[pos] = (uint16_t)((col << 8) | (uint8_t)buf[i]);
        }
    }
    for (int i = len; i < *prev_len; i++) {
        int pos = base + i;
        if (pos >= 2 * COLS && pos < ROWS * COLS) {
            vga[pos] = (0x07 << 8) | ' ';
        }
    }

    int cpos = base + cur;
    if (cpos >= ROWS * COLS) cpos = ROWS * COLS - 1;
    cx = cpos % COLS;
    cy = cpos / COLS;
    cursor_mover();
    *prev_len = len;
}

/* Renderiza el editor de archivos completo (barra superior, 22 filas con scroll y seleccion, barra inferior) */
void krender_editor_doc(const char *nombre, const char *buf, int len, int cur,
                        int sel_a, int sel_b, int max_bytes, int modificado,
                        int *scroll_row, const char *estado_msg) {
    /* 1) Calcular fila y columna de documento donde esta el cursor */
    int cur_r = 0, cur_c = 0;
    for (int i = 0; i < cur && i < len; i++) {
        if (buf[i] == '\n') { cur_r++; cur_c = 0; }
        else {
            cur_c++;
            if (cur_c >= COLS) { cur_r++; cur_c = 0; }
        }
    }
    if (cur_r < *scroll_row) *scroll_row = cur_r;
    if (cur_r >= *scroll_row + 22) *scroll_row = cur_r - 21;

    /* 2) Barra superior (fila 0): EDITOR | archivo* | bytes/1023 B | Lx:Cy + reloj */
    for (int i = 0; i < 70; i++) vga[i] = (COLOR_BARRA << 8) | ' ';
    int x = 1;
    const char *pre = "EDITOR | ";
    for (int i = 0; pre[i] && x < 70; i++) vga[x++] = (uint16_t)((COLOR_BARRA << 8) | (uint8_t)pre[i]);
    for (int i = 0; nombre[i] && i < 18 && x < 70; i++)
        vga[x++] = (uint16_t)((0x1B << 8) | (uint8_t)nombre[i]);
    if (modificado && x < 70) vga[x++] = (uint16_t)((0x1E << 8) | '*');

    const char *sep = " | ";
    for (int i = 0; sep[i] && x < 70; i++) vga[x++] = (uint16_t)((COLOR_BARRA << 8) | (uint8_t)sep[i]);

    char b1[12], b2[12], bl[12], bc[12];
    uint_a_str((uint32_t)len, b1);
    uint_a_str((uint32_t)max_bytes, b2);
    uint_a_str((uint32_t)(cur_r + 1), bl);
    uint_a_str((uint32_t)(cur_c + 1), bc);

    uint8_t col_cnt = (len >= max_bytes - 64) ? 0x1E : 0x1A;
    if (len >= max_bytes) col_cnt = 0x1C;
    for (int i = 0; b1[i] && x < 70; i++) vga[x++] = (uint16_t)((col_cnt << 8) | (uint8_t)b1[i]);
    if (x < 70) vga[x++] = (uint16_t)((COLOR_BARRA << 8) | '/');
    for (int i = 0; b2[i] && x < 70; i++) vga[x++] = (uint16_t)((COLOR_BARRA << 8) | (uint8_t)b2[i]);
    const char *sb_txt = " B | L";
    for (int i = 0; sb_txt[i] && x < 70; i++) vga[x++] = (uint16_t)((COLOR_BARRA << 8) | (uint8_t)sb_txt[i]);
    for (int i = 0; bl[i] && x < 70; i++) vga[x++] = (uint16_t)((0x1F << 8) | (uint8_t)bl[i]);
    if (x < 70) vga[x++] = (uint16_t)((COLOR_BARRA << 8) | ':');
    if (x < 70) vga[x++] = (uint16_t)((COLOR_BARRA << 8) | 'C');
    for (int i = 0; bc[i] && x < 70; i++) vga[x++] = (uint16_t)((0x1F << 8) | (uint8_t)bc[i]);
    reloj_refrescar_barra();

    /* 3) Limpiar filas 1..23 y renderizar texto con seleccion */
    for (int i = COLS; i < 24 * COLS; i++) vga[i] = (0x07 << 8) | ' ';

    int r = 0, c = 0;
    for (int i = 0; i < len; i++) {
        uint8_t col = (sel_a < sel_b && i >= sel_a && i < sel_b) ? 0x30 : 0x07;
        if (buf[i] == '\n') {
            if (r >= *scroll_row && r < *scroll_row + 22 && col == 0x30) {
                int sy = 2 + (r - *scroll_row);
                vga[sy * COLS + c] = (uint16_t)((0x30 << 8) | ' ');
            }
            r++; c = 0;
        } else {
            if (r >= *scroll_row && r < *scroll_row + 22) {
                int sy = 2 + (r - *scroll_row);
                vga[sy * COLS + c] = (uint16_t)((col << 8) | (uint8_t)buf[i]);
            }
            c++;
            if (c >= COLS) { r++; c = 0; }
        }
    }

    /* 4) Barra inferior de atajos / aviso (fila 24) */
    for (int i = 0; i < COLS; i++) vga[24 * COLS + i] = (COLOR_BARRA << 8) | ' ';
    if (estado_msg && estado_msg[0]) {
        vga_texto_en(1, 24, 0x1E, estado_msg);
        vga_texto_en(53, 24, 0x17, "| ESC: Salir");
    } else {
        vga_texto_en(1, 24, 0x1F, "^C Copiar | ^X Cortar | ^V Pegar | ^A Todo | Shift+Flechas | ESC Salir");
    }

    /* 5) Ubicar cursor fisico */
    cx = cur_c;
    cy = 2 + (cur_r - *scroll_row);
    cursor_mover();
}

static void kscroll(void) {
    for (int r = 2; r < ROWS - 1; r++) {
        for (int c = 0; c < COLS; c++) {
            vga[r * COLS + c] = vga[(r + 1) * COLS + c];
        }
    }
    for (int c = 0; c < COLS; c++) {
        vga[(ROWS - 1) * COLS + c] = (0x07 << 8) | ' ';
    }
    cy = ROWS - 1;
}

void kputc(char c) {
    if (c == '\n') { cx = 0; cy++; }
    else if (c == '\b') {
        if (cx > 0) cx--;
        else if (cy > 2) { cy--; cx = COLS - 1; }
        vga[cy * COLS + cx] = (0x07 << 8) | ' ';
    } else {
        vga[cy * COLS + cx] = (uint16_t)((color_actual << 8) | (uint8_t)c);
        cx++;
        if (cx >= COLS) { cx = 0; cy++; }
    }
    if (cy >= ROWS) kscroll();
    cursor_mover();
}

void kprint(const char *s) {
    const uint8_t *p = (const uint8_t *)s;
    while (*p) {
        uint8_t c = *p++;
        if ((c == 0xC3 || c == 0xC2) && (*p & 0xC0) == 0x80) {
            kputc((char)utf8_a_vga(c, *p++));
        } else {
            kputc((char)c);
        }
    }
}

void kprint_pad(const char *s, int ancho) {
    int visibles = largo_visible(s);
    kprint(s);
    while (visibles++ < ancho) kputc(' ');
}

void kprint_hex(uint32_t v, int digitos) {
    static const char hex[] = "0123456789ABCDEF";
    kputc('0'); kputc('x');
    for (int i = digitos - 1; i >= 0; i--) kputc(hex[(v >> (i * 4)) & 0xF]);
}

void kprint_dec(uint32_t v) {
    char buf[11];
    int n = 0;
    do { buf[n++] = (char)('0' + v % 10); v /= 10; } while (v);
    while (n--) kputc(buf[n]);
}

void kprint_logo(void) {
    kset_color(COLOR_MORADO);
    kprint("           ..\n");
    kprint("          :##:\n");
    kprint("         :####:           T E C N O L Ó G I C O\n");
    kprint("        :######:          U N I V E R S I T A R I O\n");
    kprint("       :###::###:\n");
    kset_color(COLOR_CELESTE);
    kprint("      :###:++:###:         ###   ####   ####   ###   ####\n");
    kprint("     :###:++++:###:       #   #  #   # #      #   # #\n");
    kprint("    :###:++##++:###:      #####  ####  #  ##  #   #  ###\n");
    kprint("   :###:++####++:###:     #   #  #  #  #   #  #   #     #\n");
    kprint("  :###:++++++++++:###:    #   #  #   #  ####   ###  ####\n");
    kprint(" :###:============:###:\n\n");
    kset_color(0x07);
}

int kconfirmar_guardar(const char *nombre) {
    int opcion = 1;
    const int x0 = 13, y0 = 8, ancho = 54, alto = 9;

    while (1) {
        vga_dibujar_caja(x0, y0, ancho, alto, 0x1F, 0x1B);
        vga_texto_en(x0 + 6, y0 + 2, 0x1F, "¿Desea guardar la edición de este archivo?");

        vga_texto_en(x0 + 6, y0 + 3, 0x1B, "Archivo: ");
        vga_texto_en(x0 + 15, y0 + 3, 0x1E, nombre);

        uint8_t col_si = (opcion == 1) ? 0x30 : 0x17;
        uint8_t col_no = (opcion == 0) ? 0x30 : 0x17;
        vga_texto_en(x0 + 13, y0 + 5, col_si, "  [  Sí  ]  ");
        vga_texto_en(x0 + 29, y0 + 5, col_no, "  [  No  ]  ");

        vga_texto_en(x0 + 3, y0 + 7, 0x17, "Flechas: elegir | Enter: aceptar | ESC: volver");
        cursor_pos(opcion == 1 ? x0 + 18 : x0 + 34, y0 + 5);

        int k = teclado_getkey();
        if (k == KEY_LEFT || k == KEY_RIGHT || k == KEY_UP || k == KEY_DOWN || k == KEY_TAB) {
            opcion = !opcion;
        } else if (k == KEY_ENTER) {
            return opcion;
        } else if (k == KEY_ESC) {
            return -1;
        }
    }
}

/* Cuadro de aviso de cambios sin guardar antes de reboot / shutdown
 * Devuelve: 0 = Guardar y continuar, 1 = Continuar sin guardar, 2 = Cancelar
 */
static int kconfirmar_energia(int es_reboot) {
    int opcion = 0;
    const int x0 = 8, y0 = 8, ancho = 64, alto = 9;

    while (1) {
        vga_dibujar_caja(x0, y0, ancho, alto, 0x1F, 0x1E);
        vga_texto_en(x0 + 5, y0 + 2, 0x1E,
            es_reboot ? "ATENCIÓN: Hay cambios sin guardar antes de reiniciar"
                      : "ATENCIÓN: Hay cambios sin guardar antes de apagar");
        vga_texto_en(x0 + 5, y0 + 3, 0x1F, "¿Desea guardar TIC340FS en el disco ATA primero?");

        uint8_t c0 = (opcion == 0) ? 0x30 : 0x17;
        uint8_t c1 = (opcion == 1) ? 0x30 : 0x17;
        uint8_t c2 = (opcion == 2) ? 0x30 : 0x17;
        vga_texto_en(x0 + 4,  y0 + 5, c0, " [ Guardar y seguir ] ");
        vga_texto_en(x0 + 28, y0 + 5, c1, " [ Sin guardar ] ");
        vga_texto_en(x0 + 47, y0 + 5, c2, " [ Cancelar ] ");

        vga_texto_en(x0 + 7, y0 + 7, 0x17, "Flechas Izq/Der: elegir | Enter: aceptar | ESC: cancelar");
        cursor_pos(opcion == 0 ? x0 + 7 : (opcion == 1 ? x0 + 31 : x0 + 50), y0 + 5);

        int k = teclado_getkey();
        if (k == KEY_LEFT) opcion = (opcion + 2) % 3;
        else if (k == KEY_RIGHT || k == KEY_TAB) opcion = (opcion + 1) % 3;
        else if (k == KEY_ENTER) return opcion;
        else if (k == KEY_ESC) return 2;
    }
}

/* ==================== PANEL SYSINFO (ESTILO NEOFETCH) ==================== */
static void cmd_sysinfo(void) {
    kclear();

    /* Logo compacto a la izquierda (filas 3..13) */
    vga_texto_en(11, 3,  COLOR_MORADO,  "..");
    vga_texto_en(10, 4,  COLOR_MORADO,  ":##:");
    vga_texto_en(9,  5,  COLOR_MORADO,  ":####:");
    vga_texto_en(8,  6,  COLOR_MORADO,  ":######:");
    vga_texto_en(7,  7,  COLOR_MORADO,  ":###::###:");
    vga_texto_en(6,  8,  COLOR_CELESTE, ":###:++:###:");
    vga_texto_en(5,  9,  COLOR_CELESTE, ":###:++++:###:");
    vga_texto_en(4,  10, COLOR_CELESTE, ":###:++##++:###:");
    vga_texto_en(3,  11, COLOR_CELESTE, ":###:++####++:###:");
    vga_texto_en(2,  12, COLOR_CELESTE, ":###:++++++++++:###:");
    vga_texto_en(1,  13, COLOR_CELESTE, ":###:============:###:");
    vga_texto_en(4,  15, 0x0F,          "TECNOLÓGICO ARGOS");
    vga_texto_en(6,  16, 0x08,          "TIC340 - x86");

    int usados = 0, archs = 0, dirs = 0;
    uint32_t bytes_fs = 0;
    fs_contar_nodos(&usados, &archs, &dirs, &bytes_fs);

    uint32_t up = reloj_uptime_seg();
    uint32_t uh = up / 3600, um = (up % 3600) / 60, us = up % 60;

    /* Columna derecha de informacion en vivo (col 27) */
    const int X = 27;

    cursor_pos(X, 3);
    kset_color(0x0A); kprint(usuarios[usuario_activo].nombre_corto);
    kset_color(0x07); kprint("@");
    kset_color(COLOR_CELESTE); kprint("argos");
    kset_color(0x08); kprint("  (ARGOS OS v8.3)");

    cursor_pos(X, 4);
    kset_color(COLOR_MORADO);
    kprint("------------------------------------------------");

    cursor_pos(X, 5);
    kset_color(COLOR_CELESTE); kprint("Usuario    : ");
    kset_color(0x0F); kprint(usuarios[usuario_activo].nombre_completo);
    kset_color(0x08); kprint(" ("); kprint(usuarios[usuario_activo].desc_permisos); kprint(")");

    cursor_pos(X, 6);
    kset_color(COLOR_CELESTE); kprint("CPU / Modo : ");
    kset_color(0x07); kprint("x86 32-bit Protegido (GDT 6 + IDT 48)");

    cursor_pos(X, 7);
    kset_color(COLOR_CELESTE); kprint("Memoria    : ");
    kset_color(0x0F); kprint_dec(mem_ram_mb()); kprint(" MB RAM");
    kset_color(0x07); kprint(" | Kernel: "); kprint_dec(mem_kernel_kb()); kprint(" KB");

    cursor_pos(X, 8);
    kset_color(COLOR_CELESTE); kprint("Paginación : ");
    if (mem_paginacion_activa()) { kset_color(0x0A); kprint("ACTIVA (CR0.PG=1)"); }
    else { kset_color(0x0C); kprint("INACTIVA"); }
    kset_color(0x07); kprint(" | #PF: ");
    kset_color(0x0E); kprint_dec(mem_pf_total());

    cursor_pos(X, 9);
    kset_color(COLOR_CELESTE); kprint("Timer PIT  : ");
    kset_color(0x07); kprint("100 Hz (IRQ0) | Tics: ");
    kset_color(0x0A); kprint_dec(reloj_ticks());

    cursor_pos(X, 10);
    kset_color(COLOR_CELESTE); kprint("Encendido  : ");
    kset_color(0x0F);
    if (uh < 10) kputc('0');
    kprint_dec(uh); kputc(':');
    if (um < 10) kputc('0');
    kprint_dec(um); kputc(':');
    if (us < 10) kputc('0');
    kprint_dec(us);
    kset_color(0x07); kprint(" | Procesos activos: ");
    kset_color(0x0F); kprint_dec(proc_activos());

    cursor_pos(X, 11);
    kset_color(COLOR_CELESTE); kprint("TIC340FS   : ");
    kset_color(0x0F); kprint_dec((uint32_t)usados); kprint("/128 nodos (4KB/arch)");
    kset_color(0x07); kprint(" ("); kprint_dec((uint32_t)archs); kprint(" arch, ");
    kprint_dec((uint32_t)dirs); kprint(" dir, "); kprint_dec(bytes_fs); kprint(" B)");

    cursor_pos(X, 12);
    kset_color(COLOR_CELESTE); kprint("Disco ATA  : ");
    if (fs_estado_disco() == -2) {
        kset_color(0x0C); kprint("No detectado (solo RAM)");
    } else if (fs_hay_cambios()) {
        kset_color(0x0E); kprint("Conectado (cambios sin guardar)");
    } else {
        kset_color(0x0A); kprint("Conectado y sincronizado");
    }

    cursor_pos(X, 13);
    kset_color(COLOR_CELESTE); kprint("Red / NIC  : ");
    if (net_tiene_ip()) {
        kset_color(0x0A); kprint("Intel e1000 | IP ");
        kset_color(0x0F); net_imprimir_ip(net_mi_ip());
    } else if (net_listo()) {
        kset_color(0x0E); kprint("Intel e1000 (sin IP, usa 'net dhcp')");
    } else {
        kset_color(0x0C); kprint("No detectada (usa Intel PRO/1000)");
    }

    cursor_pos(X, 14);
    kset_color(COLOR_CELESTE); kprint("Teclado    : ");
    kset_color(0x07); kprint(teclado_layout_nombre());
    kprint(" | Tema: "); kprint(kernel_tema_nombre());

    /* Barra de paleta de colores VGA (fila 16) */
    static const uint8_t pal[8] = { 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x0B };
    for (int i = 0; i < 8; i++) {
        int px = X + i * 4;
        uint8_t col = (i < 7) ? pal[i] : 0x3F;
        vga[16 * COLS + px]     = (uint16_t)((col << 8) | ' ');
        vga[16 * COLS + px + 1] = (uint16_t)((col << 8) | ' ');
        vga[16 * COLS + px + 2] = (uint16_t)((col << 8) | ' ');
    }

    kset_color(0x07);
    cursor_pos(0, 18);
}

void kernel_mostrar_sysinfo(void) {
    cmd_sysinfo();
}

/* ==================== APAGADO Y REINICIO REALES ==================== */
static void cmd_energia(int es_reboot) {
    if (fs_hay_cambios() && usuarios[usuario_activo].rol != ROL_INVITADO) {
        int dec = kconfirmar_energia(es_reboot);
        kclear();
        if (dec == 2) {
            kprint(es_reboot ? "Reinicio cancelado.\n" : "Apagado cancelado.\n");
            return;
        }
        if (dec == 0) {
            fs_save();
        }
    }

    audit_registrar(LOG_WARN, kernel_usuario_corto(),
                    es_reboot ? "REBOOT" : "SHUTDOWN",
                    es_reboot ? "Reinicio solicitado" : "Apagado solicitado");

    kclear();
    kprint_logo();
    kset_color(0x0E);
    kprint(es_reboot ? "  Reiniciando ARGOS OS...\n" : "  Apagando ARGOS OS...\n");
    kset_color(0x07);

    __asm__ volatile("cli");

    if (es_reboot) {
        /* 1) Pulso de reset por controlador de teclado PS/2 (0x64 -> 0xFE) */
        for (int t = 0; t < 100000; t++) {
            if (!(inb(0x64) & 0x02)) break;
        }
        outb(0x64, 0xFE);

        /* 2) Respaldo: Fast Reset por puerto 0x92 */
        outb(0x92, (uint8_t)(inb(0x92) | 0x01));

        /* 3) Respaldo final: Triple Fault controlado cargando IDT vacia */
        struct __attribute__((packed)) { uint16_t lim; uint32_t base; } nula = { 0, 0 };
        __asm__ volatile("lidt %0; int $3" : : "m"(nula));
    } else {
        /* 1) Apagado ACPI directo en VirtualBox */
        outw(0x4004, 0x3400);
        /* 2) Apagado ACPI en QEMU >= 2.0 */
        outw(0x0604, 0x2000);
        /* 3) Apagado ACPI en Bochs / QEMU antiguo */
        outw(0xB004, 0x2000);

        kset_color(0x0A);
        kprint("\n  Sistema detenido de forma segura.\n");
        kset_color(0x07);
        kprint("  Ya puedes cerrar la ventana de la máquina virtual.\n");
    }

    for (;;) __asm__ volatile("hlt");
}

static int igual(const char *a, const char *b) {
    while (*a && *a == *b) { a++; b++; }
    return *a == *b;
}

static int prefijo_de(const char *str, const char *pre) {
    while (*pre) {
        if (*str++ != *pre++) return 0;
    }
    return 1;
}

void kernel_imprimir_prompt(void) {
    kset_color(0x0A);
    kprint(usuarios[usuario_activo].nombre_corto);
    kset_color(0x07);
    kprint("@");
    kset_color(COLOR_CELESTE);
    kprint("argos");
    kset_color(0x07);
    kprint(":");
    kset_color(0x0D);
    fs_pwd();
    kset_color(0x07);
    kprint("> ");
}

/* ==================== AUTOCOMPLETADO CON TAB ==================== */
static const char * const lista_comandos[] = {
    "2048", "agenda", "ahorcado", "apagar", "apps", "archivos", "ayuda",
    "buscar", "calc", "calculadora", "calendario", "cat", "cd", "chmod",
    "clear", "clip", "cp", "cronometro", "culebrita", "date", "df", "dns",
    "edit", "find", "guardar", "help", "hora", "http", "inicio", "juegos",
    "kbd", "limpiar", "log", "logo", "logout", "ls", "mem", "menu", "mkdir",
    "mv", "net", "ping", "pomodoro", "proc", "ps", "pwd", "reboot",
    "reiniciar", "rma", "rme", "save", "sched", "scholar", "shutdown",
    "snake", "stat", "sysinfo", "tareas", "teclado", "tema", "timer",
    "touch", "tree", "uptime", "whoami", "write"
};
#define NUM_COMANDOS ((int)(sizeof(lista_comandos) / sizeof(lista_comandos[0])))

int shell_autocompletar(char *destino, int *len, int *cur, int max_len) {
    const char *cands[64];
    int n_cands = 0;

    int ini = 0;
    while (ini < *len && destino[ini] == ' ') ini++;

    int ult_esp = -1;
    for (int i = ini; i < *len; i++) {
        if (destino[i] == ' ') ult_esp = i;
    }

    const char *token = (ult_esp == -1) ? (destino + ini) : (destino + ult_esp + 1);
    int tok_len = *len - (int)(token - destino);

    if (ult_esp == -1) {
        for (int i = 0; i < NUM_COMANDOS && n_cands < 64; i++) {
            if (prefijo_de(lista_comandos[i], token)) {
                cands[n_cands++] = lista_comandos[i];
            }
        }
    } else {
        char cmd_base[24];
        int cl = 0;
        for (int i = ini; i < *len && destino[i] != ' ' && cl < 23; i++) {
            cmd_base[cl++] = destino[i];
        }
        cmd_base[cl] = '\0';

        int arg_num = 0;
        int en_pal = 0;
        for (int i = ini; i < ult_esp + 1; i++) {
            if (destino[i] != ' ') {
                if (!en_pal) { arg_num++; en_pal = 1; }
            } else {
                en_pal = 0;
            }
        }

        if (arg_num == 1 && igual(cmd_base, "mem")) {
            static const char * const sub[2] = { "seg", "pag" };
            for (int i = 0; i < 2; i++)
                if (prefijo_de(sub[i], token)) cands[n_cands++] = sub[i];
        } else if (arg_num == 1 && igual(cmd_base, "proc")) {
            if (prefijo_de("demo", token)) cands[n_cands++] = "demo";
        } else if (arg_num == 1 && igual(cmd_base, "ps")) {
            if (prefijo_de("pcb", token)) cands[n_cands++] = "pcb";
        } else if (arg_num == 1 && igual(cmd_base, "date")) {
            if (prefijo_de("tz", token)) cands[n_cands++] = "tz";
        } else if (arg_num == 1 && igual(cmd_base, "log")) {
            static const char * const sub[2] = { "all", "clear" };
            for (int i = 0; i < 2; i++)
                if (prefijo_de(sub[i], token)) cands[n_cands++] = sub[i];
        } else if (arg_num == 1 && igual(cmd_base, "net")) {
            static const char * const sub[3] = { "info", "dhcp", "arp" };
            for (int i = 0; i < 3; i++)
                if (prefijo_de(sub[i], token)) cands[n_cands++] = sub[i];
        } else if (arg_num == 1 && igual(cmd_base, "kbd")) {
            static const char * const sub[3] = { "latam", "es", "us" };
            for (int i = 0; i < 3; i++)
                if (prefijo_de(sub[i], token)) cands[n_cands++] = sub[i];
        } else if (arg_num == 1 && igual(cmd_base, "scholar")) {
            static const char * const sub[2] = { "status", "gw" };
            for (int i = 0; i < 2; i++)
                if (prefijo_de(sub[i], token)) cands[n_cands++] = sub[i];
        } else if (arg_num == 1 && igual(cmd_base, "tema")) {
            static const char * const sub[3] = { "argos", "claro", "retro" };
            for (int i = 0; i < 3; i++)
                if (prefijo_de(sub[i], token)) cands[n_cands++] = sub[i];
        } else {
            int solo_dirs = igual(cmd_base, "cd") || igual(cmd_base, "rme");
            int solo_archs = igual(cmd_base, "cat") || igual(cmd_base, "edit") ||
                             igual(cmd_base, "rma") || igual(cmd_base, "clip") ||
                             (arg_num == 1 && (igual(cmd_base, "write") || igual(cmd_base, "cp")));
            n_cands = fs_listar_candidatos(token, solo_dirs, solo_archs, cands, 64);
        }
    }

    if (n_cands == 0) return 0;

    int lcp = 0;
    while (cands[0][lcp]) {
        char ch = cands[0][lcp];
        int todos = 1;
        for (int i = 1; i < n_cands; i++) {
            if (cands[i][lcp] != ch) { todos = 0; break; }
        }
        if (!todos) break;
        lcp++;
    }

    if (lcp > tok_len) {
        for (int i = tok_len; i < lcp && *len < max_len - 1; i++) {
            destino[(*len)++] = cands[0][i];
        }
        destino[*len] = '\0';
        *cur = *len;
        return 0;
    }

    if (n_cands > 1) {
        kputc('\n');
        kset_color(0x0B);
        int col = 0;
        for (int i = 0; i < n_cands; i++) {
            int l = largo_visible(cands[i]);
            if (col + l + 2 >= COLS) { kputc('\n'); col = 0; }
            kprint("  ");
            kprint(cands[i]);
            col += l + 2;
        }
        kset_color(0x07);
        kputc('\n');
        kernel_imprimir_prompt();
        return 1;
    }
    return 0;
}

static void pantalla_login(void) {
    int sel = 0;
    int pidiendo_clave = 0;
    char clave[32];
    int clen = 0;
    const char *error_msg = "";

    while (1) {
        for (int i = 0; i < COLS * ROWS; i++) vga[i] = (0x07 << 8) | ' ';
        barra_titulo("ARGOS - INICIO DE SESIÓN");

        vga_texto_en(11, 1,  COLOR_MORADO,  "..");
        vga_texto_en(10, 2,  COLOR_MORADO,  ":##:");
        vga_texto_en(9,  3,  COLOR_MORADO,  ":####:           T E C N O L Ó G I C O");
        vga_texto_en(8,  4,  COLOR_MORADO,  ":######:          U N I V E R S I T A R I O");
        vga_texto_en(7,  5,  COLOR_MORADO,  ":###::###:");
        vga_texto_en(6,  6,  COLOR_CELESTE, ":###:++:###:         ###   ####   ####   ###   ####");
        vga_texto_en(5,  7,  COLOR_CELESTE, ":###:++++:###:       #   #  #   # #      #   # #");
        vga_texto_en(4,  8,  COLOR_CELESTE, ":###:++##++:###:      #####  ####  #  ##  #   #  ###");
        vga_texto_en(3,  9,  COLOR_CELESTE, ":###:++####++:###:     #   #  #  #  #   #  #   #     #");
        vga_texto_en(2,  10, COLOR_CELESTE, ":###:++++++++++:###:    #   #  #   #  ####   ###  ####");
        vga_texto_en(1,  11, COLOR_CELESTE, ":###:============:###:");

        const int x0 = 11, y0 = 13, ancho = 58, alto = 10;
        vga_dibujar_caja(x0, y0, ancho, alto, 0x1F, 0x1B);
        vga_texto_en(x0 + 17, y0 + 1, 0x1E, "INICIO DE SESIÓN DE USUARIO");

        for (int i = 0; i < 3; i++) {
            int y = y0 + 3 + i;
            uint8_t col = (i == sel) ? 0x30 : 0x1F;
            for (int x = x0 + 2; x < x0 + ancho - 2; x++) {
                vga[y * COLS + x] = (uint16_t)((col << 8) | ' ');
            }
            vga_texto_en(x0 + 3, y, col, (i == sel) ? "> " : "  ");
            vga_texto_en(x0 + 5, y, col, usuarios[i].nombre_completo);
            vga_texto_en(x0 + 27, y, (i == sel) ? 0x30 : 0x1B, "| ");
            vga_texto_en(x0 + 29, y, (i == sel) ? 0x30 : 0x17, usuarios[i].desc_permisos);
        }

        if (pidiendo_clave) {
            vga_texto_en(x0 + 4, y0 + 7, 0x1F, "Contraseña: ");
            for (int i = 0; i < 20; i++) {
                vga[(y0 + 7) * COLS + x0 + 16 + i] = (0x0F << 8) | ' ';
            }
            for (int i = 0; i < clen && i < 20; i++) {
                vga[(y0 + 7) * COLS + x0 + 16 + i] = (0x0F << 8) | '*';
            }
            cursor_pos(x0 + 16 + clen, y0 + 7);
        } else {
            vga_texto_en(x0 + 4, y0 + 7, 0x17, "Flechas Arr/Abj para elegir usuario y pulsa Enter.");
            cursor_pos(x0 + 3, y0 + 3 + sel);
        }

        if (error_msg[0]) {
            vga_texto_en(x0 + 4, y0 + 8, 0x1C, error_msg);
        }

        vga_texto_en(8, 24, 0x08, "Flechas Arr/Abj: elegir | Enter: ingresar | ESC: cancelar clave");

        int k = teclado_getkey();
        if (!pidiendo_clave) {
            error_msg = "";
            if (k == KEY_UP) {
                sel = (sel + 2) % 3;
            } else if (k == KEY_DOWN) {
                sel = (sel + 1) % 3;
            } else if (k == KEY_ENTER) {
                if (usuarios[sel].clave[0] == '\0') {
                    usuario_activo = sel;
                    fs_set_rol(usuarios[sel].rol);
                    audit_registrar(LOG_OK, usuarios[sel].nombre_corto, "LOGIN", "Inicio de sesion (sin clave)");
                    return;
                } else {
                    pidiendo_clave = 1;
                    clen = 0;
                    clave[0] = '\0';
                }
            }
        } else {
            if (k == KEY_ESC) {
                pidiendo_clave = 0;
                clen = 0;
                clave[0] = '\0';
                error_msg = "";
            } else if (k == KEY_ENTER) {
                clave[clen] = '\0';
                if (igual(clave, usuarios[sel].clave)) {
                    usuario_activo = sel;
                    fs_set_rol(usuarios[sel].rol);
                    audit_registrar(LOG_OK, usuarios[sel].nombre_corto, "LOGIN", "Inicio de sesion exitoso");
                    return;
                } else {
                    audit_registrar(LOG_ALERT, usuarios[sel].nombre_corto, "LOGIN_FAIL", "Contrasena incorrecta");
                    error_msg = "Contraseña incorrecta. Intenta de nuevo.";
                    clen = 0;
                    clave[0] = '\0';
                }
            } else if (k == KEY_BS) {
                if (clen > 0) {
                    clen--;
                    clave[clen] = '\0';
                }
            } else if (k >= 32 && k < 0x100 && clen < 20) {
                clave[clen++] = (char)k;
                clave[clen] = '\0';
                error_msg = "";
            }
        }
    }
}

static void cmd_clip(const char *arg) {
    while (*arg == ' ') arg++;
    if (arg[0] == '\0') {
        int n = clip_largo();
        if (n == 0) {
            kprint("Portapapeles vacío. Usa Ctrl+C en la consola/editor o 'clip <archivo>'.\n");
            return;
        }
        kset_color(0x0B); kprint("Portapapeles ("); kprint_dec((uint32_t)n); kprint(" bytes):\n");
        kset_color(0x07);
        kprint(clip_obtener());
        kprint("\n");
        return;
    }
    if (igual(arg, "clear")) {
        clip_limpiar();
        kprint("Portapapeles vaciado.\n");
        return;
    }
    fs_copiar_a_clip(arg);
}

static void ayuda_linea(const char *cmd, const char *desc) {
    kprint("  ");
    kset_color(COLOR_CELESTE);
    kprint_pad(cmd, 19);
    kset_color(0x07);
    kprint(": ");
    kprint(desc);
    kprint("\n");
}

static void mostrar_ayuda(void) {
    kprint("Lista de comandos del sistema:\n");
    ayuda_linea("mkdir / cd / pwd", "Crea carpetas, navega rutas o muestra ruta actual");
    ayuda_linea("ls [ruta] / tree", "Lista archivos y árbol de directorios con permisos");
    ayuda_linea("touch / write / cat", "Crea archivo, escribe texto o muestra su contenido");
    ayuda_linea("edit <archivo>", "Editor con contador de bytes y aviso de guardado");
    ayuda_linea("cp / mv <or> <dst>", "Copia archivos (cp) o renombra/mueve (mv)");
    ayuda_linea("find / stat / df", "Busca texto, ficha de inodo (stat) o espacio (df)");
    ayuda_linea("chmod <modo> <nom>", "Cambia permisos (solo Administrador)");
    ayuda_linea("rma / rme <nombre>", "Elimina archivo (rma) o directorio vacío (rme)");
    ayuda_linea("save", "Guarda el sistema de archivos en el disco ATA");
    ayuda_linea("date [tz] / uptime", "Reloj real CMOS/RTC y tics del timer PIT (IRQ0)");
    ayuda_linea("ps / proc demo", "Tabla PCB (ps [pcb <id>]) y cambio de contexto real");
    ayuda_linea("sched [q] [ll,r..]", "Diagrama de Gantt y métricas FCFS, SJF y RR");
    ayuda_linea("mem / seg / pag", "Memoria: mem | mem seg | mem pag <m> <refs>");
    ayuda_linea("net [dhcp | arp]", "Estado de red e1000, DHCP y caché ARP");
    ayuda_linea("ping / dns / http", "ICMP, DNS y peticiones TCP/HTTP reales");
    ayuda_linea("scholar <tema>", "Buscador Google Académico + guardar cita APA");
    ayuda_linea("kbd / tema / clip", "Teclado, tema visual (argos/claro/retro) y clip");
    ayuda_linea("sysinfo / log", "Resumen del sistema y auditoría (solo admin)");
    ayuda_linea("calc / agenda / timer", "Calculadora, calendario con tareas y Pomodoro");
    ayuda_linea("juegos / snake / 2048", "Juegos: Snake, 2048 y Ahorcado (ahorcado)");
    ayuda_linea("menu / archivos", "Menú Fácil, Explorador visual o apps");
    ayuda_linea("logout / apagar", "Cerrar sesión, reiniciar o apagar de forma segura");
    kset_color(0x08);
    kprint("  Alias español: ayuda, buscar, guardar, hora, teclado, limpiar, reiniciar.\n");
    kset_color(0x07);
}

static void mostrar_bienvenida(int estado_fs) {
    kclear();
    kprint_logo();
    if (estado_fs == 0) {
        kprint("Sistema de archivos TIC340FS cargado desde el disco ATA.\n");
    } else if (estado_fs == -2) {
        kprint("No se detectó disco ATA (IDE primario maestro): archivos solo en RAM.\n");
    } else {
        kprint("Disco sin formato previo. Usa 'save' para guardar en disco.\n");
    }
    if (net_tiene_ip()) {
        kprint("Red activa (Intel e1000): IP ");
        kset_color(0x0A); net_imprimir_ip(net_mi_ip()); kset_color(0x07);
        kprint("\n");
    }
    kprint("Sesión iniciada como: ");
    kset_color(0x0E);
    kprint(usuarios[usuario_activo].nombre_completo);
    kset_color(0x07);
    kprint(" (");
    kprint(usuarios[usuario_activo].desc_permisos);
    kprint(")\n");
    kprint("Consola lista. Escribe ");
    kset_color(COLOR_CELESTE);
    kprint("menu");
    kset_color(0x07);
    kprint(" para volver al Menú Fácil o ");
    kset_color(COLOR_CELESTE);
    kprint("ayuda");
    kset_color(0x07);
    kprint(" para comandos.\n\n");
}

static int requiere_arg(const char *arg, const char *uso) {
    if (*arg) return 1;
    kprint("Uso: ");
    kprint(uso);
    kprint("\n");
    return 0;
}

static int dividir_dos_args(char *arg, char **a1, char **a2) {
    if (!*arg) return 0;
    char *esp = arg;
    while (*esp && *esp != ' ') esp++;
    if (*esp != ' ') return 0;
    *esp = '\0';
    char *resto = esp + 1;
    while (*resto == ' ') resto++;
    if (!*resto) return 0;
    *a1 = arg;
    *a2 = resto;
    return 1;
}

static void cmd_tema(const char *arg) {
    while (*arg == ' ') arg++;
    if (!*arg) {
        kprint("Tema actual: "); kprint(kernel_tema_nombre()); kprint("\n");
        kprint("Uso: tema <argos | claro | retro>\n");
        return;
    }
    if (igual(arg, "argos")) kernel_set_tema(0);
    else if (igual(arg, "claro")) kernel_set_tema(1);
    else if (igual(arg, "retro")) kernel_set_tema(2);
    else { kprint("Uso: tema <argos | claro | retro>\n"); return; }
    kernel_guardar_prefs();
    barra_titulo("ARGOS - SISTEMA OPERATIVO");
    kprint("Tema actualizado y guardado: "); kprint(kernel_tema_nombre()); kprint("\n");
}

static void ejecutar_menu_interactivo(void) {
    while (1) {
        int acc = ui_menu_principal();
        if (acc == 0) {
            mostrar_bienvenida(fs_estado_disco());
            return;
        } else if (acc == 1) {
            audit_registrar(LOG_INFO, usuarios[usuario_activo].nombre_corto, "LOGOUT", "Sesion cerrada");
            fs_reset_dir();
            teclado_hist_clear();
            pantalla_login();
        } else if (acc == 2) {
            cmd_energia(1);
        } else if (acc == 3) {
            cmd_energia(0);
        }
    }
}

void kernel_main(uint32_t magic, uint32_t mbi_dir) {
    uint32_t ram_kb = 0;
    if (magic == 0x2BADB002u) {
        const uint32_t *mbi = (const uint32_t *)mbi_dir;
        if (mbi[0] & 1) ram_kb = mbi[2] + 1024;
    }
    vga_fuente_tildes();
    cursor_init();
    gdt_init();
    idt_init();
    paginacion_init(ram_kb);
    reloj_init();
    proc_init();
    audit_init();

    int estado_fs = fs_init();
    if (fs_tiene_prefs_guardadas()) {
        uint8_t pk = 0, pt = 0; int8_t ptz = 0;
        fs_obtener_prefs(&pk, &ptz, &pt);
        teclado_set_layout((int)pk);
        reloj_set_tz((int)ptz);
        kernel_set_tema((int)pt);
    }
    kclear();
    kprint("Iniciando hardware de red (PCI + Intel e1000 + DHCP)...\n");
    net_init();
    scholar_init();
    audit_registrar(LOG_INFO, "sistema", "ARRANQUE",
                    estado_fs == 0 ? "Kernel listo + TIC340FS ATA" : "Kernel listo (FS en RAM)");

    pantalla_login();
    ejecutar_menu_interactivo();

    char linea[128];
    while (1) {
        kernel_imprimir_prompt();
        teclado_readline(linea, 128);

        char *cmd = linea;
        while (*cmd == ' ') cmd++;
        char *arg = cmd;
        while (*arg && *arg != ' ') arg++;
        if (*arg) { *arg++ = '\0'; while (*arg == ' ') arg++; }
        char *fin = arg;
        while (*fin) fin++;
        while (fin > arg && fin[-1] == ' ') *--fin = '\0';

        if (cmd[0] == '\0') continue;
        else if (igual(cmd, "mkdir")) { if (requiere_arg(arg, "mkdir <dir>")) fs_mkdir(arg); }
        else if (igual(cmd, "cd")) fs_cd(*arg ? arg : "/");
        else if (igual(cmd, "pwd")) { fs_pwd(); kprint("\n"); }
        else if (igual(cmd, "touch")) { if (requiere_arg(arg, "touch <archivo>")) fs_touch(arg); }
        else if (igual(cmd, "cat")) { if (requiere_arg(arg, "cat <archivo>")) fs_cat(arg); }
        else if (igual(cmd, "edit")) { if (requiere_arg(arg, "edit <archivo>")) fs_edit(arg); }
        else if (igual(cmd, "stat")) { fs_stat(*arg ? arg : "."); }
        else if (igual(cmd, "df")) fs_df();
        else if (igual(cmd, "find")) { if (requiere_arg(arg, "find <texto>")) fs_find(arg); }
        else if (igual(cmd, "cp")) {
            char *a1, *a2;
            if (dividir_dos_args(arg, &a1, &a2)) fs_cp(a1, a2);
            else kprint("Uso: cp <archivo_origen> <destino | directorio>\n");
        }
        else if (igual(cmd, "mv")) {
            char *a1, *a2;
            if (dividir_dos_args(arg, &a1, &a2)) fs_mv(a1, a2);
            else kprint("Uso: mv <origen> <nuevo_nombre | directorio>\n");
        }
        else if (igual(cmd, "rma")) { if (requiere_arg(arg, "rma <archivo>")) fs_rma(arg); }
        else if (igual(cmd, "rme")) { if (requiere_arg(arg, "rme <directorio>")) fs_rme(arg); }
        else if (igual(cmd, "rm")) {
            kprint("Usa 'rma <archivo>' para eliminar archivos o 'rme <directorio>' para directorios.\n");
        }
        else if (igual(cmd, "chmod") || igual(cmd, "write")) {
            int es_chmod = igual(cmd, "chmod");
            char *a1, *a2;
            if (dividir_dos_args(arg, &a1, &a2)) {
                if (es_chmod) fs_chmod(a1, a2);
                else fs_write(a1, a2);
            } else {
                kprint(es_chmod ? "Uso: chmod <modo> <archivo/dir> (ej: chmod 644 nota.txt)\n"
                                : "Uso: write <archivo> <texto>\n");
            }
        }
        else if (igual(cmd, "ls")) fs_ls(arg);
        else if (igual(cmd, "tree")) fs_tree(-1, 0);
        else if (igual(cmd, "menu") || igual(cmd, "inicio")) ejecutar_menu_interactivo();
        else if (igual(cmd, "archivos")) { ui_explorador_archivos(); kclear(); }
        else if (igual(cmd, "apps")) { apps_menu(); kclear(); }
        else if (igual(cmd, "calc") || igual(cmd, "calculadora")) apps_cmd_calc(arg);
        else if (igual(cmd, "agenda") || igual(cmd, "calendario") || igual(cmd, "tareas")) { apps_agenda(); kclear(); }
        else if (igual(cmd, "timer") || igual(cmd, "pomodoro") || igual(cmd, "cronometro")) { apps_timer(); kclear(); }
        else if (igual(cmd, "juegos")) { juegos_menu(); kclear(); }
        else if (igual(cmd, "snake") || igual(cmd, "culebrita")) { juegos_snake(); kclear(); }
        else if (igual(cmd, "2048")) { juegos_2048(); kclear(); }
        else if (igual(cmd, "ahorcado")) { juegos_ahorcado(); kclear(); }
        else if (igual(cmd, "save") || igual(cmd, "guardar")) fs_save();
        else if (igual(cmd, "date") || igual(cmd, "hora")) reloj_cmd_date(arg);
        else if (igual(cmd, "uptime")) reloj_cmd_uptime();
        else if (igual(cmd, "ps")) proc_cmd_ps(arg);
        else if (igual(cmd, "proc")) {
            if (igual(arg, "demo")) proc_cmd_demo();
            else kprint("Uso: proc demo\n");
        }
        else if (igual(cmd, "sched")) proc_cmd_sched(arg);
        else if (igual(cmd, "net")) net_cmd_net(arg);
        else if (igual(cmd, "ping")) net_cmd_ping(arg);
        else if (igual(cmd, "dns")) net_cmd_dns(arg);
        else if (igual(cmd, "http")) net_cmd_http(arg);
        else if (igual(cmd, "scholar") || igual(cmd, "buscar")) scholar_cmd(arg);
        else if (igual(cmd, "kbd") || igual(cmd, "teclado")) teclado_cmd_kbd(arg);
        else if (igual(cmd, "tema")) cmd_tema(arg);
        else if (igual(cmd, "clip")) cmd_clip(arg);
        else if (igual(cmd, "sysinfo")) cmd_sysinfo();
        else if (igual(cmd, "log")) audit_cmd_log(arg, usuarios[usuario_activo].rol);
        else if (igual(cmd, "reboot") || igual(cmd, "reiniciar")) cmd_energia(1);
        else if (igual(cmd, "shutdown") || igual(cmd, "apagar")) cmd_energia(0);
        else if (igual(cmd, "logo")) { kclear(); kprint_logo(); }
        else if (igual(cmd, "mem")) mem_comando(arg);
        else if (igual(cmd, "clear") || igual(cmd, "limpiar")) kclear();
        else if (igual(cmd, "help") || igual(cmd, "ayuda")) mostrar_ayuda();
        else if (igual(cmd, "whoami")) {
            kprint("Usuario: ");
            kprint(usuarios[usuario_activo].nombre_completo);
            kprint(" (");
            kprint(usuarios[usuario_activo].nombre_corto);
            kprint(") | Permisos: ");
            kprint(usuarios[usuario_activo].desc_permisos);
            kprint("\n");
        }
        else if (igual(cmd, "logout") || igual(cmd, "salir")) {
            audit_registrar(LOG_INFO, usuarios[usuario_activo].nombre_corto, "LOGOUT", "Sesion cerrada");
            fs_reset_dir();
            teclado_hist_clear();
            pantalla_login();
            ejecutar_menu_interactivo();
        }
        else kprint("Comando no reconocido. Escribe 'help' para ver la ayuda.\n");
    }
}
