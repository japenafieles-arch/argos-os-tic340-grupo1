/*
 * Modulo 8 (Bloque 3): Entretenimiento Liviano en Modo Texto VGA (80x25)
 *  1. Snake (La Culebrita): tiempo real con PIT 100 Hz (IRQ0) + teclado no bloqueante,
 *     3 velocidades, fruta bonus y record persistente en /records.txt.
 *  2. 2048: rompecabezas numerico 4x4 a color con flechas/WASD y mejor puntaje.
 *  3. Ahorcado: palabras de Informatica/TIC340 y Cultura General/Ecuador con pistas,
 *     dibujo por etapas y mejor racha persistente.
 */
#include <stdint.h>
#include "juegos.h"
#include "fs.h"
#include "teclado.h"
#include "reloj.h"
#include "audit.h"

#define COLS 80

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

/* ==================== UTILIDADES Y PRNG ==================== */
static uint32_t rng_state = 0xA9051337u;
static uint32_t rec_snake = 0;
static uint32_t rec_2048  = 0;
static uint32_t rec_ahorc = 0;
static int      recs_cargados = 0;
static char     rec_buf[256];

static int j_slen(const char *s) { int n = 0; while (s[n]) n++; return n; }

static void j_scpy(char *d, const char *s, int max) {
    int i = 0;
    while (i < max - 1 && s && s[i]) { d[i] = s[i]; i++; }
    d[i] = '\0';
}

static void j_u32_str(uint32_t v, char *out) {
    char tmp[12];
    int n = 0;
    do { tmp[n++] = (char)('0' + (v % 10u)); v /= 10u; } while (v);
    for (int i = 0; i < n; i++) out[i] = tmp[n - 1 - i];
    out[n] = '\0';
}

static uint32_t j_rand(void) {
    rng_state ^= (reloj_ticks() * 2654435761u);
    rng_state = rng_state * 1664525u + 1013904223u;
    return (rng_state >> 8) & 0x00FFFFFFu;
}

static void j_barra_inf(const char *texto, int es_aviso) {
    uint8_t bg = kcol_barra();
    uint8_t fg = es_aviso ? (uint8_t)((bg & 0xF0) | 0x0E) : bg;
    if (kernel_get_tema() == 2 && es_aviso) fg = 0x2F;
    char vacio[81];
    for (int i = 0; i < COLS; i++) vacio[i] = ' ';
    vacio[COLS] = '\0';
    kvga_texto_en(0, 24, bg, vacio);
    kvga_texto_en(1, 24, fg, texto);
}

static int j_empieza(const char *s, const char *pre) {
    while (*pre) { if (*s++ != *pre++) return 0; }
    return 1;
}

static uint32_t j_parse_u32(const char *s, int len) {
    uint32_t v = 0;
    for (int i = 0; i < len && s[i] >= '0' && s[i] <= '9'; i++) {
        v = v * 10u + (uint32_t)(s[i] - '0');
    }
    return v;
}

/* ==================== PERSISTENCIA DE RECORDS (/records.txt) ==================== */
static void records_cargar(void) {
    if (recs_cargados) return;
    recs_cargados = 1;
    int n = fs_leer_raiz_archivo("records.txt", rec_buf, sizeof(rec_buf));
    if (n <= 0) return;

    int i = 0;
    while (i < n) {
        int j = i;
        while (j < n && rec_buf[j] != '\n') j++;
        int llen = j - i;
        if (llen > 0 && rec_buf[i + llen - 1] == '\r') llen--;
        const char *ln = rec_buf + i;
        if (llen > 6 && j_empieza(ln, "SNAKE="))         rec_snake = j_parse_u32(ln + 6, llen - 6);
        else if (llen > 6 && j_empieza(ln, "G2048="))    rec_2048  = j_parse_u32(ln + 6, llen - 6);
        else if (llen > 9 && j_empieza(ln, "AHORCADO=")) rec_ahorc = j_parse_u32(ln + 9, llen - 9);
        i = j + 1;
    }
}

static void records_guardar_ram(void) {
    if (fs_get_rol() == ROL_INVITADO) return;
    int p = 0;
    char num[12];
    const char *k1 = "SNAKE=";
    const char *k2 = "\nG2048=";
    const char *k3 = "\nAHORCADO=";

    for (int i = 0; k1[i]; i++) rec_buf[p++] = k1[i];
    j_u32_str(rec_snake, num);
    for (int i = 0; num[i]; i++) rec_buf[p++] = num[i];

    for (int i = 0; k2[i]; i++) rec_buf[p++] = k2[i];
    j_u32_str(rec_2048, num);
    for (int i = 0; num[i]; i++) rec_buf[p++] = num[i];

    for (int i = 0; k3[i]; i++) rec_buf[p++] = k3[i];
    j_u32_str(rec_ahorc, num);
    for (int i = 0; num[i]; i++) rec_buf[p++] = num[i];

    rec_buf[p++] = '\n';
    rec_buf[p] = '\0';

    const char *err = 0;
    fs_guardar_raiz_archivo("records.txt", rec_buf, &err);
}

