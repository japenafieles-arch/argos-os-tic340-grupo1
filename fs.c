#include "fs.h"
#include "ata.h"
#include "teclado.h"
#include "audit.h"

#define FS_VERSION_V2    2
#define FS_MAX_NODOS_V1  64
#define FS_MAX_DATOS_V1  1024
#define PREFS_MAGIC      0xA5

typedef struct {
    char     firma[8];
    uint32_t version;
    uint32_t total_nodos;
    uint32_t checksum;
    uint32_t max_datos;
    uint8_t  pref_kbd;
    int8_t   pref_tz;
    uint8_t  pref_tema;
    uint8_t  pref_validas;
} superbloque_t;

typedef struct {
    uint8_t  tipo;
    int16_t  padre;
    uint32_t tam;
    uint16_t permisos;
    char     nombre[MAX_NOMBRE];
    char     datos[FS_MAX_DATOS_V1];
} nodo_v1_t;

static nodo_t   nodos[MAX_NODOS];
static int16_t  dir_actual = -1;
static int      rol_actual = ROL_ADMIN;
static int      fs_dirty = 0;
static int      fs_disco_st = -1;
static int      fs_migrado_v1 = 0;
static uint32_t checksum_disco = 0;
static uint8_t  pref_kbd_mem = 0;
static int8_t   pref_tz_mem = 0;
static uint8_t  pref_tema_mem = 0;
static int      prefs_cargadas = 0;
static char     edit_buf[MAX_DATOS];
static uint8_t  sec_buf[512];

extern void kprint(const char *str);
extern void kputc(char c);
extern void kset_color(uint8_t c);
extern void kprint_dec(uint32_t v);
extern void kprint_pad(const char *s, int ancho);
extern void kclear(void);
extern void krender_editor_doc(const char *nombre, const char *buf, int len, int cur,
                               int sel_a, int sel_b, int max_bytes, int modificado,
                               int *scroll_row, const char *estado_msg);
extern int kconfirmar_guardar(const char *nombre);
extern const char *kernel_usuario_corto(void);

static int slen(const char *s) {
    int n = 0;
    while (s[n]) n++;
    return n;
}

static int scmp(const char *a, const char *b) {
    while (*a && (*a == *b)) { a++; b++; }
    return *(const unsigned char *)a - *(const unsigned char *)b;
}

static void scpy(char *d, const char *s, int max) {
    int i = 0;
    while (i < max - 1 && s[i]) { d[i] = s[i]; i++; }
    d[i] = '\0';
}

static char a_minuscula(char c) {
    uint8_t u = (uint8_t)c;
    if (u >= 'A' && u <= 'Z') return (char)(u + ('a' - 'A'));
    if (u == 0xA5) return (char)0xA4; /* Ñ -> ñ */
    if (u == 0x9B) return (char)0xA0; /* Á -> á */
    if (u == 0x90) return (char)0x82; /* É -> é */
    if (u == 0x9C) return (char)0xA1; /* Í -> í */
    if (u == 0x9D) return (char)0xA2; /* Ó -> ó */
    if (u == 0x9E) return (char)0xA3; /* Ú -> ú */
    if (u == 0x9A) return (char)0x81; /* Ü -> ü */
    return c;
}

static int empieza_con(const char *str, const char *pre) {
    while (*pre) {
        if (*str++ != *pre++) return 0;
    }
    return 1;
}

static int contiene_ci(const char *texto, const char *patron) {
    if (!patron[0]) return 1;
    for (int i = 0; texto[i]; i++) {
        int j = 0;
        while (patron[j] && texto[i + j] &&
               a_minuscula(texto[i + j]) == a_minuscula(patron[j])) {
            j++;
        }
        if (patron[j] == '\0') return 1;
    }
    return 0;
}

static uint32_t calc_checksum(void) {
    uint32_t sum = 0;
    const uint8_t *p = (const uint8_t *)nodos;
    for (uint32_t i = 0; i < sizeof(nodos); i++) {
        sum = (sum * 31) + p[i];
    }
    return sum;
}

static void imprimir_permisos(uint8_t tipo, uint16_t p) {
    kputc(tipo == NODO_DIR ? 'd' : '-');
    kputc((p & 0400) ? 'r' : '-');
    kputc((p & 0200) ? 'w' : '-');
    kputc((p & 0100) ? 'x' : '-');
    kputc((p & 0040) ? 'r' : '-');
    kputc((p & 0020) ? 'w' : '-');
    kputc((p & 0010) ? 'x' : '-');
    kputc((p & 0004) ? 'r' : '-');
    kputc((p & 0002) ? 'w' : '-');
    kputc((p & 0001) ? 'x' : '-');
}

static void imprimir_octal(uint16_t p) {
    kputc('0');
    kputc((char)('0' + ((p >> 6) & 7)));
    kputc((char)('0' + ((p >> 3) & 7)));
    kputc((char)('0' + (p & 7)));
}

static int dir_permiso(uint16_t bit) {
    if (dir_actual == -1) return 1;
    return (nodos[dir_actual].permisos & bit) != 0;
}

static int puede_escribir_rol(void) {
    if (rol_actual == ROL_INVITADO) {
        audit_registrar(LOG_ALERT, kernel_usuario_corto(), "DENEGADO", "Invitado intento escribir en FS");
        kprint("Permiso denegado: el invitado solo tiene permisos de lectura.\n");
        return 0;
    }
    return 1;
}

static int puede_eliminar_rol(const char *tipo_txt) {
    if (rol_actual == ROL_INVITADO) {
        audit_registrar(LOG_ALERT, kernel_usuario_corto(), "DENEGADO", "Invitado intento eliminar");
        kprint("Permiso denegado: el invitado solo tiene permisos de lectura.\n");
        return 0;
    }
    if (rol_actual == ROL_USUARIO) {
        audit_registrar(LOG_ALERT, kernel_usuario_corto(), "DENEGADO", "Usuario comun intento eliminar");
        kprint("Permiso denegado: el usuario común no tiene permiso para eliminar ");
        kprint(tipo_txt);
        kprint(".\n");
        return 0;
    }
    return 1;
}

static int fs_cargar_v1_migrado(uint32_t esperada) {
    uint32_t total_v1 = (uint32_t)(FS_MAX_NODOS_V1 * sizeof(nodo_v1_t));
    uint32_t sec_actual = 0xFFFFFFFFu;
    uint32_t sum = 0;
    uint32_t byte_pos = 0;
    nodo_v1_t tmp;

    for (int i = 0; i < FS_MAX_NODOS_V1; i++) {
        uint8_t *dst = (uint8_t *)&tmp;
        for (uint32_t k = 0; k < sizeof(nodo_v1_t); k++) {
            uint32_t s = byte_pos / 512u;
            uint32_t off = byte_pos % 512u;
            if (s != sec_actual) {
                if (ata_read_sector(2u + s, sec_buf) != 0) return -1;
                sec_actual = s;
            }
            uint8_t val = sec_buf[off];
            dst[k] = val;
            sum = (sum * 31u) + val;
            byte_pos++;
        }
        if (tmp.tipo != NODO_LIBRE) {
            nodos[i].tipo = tmp.tipo;
            nodos[i].padre = tmp.padre;
            nodos[i].permisos = tmp.permisos;
            scpy(nodos[i].nombre, tmp.nombre, MAX_NOMBRE);
            if (tmp.tipo == NODO_ARCH) {
                scpy(nodos[i].datos, tmp.datos, MAX_DATOS);
                nodos[i].tam = (uint32_t)slen(nodos[i].datos);
            } else {
                nodos[i].datos[0] = '\0';
                nodos[i].tam = 0;
            }
        }
    }
    (void)total_v1;
    if (sum != esperada) {
        for (int i = 0; i < MAX_NODOS; i++) nodos[i].tipo = NODO_LIBRE;
        return -1;
    }
    fs_migrado_v1 = 1;
    return 0;
}

static int fs_load(void) {
    fs_migrado_v1 = 0;
    prefs_cargadas = 0;
    if (ata_read_sector(1, sec_buf) != 0) return -2;
    superbloque_t *sb = (superbloque_t *)sec_buf;
    const char *magic = "TIC340FS";
    for (int i = 0; i < 8; i++) {
        if (sb->firma[i] != magic[i]) return -1;
    }

    /* Migracion automatica desde TIC340FS v1 (64 nodos, 1 KB) sin perder archivos */
    if (sb->version == 1 && sb->total_nodos == FS_MAX_NODOS_V1) {
        return fs_cargar_v1_migrado(sb->checksum);
    }

    if (sb->version != FS_VERSION_V2 || sb->total_nodos != MAX_NODOS || sb->max_datos != MAX_DATOS) {
        return -1;
    }

    uint32_t esperada = sb->checksum;
    uint8_t p_kbd = sb->pref_kbd;
    int8_t  p_tz  = sb->pref_tz;
    uint8_t p_tem = sb->pref_tema;
    uint8_t p_val = sb->pref_validas;

    uint8_t *dest = (uint8_t *)nodos;
    uint32_t total = sizeof(nodos);
    uint32_t sectores = (total + 511u) / 512u;

    for (uint32_t s = 0; s < sectores; s++) {
        if (ata_read_sector(2u + s, sec_buf) != 0) return -1;
        uint32_t offset = s * 512u;
        uint32_t copiar = (total - offset < 512u) ? (total - offset) : 512u;
        for (uint32_t b = 0; b < copiar; b++) {
            dest[offset + b] = sec_buf[b];
        }
    }
    if (calc_checksum() != esperada) return -1;

    checksum_disco = esperada;
    if (p_val == PREFS_MAGIC) {
        pref_kbd_mem = (p_kbd <= 2) ? p_kbd : 0;
        pref_tz_mem  = (p_tz >= -12 && p_tz <= 12) ? p_tz : 0;
        pref_tema_mem = (p_tem <= 2) ? p_tem : 0;
        prefs_cargadas = 1;
    }
    return 0;
}

