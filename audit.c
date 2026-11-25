/*
 * Modulo 4: Registro de Auditoria de Seguridad (log / log clear)
 *  - Buffer circular en memoria con los ultimos 32 eventos del sistema
 *  - Cada entrada guarda: secuencia, hora real (HH:MM:SS), usuario, evento y detalle
 *  - Acceso exclusivo para el Administrador Argos (intentos no autorizados quedan registrados)
 */
#include "audit.h"
#include "reloj.h"
#include "fs.h"

#define MAX_LOG 32

typedef struct {
    uint32_t seq;
    uint8_t  h, m, s;
    uint8_t  nivel;
    char     usuario[12];
    char     evento[14];
    char     detalle[40];
} audit_entry_t;

extern void kprint(const char *s);
extern void kputc(char c);
extern void kset_color(uint8_t c);
extern void kprint_dec(uint32_t v);
extern void kprint_pad(const char *s, int ancho);
extern const char *kernel_usuario_corto(void);

static audit_entry_t entradas[MAX_LOG];
static int log_head = 0;
static int log_count = 0;
static uint32_t log_seq = 0;

static void a_scpy(char *d, const char *s, int max) {
    int i = 0;
    while (i < max - 1 && s && s[i]) { d[i] = s[i]; i++; }
    d[i] = '\0';
}

static int a_igual(const char *a, const char *b) {
    while (*a && *a == *b) { a++; b++; }
    return *a == *b;
}

static void imprimir_2dig(uint8_t v) {
    if (v < 10) kputc('0');
    kprint_dec(v);
}

void audit_init(void) {
    log_head = 0;
    log_count = 0;
    log_seq = 0;
}

void audit_registrar(uint8_t nivel, const char *usuario, const char *evento, const char *detalle) {
    int slot = log_head;
    log_head = (log_head + 1) % MAX_LOG;
    if (log_count < MAX_LOG) log_count++;
    log_seq++;

    uint8_t h = 0, m = 0, s = 0;
    reloj_obtener_hora_barra(&h, &m, &s);

    entradas[slot].seq = log_seq;
    entradas[slot].h = h;
    entradas[slot].m = m;
    entradas[slot].s = s;
    entradas[slot].nivel = nivel;
    a_scpy(entradas[slot].usuario, usuario ? usuario : "sistema", 12);
    a_scpy(entradas[slot].evento,  evento  ? evento  : "EVENTO",  14);
    a_scpy(entradas[slot].detalle, detalle ? detalle : "",        40);
}

uint32_t audit_total(void) {
    return (uint32_t)log_count;
}

static uint8_t color_nivel(uint8_t niv) {
    switch (niv) {
        case LOG_OK:    return 0x0A;
        case LOG_WARN:  return 0x0E;
        case LOG_ALERT: return 0x0C;
        default:        return 0x0B;
    }
}

void audit_cmd_log(const char *args, int rol_actual) {
    if (rol_actual != ROL_ADMIN) {
        audit_registrar(LOG_ALERT, kernel_usuario_corto(), "DENEGADO", "Intento de leer auditoria (log)");
        kset_color(0x0C);
        kprint("Permiso denegado: solo el Administrador Argos puede ver la auditoría.\n");
        kset_color(0x07);
        return;
    }

    while (*args == ' ') args++;
    if (a_igual(args, "clear")) {
        audit_init();
        audit_registrar(LOG_WARN, kernel_usuario_corto(), "LOG_CLEAR", "Registro limpiado por admin");
        kprint("Registro de auditoría reiniciado.\n");
        return;
    }

    int mostrar_todos = a_igual(args, "all");
    if (*args != '\0' && !mostrar_todos) {
        kprint("Uso: log | log all | log clear\n");
        return;
    }

    kset_color(0x0D);
    kprint("=== Registro de Auditoría de ARGOS (");
    kprint_dec((uint32_t)log_count);
    kprint(" eventos en memoria) ===\n");
    kset_color(0x0B);
    kprint("#    HORA      USUARIO    EVENTO       DETALLE\n");
    kset_color(0x07);

    if (log_count == 0) {
        kprint("  (sin eventos registrados)\n");
        return;
    }

    int max_ver = mostrar_todos ? log_count : 16;
    int saltar = (log_count > max_ver) ? (log_count - max_ver) : 0;
    int inicio = (log_head - log_count + MAX_LOG) % MAX_LOG;

    for (int i = saltar; i < log_count; i++) {
        int idx = (inicio + i) % MAX_LOG;
        audit_entry_t *e = &entradas[idx];

        kset_color(0x08);
        kprint_dec(e->seq);
        if (e->seq < 10) kprint("    ");
        else if (e->seq < 100) kprint("   ");
        else kprint("  ");

        kset_color(0x07);
        imprimir_2dig(e->h); kputc(':');
        imprimir_2dig(e->m); kputc(':');
        imprimir_2dig(e->s); kprint("  ");

        kset_color(0x0F);
        kprint_pad(e->usuario, 11);

        kset_color(color_nivel(e->nivel));
        kprint_pad(e->evento, 13);

        kset_color(0x07);
        kprint(e->detalle);
        kprint("\n");
    }

    if (saltar > 0) {
        kset_color(0x08);
        kprint("Mostrando últimos 16 eventos. Usa 'log all' para ver todos o 'log clear'.\n");
        kset_color(0x07);
    }
}