/* ==================== 1. SNAKE (LA CULEBRITA) ==================== */
#define SN_W     46
#define SN_H     18
#define SN_X0    3
#define SN_Y0    3
#define SN_MAX   (SN_W * SN_H)

static int8_t sn_x[SN_MAX];
static int8_t sn_y[SN_MAX];

static int sn_ocupa(int x, int y, int len) {
    for (int i = 0; i < len; i++) {
        if (sn_x[i] == x && sn_y[i] == y) return 1;
    }
    return 0;
}

static void sn_poner_comida(int *fx, int *fy, int len, int bx, int by) {
    for (int t = 0; t < 200; t++) {
        int rx = (int)(j_rand() % SN_W);
        int ry = (int)(j_rand() % SN_H);
        if (!sn_ocupa(rx, ry, len) && !(rx == bx && ry == by)) {
            *fx = rx; *fy = ry;
            return;
        }
    }
    for (int y = 0; y < SN_H; y++) {
        for (int x = 0; x < SN_W; x++) {
            if (!sn_ocupa(x, y, len) && !(x == bx && y == by)) {
                *fx = x; *fy = y;
                return;
            }
        }
    }
}

void juegos_snake(void) {
    records_cargar();
    int vel = 1; /* 0=Lento, 1=Normal, 2=Rapido */
    static const uint32_t vel_tics[3] = { 16u, 10u, 6u };
    static const char * const vel_nom[3] = { "Lento ", "Normal", "Rápido" };

    while (1) {
        int len = 4;
        for (int i = 0; i < len; i++) {
            sn_x[i] = (int8_t)(SN_W / 2 - i);
            sn_y[i] = (int8_t)(SN_H / 2);
        }
        int dx = 1, dy = 0;
        int ndx = 1, ndy = 0;
        int fx = 0, fy = 0;
        int bx = -1, by = -1, b_ttl = 0;
        int comidas = 0;
        uint32_t pts = 0;
        int pausado = 0;
        int muerto = 0;
        int nuevo_rec = 0;
        sn_poner_comida(&fx, &fy, len, -1, -1);

        uint32_t ult_paso = reloj_ticks();
        int redibujar = 1;
        int reiniciar = 0;

        while (1) {
            if (redibujar) {
                redibujar = 0;
                kvga_barra_titulo("ARGOS JUEGOS - SNAKE (LA CULEBRITA)");
                kvga_limpiar_area(1, 23, 0x07);

                /* Tablero de juego (cols 3..50, rows 3..22) */
                kvga_dibujar_caja(SN_X0, SN_Y0, SN_W + 2, SN_H + 2, 0x07, 0x0B);

                /* Comida normal y bonus */
                kvga_texto_en(SN_X0 + 1 + fx, SN_Y0 + 1 + fy, 0x0C, "*");
                if (bx >= 0 && b_ttl > 0) {
                    kvga_texto_en(SN_X0 + 1 + bx, SN_Y0 + 1 + by, 0x0E, "$");
                }

                /* Cuerpo y cabeza */
                for (int i = len - 1; i >= 1; i--) {
                    kvga_texto_en(SN_X0 + 1 + sn_x[i], SN_Y0 + 1 + sn_y[i], 0x0A, "o");
                }
                kvga_texto_en(SN_X0 + 1 + sn_x[0], SN_Y0 + 1 + sn_y[0], muerto ? 0x0C : 0x0E, "@");

                /* Panel lateral derecho (cols 53..77) */
                kvga_dibujar_caja(53, 3, 25, 20, kcol_caja(), kcol_borde());
                kvga_texto_en(58, 4, kcol_caja_tit(), "ESTADÍSTICAS");

                char sbuf[14];
                j_u32_str(pts, sbuf);
                kvga_texto_en(55, 6, kcol_caja_ten(), "Puntos  : ");
                kvga_texto_en(65, 6, kcol_caja_tit(), sbuf);

                j_u32_str(rec_snake, sbuf);
                kvga_texto_en(55, 7, kcol_caja_ten(), "Récord  : ");
                kvga_texto_en(65, 7, kcol_caja(), sbuf);

                j_u32_str((uint32_t)len, sbuf);
                kvga_texto_en(55, 8, kcol_caja_ten(), "Largo   : ");
                kvga_texto_en(65, 8, kcol_caja(), sbuf);

                kvga_texto_en(55, 9, kcol_caja_ten(), "Veloc.  : ");
                kvga_texto_en(65, 9, kcol_borde(), vel_nom[vel]);

                kvga_texto_en(55, 11, kcol_caja_tit(), "Frutas:");
                kvga_texto_en(55, 12, kcol_caja(), "* Normal (+10 pts)");
                kvga_texto_en(55, 13, kcol_caja(), "$ Bonus  (+30 pts)");

                kvga_texto_en(55, 15, kcol_caja_tit(), "Controles:");
                kvga_texto_en(55, 16, kcol_caja_ten(), "Flechas / WASD: Mover");
                kvga_texto_en(55, 17, kcol_caja_ten(), "1-3: Velocidad");
                kvga_texto_en(55, 18, kcol_caja_ten(), "P: Pausa | R: Nuevo");
                kvga_texto_en(55, 19, kcol_caja_ten(), "ESC: Salir a Juegos");

                if (pausado && !muerto) {
                    kvga_dibujar_caja(16, 10, 22, 5, kcol_caja(), kcol_borde());
                    kvga_texto_en(23, 12, kcol_caja_tit(), "PAUSADO");
                } else if (muerto) {
                    kvga_dibujar_caja(11, 9, 32, 7, 0x4F, 0x4E);
                    kvga_texto_en(20, 10, 0x4E, "FIN DEL JUEGO");
                    if (nuevo_rec) {
                        kvga_texto_en(15, 12, 0x4F, "¡NUEVO RÉCORD GUARDADO!");
                    } else {
                        kvga_texto_en(16, 12, 0x4F, "Chocaste. ¡Buen intento!");
                    }
                    kvga_texto_en(13, 14, 0x4E, "Enter/R: Jugar | ESC: Salir");
                }

                j_barra_inf("Snake en vivo (PIT 100 Hz) | Come * (+10) y $ (+30) sin chocar bordes ni cola", 0);
                kset_cursor(53, 3);
            }

            int k = teclado_poll_key();
            if (k != 0) {
                rng_state ^= (uint32_t)k * 31337u;
                if (k == KEY_ESC || k == 'q' || k == 'Q') return;
                if (k == 'r' || k == 'R' || (muerto && (k == KEY_ENTER || k == ' '))) {
                    reiniciar = 1;
                    break;
                }
                if (k == '1') { vel = 0; redibujar = 1; }
                else if (k == '2') { vel = 1; redibujar = 1; }
                else if (k == '3') { vel = 2; redibujar = 1; }
                else if (!muerto && (k == 'p' || k == 'P' || k == ' ')) {
                    pausado = !pausado;
                    ult_paso = reloj_ticks();
                    redibujar = 1;
                } else if (!muerto && !pausado) {
                    if ((k == KEY_UP || k == 'w' || k == 'W') && dy != 1)      { ndx = 0; ndy = -1; }
                    else if ((k == KEY_DOWN || k == 's' || k == 'S') && dy != -1)  { ndx = 0; ndy = 1; }
                    else if ((k == KEY_LEFT || k == 'a' || k == 'A') && dx != 1)   { ndx = -1; ndy = 0; }
                    else if ((k == KEY_RIGHT || k == 'd' || k == 'D') && dx != -1) { ndx = 1; ndy = 0; }
                }
            }

            if (!muerto && !pausado) {
                uint32_t paso = vel_tics[vel];
                if (ndy != 0) paso = paso + (paso / 3u) + 1u; /* compensar proporcion vertical 80x25 */
                uint32_t ahora = reloj_ticks();
                if ((ahora - ult_paso) >= paso) {
                    ult_paso = ahora;
                    dx = ndx; dy = ndy;
                    int nx = (int)sn_x[0] + dx;
                    int ny = (int)sn_y[0] + dy;

                    if (nx < 0 || nx >= SN_W || ny < 0 || ny >= SN_H || sn_ocupa(nx, ny, len - 1)) {
                        muerto = 1;
                        if (pts > rec_snake) {
                            rec_snake = pts;
                            nuevo_rec = 1;
                            records_guardar_ram();
                        }
                        redibujar = 1;
                    } else {
                        int come_norm  = (nx == fx && ny == fy);
                        int come_bonus = (bx >= 0 && b_ttl > 0 && nx == bx && ny == by);

                        if ((come_norm || come_bonus) && len < SN_MAX - 1) len++;
                        for (int i = len - 1; i >= 1; i--) {
                            sn_x[i] = sn_x[i - 1];
                            sn_y[i] = sn_y[i - 1];
                        }
                        sn_x[0] = (int8_t)nx;
                        sn_y[0] = (int8_t)ny;

                        if (come_norm) {
                            pts += 10u;
                            comidas++;
                            sn_poner_comida(&fx, &fy, len, bx, by);
                            if ((comidas % 5) == 0 && bx < 0) {
                                sn_poner_comida(&bx, &by, len, fx, fy);
                                b_ttl = 55;
                            }
                        } else if (come_bonus) {
                            pts += 30u;
                            bx = -1; by = -1; b_ttl = 0;
                        }

                        if (b_ttl > 0) {
                            b_ttl--;
                            if (b_ttl == 0) { bx = -1; by = -1; }
                        }

                        if (pts > rec_snake) {
                            rec_snake = pts;
                            nuevo_rec = 1;
                        }
                        redibujar = 1;
                    }
                }
            }

            if (!redibujar) {
                if (reloj_activo()) __asm__ volatile("hlt");
            }
        }
        if (!reiniciar) break;
    }
}