int fs_init(void) {
    for (int i = 0; i < MAX_NODOS; i++) {
        nodos[i].tipo = NODO_LIBRE;
        nodos[i].padre = -1;
        nodos[i].tam = 0;
        nodos[i].permisos = 0;
    }
    int r = fs_load();
    fs_disco_st = r;
    fs_dirty = fs_migrado_v1 ? 1 : 0;
    if (r != 0) {
        for (int i = 0; i < MAX_NODOS; i++) nodos[i].tipo = NODO_LIBRE;
    }
    return r;
}

void fs_set_rol(int rol) {
    rol_actual = rol;
}

void fs_reset_dir(void) {
    dir_actual = -1;
}

int fs_hay_cambios(void) {
    return fs_dirty;
}

int fs_estado_disco(void) {
    return fs_disco_st;
}

void fs_contar_nodos(int *usados, int *archivos, int *dirs, uint32_t *bytes) {
    int u = 0, a = 0, d = 0;
    uint32_t b = 0;
    for (int i = 0; i < MAX_NODOS; i++) {
        if (nodos[i].tipo != NODO_LIBRE) {
            u++;
            if (nodos[i].tipo == NODO_ARCH) {
                a++;
                b += nodos[i].tam;
            } else if (nodos[i].tipo == NODO_DIR) {
                d++;
            }
        }
    }
    if (usados) *usados = u;
    if (archivos) *archivos = a;
    if (dirs) *dirs = d;
    if (bytes) *bytes = b;
}

static int resolver_dir(const char *ruta, int16_t *salida);

static int nombre_valido(const char *nombre) {
    int n = slen(nombre);
    if (n == 0) { kprint("Error: falta el nombre.\n"); return 0; }
    if (n > MAX_NOMBRE - 1) { kprint("Error: el nombre admite hasta 32 caracteres.\n"); return 0; }
    if (scmp(nombre, ".") == 0 || scmp(nombre, "..") == 0) { kprint("Error: nombre reservado.\n"); return 0; }
    for (int i = 0; i < n; i++) {
        if (nombre[i] == '/' || nombre[i] == ' ') {
            kprint("Error: el nombre no puede tener '/' ni espacios.\n");
            return 0;
        }
    }
    return 1;
}

static int nodo_libre(void) {
    for (int i = 0; i < MAX_NODOS; i++)
        if (nodos[i].tipo == NODO_LIBRE) return i;
    return -1;
}

static int buscar(const char *nombre, int16_t padre) {
    for (int i = 0; i < MAX_NODOS; i++)
        if (nodos[i].tipo != NODO_LIBRE && nodos[i].padre == padre && scmp(nodos[i].nombre, nombre) == 0)
            return i;
    return -1;
}

static int es_descendiente(int16_t posible_hijo, int16_t ancestro) {
    int16_t cur = posible_hijo;
    int guarda = 0;
    while (cur != -1 && guarda++ < MAX_NODOS) {
        if (cur == ancestro) return 1;
        cur = nodos[cur].padre;
    }
    return 0;
}

static void pwd_rec(int16_t d) {
    if (d == -1) return;
    pwd_rec(nodos[d].padre);
    kputc('/');
    kprint(nodos[d].nombre);
}

static void imprimir_ruta_nodo(int16_t id) {
    if (id == -1) kputc('/');
    else pwd_rec(id);
}

int fs_listar_candidatos(const char *prefijo, int solo_dirs, int solo_archs, const char *out[], int max_out) {
    if (!dir_permiso(PERM_R)) return 0;
    int n = 0;
    for (int i = 0; i < MAX_NODOS && n < max_out; i++) {
        if (nodos[i].tipo == NODO_LIBRE || nodos[i].padre != dir_actual) continue;
        if (solo_dirs && nodos[i].tipo != NODO_DIR) continue;
        if (solo_archs && nodos[i].tipo != NODO_ARCH) continue;
        if (empieza_con(nodos[i].nombre, prefijo)) {
            out[n++] = nodos[i].nombre;
        }
    }
    return n;
}

int fs_mkdir(const char *nombre) {
    if (!puede_escribir_rol()) return -1;
    if (!nombre_valido(nombre)) return -1;
    if (!dir_permiso(PERM_W)) {
        kprint("Permiso denegado: el directorio actual no permite escritura (w).\n");
        return -1;
    }
    if (buscar(nombre, dir_actual) != -1) {
        kprint("Error: ya existe un elemento con ese nombre.\n");
        return -1;
    }
    int i = nodo_libre();
    if (i == -1) { kprint("Error: no quedan nodos libres (máximo 128).\n"); return -1; }
    nodos[i].tipo = NODO_DIR;
    nodos[i].padre = dir_actual;
    nodos[i].tam = 0;
    nodos[i].permisos = 0755;
    scpy(nodos[i].nombre, nombre, MAX_NOMBRE);
    fs_dirty = 1;
    return i;
}

int fs_touch(const char *nombre) {
    if (!puede_escribir_rol()) return -1;
    if (!nombre_valido(nombre)) return -1;
    if (!dir_permiso(PERM_W)) {
        kprint("Permiso denegado: el directorio actual no permite escritura (w).\n");
        return -1;
    }
    int ex = buscar(nombre, dir_actual);
    if (ex != -1) return ex;
    int i = nodo_libre();
    if (i == -1) { kprint("Error: no quedan nodos libres (máximo 128).\n"); return -1; }
    nodos[i].tipo = NODO_ARCH;
    nodos[i].padre = dir_actual;
    nodos[i].tam = 0;
    nodos[i].permisos = 0644;
    scpy(nodos[i].nombre, nombre, MAX_NOMBRE);
    nodos[i].datos[0] = '\0';
    fs_dirty = 1;
    return i;
}

int fs_write(const char *nombre, const char *contenido) {
    if (!puede_escribir_rol()) return -1;
    int i = buscar(nombre, dir_actual);
    if (i == -1 || nodos[i].tipo != NODO_ARCH) {
        kprint("Error: el archivo no existe.\n");
        return -1;
    }
    if (!(nodos[i].permisos & PERM_W)) {
        kprint("Permiso denegado: archivo sin permiso de escritura (w).\n");
        return -1;
    }
    scpy(nodos[i].datos, contenido, MAX_DATOS);
    nodos[i].tam = (uint32_t)slen(nodos[i].datos);
    fs_dirty = 1;
    return 0;
}

int fs_cat(const char *nombre) {
    int i = buscar(nombre, dir_actual);
    if (i == -1 || nodos[i].tipo != NODO_ARCH) {
        kprint("Error: archivo no encontrado.\n");
        return -1;
    }
    if (!(nodos[i].permisos & PERM_R)) {
        kprint("Permiso denegado: archivo sin permiso de lectura (r).\n");
        return -1;
    }
    kprint(nodos[i].datos);
    kprint("\n");
    return 0;
}

static int edit_inicio_linea(const char *buf, int pos) {
    while (pos > 0 && buf[pos - 1] != '\n') pos--;
    return pos;
}

static int edit_fin_linea(const char *buf, int len, int pos) {
    while (pos < len && buf[pos] != '\n') pos++;
    return pos;
}

static int edit_subir(const char *buf, int pos) {
    int ini = edit_inicio_linea(buf, pos);
    if (ini == 0) return 0;
    int col = pos - ini;
    int prev_fin = ini - 1;
    int prev_ini = edit_inicio_linea(buf, prev_fin);
    int prev_len = prev_fin - prev_ini;
    return prev_ini + (col < prev_len ? col : prev_len);
}

static int edit_bajar(const char *buf, int len, int pos) {
    int ini = edit_inicio_linea(buf, pos);
    int fin = edit_fin_linea(buf, len, pos);
    if (fin >= len) return len;
    int col = pos - ini;
    int next_ini = fin + 1;
    int next_fin = edit_fin_linea(buf, len, next_ini);
    int next_len = next_fin - next_ini;
    return next_ini + (col < next_len ? col : next_len);
}

static void edit_sel_rango(int cur, int sel_ini, int *sa, int *sb) {
    if (sel_ini >= 0 && sel_ini != cur) {
        *sa = (sel_ini < cur) ? sel_ini : cur;
        *sb = (sel_ini < cur) ? cur : sel_ini;
    } else {
        *sa = 0;
        *sb = 0;
    }
}

static int edit_borrar_sel(char *buf, int *len, int *cur, int *sel_ini) {
    int sa = 0, sb = 0;
    edit_sel_rango(*cur, *sel_ini, &sa, &sb);
    if (sb <= sa) return 0;
    int dif = sb - sa;
    for (int i = sb; i <= *len; i++) buf[i - dif] = buf[i];
    *len -= dif;
    *cur = sa;
    *sel_ini = -1;
    return 1;
}

