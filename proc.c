/*
 * Modulo 2: Procesos (PCB), Cambio de Contexto Real (ctx_switch) y Planificacion (sched)
 *  - Tabla de PCBs con PID, PPID, Estado (Nuevo/Listo/Ejecucion/Bloqueado/Terminado),
 *    STAT (R/S/Z), Prioridad, CR3, ESP, EIP, tics de CPU y cambios de contexto.
 *  - Demo multitarea real: 3 tareas con pilas propias de 4 KB alternando mediante
 *    ctx_switch() en ensamblador (cpu.s) bajo Round Robin.
 *  - Planificador comparativo (sched): dibuja diagramas de Gantt y calcula tiempos
 *    promedio de Espera (TE) y Retorno (TR) para FCFS, SJF y Round Robin.
 */
#include "proc.h"
#include "reloj.h"

extern void kprint(const char *s);
extern void kputc(char c);
extern void kset_color(uint8_t c);
extern void kclear(void);
extern void kprint_hex(uint32_t v, int digitos);
extern void kprint_dec(uint32_t v);
extern void kprint_pad(const char *s, int ancho);
extern void ctx_switch(uint32_t *old_esp, uint32_t new_esp);

#define C_NORMAL 0x07
#define C_TITULO 0x0B
#define C_MORADO 0x0D
#define C_DATO   0x0F
#define C_OK     0x0A
#define C_ERROR  0x0C
#define C_AMAR   0x0E
#define C_TENUE  0x08

static pcb_t pcbs[MAX_PROCS];

static void p_scpy(char *d, const char *s, int max) {
    int i = 0;
    while (i < max - 1 && s[i]) { d[i] = s[i]; i++; }
    d[i] = '\0';
}

static inline uint32_t leer_cr3(void) {
    uint32_t v;
    __asm__ volatile("mov %%cr3, %0" : "=r"(v));
    return v;
}

static inline uint32_t leer_esp(void) {
    uint32_t v;
    __asm__ volatile("mov %%esp, %0" : "=r"(v));
    return v;
}

static const char *estado_nombre(uint8_t e) {
    switch (e) {
        case PROC_NUEVO: return "Nuevo";
        case PROC_LISTO: return "Listo";
        case PROC_EJEC:  return "Ejecución";
        case PROC_BLOQ:  return "Bloqueado";
        case PROC_TERM:  return "Terminado";
        default:         return "Libre";
    }
}

static char estado_stat(uint8_t e) {
    switch (e) {
        case PROC_EJEC:
        case PROC_LISTO: return 'R';
        case PROC_BLOQ:
        case PROC_NUEVO: return 'S';
        case PROC_TERM:  return 'Z';
        default:         return '-';
    }
}

static uint8_t estado_color(uint8_t e) {
    switch (e) {
        case PROC_EJEC:  return C_OK;
        case PROC_LISTO: return C_TITULO;
        case PROC_BLOQ:  return C_AMAR;
        case PROC_TERM:  return C_TENUE;
        default:         return C_NORMAL;
    }
}

static void registrar_pcb(int slot, uint32_t pid, uint32_t ppid, uint8_t estado,
                          uint8_t prio, uint32_t esp, uint32_t eip, const char *nom) {
    pcbs[slot].pid = pid;
    pcbs[slot].ppid = ppid;
    pcbs[slot].estado = estado;
    pcbs[slot].prioridad = prio;
    pcbs[slot].esp = esp;
    pcbs[slot].eip = eip;
    pcbs[slot].cr3 = leer_cr3();
    pcbs[slot].tics_cpu = 0;
    pcbs[slot].cambios_ctx = 0;
    p_scpy(pcbs[slot].nombre, nom, 16);
}