/* ==================== 2. JUEGO 2048 ==================== */
static uint16_t g2_tab[4][4];

static uint8_t g2_color_celda(uint16_t v) {
    /* Solo fondos sin bit 7 (0x00..0x70) para evitar parpadeo en VGA */
    switch (v) {
        case 0:    return 0x08;
        case 2:    return 0x70;
        case 4:    return 0x30;
        case 8:    return 0x20;
        case 16:   return 0x60;
        case 32:   return 0x4F;
        case 64:   return 0x5F;
        case 128:  return 0x1E;
        case 256:  return 0x2F;
        case 512:  return 0x3F;
        case 1024: return 0x6F;
        default:   return 0x4E;
    }
}

static void g2_agregar_ficha(void) {
    int vacias_r[16], vacias_c[16], cnt = 0;
    for (int r = 0; r < 4; r++) {
        for (int c = 0; c < 4; c++) {
            if (g2_tab[r][c] == 0) {
                vacias_r[cnt] = r;
                vacias_c[cnt] = c;
                cnt++;
            }
        }
    }
    if (cnt == 0) return;
    int idx = (int)(j_rand() % (uint32_t)cnt);
    g2_tab[vacias_r[idx]][vacias_c[idx]] = ((j_rand() % 10u) == 0u) ? 4u : 2u;
}