int fs_copiar_a_clip(const char *nombre) {
    int i = buscar(nombre, dir_actual);
    if (i == -1 || nodos[i].tipo != NODO_ARCH) {
        kprint("Error: archivo '"); kprint(nombre); kprint("' no encontrado.\n");
        return -1;
    }
    if (!(nodos[i].permisos & PERM_R)) {
        kprint("Permiso denegado: archivo sin permiso de lectura (r).\n");
        return -1;
    }
    int n = (int)nodos[i].tam;
    if (n == 0) {
        clip_limpiar();
        kprint("El archivo está vacío (portapapeles vaciado).\n");
        return 0;
    }
    clip_copiar(nodos[i].datos, n);
    kprint("Copiados "); kprint_dec((uint32_t)n);
    kprint(" bytes de '"); kprint(nombre); kprint("' al portapapeles (usa Ctrl+V).\n");
    return 0;
}

int fs_edit(const char *nombre) {
    if (!puede_escribir_rol()) return -1;
    int recien_creado = 0;
    int dirty_antes = fs_dirty;
    int i = buscar(nombre, dir_actual);
    if (i == -1) {
        i = fs_touch(nombre);
        if (i == -1) return -1;
        recien_creado = 1;
    }
    if (nodos[i].tipo != NODO_ARCH) {
        kprint("Error: no se puede editar un directorio.\n");
        return -1;
    }
    if (!(nodos[i].permisos & PERM_R)) {
        kprint("Permiso denegado: archivo sin permiso de lectura (r).\n");
        return -1;
    }
    if (!(nodos[i].permisos & PERM_W)) {
        kprint("Permiso denegado: archivo sin permiso de escritura (w).\n");
        return -1;
    }

    scpy(edit_buf, nodos[i].datos, MAX_DATOS);
    int len = slen(edit_buf);
    int cur = len;
    int sel_ini = -1;
    int scroll_row = 0;
    int mod = recien_creado;
    const char *aviso = "";

    int guardar = 0;
    int sin_cambios = 0;
    while (1) {
        int sa = 0, sb = 0;
        edit_sel_rango(cur, sel_ini, &sa, &sb);
        mod = recien_creado || (scmp(edit_buf, nodos[i].datos) != 0);
        krender_editor_doc(nombre, edit_buf, len, cur, sa, sb, MAX_DATOS - 1, mod, &scroll_row, aviso);
        aviso = "";

        int k = teclado_getkey();
        if (k == KEY_ESC) {
            if (!mod) {
                sin_cambios = 1;
                break;
            }
            int decision = kconfirmar_guardar(nombre);
            if (decision == -1) continue;
            guardar = decision;
            break;
        } else if (k == KEY_LEFT) {
            if (sb > sa) { cur = sa; sel_ini = -1; }
            else { sel_ini = -1; if (cur > 0) cur--; }
        } else if (k == KEY_RIGHT) {
            if (sb > sa) { cur = sb; sel_ini = -1; }
            else { sel_ini = -1; if (cur < len) cur++; }
        } else if (k == KEY_UP) {
            sel_ini = -1;
            cur = edit_subir(edit_buf, cur);
        } else if (k == KEY_DOWN) {
            sel_ini = -1;
            cur = edit_bajar(edit_buf, len, cur);
        } else if (k == KEY_HOME) {
            sel_ini = -1;
            cur = edit_inicio_linea(edit_buf, cur);
        } else if (k == KEY_END) {
            sel_ini = -1;
            cur = edit_fin_linea(edit_buf, len, cur);
        } else if (k == KEY_PGUP) {
            sel_ini = -1;
            for (int r = 0; r < 10; r++) cur = edit_subir(edit_buf, cur);
        } else if (k == KEY_PGDN) {
            sel_ini = -1;
            for (int r = 0; r < 10; r++) cur = edit_bajar(edit_buf, len, cur);
        } else if (k == KEY_S_LEFT) {
            if (sel_ini < 0) sel_ini = cur;
            if (cur > 0) cur--;
        } else if (k == KEY_S_RIGHT) {
            if (sel_ini < 0) sel_ini = cur;
            if (cur < len) cur++;
        } else if (k == KEY_S_UP) {
            if (sel_ini < 0) sel_ini = cur;
            cur = edit_subir(edit_buf, cur);
        } else if (k == KEY_S_DOWN) {
            if (sel_ini < 0) sel_ini = cur;
            cur = edit_bajar(edit_buf, len, cur);
        } else if (k == KEY_S_HOME) {
            if (sel_ini < 0) sel_ini = cur;
            cur = edit_inicio_linea(edit_buf, cur);
        } else if (k == KEY_S_END) {
            if (sel_ini < 0) sel_ini = cur;
            cur = edit_fin_linea(edit_buf, len, cur);
        } else if (k == KEY_CTRL_A) {
            if (len > 0) { sel_ini = 0; cur = len; aviso = "Todo seleccionado"; }
        } else if (k == KEY_CTRL_C) {
            if (sb > sa) {
                clip_copiar(edit_buf + sa, sb - sa);
                aviso = "Selección copiada al portapapeles";
            } else {
                int li = edit_inicio_linea(edit_buf, cur);
                int lf = edit_fin_linea(edit_buf, len, cur);
                if (lf > li) {
                    clip_copiar(edit_buf + li, lf - li);
                    aviso = "Línea actual copiada al portapapeles";
                }
            }
        } else if (k == KEY_CTRL_X) {
            if (sb > sa) {
                clip_copiar(edit_buf + sa, sb - sa);
                edit_borrar_sel(edit_buf, &len, &cur, &sel_ini);
                aviso = "Selección cortada al portapapeles";
            } else {
                int li = edit_inicio_linea(edit_buf, cur);
                int lf = edit_fin_linea(edit_buf, len, cur);
                if (lf > li) {
                    clip_copiar(edit_buf + li, lf - li);
                    int fin_del = (lf < len && edit_buf[lf] == '\n') ? lf + 1 : lf;
                    int dif = fin_del - li;
                    for (int m = fin_del; m <= len; m++) edit_buf[m - dif] = edit_buf[m];
                    len -= dif;
                    cur = li;
                    sel_ini = -1;
                    aviso = "Línea cortada al portapapeles";
                }
            }
        } else if (k == KEY_CTRL_V) {
            edit_borrar_sel(edit_buf, &len, &cur, &sel_ini);
            const char *cl = clip_obtener();
            int clen = clip_largo();
            int pegados = 0;
            for (int m = 0; m < clen && len < MAX_DATOS - 1; m++) {
                uint8_t ch = (uint8_t)cl[m];
                if (ch == '\r') continue;
                if (ch < 32 && ch != '\n') continue;
                for (int j = len; j >= cur; j--) edit_buf[j + 1] = edit_buf[j];
                edit_buf[cur++] = (char)ch;
                len++;
                pegados++;
            }
            aviso = pegados > 0 ? "Texto pegado desde el portapapeles" : "Portapapeles vacío";
        } else if (k == KEY_BS) {
            if (!edit_borrar_sel(edit_buf, &len, &cur, &sel_ini)) {
                if (cur > 0) {
                    for (int m = cur; m <= len; m++) edit_buf[m - 1] = edit_buf[m];
                    cur--;
                    len--;
                }
            }
        } else if (k == KEY_DEL) {
            if (!edit_borrar_sel(edit_buf, &len, &cur, &sel_ini)) {
                if (cur < len) {
                    for (int m = cur + 1; m <= len; m++) edit_buf[m - 1] = edit_buf[m];
                    len--;
                }
            }
        } else if (k == KEY_TAB) {
            edit_borrar_sel(edit_buf, &len, &cur, &sel_ini);
            for (int s = 0; s < 2 && len < MAX_DATOS - 1; s++) {
                for (int j = len; j >= cur; j--) edit_buf[j + 1] = edit_buf[j];
                edit_buf[cur++] = ' ';
                len++;
            }
        } else if (k == KEY_ENTER || (k >= 32 && k < 0x100)) {
            edit_borrar_sel(edit_buf, &len, &cur, &sel_ini);
            if (len < MAX_DATOS - 1) {
                for (int j = len; j >= cur; j--) edit_buf[j + 1] = edit_buf[j];
                edit_buf[cur++] = (char)k;
                len++;
            } else {
                aviso = "Límite máximo alcanzado (4095 bytes)";
            }
        }
    }

    kclear();
    if (sin_cambios) {
        kprint("Sin cambios en '");
        kprint(nombre);
        kprint("'.\n");
    } else if (guardar) {
        scpy(nodos[i].datos, edit_buf, MAX_DATOS);
        nodos[i].tam = (uint32_t)slen(nodos[i].datos);
        fs_dirty = 1;
        audit_registrar(LOG_INFO, kernel_usuario_corto(), "EDITAR", nombre);
        kprint("Archivo '");
        kprint(nombre);
        kprint("' guardado en RAM (");
        kprint_dec(nodos[i].tam);
        kprint(" bytes). Usa 'save' para persistir en disco.\n");
    } else {
        if (recien_creado) {
            nodos[i].tipo = NODO_LIBRE;
            nodos[i].padre = -1;
            fs_dirty = dirty_antes;
        }
        kprint("Cambios descartados en '");
        kprint(nombre);
        kprint("'. No se guardó la edición.\n");
    }
    return 0;
}