void proc_init(void) {
    for (int i = 0; i < MAX_PROCS; i++) pcbs[i].estado = PROC_LIBRE;
    uint32_t sp = leer_esp();
    registrar_pcb(0, 0, 0, PROC_BLOQ,  0, sp,         (uint32_t)proc_init,   "kernel/idle");
    registrar_pcb(1, 1, 0, PROC_BLOQ,  1, sp,         (uint32_t)proc_init,   "init/argos");
    registrar_pcb(2, 2, 1, PROC_LISTO, 1, sp,         (uint32_t)reloj_ticks, "reloj_irq0");
    registrar_pcb(3, 3, 1, PROC_EJEC,  2, sp,         (uint32_t)proc_cmd_ps, "shell");
    registrar_pcb(4, 4, 1, PROC_BLOQ,  2, sp,         (uint32_t)proc_init,   "tic340fs");
}

uint32_t proc_activos(void) {
    uint32_t n = 0;
    for (int i = 0; i < MAX_PROCS; i++) {
        if (pcbs[i].estado != PROC_LIBRE && pcbs[i].estado != PROC_TERM) n++;
    }
    return n;
}

static void sincronizar_pcbs_sistema(void) {
    uint32_t tics = reloj_ticks();
    uint32_t sp = leer_esp();
    uint32_t cr3 = leer_cr3();
    for (int i = 0; i < 5; i++) pcbs[i].cr3 = cr3;
    pcbs[0].tics_cpu = (tics > 10) ? (tics * 7) / 10 : tics;
    pcbs[1].tics_cpu = 1;
    pcbs[2].tics_cpu = tics;
    pcbs[3].esp = sp;
    pcbs[3].eip = (uint32_t)proc_cmd_ps;
    pcbs[3].tics_cpu = (tics > 10) ? (tics * 3) / 10 : 1;
    pcbs[3].cambios_ctx++;
}

static int parsear_uint(const char *s, uint32_t *out) {
    while (*s == ' ') s++;
    if (*s < '0' || *s > '9') return -1;
    uint32_t v = 0;
    while (*s >= '0' && *s <= '9') { v = v * 10 + (uint32_t)(*s - '0'); s++; }
    while (*s == ' ') s++;
    if (*s != '\0') return -1;
    *out = v;
    return 0;
}

static void mostrar_pcb_detalle(uint32_t pid) {
    int idx = -1;
    for (int i = 0; i < MAX_PROCS; i++) {
        if (pcbs[i].estado != PROC_LIBRE && pcbs[i].pid == pid) { idx = i; break; }
    }
    if (idx == -1) {
        kprint("Error: no existe un proceso con PID ");
        kprint_dec(pid);
        kprint(".\n");
        return;
    }
    pcb_t *p = &pcbs[idx];
    kset_color(C_MORADO); kprint("=== Ficha del Proceso (PCB) ===\n");
    kset_color(C_TITULO); kprint("  PID / PPID : ");
    kset_color(C_DATO);   kprint_dec(p->pid); kprint(" / "); kprint_dec(p->ppid);
    kset_color(C_TITULO); kprint("    Nombre: ");
    kset_color(C_DATO);   kprint(p->nombre); kprint("\n");

    kset_color(C_TITULO); kprint("  Estado     : ");
    kset_color(estado_color(p->estado));
    kprint(estado_nombre(p->estado));
    kprint(" (STAT="); kputc(estado_stat(p->estado)); kprint(")");
    kset_color(C_TITULO); kprint("    Prioridad: ");
    kset_color(C_DATO);   kprint_dec(p->prioridad); kprint("\n");

    kset_color(C_TITULO); kprint("  Registros  : ");
    kset_color(C_NORMAL); kprint("ESP="); kprint_hex(p->esp, 8);
    kprint("  EIP="); kprint_hex(p->eip, 8);
    kprint("  CR3="); kprint_hex(p->cr3, 8); kprint("\n");

    kset_color(C_TITULO); kprint("  Actividad  : ");
    kset_color(C_NORMAL); kprint("Tics CPU="); kprint_dec(p->tics_cpu);
    kprint("  |  Cambios de contexto="); kprint_dec(p->cambios_ctx); kprint("\n");
}