static int g2_colapsar_linea(uint16_t a[4], uint32_t *pts_gan) {
    uint16_t orig[4];
    for (int i = 0; i < 4; i++) orig[i] = a[i];

    uint16_t tmp[4] = { 0, 0, 0, 0 };
    int w = 0;
    for (int i = 0; i < 4; i++) if (a[i] != 0) tmp[w++] = a[i];

    for (int i = 0; i < 3; i++) {
        if (tmp[i] != 0 && tmp[i] == tmp[i + 1]) {
            tmp[i] = (uint16_t)(tmp[i] * 2u);
            *pts_gan += (uint32_t)tmp[i];
            tmp[i + 1] = 0;
            i++;
        }
    }

    for (int i = 0; i < 4; i++) a[i] = 0;
    w = 0;
    for (int i = 0; i < 4; i++) if (tmp[i] != 0) a[w++] = tmp[i];

    for (int i = 0; i < 4; i++) if (a[i] != orig[i]) return 1;
    return 0;
}

/* dir: 0=Izq, 1=Der, 2=Arr, 3=Abj */
static int g2_mover(int dir, uint32_t *pts_gan) {
    int movio = 0;
    uint16_t ln[4];
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            if (dir == 0)      ln[j] = g2_tab[i][j];
            else if (dir == 1) ln[j] = g2_tab[i][3 - j];
            else if (dir == 2) ln[j] = g2_tab[j][i];
            else               ln[j] = g2_tab[3 - j][i];
        }
        if (g2_colapsar_linea(ln, pts_gan)) movio = 1;
        for (int j = 0; j < 4; j++) {
            if (dir == 0)      g2_tab[i][j] = ln[j];
            else if (dir == 1) g2_tab[i][3 - j] = ln[j];
            else if (dir == 2) g2_tab[j][i] = ln[j];
            else               g2_tab[3 - j][i] = ln[j];
        }
    }
    return movio;
}

static int g2_hay_movimientos(void) {
    for (int r = 0; r < 4; r++) {
        for (int c = 0; c < 4; c++) {
            if (g2_tab[r][c] == 0) return 1;
            if (c < 3 && g2_tab[r][c] == g2_tab[r][c + 1]) return 1;
            if (r < 3 && g2_tab[r][c] == g2_tab[r + 1][c]) return 1;
        }
    }
    return 0;
}