int fs_chmod(const char *modo_str, const char *nombre) {
    if (rol_actual != ROL_ADMIN) {
        audit_registrar(LOG_ALERT, kernel_usuario_corto(), "DENEGADO", "chmod no autorizado");
        kprint("Permiso denegado: solo el Administrador puede cambiar permisos.\n");
        return -1;
    }
    if (slen(modo_str) != 3 ||
        modo_str[0] < '0' || modo_str[0] > '7' ||
        modo_str[1] < '0' || modo_str[1] > '7' ||
        modo_str[2] < '0' || modo_str[2] > '7') {
        kprint("Uso: chmod <modo> <archivo/dir> (ej: chmod 644 nota.txt)\n");
        return -1;
    }
    int i = buscar(nombre, dir_actual);
    if (i == -1) {
        kprint("Error: archivo o directorio no encontrado.\n");
        return -1;
    }
    uint16_t u = (uint16_t)(modo_str[0] - '0');
    uint16_t g = (uint16_t)(modo_str[1] - '0');
    uint16_t o = (uint16_t)(modo_str[2] - '0');
    nodos[i].permisos = (uint16_t)((u << 6) | (g << 3) | o);
    fs_dirty = 1;
    {
        char det[40]; int p = 0;
        for (int k = 0; k < 3 && p < 38; k++) det[p++] = modo_str[k];
        det[p++] = ' ';
        for (int k = 0; nodos[i].nombre[k] && p < 39; k++) det[p++] = nodos[i].nombre[k];
        det[p] = '\0';
        audit_registrar(LOG_WARN, kernel_usuario_corto(), "CHMOD", det);
    }

    kprint("Permisos actualizados: ");
    imprimir_permisos(nodos[i].tipo, nodos[i].permisos);
    kprint("  ");
    kprint(nodos[i].nombre);
    kprint("\n");
    return 0;
}

/* Copiar archivo: cp <origen> <destino | directorio> */
int fs_cp(const char *origen, const char *destino) {
    if (!puede_escribir_rol()) return -1;

    int src = buscar(origen, dir_actual);
    if (src == -1) {
        kprint("Error: archivo origen '"); kprint(origen); kprint("' no encontrado.\n");
        return -1;
    }
    if (nodos[src].tipo != NODO_ARCH) {
        kprint("Error: '"); kprint(origen); kprint("' es un directorio. 'cp' solo copia archivos.\n");
        return -1;
    }
    if (!(nodos[src].permisos & PERM_R)) {
        kprint("Permiso denegado: archivo origen sin permiso de lectura (r).\n");
        return -1;
    }

    /* Comprobar si destino es un directorio destino (/, .. o carpeta existente) */
    int es_dir_dest = 0;
    int16_t dir_dest = dir_actual;
    const char *nombre_final = destino;

    if (scmp(destino, "/") == 0) {
        es_dir_dest = 1;
        dir_dest = -1;
        nombre_final = nodos[src].nombre;
    } else if (scmp(destino, "..") == 0) {
        es_dir_dest = 1;
        dir_dest = (dir_actual == -1) ? -1 : nodos[dir_actual].padre;
        nombre_final = nodos[src].nombre;
    } else {
        int ex = buscar(destino, dir_actual);
        if (ex != -1 && nodos[ex].tipo == NODO_DIR) {
            es_dir_dest = 1;
            dir_dest = (int16_t)ex;
            nombre_final = nodos[src].nombre;
        }
    }

    if (es_dir_dest) {
        if (dir_dest != -1) {
            if (!(nodos[dir_dest].permisos & PERM_X) || !(nodos[dir_dest].permisos & PERM_W)) {
                kprint("Permiso denegado: directorio destino sin permiso de acceso/escritura (wx).\n");
                return -1;
            }
        }
        if (dir_dest == dir_actual) {
            kprint("Error: origen y destino son el mismo archivo.\n");
            return -1;
        }
    } else {
        if (!dir_permiso(PERM_W)) {
            kprint("Permiso denegado: el directorio actual no permite escritura (w).\n");
            return -1;
        }
        if (!nombre_valido(destino)) return -1;
    }

    int dst = buscar(nombre_final, dir_dest);
    if (dst == src) {
        kprint("Error: origen y destino son el mismo archivo.\n");
        return -1;
    }
    if (dst != -1) {
        if (nodos[dst].tipo != NODO_ARCH) {
            kprint("Error: ya existe un directorio con ese nombre en el destino.\n");
            return -1;
        }
        if (!(nodos[dst].permisos & PERM_W)) {
            kprint("Permiso denegado: el archivo destino no permite escritura (w).\n");
            return -1;
        }
    } else {
        dst = nodo_libre();
        if (dst == -1) {
            kprint("Error: no quedan nodos libres (máximo 128).\n");
            return -1;
        }
        nodos[dst].tipo = NODO_ARCH;
        nodos[dst].padre = dir_dest;
        nodos[dst].permisos = nodos[src].permisos;
        scpy(nodos[dst].nombre, nombre_final, MAX_NOMBRE);
    }

    scpy(nodos[dst].datos, nodos[src].datos, MAX_DATOS);
    nodos[dst].tam = nodos[src].tam;
    fs_dirty = 1;

    kprint("Copiado: ");
    imprimir_ruta_nodo((int16_t)src);
    kprint(" -> ");
    imprimir_ruta_nodo((int16_t)dst);
    kprint("\n");
    return 0;
}

/* Mover o renombrar archivo/directorio: mv <origen> <nuevo_nombre | directorio> */
int fs_mv(const char *origen, const char *destino) {
    if (!puede_escribir_rol()) return -1;
    if (!dir_permiso(PERM_W)) {
        kprint("Permiso denegado: el directorio actual no permite escritura (w).\n");
        return -1;
    }

    int src = buscar(origen, dir_actual);
    if (src == -1) {
        kprint("Error: '"); kprint(origen); kprint("' no encontrado.\n");
        return -1;
    }
    if (!(nodos[src].permisos & PERM_W)) {
        kprint("Permiso denegado: '"); kprint(origen); kprint("' no tiene permiso de escritura (w).\n");
        return -1;
    }

    /* Comprobar si destino es una carpeta destino (/, .. o subdirectorio) */
    int es_mover = 0;
    int16_t dir_dest = dir_actual;

    if (scmp(destino, "/") == 0) {
        es_mover = 1;
        dir_dest = -1;
    } else if (scmp(destino, "..") == 0) {
        es_mover = 1;
        dir_dest = (dir_actual == -1) ? -1 : nodos[dir_actual].padre;
    } else {
        int ex = buscar(destino, dir_actual);
        if (ex != -1) {
            if (nodos[ex].tipo == NODO_DIR) {
                es_mover = 1;
                dir_dest = (int16_t)ex;
            } else {
                kprint("Error: ya existe un archivo llamado '");
                kprint(destino);
                kprint("'. Usa otro nombre.\n");
                return -1;
            }
        }
    }

    if (es_mover) {
        if (dir_dest == dir_actual) {
            kprint("Aviso: el elemento ya se encuentra en ese directorio.\n");
            return 0;
        }
        if (nodos[src].tipo == NODO_DIR && es_descendiente(dir_dest, (int16_t)src)) {
            kprint("Error: no se puede mover un directorio dentro de sí mismo.\n");
            return -1;
        }
        if (dir_dest != -1) {
            if (!(nodos[dir_dest].permisos & PERM_X) || !(nodos[dir_dest].permisos & PERM_W)) {
                kprint("Permiso denegado: directorio destino sin permiso de acceso/escritura (wx).\n");
                return -1;
            }
        }
        if (buscar(nodos[src].nombre, dir_dest) != -1) {
            kprint("Error: ya existe un elemento con ese nombre en el directorio destino.\n");
            return -1;
        }
        nodos[src].padre = dir_dest;
        fs_dirty = 1;
        kprint("Movido a: ");
        imprimir_ruta_nodo((int16_t)src);
        kprint("\n");
        return 0;
    }

    if (!nombre_valido(destino)) return -1;
    scpy(nodos[src].nombre, destino, MAX_NOMBRE);
    fs_dirty = 1;
    kprint("Renombrado: '"); kprint(origen); kprint("' -> '"); kprint(destino); kprint("'\n");
    return 0;
}

static void find_rec(int16_t padre, const char *patron, int *total) {
    for (int i = 0; i < MAX_NODOS; i++) {
        if (nodos[i].tipo == NODO_LIBRE || nodos[i].padre != padre) continue;

        if (contiene_ci(nodos[i].nombre, patron)) {
            (*total)++;
            kset_color(0x0B);
            kprint("  [NOMBRE]    ");
            kset_color(0x0F);
            imprimir_ruta_nodo((int16_t)i);
            if (nodos[i].tipo == NODO_DIR) kputc('/');
            kset_color(0x07);
            kprint("\n");
        }

        if (nodos[i].tipo == NODO_ARCH && (nodos[i].permisos & PERM_R)) {
            if (contiene_ci(nodos[i].datos, patron)) {
                (*total)++;
                kset_color(0x0E);
                kprint("  [CONTENIDO] ");
                kset_color(0x07);
                imprimir_ruta_nodo((int16_t)i);
                kprint("\n");
            }
        }

        if (nodos[i].tipo == NODO_DIR &&
            (nodos[i].permisos & PERM_R) && (nodos[i].permisos & PERM_X)) {
            find_rec((int16_t)i, patron, total);
        }
    }
}