void proc_cmd_ps(const char *args) {
    sincronizar_pcbs_sistema();
    while (*args == ' ') args++;
    if (args[0] == 'p' && args[1] == 'c' && args[2] == 'b' && (args[3] == ' ' || args[3] == '\0')) {
        uint32_t pid = 0;
        if (parsear_uint(args + 3, &pid) != 0) {
            kprint("Uso: ps pcb <pid>   (ej: ps pcb 3)\n");
            return;
        }
        mostrar_pcb_detalle(pid);
        return;
    } else if (*args != '\0') {
        kprint("Uso: ps | ps pcb <pid>\n");
        return;
    }

    kset_color(C_MORADO);
    kprint("=== Tabla de Procesos (PCB) de ARGOS ===\n");
    kset_color(C_TITULO);
    kprint("PID  PPID  ST  ESTADO      PRIO  CR3         ESP         TICS    NOMBRE\n");
    kset_color(C_NORMAL);

    for (int i = 0; i < MAX_PROCS; i++) {
        if (pcbs[i].estado == PROC_LIBRE) continue;
        pcb_t *p = &pcbs[i];

        kset_color(C_DATO);
        kprint(" "); kprint_dec(p->pid);
        if (p->pid < 10) kprint("   "); else kprint("  ");
        kset_color(C_NORMAL);
        kprint(" "); kprint_dec(p->ppid);
        if (p->ppid < 10) kprint("    "); else kprint("   ");

        kset_color(estado_color(p->estado));
        kputc(estado_stat(p->estado)); kprint("   ");
        kprint_pad(estado_nombre(p->estado), 12);

        kset_color(C_NORMAL);
        kprint(" "); kprint_dec(p->prioridad); kprint("    ");
        kprint_hex(p->cr3, 8); kprint("  ");
        kprint_hex(p->esp, 8); kprint("  ");

        char tbuf[12];
        uint32_t v = p->tics_cpu;
        int n = 0;
        do { tbuf[n++] = (char)('0' + v % 10); v /= 10; } while (v);
        char tstr[12];
        for (int k = 0; k < n; k++) tstr[k] = tbuf[n - 1 - k];
        tstr[n] = '\0';
        kprint_pad(tstr, 8);

        kset_color(p->estado == PROC_EJEC ? C_OK : C_NORMAL);
        kprint(p->nombre);
        kprint("\n");
    }

    kset_color(C_TENUE);
    kprint("STAT: R=Ejecutando/Listo  S=Bloqueado/Dormido  Z=Terminado\n");
    kprint("Más detalle: ps pcb <pid>  |  proc demo  |  sched\n");
    kset_color(C_NORMAL);
}

/* ==================== CAMBIO DE CONTEXTO REAL (proc demo) ==================== */

#define DEMO_N 3
static uint8_t demo_pilas[DEMO_N][4096] __attribute__((aligned(16)));
static uint32_t esp_despachador = 0;
static volatile int demo_slot_actual = -1;
static int demo_pasos_meta[DEMO_N] = { 3, 2, 3 };
static int demo_pasos_hechos[DEMO_N];
static uint32_t demo_cambios_totales = 0;

static void demo_trampolin(void) {
    int slot = demo_slot_actual;
    int idx = slot - 5;
    int meta = demo_pasos_meta[idx];

    for (int paso = 1; paso <= meta; paso++) {
        pcbs[slot].estado = PROC_EJEC;
        pcbs[slot].tics_cpu += 10;
        demo_pasos_hechos[idx] = paso;
        uint32_t sp_actual = leer_esp();

        kset_color(C_TENUE);  kprint("  [Turno ");
        kset_color(C_DATO);   kprint_dec(demo_cambios_totales);
        kset_color(C_TENUE);  kprint("] ");
        kset_color(idx == 0 ? C_TITULO : (idx == 1 ? C_AMAR : C_OK));
        kprint_pad(pcbs[slot].nombre, 9);
        kset_color(C_NORMAL);
        kprint("(PID "); kprint_dec(pcbs[slot].pid);
        kprint(")  ESP="); kprint_hex(sp_actual, 8);
        kprint("  paso "); kprint_dec((uint32_t)paso);
        kputc('/'); kprint_dec((uint32_t)meta);

        if (paso < meta) {
            kset_color(C_TENUE); kprint(" -> Ejecución -> Listo (cediendo CPU)\n");
            kset_color(C_NORMAL);
            pcbs[slot].estado = PROC_LISTO;
            ctx_switch(&pcbs[slot].esp, esp_despachador);
        } else {
            kset_color(C_OK); kprint(" -> Terminado\n");
            kset_color(C_NORMAL);
            pcbs[slot].estado = PROC_TERM;
            ctx_switch(&pcbs[slot].esp, esp_despachador);
        }
    }

    for (;;) ctx_switch(&pcbs[slot].esp, esp_despachador);
}