void juegos_2048(void) {
    records_cargar();

    while (1) {
        for (int r = 0; r < 4; r++) for (int c = 0; c < 4; c++) g2_tab[r][c] = 0;
        g2_agregar_ficha();
        g2_agregar_ficha();

        uint32_t pts = 0;
        uint32_t movs = 0;
        int gano = 0;
        int sin_mov = 0;
        int nuevo_rec = 0;
        int reiniciar = 0;

        while (1) {
            kvga_barra_titulo("ARGOS JUEGOS - 2048 (ROMPECABEZAS NUMÉRICO)");
            kvga_limpiar_area(1, 23, kcol_fondo());

            /* Marco del tablero 4x4 (cols 8..47, rows 3..21) */
            kvga_dibujar_caja(8, 3, 40, 19, 0x07, kcol_acento());

            uint16_t max_ficha = 0;
            for (int r = 0; r < 4; r++) {
                for (int c = 0; c < 4; c++) {
                    uint16_t val = g2_tab[r][c];
                    if (val > max_ficha) max_ficha = val;
                    uint8_t col = g2_color_celda(val);
                    int tx = 10 + c * 9;
                    int ty = 5 + r * 4;

                    kvga_texto_en(tx, ty,     col, "        ");
                    kvga_texto_en(tx, ty + 1, col, "        ");
                    kvga_texto_en(tx, ty + 2, col, "        ");

                    if (val == 0) {
                        kvga_texto_en(tx + 3, ty + 1, col, ".");
                    } else {
                        char nstr[8];
                        j_u32_str(val, nstr);
                        int pad = (8 - j_slen(nstr)) / 2;
                        kvga_texto_en(tx + pad, ty + 1, col, nstr);
                    }
                }
            }

            /* Panel lateral derecho */
            kvga_dibujar_caja(51, 3, 26, 19, kcol_caja(), kcol_borde());
            kvga_texto_en(57, 4, kcol_caja_tit(), "MARCADOR 2048");

            char sbuf[14];
            j_u32_str(pts, sbuf);
            kvga_texto_en(53, 6, kcol_caja_ten(), "Puntos  : ");
            kvga_texto_en(63, 6, kcol_caja_tit(), sbuf);

            j_u32_str(rec_2048, sbuf);
            kvga_texto_en(53, 7, kcol_caja_ten(), "Récord  : ");
            kvga_texto_en(63, 7, kcol_caja(), sbuf);

            j_u32_str(max_ficha, sbuf);
            kvga_texto_en(53, 8, kcol_caja_ten(), "Máxima  : ");
            kvga_texto_en(63, 8, kcol_borde(), sbuf);

            j_u32_str(movs, sbuf);
            kvga_texto_en(53, 9, kcol_caja_ten(), "Jugadas : ");
            kvga_texto_en(63, 9, kcol_caja(), sbuf);

            kvga_texto_en(53, 11, kcol_caja_tit(), "Objetivo:");
            kvga_texto_en(53, 12, kcol_caja(), "Une fichas iguales");
            kvga_texto_en(53, 13, kcol_caja(), "hasta formar 2048.");

            kvga_texto_en(53, 15, kcol_caja_tit(), "Controles:");
            kvga_texto_en(53, 16, kcol_caja_ten(), "Flechas / WASD: Mover");
            kvga_texto_en(53, 17, kcol_caja_ten(), "R: Nueva partida");
            kvga_texto_en(53, 18, kcol_caja_ten(), "ESC: Volver a Juegos");

            if (gano == 1) {
                kvga_dibujar_caja(13, 9, 30, 6, 0x2F, 0x2E);
                kvga_texto_en(18, 10, 0x2E, "¡FELICIDADES: 2048!");
                kvga_texto_en(15, 12, 0x2F, "Enter: Seguir | R: Nuevo");
            } else if (sin_mov) {
                kvga_dibujar_caja(12, 9, 32, 6, 0x4F, 0x4E);
                kvga_texto_en(17, 10, 0x4E, "SIN MOVIMIENTOS");
                kvga_texto_en(14, 12, 0x4F, nuevo_rec ? "¡Nuevo récord! R: Jugar" : "R/Enter: Nuevo | ESC: Salir");
            }

            j_barra_inf("Flechas / WASD: Deslizar todas las fichas | R: Reiniciar | ESC: Salir", 0);
            kset_cursor(51, 3);

            int k = teclado_getkey();
            rng_state ^= (uint32_t)k * 65521u;
            if (k == KEY_ESC || k == 'q' || k == 'Q') {
                if (nuevo_rec) records_guardar_ram();
                return;
            }
            if (k == 'r' || k == 'R' || (sin_mov && k == KEY_ENTER)) {
                if (nuevo_rec) records_guardar_ram();
                reiniciar = 1;
                break;
            }
            if (gano == 1 && (k == KEY_ENTER || k == ' ')) {
                gano = 2; /* continuar jugando tras 2048 */
                continue;
            }
            if (sin_mov) continue;

            int dir = -1;
            if (k == KEY_LEFT  || k == 'a' || k == 'A') dir = 0;
            else if (k == KEY_RIGHT || k == 'd' || k == 'D') dir = 1;
            else if (k == KEY_UP    || k == 'w' || k == 'W') dir = 2;
            else if (k == KEY_DOWN  || k == 's' || k == 'S') dir = 3;

            if (dir >= 0) {
                uint32_t gan = 0;
                if (g2_mover(dir, &gan)) {
                    pts += gan;
                    movs++;
                    if (pts > rec_2048) {
                        rec_2048 = pts;
                        nuevo_rec = 1;
                    }
                    g2_agregar_ficha();
                    if (gano == 0) {
                        for (int r = 0; r < 4; r++)
                            for (int c = 0; c < 4; c++)
                                if (g2_tab[r][c] >= 2048u) gano = 1;
                    }
                    if (!g2_hay_movimientos()) {
                        sin_mov = 1;
                        if (nuevo_rec) records_guardar_ram();
                    }
                }
            }
        }
        if (!reiniciar) break;
    }
}