void fs_find(const char *patron) {
    if (!patron || !patron[0]) {
        kprint("Uso: find <texto>   (busca en nombres y contenido de archivos)\n");
        return;
    }
    kset_color(0x0D);
    kprint("=== Búsqueda en TIC340FS: \""); kprint(patron); kprint("\" ===\n");
    kset_color(0x07);
    int total = 0;
    find_rec(-1, patron, &total);
    if (total == 0) {
        kprint("  No se encontraron coincidencias.\n");
    } else {
        kset_color(0x0A);
        kprint("Total: "); kprint_dec((uint32_t)total);
        kprint(total == 1 ? " coincidencia.\n" : " coincidencias.\n");
        kset_color(0x07);
    }
}

int fs_stat(const char *nombre) {
    if (scmp(nombre, "/") == 0 || (scmp(nombre, ".") == 0 && dir_actual == -1)) {
        int hijos = 0;
        for (int i = 0; i < MAX_NODOS; i++)
            if (nodos[i].tipo != NODO_LIBRE && nodos[i].padre == -1) hijos++;
        kset_color(0x0D); kprint("=== Información del nodo (stat) ===\n");
        kset_color(0x0B); kprint("  Inodo    : "); kset_color(0x0F); kprint("raíz (-1)  |  Tipo: Directorio raíz\n");
        kset_color(0x0B); kprint("  Ruta     : "); kset_color(0x0F); kprint("/\n");
        kset_color(0x0B); kprint("  Permisos : "); kset_color(0x07); kprint("drwxr-xr-x (0755)\n");
        kset_color(0x0B); kprint("  Hijos    : "); kset_color(0x07); kprint_dec((uint32_t)hijos); kprint(" elemento(s)\n");
        return 0;
    }

    int idx = (scmp(nombre, ".") == 0) ? (int)dir_actual : buscar(nombre, dir_actual);
    if (idx == -1) {
        kprint("Error: '"); kprint(nombre); kprint("' no encontrado.\n");
        return -1;
    }

    nodo_t *nd = &nodos[idx];
    kset_color(0x0D); kprint("=== Información del nodo (stat) ===\n");
    kset_color(0x0B); kprint("  Inodo    : ");
    kset_color(0x0F); kputc('#'); kprint_dec((uint32_t)idx);
    kset_color(0x0B); kprint("    Tipo: ");
    kset_color(0x0F); kprint(nd->tipo == NODO_DIR ? "Directorio\n" : "Archivo regular\n");

    kset_color(0x0B); kprint("  Nombre   : ");
    kset_color(0x0F); kprint(nd->nombre);
    kset_color(0x0B); kprint("    Ruta: ");
    kset_color(0x07); imprimir_ruta_nodo((int16_t)idx);
    if (nd->tipo == NODO_DIR) kputc('/');
    kprint("\n");

    kset_color(0x0B); kprint("  Permisos : ");
    kset_color(0x0A); imprimir_permisos(nd->tipo, nd->permisos);
    kset_color(0x07); kprint("  (octal "); imprimir_octal(nd->permisos); kprint(")  [");
    kprint((nd->permisos & PERM_R) ? "R:Sí " : "R:No ");
    kprint((nd->permisos & PERM_W) ? "W:Sí " : "W:No ");
    kprint((nd->permisos & PERM_X) ? "X:Sí]\n" : "X:No]\n");

    if (nd->tipo == NODO_ARCH) {
        kset_color(0x0B); kprint("  Tamaño   : ");
        kset_color(0x0F); kprint_dec(nd->tam);
        kset_color(0x07); kprint(" / "); kprint_dec(MAX_DATOS); kprint(" bytes\n");
    } else {
        int hijos = 0;
        for (int j = 0; j < MAX_NODOS; j++)
            if (nodos[j].tipo != NODO_LIBRE && nodos[j].padre == idx) hijos++;
        kset_color(0x0B); kprint("  Contenido: ");
        kset_color(0x0F); kprint_dec((uint32_t)hijos);
        kset_color(0x07); kprint(" elemento(s) directo(s)\n");
    }

    kset_color(0x0B); kprint("  Padre    : ");
    kset_color(0x07);
    if (nd->padre == -1) kprint("/ (raíz)\n");
    else {
        kputc('#'); kprint_dec((uint32_t)nd->padre);
        kprint(" ("); imprimir_ruta_nodo(nd->padre); kprint(")\n");
    }
    return 0;
}

void fs_df(void) {
    int usados = 0, archs = 0, dirs = 0;
    uint32_t bytes_usados = 0;
    fs_contar_nodos(&usados, &archs, &dirs, &bytes_usados);
    int libres = MAX_NODOS - usados;
    int pct_nodos = (usados * 100) / MAX_NODOS;
    uint32_t cap_datos = MAX_NODOS * MAX_DATOS;
    uint32_t pct_datos = (bytes_usados * 100) / cap_datos;
    uint32_t sectores_tabla = ((uint32_t)sizeof(nodos) + 511u) / 512u;

    kset_color(0x0D);
    kprint("=== Espacio del Sistema de Archivos (TIC340FS) ===\n");

    kset_color(0x0B); kprint("  Nodos    : ");
    kset_color(0x0F); kprint_dec((uint32_t)usados);
    kset_color(0x07); kprint(" / "); kprint_dec(MAX_NODOS);
    kprint(" usados ("); kprint_dec((uint32_t)pct_nodos); kprint("%)  [");
    int llenos = (usados * 20) / MAX_NODOS;
    kset_color(pct_nodos >= 80 ? 0x0C : 0x0A);
    for (int i = 0; i < 20; i++) kputc(i < llenos ? '#' : '.');
    kset_color(0x07); kprint("]\n");

    kset_color(0x0B); kprint("  Desglose : ");
    kset_color(0x07); kprint("Archivos="); kprint_dec((uint32_t)archs);
    kprint("  |  Directorios="); kprint_dec((uint32_t)dirs);
    kprint("  |  Libres="); kset_color(0x0A); kprint_dec((uint32_t)libres);
    kset_color(0x07); kprint("\n");

    kset_color(0x0B); kprint("  Datos    : ");
    kset_color(0x0F); kprint_dec(bytes_usados);
    kset_color(0x07); kprint(" / "); kprint_dec(cap_datos);
    kprint(" bytes ("); kprint_dec(pct_datos); kprint("%)\n");

    kset_color(0x0B); kprint("  Disco ATA: ");
    kset_color(0x07); kprint("Superbloque LBA 1 + ");
    kprint_dec(sectores_tabla); kprint(" sectores de nodos (LBA 2..");
    kprint_dec(1 + sectores_tabla); kprint(")\n");

    kset_color(0x0B); kprint("  Estado   : ");
    if (fs_disco_st == -2) {
        kset_color(0x0C); kprint("Sin disco ATA (solo RAM)");
    } else if (fs_dirty) {
        kset_color(0x0E); kprint("Hay cambios sin guardar en disco (usa 'save')");
    } else {
        kset_color(0x0A); kprint("Sincronizado con disco ATA");
    }
    kset_color(0x07); kprint("\n");
}

void fs_ls(const char *ruta) {
    int16_t d = dir_actual;
    if (ruta && ruta[0] && resolver_dir(ruta, &d) != 0) return;
    if (d != -1 && !(nodos[d].permisos & PERM_R)) {
        kprint("Permiso denegado: directorio sin permiso de lectura (r).\n");
        return;
    }
    int hay = 0;
    for (int i = 0; i < MAX_NODOS; i++) {
        if (nodos[i].tipo != NODO_LIBRE && nodos[i].padre == d) {
            hay = 1;
            imprimir_permisos(nodos[i].tipo, nodos[i].permisos);
            kprint("  ");
            kprint(nodos[i].nombre);
            if (nodos[i].tipo == NODO_DIR) kprint("/\n");
            else kprint("\n");
        }
    }
    if (!hay) kprint("(directorio vacío)\n");
}

void fs_tree(int16_t padre, int nivel) {
    if (padre == -1 && nivel == 0) kprint("/\n");
    for (int i = 0; i < MAX_NODOS; i++) {
        if (nodos[i].tipo != NODO_LIBRE && nodos[i].padre == padre) {
            for (int j = 0; j < nivel; j++) kprint("  ");
            kprint("|- ");
            imprimir_permisos(nodos[i].tipo, nodos[i].permisos);
            kprint(" ");
            kprint(nodos[i].nombre);
            if (nodos[i].tipo == NODO_DIR) {
                kprint("/\n");
                fs_tree((int16_t)i, nivel + 1);
            } else {
                kprint("\n");
            }
        }
    }
}