void proc_cmd_demo(void) {
    static const char *nombres[DEMO_N] = { "tarea_A", "tarea_B", "tarea_C" };
    static const uint8_t prios[DEMO_N] = { 2, 1, 3 };

    kclear();
    kset_color(C_MORADO);
    kprint("=== Demostración real de Cambio de Contexto (Round Robin) ===\n");
    kset_color(C_NORMAL);
    kprint("Se crean 3 procesos con pilas independientes de 4 KB y se alternan con\n");
    kprint("ctx_switch() en ensamblador (cpu.s) guardando y restaurando ESP/EBP/EBX/ESI/EDI:\n\n");

    demo_cambios_totales = 0;
    pcbs[3].estado = PROC_BLOQ; /* shell espera mientras corren las tareas */

    for (int i = 0; i < DEMO_N; i++) {
        int slot = 5 + i;
        demo_pasos_hechos[i] = 0;

        /* Preparar pila inicial: direccion de retorno + 4 registros preservados */
        uint32_t *sp = (uint32_t *)(&demo_pilas[i][4096]);
        *--sp = (uint32_t)demo_trampolin;
        *--sp = 0; /* ebp */
        *--sp = 0; /* ebx */
        *--sp = 0; /* esi */
        *--sp = 0; /* edi */

        registrar_pcb(slot, (uint32_t)slot, 3, PROC_NUEVO, prios[i],
                      (uint32_t)sp, (uint32_t)demo_trampolin, nombres[i]);
        pcbs[slot].estado = PROC_LISTO;
    }

    int activos = DEMO_N;
    while (activos > 0) {
        activos = 0;
        for (int i = 0; i < DEMO_N; i++) {
            int slot = 5 + i;
            if (pcbs[slot].estado == PROC_LISTO) {
                activos++;
                demo_slot_actual = slot;
                demo_cambios_totales++;
                pcbs[slot].cambios_ctx++;
                ctx_switch(&esp_despachador, pcbs[slot].esp);
            }
        }
    }

    pcbs[3].estado = PROC_EJEC;
    pcbs[3].cambios_ctx++;

    kprint("\n");
    kset_color(C_TITULO); kprint("Resumen: ");
    kset_color(C_OK);     kprint("3 procesos completados");
    kset_color(C_NORMAL); kprint(" | Cambios de contexto reales: ");
    kset_color(C_DATO);   kprint_dec(demo_cambios_totales * 2);
    kset_color(C_NORMAL); kprint(" (ida y vuelta)\n");
    kset_color(C_TENUE);
    kprint("Escribe 'ps' para ver sus PCB actualizados o 'ps pcb 5' para inspeccionar tarea_A.\n");
    kset_color(C_NORMAL);
}

/* ==================== PLANIFICACION DE CPU (sched) ==================== */

#define MAX_SP   5
#define MAX_TIME 30

typedef struct {
    char id;
    int llegada;
    int rafaga;
} sp_t;

typedef struct {
    int8_t gantt[MAX_TIME];
    int total_t;
    int te[MAX_SP];
    int tr[MAX_SP];
    int sum_te;
    int sum_tr;
} sched_res_t;