/* ==================== 3. AHORCADO (INFORMATICA Y CULTURA) ==================== */
typedef struct {
    const char *palabra;
    const char *cat;
    const char *pista;
} ah_word_t;

static const ah_word_t ah_banco[] = {
    { "KERNEL",       "Informática", "Núcleo central que administra el hardware del SO" },
    { "PAGINACION",   "Informática", "Divide la memoria en bloques fijos de 4 KB" },
    { "PROCESO",      "Informática", "Programa en ejecución con PID, estado y registros" },
    { "ENSAMBLADOR",  "Informática", "Lenguaje de bajo nivel cercano al código máquina" },
    { "REGISTRO",     "Informática", "Memoria ultrarrápida dentro de la CPU (EAX, ESP)" },
    { "INTERRUPCION", "Informática", "Señal que pausa la CPU para atender un evento" },
    { "CONCURRENCIA", "Informática", "Varios procesos alternando turnos de CPU" },
    { "ALGORITMO",    "Informática", "Secuencia finita de pasos para resolver un problema" },
    { "COMPILADOR",   "Informática", "Traduce código fuente C a instrucciones máquina" },
    { "SOCKET",       "Informática", "Extremo de comunicación de red mediante TCP o UDP" },
    { "DIRECTORIO",   "Informática", "Carpeta que agrupa archivos y otros nodos" },
    { "PLANIFICADOR", "Informática", "Decide qué proceso listo recibe la CPU (FCFS, RR)" },
    { "MEMORIA",      "Informática", "Espacio donde viven el código, los datos y la pila" },
    { "SERVIDOR",     "Informática", "Equipo en red que responde peticiones de clientes" },
    { "SEGURIDAD",    "Informática", "Protección mediante permisos, roles y auditoría" },
    { "PROTOCOLO",    "Informática", "Conjunto de reglas para transmitir datos (HTTP, IP)" },
    { "ECUADOR",      "Cultura",     "País atravesado por la línea equinoccial" },
    { "GUAYAQUIL",    "Cultura",     "Puerto principal del Ecuador y sede de Argos" },
    { "GALAPAGOS",    "Cultura",     "Archipiélago ecuatoriano famoso por su fauna única" },
    { "CHIMBORAZO",   "Cultura",     "Volcán más alto del Ecuador y punto cercano al sol" },
    { "AMAZONAS",     "Cultura",     "Gran cuenca selvática y río más caudaloso" },
    { "ASTRONOMIA",   "Cultura",     "Ciencia que estudia estrellas, planetas y galaxias" },
    { "BIBLIOTECA",   "Cultura",     "Lugar que resguarda libros y conocimiento" },
    { "UNIVERSO",     "Cultura",     "Totalidad del espacio, tiempo, materia y energía" },
    { "VOLCAN",       "Cultura",     "Abertura terrestre por donde emerge magma" },
    { "CIENCIA",      "Cultura",     "Conocimiento basado en observación y método" }
};
#define AH_TOTAL ((int)(sizeof(ah_banco) / sizeof(ah_banco[0])))

static void ah_dibujar_horca(int x, int y, int err) {
    uint8_t cm = kcol_borde();
    uint8_t cp = (err >= 6) ? 0x0C : kcol_aviso();
    kvga_texto_en(x, y + 0, cm, "  +------+  ");
    kvga_texto_en(x, y + 1, cm, "  |      |  ");
    kvga_texto_en(x, y + 2, cm, "  |         ");
    kvga_texto_en(x, y + 3, cm, "  |         ");
    kvga_texto_en(x, y + 4, cm, "  |         ");
    kvga_texto_en(x, y + 5, cm, "  |         ");
    kvga_texto_en(x, y + 6, cm, " ===        ");

    if (err >= 1) kvga_texto_en(x + 9, y + 2, cp, "O");
    if (err >= 2) kvga_texto_en(x + 9, y + 3, cp, "|");
    if (err >= 3) kvga_texto_en(x + 8, y + 3, cp, "/");
    if (err >= 4) kvga_texto_en(x + 10, y + 3, cp, "\\");
    if (err >= 5) kvga_texto_en(x + 8, y + 4, cp, "/");
    if (err >= 6) kvga_texto_en(x + 10, y + 4, cp, "\\");
}