static int resolver_dir(const char *ruta, int16_t *salida) {
    int16_t d = (ruta[0] == '/') ? -1 : dir_actual;
    const char *p = ruta;
    char comp[MAX_NOMBRE];
    while (*p) {
        while (*p == '/') p++;
        if (!*p) break;
        int n = 0, largo = 0;
        while (*p && *p != '/') {
            if (n < MAX_NOMBRE - 1) comp[n++] = *p;
            largo++;
            p++;
        }
        comp[n] = '\0';
        if (largo > MAX_NOMBRE - 1) { kprint("Error: nombre demasiado largo en la ruta.\n"); return -1; }
        if (scmp(comp, ".") == 0) continue;
        if (scmp(comp, "..") == 0) {
            if (d != -1) d = nodos[d].padre;
            continue;
        }
        int i = buscar(comp, d);
        if (i == -1 || nodos[i].tipo != NODO_DIR) {
            kprint("Directorio no encontrado: ");
            kprint(comp);
            kprint("\n");
            return -1;
        }
        if (!(nodos[i].permisos & PERM_X)) {
            kprint("Permiso denegado: '");
            kprint(comp);
            kprint("' no tiene permiso de acceso (x).\n");
            return -1;
        }
        d = (int16_t)i;
    }
    *salida = d;
    return 0;
}

int fs_cd(const char *ruta) {
    int16_t d;
    if (resolver_dir(ruta, &d) != 0) return -1;
    dir_actual = d;
    return 0;
}

int fs_rma(const char *nombre) {
    if (!puede_eliminar_rol("archivos")) return -1;
    if (!dir_permiso(PERM_W)) {
        kprint("Permiso denegado: el directorio actual no permite escritura (w).\n");
        return -1;
    }
    int i = buscar(nombre, dir_actual);
    if (i == -1) { kprint("Error: archivo no encontrado.\n"); return -1; }
    if (nodos[i].tipo != NODO_ARCH) {
        kprint("Error: '");
        kprint(nombre);
        kprint("' es un directorio. Usa 'rme' para eliminar directorios.\n");
        return -1;
    }
    if (!(nodos[i].permisos & PERM_W)) {
        kprint("Permiso denegado: archivo protegido sin permiso de escritura (w).\n");
        return -1;
    }
    nodos[i].tipo = NODO_LIBRE;
    nodos[i].padre = -1;
    fs_dirty = 1;
    audit_registrar(LOG_WARN, kernel_usuario_corto(), "ELIM_ARCH", nombre);
    kprint("Archivo '");
    kprint(nombre);
    kprint("' eliminado correctamente.\n");
    return 0;
}

int fs_rme(const char *nombre) {
    if (!puede_eliminar_rol("directorios")) return -1;
    if (!dir_permiso(PERM_W)) {
        kprint("Permiso denegado: el directorio actual no permite escritura (w).\n");
        return -1;
    }
    int i = buscar(nombre, dir_actual);
    if (i == -1) { kprint("Error: directorio no encontrado.\n"); return -1; }
    if (nodos[i].tipo != NODO_DIR) {
        kprint("Error: '");
        kprint(nombre);
        kprint("' es un archivo. Usa 'rma' para eliminar archivos.\n");
        return -1;
    }
    if (!(nodos[i].permisos & PERM_W)) {
        kprint("Permiso denegado: directorio protegido sin permiso de escritura (w).\n");
        return -1;
    }
    for (int j = 0; j < MAX_NODOS; j++) {
        if (nodos[j].tipo != NODO_LIBRE && nodos[j].padre == i) {
            kprint("Error: el directorio no está vacío. Elimina primero su contenido.\n");
            return -1;
        }
    }
    nodos[i].tipo = NODO_LIBRE;
    nodos[i].padre = -1;
    fs_dirty = 1;
    audit_registrar(LOG_WARN, kernel_usuario_corto(), "ELIM_DIR", nombre);
    kprint("Directorio '");
    kprint(nombre);
    kprint("' eliminado correctamente.\n");
    return 0;
}

static void llenar_superbloque_v2(uint32_t cksum) {
    for (int i = 0; i < 512; i++) sec_buf[i] = 0;
    superbloque_t *sb = (superbloque_t *)sec_buf;
    const char *magic = "TIC340FS";
    for (int i = 0; i < 8; i++) sb->firma[i] = magic[i];
    sb->version      = FS_VERSION_V2;
    sb->total_nodos  = MAX_NODOS;
    sb->checksum     = cksum;
    sb->max_datos    = MAX_DATOS;
    sb->pref_kbd     = pref_kbd_mem;
    sb->pref_tz      = pref_tz_mem;
    sb->pref_tema    = pref_tema_mem;
    sb->pref_validas = PREFS_MAGIC;
}

static int escribir_fs_completo(const char **err_out) {
    uint32_t cksum = calc_checksum();
    const uint8_t *src = (const uint8_t *)nodos;
    uint32_t total = sizeof(nodos);
    uint32_t sectores = (total + 511u) / 512u;

    /* Escribir primero la tabla de nodos y por ultimo el superbloque (actualizacion mas segura) */
    for (uint32_t s = 0; s < sectores; s++) {
        for (int b = 0; b < 512; b++) sec_buf[b] = 0;
        uint32_t offset = s * 512u;
        uint32_t copiar = (total - offset < 512u) ? (total - offset) : 512u;
        for (uint32_t b = 0; b < copiar; b++) sec_buf[b] = src[offset + b];
        if (ata_write_sector_raw(2u + s, sec_buf) != 0) {
            if (s == 0) fs_disco_st = -2;
            if (err_out) *err_out = (s == 0) ? "No se detectó disco ATA en VirtualBox" : "Error escribiendo datos en disco ATA";
            return -1;
        }
    }

    llenar_superbloque_v2(cksum);
    if (ata_write_sector_raw(1u, sec_buf) != 0 || ata_flush() != 0) {
        if (err_out) *err_out = "Error escribiendo superbloque en disco ATA";
        return -1;
    }

    checksum_disco = cksum;
    fs_disco_st = 0;
    fs_migrado_v1 = 0;
    fs_dirty = 0;
    prefs_cargadas = 1;
    return 0;
}

int fs_save(void) {
    if (!puede_escribir_rol()) return -1;
    const char *err = 0;
    if (escribir_fs_completo(&err) != 0) {
        kprint("Error: "); kprint(err ? err : "fallo al escribir en disco ATA"); kprint(".\n");
        return -1;
    }
    audit_registrar(LOG_OK, kernel_usuario_corto(), "SAVE_ATA", "TIC340FS v2 persistido en disco");
    kprint("TIC340FS v2 (128 nodos x 4 KB) guardado en disco ATA correctamente.\n");
    return 0;
}

void fs_pwd(void) {
    imprimir_ruta_nodo(dir_actual);
}

int fs_guardar_silencioso(const char *nombre, const char *contenido, const char **err_out) {
    if (rol_actual == ROL_INVITADO) {
        audit_registrar(LOG_ALERT, kernel_usuario_corto(), "DENEGADO", "Invitado intento guardar cita");
        if (err_out) *err_out = "Permiso denegado: invitado es solo lectura";
        return -1;
    }
    int n = slen(nombre);
    if (n == 0 || n > MAX_NOMBRE - 1 || scmp(nombre, ".") == 0 || scmp(nombre, "..") == 0) {
        if (err_out) *err_out = "Nombre de archivo inválido";
        return -1;
    }
    for (int k = 0; k < n; k++) {
        if (nombre[k] == '/' || nombre[k] == ' ') {
            if (err_out) *err_out = "Sin '/' ni espacios en el nombre";
            return -1;
        }
    }
    if (!dir_permiso(PERM_W)) {
        if (err_out) *err_out = "Directorio actual sin permiso de escritura";
        return -1;
    }
    int idx = buscar(nombre, dir_actual);
    if (idx != -1) {
        if (nodos[idx].tipo != NODO_ARCH) {
            if (err_out) *err_out = "Ya existe un directorio con ese nombre";
            return -1;
        }
        if (!(nodos[idx].permisos & PERM_W)) {
            if (err_out) *err_out = "Archivo protegido sin permiso de escritura";
            return -1;
        }
    } else {
        idx = nodo_libre();
        if (idx == -1) {
            if (err_out) *err_out = "Sin nodos libres en TIC340FS (128/128)";
            return -1;
        }
        nodos[idx].tipo = NODO_ARCH;
        nodos[idx].padre = dir_actual;
        nodos[idx].permisos = 0644;
        scpy(nodos[idx].nombre, nombre, MAX_NOMBRE);
    }
    scpy(nodos[idx].datos, contenido, MAX_DATOS);
    nodos[idx].tam = (uint32_t)slen(nodos[idx].datos);
    fs_dirty = 1;
    audit_registrar(LOG_OK, kernel_usuario_corto(), "SCHOLAR_SAVE", nombre);
    return 0;
}

int fs_get_rol(void) {
    return rol_actual;
}

int fs_en_raiz(void) {
    return dir_actual == -1;
}

static void ruta_str_rec(int16_t d, char *out, int *pos, int max_len) {
    if (d == -1) return;
    ruta_str_rec(nodos[d].padre, out, pos, max_len);
    if (*pos < max_len - 1) out[(*pos)++] = '/';
    for (int i = 0; nodos[d].nombre[i] && *pos < max_len - 1; i++) {
        out[(*pos)++] = nodos[d].nombre[i];
    }
}