static void sim_fcfs(const sp_t *p, int n, sched_res_t *r) {
    int hecho[MAX_SP] = {0};
    int t = 0, comp = 0;
    r->sum_te = 0; r->sum_tr = 0;

    while (comp < n && t < MAX_TIME) {
        int sel = -1;
        for (int i = 0; i < n; i++) {
            if (!hecho[i] && p[i].llegada <= t) {
                if (sel == -1 || p[i].llegada < p[sel].llegada) sel = i;
            }
        }
        if (sel == -1) {
            r->gantt[t++] = -1;
            continue;
        }
        for (int k = 0; k < p[sel].rafaga && t < MAX_TIME; k++) {
            r->gantt[t++] = (int8_t)sel;
        }
        hecho[sel] = 1;
        comp++;
        r->tr[sel] = t - p[sel].llegada;
        r->te[sel] = r->tr[sel] - p[sel].rafaga;
        r->sum_te += r->te[sel];
        r->sum_tr += r->tr[sel];
    }
    r->total_t = t;
}

static void sim_sjf(const sp_t *p, int n, sched_res_t *r) {
    int hecho[MAX_SP] = {0};
    int t = 0, comp = 0;
    r->sum_te = 0; r->sum_tr = 0;

    while (comp < n && t < MAX_TIME) {
        int sel = -1;
        for (int i = 0; i < n; i++) {
            if (!hecho[i] && p[i].llegada <= t) {
                if (sel == -1 || p[i].rafaga < p[sel].rafaga ||
                    (p[i].rafaga == p[sel].rafaga && p[i].llegada < p[sel].llegada)) {
                    sel = i;
                }
            }
        }
        if (sel == -1) {
            r->gantt[t++] = -1;
            continue;
        }
        for (int k = 0; k < p[sel].rafaga && t < MAX_TIME; k++) {
            r->gantt[t++] = (int8_t)sel;
        }
        hecho[sel] = 1;
        comp++;
        r->tr[sel] = t - p[sel].llegada;
        r->te[sel] = r->tr[sel] - p[sel].rafaga;
        r->sum_te += r->te[sel];
        r->sum_tr += r->tr[sel];
    }
    r->total_t = t;
}

static void sim_rr(const sp_t *p, int n, int q, sched_res_t *r) {
    int rem[MAX_SP], en_cola[MAX_SP];
    int cola[64], head = 0, tail = 0;
    int t = 0, comp = 0;
    r->sum_te = 0; r->sum_tr = 0;

    for (int i = 0; i < n; i++) { rem[i] = p[i].rafaga; en_cola[i] = 0; }

    for (int i = 0; i < n; i++) {
        if (p[i].llegada == 0) { cola[tail++ & 63] = i; en_cola[i] = 1; }
    }

    while (comp < n && t < MAX_TIME) {
        if (head == tail) {
            r->gantt[t++] = -1;
            for (int i = 0; i < n; i++) {
                if (!en_cola[i] && rem[i] > 0 && p[i].llegada <= t) {
                    cola[tail++ & 63] = i;
                    en_cola[i] = 1;
                }
            }
            continue;
        }
        int cur = cola[head++ & 63];
        int paso = (rem[cur] < q) ? rem[cur] : q;
        for (int k = 0; k < paso && t < MAX_TIME; k++) {
            r->gantt[t++] = (int8_t)cur;
            for (int i = 0; i < n; i++) {
                if (!en_cola[i] && rem[i] > 0 && p[i].llegada <= t) {
                    cola[tail++ & 63] = i;
                    en_cola[i] = 1;
                }
            }
        }
        rem[cur] -= paso;
        if (rem[cur] == 0) {
            comp++;
            r->tr[cur] = t - p[cur].llegada;
            r->te[cur] = r->tr[cur] - p[cur].rafaga;
            r->sum_te += r->te[cur];
            r->sum_tr += r->tr[cur];
        } else {
            cola[tail++ & 63] = cur;
        }
    }
    r->total_t = t;
}

static uint8_t color_proc(int idx) {
    static const uint8_t cols[MAX_SP] = { 0x0B, 0x0E, 0x0A, 0x0D, 0x0F };
    if (idx < 0 || idx >= MAX_SP) return C_TENUE;
    return cols[idx];
}

static void imprimir_prom(int suma, int n) {
    int dec = (suma * 10 + n / 2) / n;
    kprint_dec((uint32_t)(dec / 10));
    kputc('.');
    kprint_dec((uint32_t)(dec % 10));
}