void juegos_ahorcado(void) {
    records_cargar();
    uint32_t racha = 0;
    int ultimo_idx = -1;

    while (1) {
        int idx = (int)(j_rand() % (uint32_t)AH_TOTAL);
        if (idx == ultimo_idx) idx = (idx + 1) % AH_TOTAL;
        ultimo_idx = idx;

        const ah_word_t *w = &ah_banco[idx];
        int wlen = j_slen(w->palabra);
        uint8_t usada[26];
        for (int i = 0; i < 26; i++) usada[i] = 0;

        int errores = 0;
        int estado = 0; /* 0=jugando, 1=gano, 2=perdio */
        int nueva_racha = 0;
        int seguir = 0;

        while (1) {
            kvga_barra_titulo("ARGOS JUEGOS - AHORCADO (INFORMÁTICA Y CULTURA)");
            kvga_limpiar_area(1, 23, kcol_fondo());

            /* Horca a la izquierda */
            kvga_dibujar_caja(3, 3, 18, 11, kcol_caja(), kcol_borde());
            ah_dibujar_horca(6, 5, errores);

            char e_str[14] = "Fallos: 0/6";
            e_str[8] = (char)('0' + errores);
            kvga_texto_en(6, 12, errores >= 5 ? 0x1C : kcol_caja_tit(), e_str);

            /* Panel derecho: categoria, pista, palabra y racha */
            kvga_dibujar_caja(23, 3, 54, 11, kcol_fondo(), kcol_acento());

            kvga_texto_en(25, 4, kcol_acento(), "Categoría: ");
            kvga_texto_en(36, 4, kcol_titulo(), w->cat);

            char r1[12], r2[12];
            j_u32_str(racha, r1);
            j_u32_str(rec_ahorc, r2);
            kvga_texto_en(52, 4, kcol_tenue(), "Racha: ");
            kvga_texto_en(59, 4, kcol_ok(), r1);
            kvga_texto_en(64, 4, kcol_tenue(), "Máx: ");
            kvga_texto_en(69, 4, kcol_aviso(), r2);

            kvga_texto_en(25, 6, kcol_acento(), "Pista:");
            kvga_texto_en(25, 7, kcol_fondo(), w->pista);

            /* Palabra enmascarada centrada */
            char masc[52];
            int mp = 0;
            for (int i = 0; i < wlen && mp < 48; i++) {
                char c = w->palabra[i];
                int vis = (estado == 2) || (c >= 'A' && c <= 'Z' && usada[c - 'A']);
                masc[mp++] = vis ? c : '_';
                if (i < wlen - 1) masc[mp++] = ' ';
            }
            masc[mp] = '\0';
            int mx = 25 + ((50 - mp) > 0 ? (50 - mp) / 2 : 0);
            kvga_texto_en(mx, 10, estado == 1 ? kcol_ok() : (estado == 2 ? 0x0C : kcol_dato()), masc);

            if (estado == 1) {
                kvga_texto_en(27, 12, kcol_ok(),
                    nueva_racha ? "¡CORRECTO! ¡Nueva mejor racha! Enter: Siguiente"
                                : "¡CORRECTO! Pulsa Enter para la siguiente palabra");
            } else if (estado == 2) {
                kvga_texto_en(27, 12, 0x0C, "Perdiste la racha. Enter: Reintentar | ESC: Salir");
            } else {
                kvga_texto_en(27, 12, kcol_tenue(), "Presiona cualquier letra (A-Z) para adivinar...");
            }

            /* Teclado visual de letras usadas (cols 3..76, rows 15..20) */
            kvga_dibujar_caja(3, 15, 74, 6, kcol_caja(), kcol_borde());
            kvga_texto_en(5, 16, kcol_caja_tit(), "Letras (verde = acierto, rojo/tenue = fallo):");
            for (int l = 0; l < 26; l++) {
                int lx = 6 + (l % 13) * 5;
                int ly = 18 + (l / 13);
                char lt[4] = { '[', (char)('A' + l), ']', '\0' };
                uint8_t lc = kcol_caja();
                if (usada[l]) {
                    int esta = 0;
                    for (int i = 0; i < wlen; i++) if (w->palabra[i] == (char)('A' + l)) { esta = 1; break; }
                    lc = esta ? 0x1A : 0x1C;
                    if (kernel_get_tema() == 1) lc = esta ? 0x72 : 0x74;
                    else if (kernel_get_tema() == 2) lc = esta ? 0x20 : 0x02;
                }
                kvga_texto_en(lx, ly, lc, lt);
            }

            j_barra_inf("Escribe letras A-Z | Enter: Nueva palabra al terminar | ESC: Volver a Juegos", 0);
            kset_cursor(27, 12);

            int k = teclado_getkey();
            rng_state ^= (uint32_t)k * 131u;
            if (k == KEY_ESC) return;

            if (estado != 0) {
                if (k == KEY_ENTER || k == ' ' || k == 'r' || k == 'R') {
                    seguir = 1;
                    break;
                }
                continue;
            }

            char ch = 0;
            if (k >= 'a' && k <= 'z') ch = (char)(k - ('a' - 'A'));
            else if (k >= 'A' && k <= 'Z') ch = (char)k;
            if (ch == 0) continue;

            int li = ch - 'A';
            if (usada[li]) continue;
            usada[li] = 1;

            int acierto = 0;
            for (int i = 0; i < wlen; i++) {
                if (w->palabra[i] == ch) acierto = 1;
            }
            if (!acierto) {
                errores++;
                if (errores >= 6) {
                    estado = 2;
                    racha = 0;
                }
            } else {
                int completa = 1;
                for (int i = 0; i < wlen; i++) {
                    if (!usada[w->palabra[i] - 'A']) { completa = 0; break; }
                }
                if (completa) {
                    estado = 1;
                    racha++;
                    if (racha > rec_ahorc) {
                        rec_ahorc = racha;
                        nueva_racha = 1;
                        records_guardar_ram();
                    }
                }
            }
        }
        if (!seguir) break;
    }
}