void fs_ruta_actual_str(char *out, int max_len) {
    if (!out || max_len < 2) return;
    if (dir_actual == -1) {
        out[0] = '/';
        out[1] = '\0';
        return;
    }
    int pos = 0;
    ruta_str_rec(dir_actual, out, &pos, max_len);
    out[pos] = '\0';
}

/* Lista primero carpetas y luego archivos del directorio actual */
int fs_listar_dir_actual(fs_item_t *out, int max_out) {
    if (!dir_permiso(PERM_R)) return -1;
    int n = 0;
    for (int fase = 0; fase < 2; fase++) {
        uint8_t tipo_busc = (fase == 0) ? NODO_DIR : NODO_ARCH;
        for (int i = 0; i < MAX_NODOS && n < max_out; i++) {
            if (nodos[i].tipo == tipo_busc && nodos[i].padre == dir_actual) {
                out[n].id = (int16_t)i;
                out[n].tipo = nodos[i].tipo;
                out[n].permisos = nodos[i].permisos;
                out[n].tam = nodos[i].tam;
                scpy(out[n].nombre, nodos[i].nombre, MAX_NOMBRE);
                n++;
            }
        }
    }
    return n;
}

int fs_leer_archivo_buf(const char *nombre, char *out, int max_len) {
    int i = buscar(nombre, dir_actual);
    if (i == -1 || nodos[i].tipo != NODO_ARCH) return -1;
    if (!(nodos[i].permisos & PERM_R)) return -2;
    scpy(out, nodos[i].datos, max_len);
    return (int)nodos[i].tam;
}

int fs_mkdir_silencioso(const char *nombre, const char **err_out) {
    if (rol_actual == ROL_INVITADO) {
        audit_registrar(LOG_ALERT, kernel_usuario_corto(), "DENEGADO", "Invitado intento crear carpeta");
        if (err_out) *err_out = "Modo Invitado: solo tienes permiso de lectura";
        return -1;
    }
    int n = slen(nombre);
    if (n == 0 || n > MAX_NOMBRE - 1 || scmp(nombre, ".") == 0 || scmp(nombre, "..") == 0) {
        if (err_out) *err_out = "Nombre de carpeta no válido";
        return -1;
    }
    for (int k = 0; k < n; k++) {
        if (nombre[k] == '/' || nombre[k] == ' ') {
            if (err_out) *err_out = "El nombre no puede tener espacios ni '/'";
            return -1;
        }
    }
    if (!dir_permiso(PERM_W)) {
        if (err_out) *err_out = "Esta carpeta no permite crear elementos";
        return -1;
    }
    if (buscar(nombre, dir_actual) != -1) {
        if (err_out) *err_out = "Ya existe un archivo o carpeta con ese nombre";
        return -1;
    }
    int i = nodo_libre();
    if (i == -1) {
        if (err_out) *err_out = "Espacio lleno (máximo 128 archivos/carpetas)";
        return -1;
    }
    nodos[i].tipo = NODO_DIR;
    nodos[i].padre = dir_actual;
    nodos[i].tam = 0;
    nodos[i].permisos = 0755;
    scpy(nodos[i].nombre, nombre, MAX_NOMBRE);
    fs_dirty = 1;
    return i;
}

int fs_eliminar_silencioso(const char *nombre, const char **err_out) {
    if (rol_actual == ROL_INVITADO) {
        audit_registrar(LOG_ALERT, kernel_usuario_corto(), "DENEGADO", "Invitado intento eliminar");
        if (err_out) *err_out = "Modo Invitado: no puedes eliminar elementos";
        return -1;
    }
    if (rol_actual == ROL_USUARIO) {
        audit_registrar(LOG_ALERT, kernel_usuario_corto(), "DENEGADO", "Usuario comun intento eliminar");
        if (err_out) *err_out = "Solo el Administrador puede eliminar archivos o carpetas";
        return -1;
    }
    if (!dir_permiso(PERM_W)) {
        if (err_out) *err_out = "Esta carpeta no permite modificaciones";
        return -1;
    }
    int i = buscar(nombre, dir_actual);
    if (i == -1) {
        if (err_out) *err_out = "Elemento no encontrado";
        return -1;
    }
    if (!(nodos[i].permisos & PERM_W)) {
        if (err_out) *err_out = "Elemento protegido (sin permiso de escritura)";
        return -1;
    }
    if (nodos[i].tipo == NODO_DIR) {
        for (int j = 0; j < MAX_NODOS; j++) {
            if (nodos[j].tipo != NODO_LIBRE && nodos[j].padre == i) {
                if (err_out) *err_out = "La carpeta no está vacía. Vacíala primero";
                return -1;
            }
        }
        audit_registrar(LOG_WARN, kernel_usuario_corto(), "ELIM_DIR", nombre);
    } else {
        audit_registrar(LOG_WARN, kernel_usuario_corto(), "ELIM_ARCH", nombre);
    }
    nodos[i].tipo = NODO_LIBRE;
    nodos[i].padre = -1;
    fs_dirty = 1;
    return 0;
}

int fs_save_silencioso(const char **err_out) {
    if (rol_actual == ROL_INVITADO) {
        audit_registrar(LOG_ALERT, kernel_usuario_corto(), "DENEGADO", "Invitado intento guardar disco");
        if (err_out) *err_out = "Modo Invitado: solo lectura (no puedes guardar)";
        return -1;
    }
    if (escribir_fs_completo(err_out) != 0) return -1;
    audit_registrar(LOG_OK, kernel_usuario_corto(), "SAVE_ATA", "TIC340FS v2 persistido en disco");
    return 0;
}

int fs_fue_migrado_v1(void) {
    return fs_migrado_v1;
}

int fs_ir_a_dir(int16_t dir_id) {
    if (dir_id == -1) { dir_actual = -1; return 0; }
    if (dir_id < 0 || dir_id >= MAX_NODOS || nodos[dir_id].tipo != NODO_DIR) return -1;
    if (!(nodos[dir_id].permisos & PERM_X)) return -1;
    dir_actual = dir_id;
    return 0;
}

static int validar_nombre_sil(const char *nombre, const char **err_out) {
    int n = slen(nombre);
    if (n == 0 || n > MAX_NOMBRE - 1 || scmp(nombre, ".") == 0 || scmp(nombre, "..") == 0) {
        if (err_out) *err_out = "Nombre inválido (1..32 caracteres)";
        return 0;
    }
    for (int k = 0; k < n; k++) {
        if (nombre[k] == '/' || nombre[k] == ' ') {
            if (err_out) *err_out = "El nombre no puede tener espacios ni '/'";
            return 0;
        }
    }
    return 1;
}

int fs_renombrar_silencioso(const char *origen, const char *nuevo_nombre, const char **err_out) {
    if (rol_actual == ROL_INVITADO) {
        audit_registrar(LOG_ALERT, kernel_usuario_corto(), "DENEGADO", "Invitado intento renombrar");
        if (err_out) *err_out = "Modo Invitado: solo tienes permiso de lectura";
        return -1;
    }
    if (!dir_permiso(PERM_W)) {
        if (err_out) *err_out = "Esta carpeta no permite modificaciones";
        return -1;
    }
    if (!validar_nombre_sil(nuevo_nombre, err_out)) return -1;
    int src = buscar(origen, dir_actual);
    if (src == -1) {
        if (err_out) *err_out = "Elemento no encontrado";
        return -1;
    }
    if (!(nodos[src].permisos & PERM_W)) {
        if (err_out) *err_out = "Elemento protegido (sin permiso de escritura)";
        return -1;
    }
    if (scmp(origen, nuevo_nombre) == 0) return 0;
    if (buscar(nuevo_nombre, dir_actual) != -1) {
        if (err_out) *err_out = "Ya existe un elemento con ese nombre";
        return -1;
    }
    scpy(nodos[src].nombre, nuevo_nombre, MAX_NOMBRE);
    fs_dirty = 1;
    audit_registrar(LOG_INFO, kernel_usuario_corto(), "RENOMBRAR", nuevo_nombre);
    return 0;
}