static void imprimir_gantt(const char *etiq, const sched_res_t *r, const sp_t *p) {
    kset_color(C_TITULO);
    kprint_pad(etiq, 8);
    for (int t = 0; t < r->total_t; t++) {
        int id = r->gantt[t];
        kset_color(color_proc(id));
        kputc(id < 0 ? '-' : p[id].id);
        kputc(' ');
    }
    kset_color(C_NORMAL);
    kprint("\n");
}

static void imprimir_par(int a, int b) {
    char buf[16];
    int pos = 0;
    if (a >= 10) buf[pos++] = (char)('0' + a / 10);
    buf[pos++] = (char)('0' + a % 10);
    buf[pos++] = ' '; buf[pos++] = '/'; buf[pos++] = ' ';
    if (b >= 10) buf[pos++] = (char)('0' + b / 10);
    buf[pos++] = (char)('0' + b % 10);
    buf[pos] = '\0';
    kprint_pad(buf, 12);
}

void proc_cmd_sched(const char *args) {
    static const sp_t def[4] = {
        { 'A', 0, 5 }, { 'B', 1, 3 }, { 'C', 2, 4 }, { 'D', 4, 2 }
    };
    sp_t procs[MAX_SP];
    int n = 4;
    int q = 2;

    while (*args == ' ') args++;
    if (*args == '\0') {
        for (int i = 0; i < 4; i++) procs[i] = def[i];
    } else {
        /* Primer argumento: quantum q */
        const char *s = args;
        if (*s < '0' || *s > '9') {
            kprint("Uso: sched [q] [lleg,raf ...]  (ej: sched 3 0,5 1,3)\n");
            return;
        }
        q = 0;
        while (*s >= '0' && *s <= '9') { q = q * 10 + (*s - '0'); s++; }
        if (q < 1 || q > 10 || (*s != '\0' && *s != ' ')) {
            kprint("Error: el quantum q debe estar entre 1 y 10.\n");
            return;
        }
        while (*s == ' ') s++;
        if (*s == '\0') {
            for (int i = 0; i < 4; i++) procs[i] = def[i];
        } else {
            n = 0;
            int total_est = 0;
            while (*s) {
                while (*s == ' ') s++;
                if (!*s) break;
                if (n >= MAX_SP) { kprint("Error: máximo 5 procesos (A-E).\n"); return; }
                if (*s < '0' || *s > '9') { kprint("Uso: sched <q> <lleg,raf>... (ej: sched 3 0,5 1,3)\n"); return; }
                int ll = 0;
                while (*s >= '0' && *s <= '9') { ll = ll * 10 + (*s - '0'); s++; }
                if (*s != ',') { kprint("Error: separa llegada y ráfaga con coma (ej: 0,5).\n"); return; }
                s++;
                if (*s < '0' || *s > '9') { kprint("Error: falta la ráfaga tras la coma.\n"); return; }
                int rf = 0;
                while (*s >= '0' && *s <= '9') { rf = rf * 10 + (*s - '0'); s++; }
                if (*s != '\0' && *s != ' ') { kprint("Error de formato en procesos.\n"); return; }
                if (rf < 1 || rf > 15 || ll > 15) {
                    kprint("Error: llegada (0-15) y ráfaga (1-15) fuera de rango.\n");
                    return;
                }
                procs[n].id = (char)('A' + n);
                procs[n].llegada = ll;
                procs[n].rafaga = rf;
                if (ll > total_est) total_est = ll;
                total_est += rf;
                n++;
            }
            if (n < 2) { kprint("Error: ingresa al menos 2 procesos (ej: sched 3 0,5 1,3).\n"); return; }
            if (total_est > MAX_TIME) {
                kprint("Error: el tiempo total no debe superar 30 unidades.\n");
                return;
            }
        }
    }

    sched_res_t r_fcfs, r_sjf, r_rr;
    sim_fcfs(procs, n, &r_fcfs);
    sim_sjf(procs, n, &r_sjf);
    sim_rr(procs, n, q, &r_rr);

    kclear();
    kset_color(C_MORADO);
    kprint("=== Planificación de CPU: FCFS, SJF y Round Robin ===\n");
    kset_color(C_NORMAL);
    kprint("Procesos (llegada,ráfaga): ");
    for (int i = 0; i < n; i++) {
        kset_color(color_proc(i));
        kputc(procs[i].id);
        kset_color(C_NORMAL);
        kputc('('); kprint_dec((uint32_t)procs[i].llegada);
        kputc(','); kprint_dec((uint32_t)procs[i].rafaga);
        kprint(") ");
    }
    kset_color(C_TITULO); kprint("| q=");
    kset_color(C_DATO);   kprint_dec((uint32_t)q);
    kset_color(C_NORMAL); kprint("\n\n");

    int tmax = r_fcfs.total_t;
    kset_color(C_TENUE);
    kprint("Tiempo  ");
    for (int t = 0; t <= tmax; t += 2) {
        kprint_dec((uint32_t)t);
        if (t < 10) kprint("   ");
        else kprint("  ");
    }
    kprint("\n");

    char rr_lbl[10] = "RR q=0";
    if (q < 10) { rr_lbl[5] = (char)('0' + q); rr_lbl[6] = '\0'; }
    else { rr_lbl[5] = '1'; rr_lbl[6] = '0'; rr_lbl[7] = '\0'; }

    imprimir_gantt("FCFS", &r_fcfs, procs);
    imprimir_gantt("SJF",  &r_sjf,  procs);
    imprimir_gantt(rr_lbl, &r_rr,   procs);

    kprint("\n");
    kset_color(C_TITULO);
    kprint("Algoritmo    Política        Espera prom. (TE)   Retorno prom. (TR)\n");
    kset_color(C_NORMAL);

    kprint("FCFS         No apropiativo  ");
    kset_color(C_DATO); imprimir_prom(r_fcfs.sum_te, n); kset_color(C_NORMAL);
    kprint("                 ");
    kset_color(C_DATO); imprimir_prom(r_fcfs.sum_tr, n); kset_color(C_NORMAL); kprint("\n");

    kprint("SJF          No apropiativo  ");
    kset_color(C_OK); imprimir_prom(r_sjf.sum_te, n); kset_color(C_NORMAL);
    kprint("                 ");
    kset_color(C_OK); imprimir_prom(r_sjf.sum_tr, n); kset_color(C_NORMAL); kprint("\n");

    kprint_pad(rr_lbl, 13); kprint("Apropiativo     ");
    kset_color(C_AMAR); imprimir_prom(r_rr.sum_te, n); kset_color(C_NORMAL);
    kprint("                 ");
    kset_color(C_AMAR); imprimir_prom(r_rr.sum_tr, n); kset_color(C_NORMAL); kprint("\n");

    kprint("\n");
    kset_color(C_TITULO);
    kprint("Proc  Lleg  Ráf  | FCFS(TE/TR) | SJF(TE/TR)  | RR(TE/TR)\n");
    kset_color(C_NORMAL);
    for (int i = 0; i < n; i++) {
        kprint(" ");
        kset_color(color_proc(i)); kputc(procs[i].id);
        kset_color(C_NORMAL); kprint("     ");
        kprint_dec((uint32_t)procs[i].llegada);
        kprint(procs[i].llegada < 10 ? "     " : "    ");
        kprint_dec((uint32_t)procs[i].rafaga);
        kprint(procs[i].rafaga < 10 ? "    | " : "   | ");
        imprimir_par(r_fcfs.te[i], r_fcfs.tr[i]); kprint("| ");
        imprimir_par(r_sjf.te[i],  r_sjf.tr[i]);  kprint("| ");
        imprimir_par(r_rr.te[i],   r_rr.tr[i]);   kprint("\n");
    }

    kset_color(C_TENUE);
    kprint("Ejemplo personalizado: sched 3 0,5 1,3   (quantum 3, A(0,5) B(1,3))\n");
    kset_color(C_NORMAL);
}