/* ==================== SUBMENU DE JUEGOS ==================== */
void juegos_menu(void) {
    records_cargar();
    int sel = 0;
    char aviso[76] = "";

    static const char * const descs[5] = {
        "Clásica culebrita a color en tiempo real con fruta bonus y 3 velocidades",
        "Desliza y suma potencias de 2 en un tablero 4x4 hasta alcanzar 2048",
        "Adivina términos de Sistemas Operativos, Informática y Cultura General",
        "Guarda tus récords (/records.txt) de forma permanente en el disco ATA",
        "Regresa a la pantalla principal de ARGOS OS"
    };

    while (1) {
        kvga_barra_titulo("ARGOS - JUEGOS Y ENTRETENIMIENTO");
        kvga_limpiar_area(1, 23, kcol_fondo());

        const int x0 = 6, y0 = 4, ancho = 68, alto = 15;
        kvga_dibujar_caja(x0, y0, ancho, alto, kcol_caja(), kcol_borde());
        kvga_texto_en(x0 + 21, y0 + 1, kcol_caja_tit(), "SALA DE JUEGOS DE ARGOS OS");

        char s_sn[16], s_20[16], s_ah[16];
        j_u32_str(rec_snake, s_sn);
        j_u32_str(rec_2048,  s_20);
        j_u32_str(rec_ahorc, s_ah);

        const char *ops[5] = {
            "1. Snake (La Culebrita)",
            "2. 2048 (Rompecabezas Numérico)",
            "3. Ahorcado (Informática y Cultura)",
            "4. Guardar récords en el disco ATA",
            "5. Volver al Menú Principal"
        };

        for (int i = 0; i < 5; i++) {
            int y = y0 + 3 + i * 2;
            uint8_t col = (i == sel) ? kcol_sel() : kcol_caja();
            char bg[65];
            for (int c = 0; c < 64; c++) bg[c] = ' ';
            bg[64] = '\0';
            kvga_texto_en(x0 + 2, y, col, bg);
            kvga_texto_en(x0 + 4, y, col, i == sel ? "> " : "  ");
            kvga_texto_en(x0 + 6, y, col, ops[i]);

            uint8_t c_rec = (i == sel) ? kcol_sel() : kcol_borde();
            if (i == 0) {
                kvga_texto_en(x0 + 45, y, c_rec, "Récord: ");
                kvga_texto_en(x0 + 53, y, c_rec, s_sn);
            } else if (i == 1) {
                kvga_texto_en(x0 + 45, y, c_rec, "Récord: ");
                kvga_texto_en(x0 + 53, y, c_rec, s_20);
            } else if (i == 2) {
                kvga_texto_en(x0 + 45, y, c_rec, "Racha : ");
                kvga_texto_en(x0 + 53, y, c_rec, s_ah);
            }
        }

        kvga_texto_en(6, 20, kcol_acento(), "Info: ");
        kvga_texto_en(12, 20, kcol_fondo(), descs[sel]);

        if (aviso[0]) {
            j_barra_inf(aviso, 1);
            aviso[0] = '\0';
        } else {
            j_barra_inf("Flechas Arr/Abj o teclas 1-5: Elegir juego | Enter: Jugar | ESC: Volver", 0);
        }
        kset_cursor(x0 + 4, y0 + 3 + sel * 2);

        int k = teclado_getkey();
        if (k == KEY_ESC) break;
        else if (k == KEY_UP) sel = (sel + 4) % 5;
        else if (k == KEY_DOWN) sel = (sel + 1) % 5;
        else if (k >= '1' && k <= '5') { sel = k - '1'; k = KEY_ENTER; }

        if (k == KEY_ENTER) {
            if (sel == 0) juegos_snake();
            else if (sel == 1) juegos_2048();
            else if (sel == 2) juegos_ahorcado();
            else if (sel == 3) {
                records_guardar_ram();
                const char *err = 0;
                if (fs_save_silencioso(&err) == 0) {
                    j_scpy(aviso, "¡Récords guardados en /records.txt y en el disco ATA!", sizeof(aviso));
                } else {
                    j_scpy(aviso, err ? err : "No se pudo guardar en el disco.", sizeof(aviso));
                }
            } else {
                break;
            }
        }
    }
}