int fs_copiar_silencioso(const char *origen, const char *destino, const char **err_out) {
    if (rol_actual == ROL_INVITADO) {
        audit_registrar(LOG_ALERT, kernel_usuario_corto(), "DENEGADO", "Invitado intento copiar");
        if (err_out) *err_out = "Modo Invitado: solo tienes permiso de lectura";
        return -1;
    }
    int src = buscar(origen, dir_actual);
    if (src == -1) {
        if (err_out) *err_out = "Archivo origen no encontrado";
        return -1;
    }
    if (nodos[src].tipo != NODO_ARCH) {
        if (err_out) *err_out = "Solo se pueden copiar archivos (no carpetas)";
        return -1;
    }
    if (!(nodos[src].permisos & PERM_R)) {
        if (err_out) *err_out = "Archivo sin permiso de lectura";
        return -1;
    }

    int es_dir_dest = 0;
    int16_t dir_dest = dir_actual;
    const char *nombre_final = destino;

    if (scmp(destino, "/") == 0) {
        es_dir_dest = 1; dir_dest = -1; nombre_final = nodos[src].nombre;
    } else if (scmp(destino, "..") == 0) {
        es_dir_dest = 1; dir_dest = (dir_actual == -1) ? -1 : nodos[dir_actual].padre;
        nombre_final = nodos[src].nombre;
    } else {
        int ex = buscar(destino, dir_actual);
        if (ex != -1 && nodos[ex].tipo == NODO_DIR) {
            es_dir_dest = 1; dir_dest = (int16_t)ex; nombre_final = nodos[src].nombre;
        }
    }

    if (es_dir_dest) {
        if (dir_dest != -1 && (!(nodos[dir_dest].permisos & PERM_X) || !(nodos[dir_dest].permisos & PERM_W))) {
            if (err_out) *err_out = "Carpeta destino sin permiso de escritura";
            return -1;
        }
        if (dir_dest == dir_actual) {
            if (err_out) *err_out = "El archivo ya está en esta carpeta (elige otro nombre)";
            return -1;
        }
    } else {
        if (!dir_permiso(PERM_W)) {
            if (err_out) *err_out = "Esta carpeta no permite crear copias";
            return -1;
        }
        if (!validar_nombre_sil(destino, err_out)) return -1;
    }

    int dst = buscar(nombre_final, dir_dest);
    if (dst == src) {
        if (err_out) *err_out = "El origen y destino son el mismo archivo";
        return -1;
    }
    if (dst != -1) {
        if (nodos[dst].tipo != NODO_ARCH) {
            if (err_out) *err_out = "Ya existe una carpeta con ese nombre";
            return -1;
        }
        if (!(nodos[dst].permisos & PERM_W)) {
            if (err_out) *err_out = "El archivo destino está protegido";
            return -1;
        }
    } else {
        dst = nodo_libre();
        if (dst == -1) {
            if (err_out) *err_out = "Espacio lleno (128/128 nodos)";
            return -1;
        }
        nodos[dst].tipo = NODO_ARCH;
        nodos[dst].padre = dir_dest;
        nodos[dst].permisos = nodos[src].permisos;
        scpy(nodos[dst].nombre, nombre_final, MAX_NOMBRE);
    }
    scpy(nodos[dst].datos, nodos[src].datos, MAX_DATOS);
    nodos[dst].tam = nodos[src].tam;
    fs_dirty = 1;
    audit_registrar(LOG_INFO, kernel_usuario_corto(), "COPIAR", nombre_final);
    return 0;
}

int fs_mover_silencioso(const char *origen, const char *destino, const char **err_out) {
    if (rol_actual == ROL_INVITADO) {
        audit_registrar(LOG_ALERT, kernel_usuario_corto(), "DENEGADO", "Invitado intento mover");
        if (err_out) *err_out = "Modo Invitado: solo tienes permiso de lectura";
        return -1;
    }
    if (!dir_permiso(PERM_W)) {
        if (err_out) *err_out = "Esta carpeta no permite mover elementos";
        return -1;
    }
    int src = buscar(origen, dir_actual);
    if (src == -1) {
        if (err_out) *err_out = "Elemento no encontrado";
        return -1;
    }
    if (!(nodos[src].permisos & PERM_W)) {
        if (err_out) *err_out = "Elemento protegido (sin permiso de escritura)";
        return -1;
    }

    int16_t dir_dest = dir_actual;
    if (scmp(destino, "/") == 0) {
        dir_dest = -1;
    } else if (scmp(destino, "..") == 0) {
        dir_dest = (dir_actual == -1) ? -1 : nodos[dir_actual].padre;
    } else {
        int ex = buscar(destino, dir_actual);
        if (ex == -1 || nodos[ex].tipo != NODO_DIR) {
            if (err_out) *err_out = "La carpeta destino no existe";
            return -1;
        }
        dir_dest = (int16_t)ex;
    }

    if (dir_dest == dir_actual) {
        if (err_out) *err_out = "El elemento ya está en esa carpeta";
        return -1;
    }
    if (nodos[src].tipo == NODO_DIR && es_descendiente(dir_dest, (int16_t)src)) {
        if (err_out) *err_out = "No puedes mover una carpeta dentro de sí misma";
        return -1;
    }
    if (dir_dest != -1 && (!(nodos[dir_dest].permisos & PERM_X) || !(nodos[dir_dest].permisos & PERM_W))) {
        if (err_out) *err_out = "Carpeta destino sin permiso de escritura";
        return -1;
    }
    if (buscar(nodos[src].nombre, dir_dest) != -1) {
        if (err_out) *err_out = "Ya existe un elemento con ese nombre en el destino";
        return -1;
    }

    nodos[src].padre = dir_dest;
    fs_dirty = 1;
    audit_registrar(LOG_INFO, kernel_usuario_corto(), "MOVER", nodos[src].nombre);
    return 0;
}

static void find_hits_rec(int16_t padre, const char *patron, fs_find_hit_t *out, int *cnt, int max_out) {
    for (int i = 0; i < MAX_NODOS && *cnt < max_out; i++) {
        if (nodos[i].tipo == NODO_LIBRE || nodos[i].padre != padre) continue;

        int hit_nom = contiene_ci(nodos[i].nombre, patron);
        int hit_cnt = (!hit_nom && nodos[i].tipo == NODO_ARCH &&
                       (nodos[i].permisos & PERM_R) && contiene_ci(nodos[i].datos, patron));

        if (hit_nom || hit_cnt) {
            fs_find_hit_t *h = &out[*cnt];
            h->id = (int16_t)i;
            h->padre = nodos[i].padre;
            h->tipo = nodos[i].tipo;
            h->por_contenido = hit_cnt ? 1 : 0;
            scpy(h->nombre, nodos[i].nombre, MAX_NOMBRE);
            int p = 0;
            ruta_str_rec((int16_t)i, h->ruta, &p, (int)sizeof(h->ruta));
            h->ruta[p] = '\0';
            (*cnt)++;
        }

        if (nodos[i].tipo == NODO_DIR &&
            (nodos[i].permisos & PERM_R) && (nodos[i].permisos & PERM_X)) {
            find_hits_rec((int16_t)i, patron, out, cnt, max_out);
        }
    }
}

int fs_buscar_resultados(const char *patron, fs_find_hit_t *out, int max_out) {
    if (!patron || !patron[0] || max_out <= 0) return 0;
    int cnt = 0;
    find_hits_rec(-1, patron, out, &cnt, max_out);
    return cnt;
}

int fs_tiene_prefs_guardadas(void) {
    return prefs_cargadas;
}

void fs_obtener_prefs(uint8_t *kbd, int8_t *tz, uint8_t *tema) {
    if (kbd) *kbd = pref_kbd_mem;
    if (tz) *tz = pref_tz_mem;
    if (tema) *tema = pref_tema_mem;
}

int fs_guardar_prefs(uint8_t kbd, int8_t tz, uint8_t tema) {
    pref_kbd_mem  = (kbd <= 2) ? kbd : 0;
    pref_tz_mem   = (tz >= -12 && tz <= 12) ? tz : 0;
    pref_tema_mem = (tema <= 2) ? tema : 0;
    prefs_cargadas = 1;

    /* Si ya hay un disco formateado en v2, persistir LBA 1 al instante sin tocar los datos */
    if (fs_disco_st == 0 && !fs_migrado_v1) {
        llenar_superbloque_v2(checksum_disco);
        if (ata_write_sector(1u, sec_buf) == 0) return 0;
        return -1;
    }
    return 1; /* guardado en RAM; se persistira en disco al ejecutar save / G */
}

int fs_leer_raiz_archivo(const char *nombre, char *out, int max_len) {
    int i = buscar(nombre, -1);
    if (i == -1 || nodos[i].tipo != NODO_ARCH) return -1;
    if (!(nodos[i].permisos & PERM_R)) return -2;
    scpy(out, nodos[i].datos, max_len);
    return (int)nodos[i].tam;
}

int fs_guardar_raiz_archivo(const char *nombre, const char *contenido, const char **err_out) {
    if (rol_actual == ROL_INVITADO) {
        audit_registrar(LOG_ALERT, kernel_usuario_corto(), "DENEGADO", "Invitado intento guardar app");
        if (err_out) *err_out = "Modo Invitado: solo tienes permiso de lectura";
        return -1;
    }
    if (!validar_nombre_sil(nombre, err_out)) return -1;
    int idx = buscar(nombre, -1);
    if (idx != -1) {
        if (nodos[idx].tipo != NODO_ARCH) {
            if (err_out) *err_out = "Existe una carpeta con ese nombre en la raíz";
            return -1;
        }
        if (!(nodos[idx].permisos & PERM_W)) {
            if (err_out) *err_out = "Archivo protegido sin permiso de escritura";
            return -1;
        }
    } else {
        idx = nodo_libre();
        if (idx == -1) {
            if (err_out) *err_out = "Espacio lleno en TIC340FS (128/128)";
            return -1;
        }
        nodos[idx].tipo = NODO_ARCH;
        nodos[idx].padre = -1;
        nodos[idx].permisos = 0644;
        scpy(nodos[idx].nombre, nombre, MAX_NOMBRE);
    }
    scpy(nodos[idx].datos, contenido, MAX_DATOS);
    nodos[idx].tam = (uint32_t)slen(nodos[idx].datos);
    fs_dirty = 1;
    return 0;
}
