#include "mem.h"
#include "reloj.h"

extern void kprint(const char *s);
extern void kputc(char c);
extern void kset_color(uint8_t c);
extern void kclear(void);
extern void kprint_hex(uint32_t v, int digitos);
extern void kprint_dec(uint32_t v);
extern void kprint_pad(const char *s, int ancho);
extern void gdt_flush(void *gdtr);
extern void idt_load(void *idtr);
extern uint32_t isr_tabla[32];
extern uint32_t irq_tabla[16];
extern char _kernel_start[], _kernel_end[];

#define C_NORMAL 0x07
#define C_TITULO 0x0B
#define C_MORADO 0x0D
#define C_DATO   0x0F
#define C_OK     0x0A
#define C_ERROR  0x0C
#define C_NUEVO  0x0E
#define C_TENUE  0x08

void *memset(void *d, int c, __SIZE_TYPE__ n) {
    uint8_t *p = (uint8_t *)d;
    while (n--) *p++ = (uint8_t)c;
    return d;
}
void *memcpy(void *d, const void *s, __SIZE_TYPE__ n) {
    uint8_t *a = (uint8_t *)d;
    const uint8_t *b = (const uint8_t *)s;
    while (n--) *a++ = *b++;
    return d;
}

#define barrera() __asm__ volatile("" ::: "memory")

typedef struct __attribute__((packed)) {
    uint16_t limite_bajo;
    uint16_t base_baja;
    uint8_t  base_media;
    uint8_t  acceso;
    uint8_t  granularidad;
    uint8_t  base_alta;
} gdt_entrada_t;

typedef struct __attribute__((packed)) {
    uint16_t limite;
    uint32_t base;
} dtr_t;

#define GDT_N 6
#define SEL_DEMO 0x28
#define DEMO_BASE 0x00300000u
#define DEMO_LIMITE 0x0FFFFu

static gdt_entrada_t gdt[GDT_N];
static dtr_t gdtr;
static const char *gdt_desc[GDT_N] = {
    "Nulo (obligatorio)", "Código del kernel", "Datos y pila kernel",
    "Código de usuario", "Datos de usuario", "Segmento de demostración"
};

static void gdt_set(int i, uint32_t base, uint32_t limite, uint8_t acceso, uint8_t flags) {
    gdt[i].limite_bajo = (uint16_t)(limite & 0xFFFF);
    gdt[i].base_baja = (uint16_t)(base & 0xFFFF);
    gdt[i].base_media = (uint8_t)((base >> 16) & 0xFF);
    gdt[i].acceso = acceso;
    gdt[i].granularidad = (uint8_t)(((limite >> 16) & 0x0F) | (flags & 0xF0));
    gdt[i].base_alta = (uint8_t)((base >> 24) & 0xFF);
}

static uint32_t gdt_base(int i) {
    return (uint32_t)gdt[i].base_baja | ((uint32_t)gdt[i].base_media << 16) |
           ((uint32_t)gdt[i].base_alta << 24);
}

static uint32_t gdt_limite(int i) {
    return (uint32_t)gdt[i].limite_bajo | ((uint32_t)(gdt[i].granularidad & 0x0F) << 16);
}

void gdt_init(void) {
    gdt_set(0, 0, 0, 0, 0);
    gdt_set(1, 0, 0xFFFFF, 0x9A, 0xC0);
    gdt_set(2, 0, 0xFFFFF, 0x92, 0xC0);
    gdt_set(3, 0, 0xFFFFF, 0xFA, 0xC0);
    gdt_set(4, 0, 0xFFFFF, 0xF2, 0xC0);
    gdt_set(5, DEMO_BASE, DEMO_LIMITE, 0x92, 0x40);
    gdtr.limite = (uint16_t)(sizeof(gdt) - 1);
    gdtr.base = (uint32_t)gdt;
    gdt_flush(&gdtr);
}

typedef struct __attribute__((packed)) {
    uint16_t offset_bajo;
    uint16_t selector;
    uint8_t  cero;
    uint8_t  tipo;
    uint16_t offset_alto;
} idt_entrada_t;

typedef struct {
    uint32_t edi, esi, ebp, esp, ebx, edx, ecx, eax;
    uint32_t vector, error;
    uint32_t eip, cs, eflags;
} regs_t;

static idt_entrada_t idt[256];
static dtr_t idtr;

static const char *nombres_exc[32] = {
    "División por cero", "Depuración", "NMI", "Breakpoint", "Desbordamiento",
    "Fuera de rango", "Opcode inválido", "Dispositivo no disponible",
    "Doble falta", "Coprocesador", "TSS inválido", "Segmento no presente",
    "Fallo de pila", "Protección general (#GP)", "Fallo de página (#PF)",
    "Reservada", "Error de coma flotante", "Alineación", "Machine check",
    "SIMD", "Virtualización", "Control", "Reservada", "Reservada", "Reservada",
    "Reservada", "Reservada", "Reservada", "Reservada", "Reservada",
    "Seguridad", "Reservada"
};

static void idt_set_gate(int vec, uint32_t off) {
    idt[vec].offset_bajo = (uint16_t)(off & 0xFFFF);
    idt[vec].selector = 0x08;
    idt[vec].cero = 0;
    idt[vec].tipo = 0x8E;
    idt[vec].offset_alto = (uint16_t)(off >> 16);
}

void idt_init(void) {
    for (int i = 0; i < 32; i++) idt_set_gate(i, isr_tabla[i]);
    for (int i = 0; i < 16; i++) idt_set_gate(32 + i, irq_tabla[i]);
    idtr.limite = (uint16_t)(sizeof(idt) - 1);
    idtr.base = (uint32_t)idt;
    idt_load(&idtr);
}

static void detener(const char *motivo, regs_t *r) {
    kset_color(0x4F);
    kprint("\n EXCEPCIÓN ");
    kprint_dec(r->vector);
    kprint(": ");
    kprint(motivo);
    kprint(" | EIP=");
    kprint_hex(r->eip, 8);
    kprint(" error=");
    kprint_hex(r->error, 2);
    kprint(" \n Sistema detenido. Reinicia la máquina virtual. ");
    kset_color(C_NORMAL);
    for (;;) __asm__ volatile("cli; hlt");
}

#define VBASE    0x40000000u
#define NPAG     10
#define MAXM     4
#define MAXR     20
#define PG_P     0x01
#define PG_RW    0x02
#define PG_A     0x20
#define PG_D     0x40
#define FIRMA(p) (0xA9050000u | (uint32_t)(p))

static uint32_t dir_paginas[1024] __attribute__((aligned(4096)));
static uint32_t tabla_identidad[1024] __attribute__((aligned(4096)));
static uint32_t tabla_virtual[1024] __attribute__((aligned(4096)));
static uint32_t tabla_mmio[1024] __attribute__((aligned(4096)));
static uint8_t marcos[MAXM][4096] __attribute__((aligned(4096)));
static uint8_t swap_area[NPAG][4096] __attribute__((aligned(4096)));

static uint32_t ram_total_kb;
static volatile uint32_t pf_total, pf_corrida, swap_escrituras;
static volatile uint32_t ult_cr2, ult_error;

static volatile int marco_pag[MAXM];
static int n_marcos = 3;
static int algoritmo;
static uint32_t t_carga[NPAG], t_uso[NPAG];
static uint32_t reloj;
static int refs[MAXR];
static int nrefs, idx_ref;

static inline void invlpg(uint32_t dir) {
    __asm__ volatile("invlpg (%0)" : : "r"(dir) : "memory");
}

static inline uint32_t leer_cr0(void) { uint32_t v; __asm__ volatile("mov %%cr0, %0" : "=r"(v)); return v; }
static inline uint32_t leer_cr2(void) { uint32_t v; __asm__ volatile("mov %%cr2, %0" : "=r"(v)); return v; }
static inline uint32_t leer_cr3(void) { uint32_t v; __asm__ volatile("mov %%cr3, %0" : "=r"(v)); return v; }

void paginacion_init(uint32_t ram_kb) {
    ram_total_kb = ram_kb;
    for (int i = 0; i < 1024; i++) {
        dir_paginas[i] = 0;
        tabla_virtual[i] = 0;
        tabla_identidad[i] = ((uint32_t)i * 4096u) | PG_P | PG_RW;
    }
    tabla_identidad[0] = 0;
    dir_paginas[0] = (uint32_t)tabla_identidad | PG_P | PG_RW;
    dir_paginas[VBASE >> 22] = (uint32_t)tabla_virtual | PG_P | PG_RW;
    for (int f = 0; f < MAXM; f++) marco_pag[f] = -1;

    __asm__ volatile("mov %0, %%cr3" : : "r"((uint32_t)dir_paginas) : "memory");
    uint32_t cr0 = leer_cr0() | 0x80000000u;
    __asm__ volatile("mov %0, %%cr0" : : "r"(cr0) : "memory");
}

static void copiar_pagina(uint8_t *dst, const uint8_t *src) {
    uint32_t *d = (uint32_t *)dst;
    const uint32_t *s = (const uint32_t *)src;
    for (int i = 0; i < 1024; i++) d[i] = s[i];
}

static int elegir_victima(void) {
    int mejor = 0;
    if (algoritmo == 2) {
        int dist_mejor = -1;
        for (int f = 0; f < n_marcos; f++) {
            int q = marco_pag[f], d = 1000;
            for (int j = idx_ref + 1; j < nrefs; j++)
                if (refs[j] == q) { d = j; break; }
            if (d > dist_mejor) { dist_mejor = d; mejor = f; }
        }
        return mejor;
    }
    uint32_t menor = 0xFFFFFFFFu;
    for (int f = 0; f < n_marcos; f++) {
        int q = marco_pag[f];
        uint32_t t = (algoritmo == 0) ? t_carga[q] : t_uso[q];
        if (t < menor) { menor = t; mejor = f; }
    }
    return mejor;
}

static void pf_manejador(regs_t *r) {
    uint32_t cr2 = leer_cr2();
    ult_cr2 = cr2;
    ult_error = r->error;
    if (cr2 < VBASE || cr2 >= VBASE + NPAG * 4096u || (r->error & PG_P)) {
        detener(cr2 < 4096 ? "Fallo de página: puntero nulo" : "Fallo de página no válido", r);
    }
    int pag = (int)((cr2 - VBASE) >> 12);
    pf_total++;
    pf_corrida++;

    int m = -1;
    for (int f = 0; f < n_marcos; f++)
        if (marco_pag[f] == -1) { m = f; break; }
    if (m == -1) {
        m = elegir_victima();
        int v = marco_pag[m];
        if (tabla_virtual[v] & PG_D) {
            copiar_pagina(swap_area[v], marcos[m]);
            swap_escrituras++;
        }
        tabla_virtual[v] = 0;
        invlpg(VBASE + (uint32_t)v * 4096u);
    }
    copiar_pagina(marcos[m], swap_area[pag]);
    marco_pag[m] = pag;
    t_carga[pag] = reloj;
    t_uso[pag] = reloj;
    tabla_virtual[pag] = (uint32_t)marcos[m] | PG_P | PG_RW;
    invlpg(cr2 & ~0xFFFu);
}

void isr_manejador(regs_t *r) {
    if (r->vector == 14) { pf_manejador(r); return; }
    detener(nombres_exc[r->vector & 31], r);
}

static int traducir(uint32_t lineal, uint32_t *fisica, uint32_t *tabla) {
    uint32_t pde = dir_paginas[lineal >> 22];
    if (!(pde & PG_P)) return -1;
    uint32_t *pt = (uint32_t *)(pde & ~0xFFFu);
    uint32_t pte = pt[(lineal >> 12) & 0x3FF];
    if (!(pte & PG_P)) return -1;
    *tabla = pde & ~0xFFFu;
    *fisica = (pte & ~0xFFFu) | (lineal & 0xFFF);
    return 0;
}

static uint16_t leer_seg(int cual) {
    uint16_t v = 0;
    switch (cual) {
        case 0: __asm__ volatile("mov %%cs, %0" : "=r"(v)); break;
        case 1: __asm__ volatile("mov %%ds, %0" : "=r"(v)); break;
        case 2: __asm__ volatile("mov %%ss, %0" : "=r"(v)); break;
        case 3: __asm__ volatile("mov %%es, %0" : "=r"(v)); break;
        case 4: __asm__ volatile("mov %%fs, %0" : "=r"(v)); break;
        default: __asm__ volatile("mov %%gs, %0" : "=r"(v)); break;
    }
    return v;
}

static void imprimir_registros_seg(void) {
    static const char *nom[6] = { "CS=", "DS=", "SS=", "ES=", "FS=", "GS=" };
    kprint("  ");
    for (int i = 0; i < 6; i++) {
        kset_color(C_TENUE); kprint(nom[i]);
        kset_color(C_DATO); kprint_hex(leer_seg(i), 4);
        kprint("  ");
    }
    kset_color(C_NORMAL);
    kprint("\n");
}

static void titulo(const char *t) {
    kset_color(C_MORADO);
    kprint(t);
    kset_color(C_NORMAL);
    kprint("\n");
}

static void etiqueta(const char *t) {
    kset_color(C_TITULO);
    kprint(t);
    kset_color(C_NORMAL);
}

static void mem_resumen(void) {
    titulo("=== Gestión de memoria de ARGOS ===");
    uint32_t ini = (uint32_t)_kernel_start, fin = (uint32_t)_kernel_end;
    etiqueta("RAM detectada: ");
    kprint_dec(ram_total_kb / 1024); kprint(" MB");
    etiqueta("   Kernel: ");
    kprint_hex(ini, 8); kprint(" - "); kprint_hex(fin, 8);
    kprint(" ("); kprint_dec((fin - ini) / 1024); kprint(" KB)\n");

    etiqueta("Segmentación: ");
    kprint("GDT con "); kprint_dec(GDT_N);
    kprint(" descriptores en "); kprint_hex(gdtr.base, 8);
    kprint(" (modelo plano 4 GB + demo)\n");
    imprimir_registros_seg();

    uint32_t cr0 = leer_cr0();
    int tablas = 0;
    for (int i = 0; i < 1024; i++) if (dir_paginas[i] & PG_P) tablas++;
    etiqueta("Paginación: ");
    if (cr0 & 0x80000000u) { kset_color(C_OK); kprint("ACTIVA"); }
    else { kset_color(C_ERROR); kprint("INACTIVA"); }
    kset_color(C_NORMAL);
    kprint(" (CR0.PG=1)  CR3="); kprint_hex(leer_cr3(), 8);
    kprint("  páginas de 4 KB\n");
    kprint("  Tablas de páginas activas: "); kprint_dec((uint32_t)tablas);
    kprint(" | mapeo identidad 0-4 MB | página 0 sin mapear\n");
    kprint("  Memoria virtual: "); kprint_hex(VBASE, 8);
    kprint(", "); kprint_dec(NPAG); kprint(" páginas, hasta ");
    kprint_dec(MAXM); kprint(" marcos físicos, swap en RAM\n");

    etiqueta("Interrupciones: ");
    kprint("IDT 48 vectores (0-31 CPU, 32-47 PIC) | #PF: ");
    kset_color(C_DATO); kprint_dec(pf_total); kset_color(C_NORMAL);
    kprint(" | IRQ0: ");
    kset_color(C_OK); kprint_dec(reloj_ticks()); kset_color(C_NORMAL);
    kprint("\n");
    if (pf_total > 0) {
        kprint("  Último fallo: CR2="); kprint_hex(ult_cr2, 8);
        kprint("  error="); kprint_hex(ult_error, 2);
        kprint((ult_error & 2) ? " (página no presente, escritura)\n"
                               : " (página no presente, lectura)\n");
    }
    kprint("\n");
    etiqueta("Más detalle: ");
    kprint("mem seg  |  mem pag <marcos> <páginas>  (ej: mem pag 3 7 0 1 2 0)\n");
}

static void mem_seg(void) {
    kclear();
    titulo("=== Segmentación: tabla GDT leída de memoria ===");
    kset_color(C_TITULO);
    kprint("Selector  Base        Límite   Gran.  Tipo    DPL  Descripción\n");
    kset_color(C_NORMAL);
    for (int i = 0; i < GDT_N; i++) {
        kprint("  "); kprint_hex((uint32_t)(i * 8), 2); kprint("    ");
        if (i == 0) {
            kprint("-           -        -      -       -    ");
        } else {
            uint8_t acc = gdt[i].acceso;
            int gran4k = (gdt[i].granularidad & 0x80) != 0;
            kprint_hex(gdt_base(i), 8); kprint("  ");
            kprint_hex(gdt_limite(i), 5); kprint("  ");
            kprint_pad(gran4k ? "4 KB" : "byte", 7);
            kprint_pad((acc & 0x08) ? "Código" : "Datos", 8);
            kprint_dec((acc >> 5) & 3); kprint("    ");
        }
        kprint(gdt_desc[i]);
        kprint("\n");
    }
    dtr_t actual;
    __asm__ volatile("sgdt %0" : "=m"(actual));
    kprint("GDTR (sgdt): base="); kprint_hex(actual.base, 8);
    kprint("  límite="); kprint_dec(actual.limite); kprint(" bytes\n");
    imprimir_registros_seg();

    const uint32_t desp = 0x100;
    uint32_t w0 = 0x4F475241u;
    uint32_t w1 = 0x00000053u;
    uint16_t fs_viejo = leer_seg(4);
    __asm__ volatile("mov %0, %%fs" : : "r"((uint16_t)SEL_DEMO));
    __asm__ volatile("movl %0, %%fs:(%1)" : : "r"(w0), "r"(desp) : "memory");
    __asm__ volatile("movl %0, %%fs:4(%1)" : : "r"(w1), "r"(desp) : "memory");
    __asm__ volatile("mov %0, %%fs" : : "r"(fs_viejo));

    uint32_t lineal = gdt_base(5) + desp, fisica = 0, tabla = 0;
    kprint("\n");
    titulo("Traducción real de una dirección (lógica -> lineal -> física):");
    kprint("  Se cargó FS="); kprint_hex(SEL_DEMO, 2);
    kprint(" y se escribió \"ARGOS\" en FS:"); kprint_hex(desp, 4); kprint("\n");
    etiqueta("  Lógica  "); kprint_hex(SEL_DEMO, 4); kprint(":"); kprint_hex(desp, 8);
    kprint("\n");
    etiqueta("  Lineal  "); kprint_hex(lineal, 8);
    kprint("  = base del segmento "); kprint_hex(gdt_base(5), 8);
    kprint(" + desplazamiento\n");
    if (traducir(lineal, &fisica, &tabla) == 0) {
        etiqueta("  Página  ");
        kprint("PDE["); kprint_dec(lineal >> 22); kprint("] -> tabla ");
        kprint_hex(tabla, 8); kprint(", PTE["); kprint_dec((lineal >> 12) & 0x3FF);
        kprint("], offset "); kprint_hex(lineal & 0xFFF, 3); kprint("\n");
        etiqueta("  Física  "); kprint_hex(fisica, 8);
        kprint("  contenido leído: \"");
        const char *p = (const char *)fisica;
        for (int i = 0; i < 8 && p[i]; i++) kputc(p[i]);
        kprint("\"\n");
    }
    kprint("  Límite del segmento: "); kprint_hex(gdt_limite(5), 5);
    kprint(" -> acceder a FS:10000 provocaría #GP (vector 13)\n");
}

static int8_t tabla_estado[3][MAXR][MAXM];
static uint8_t hubo_fallo[3][MAXR];
static uint32_t fallos_alg[3];
static int datos_ok[3];
static uint32_t usos[NPAG];

static void ejecutar_algoritmo(int a) {
    algoritmo = a;
    reloj = 0;
    pf_corrida = 0;
    for (int f = 0; f < MAXM; f++) marco_pag[f] = -1;
    for (int p = 0; p < NPAG; p++) {
        uint32_t *s = (uint32_t *)swap_area[p];
        s[0] = FIRMA(p);
        s[1] = 0;
        usos[p] = 0;
        tabla_virtual[p] = 0;
        invlpg(VBASE + (uint32_t)p * 4096u);
    }
    int ok = 1;
    for (int i = 0; i < nrefs; i++) {
        idx_ref = i;
        int p = refs[i];
        uint32_t antes = pf_corrida;
        volatile uint32_t *v = (volatile uint32_t *)(VBASE + (uint32_t)p * 4096u);
        if (v[0] != FIRMA(p)) ok = 0;
        v[1] = v[1] + 1;
        usos[p]++;
        barrera();
        reloj++;
        /* Registra el uso reciente para LRU y limpia el bit Accessed (A) de la PTE */
        t_uso[p] = reloj;
        for (int f = 0; f < n_marcos; f++) {
            int q = marco_pag[f];
            if (q >= 0 && (tabla_virtual[q] & PG_A)) {
                t_uso[q] = reloj;
                tabla_virtual[q] &= ~PG_A;
                invlpg(VBASE + (uint32_t)q * 4096u);
            }
        }
        for (int f = 0; f < MAXM; f++) tabla_estado[a][i][f] = (int8_t)marco_pag[f];
        hubo_fallo[a][i] = (uint8_t)(pf_corrida != antes);
    }
    for (int p = 0; p < NPAG; p++) {
        const uint32_t *src = (const uint32_t *)swap_area[p];
        for (int f = 0; f < n_marcos; f++)
            if (marco_pag[f] == p) src = (const uint32_t *)marcos[f];
        if (src[0] != FIRMA(p) || src[1] != usos[p]) ok = 0;
    }
    fallos_alg[a] = pf_corrida;
    datos_ok[a] = ok;
}

static void imprimir_algoritmo(int a, const char *nombre) {
    kset_color(C_TITULO);
    kprint_pad(nombre, 7);
    for (int i = 0; i < nrefs; i++) kprint("---");
    kprint(" ");
    kset_color(C_DATO);
    kprint_dec(fallos_alg[a]);
    kprint(" fallos\n");
    for (int f = 0; f < n_marcos; f++) {
        kset_color(C_TENUE);
        kprint(" M"); kprint_dec((uint32_t)f); kprint("    ");
        for (int i = 0; i < nrefs; i++) {
            int val = tabla_estado[a][i][f];
            int previo = (i > 0) ? tabla_estado[a][i - 1][f] : -1;
            kprint("  ");
            if (val < 0) { kset_color(C_TENUE); kputc('.'); }
            else {
                kset_color((hubo_fallo[a][i] && val != previo) ? C_NUEVO : C_NORMAL);
                kputc((char)('0' + val));
            }
        }
        kprint("\n");
    }
    kset_color(C_NORMAL);
}

static void mem_pag(const char *args) {
    static const int def[] = { 7, 0, 1, 2, 0, 3, 0, 4, 2, 3, 0, 3, 2, 1, 2 };
    int numeros[MAXR + 1];
    int n = 0;
    const char *p = args;
    while (*p) {
        while (*p == ' ') p++;
        if (!*p) break;
        if (*p < '0' || *p > '9') { n = -1; break; }
        int v = 0;
        while (*p >= '0' && *p <= '9') { v = v * 10 + (*p - '0'); p++; }
        if (*p && *p != ' ') { n = -1; break; }
        if (n > MAXR) { n = -2; break; }
        numeros[n++] = v;
    }
    if (n == -1 || n == 1) {
        kprint("Uso: mem pag <marcos 1-4> <páginas 0-9...>   (ej: mem pag 3 7 0 1 2 0 3 0 4)\n");
        return;
    }
    if (n == -2) { kprint("Error: máximo 20 referencias.\n"); return; }
    if (n == 0) {
        n_marcos = 3;
        nrefs = (int)(sizeof(def) / sizeof(def[0]));
        for (int i = 0; i < nrefs; i++) refs[i] = def[i];
    } else {
        if (numeros[0] < 1 || numeros[0] > MAXM) { kprint("Error: los marcos deben ser de 1 a 4.\n"); return; }
        n_marcos = numeros[0];
        nrefs = n - 1;
        for (int i = 0; i < nrefs; i++) {
            if (numeros[i + 1] >= NPAG) { kprint("Error: las páginas van de 0 a 9.\n"); return; }
            refs[i] = numeros[i + 1];
        }
    }

    uint32_t pf_antes = pf_total, swap_antes = swap_escrituras;
    for (int a = 0; a < 3; a++) ejecutar_algoritmo(a);

    kclear();
    titulo("=== Paginación: reemplazo de páginas con fallos #PF reales ===");
    kprint_dec((uint32_t)n_marcos); kprint(" marcos de 4 KB | página n = ");
    kprint_hex(VBASE, 8); kprint(" + n*4 KB | respaldo en swap (RAM)\n");
    kset_color(C_TITULO);
    kprint("Ref.   ");
    kset_color(C_DATO);
    for (int i = 0; i < nrefs; i++) { kprint("  "); kputc((char)('0' + refs[i])); }
    kprint("\n");
    imprimir_algoritmo(0, "FIFO");
    imprimir_algoritmo(1, "LRU");
    imprimir_algoritmo(2, "Óptimo");

    etiqueta("Resultado: ");
    kprint("FIFO="); kprint_dec(fallos_alg[0]);
    kprint("  LRU="); kprint_dec(fallos_alg[1]);
    kprint("  Óptimo="); kprint_dec(fallos_alg[2]);
    kprint(" | #PF reales: "); kprint_dec(pf_total - pf_antes);
    kprint(" | a swap: "); kprint_dec(swap_escrituras - swap_antes);
    kprint("\n");
    int ok = datos_ok[0] && datos_ok[1] && datos_ok[2];
    etiqueta("Integridad: ");
    kset_color(ok ? C_OK : C_ERROR);
    kprint(ok ? "OK, ningún dato se perdió al sacar páginas a swap" : "ERROR en los datos");
    kset_color(C_NORMAL);
    kprint("\n");
    kset_color(C_NUEVO); kprint("Amarillo");
    kset_color(C_NORMAL); kprint(": página traída a un marco por un fallo de página (vector 14)\n");
}

void mem_comando(const char *args) {
    while (*args == ' ') args++;
    if (*args == '\0') { mem_resumen(); return; }
    if (args[0] == 's' && args[1] == 'e' && args[2] == 'g' && (args[3] == '\0' || args[3] == ' ')) {
        mem_seg();
        return;
    }
    if (args[0] == 'p' && args[1] == 'a' && args[2] == 'g' && (args[3] == '\0' || args[3] == ' ')) {
        mem_pag(args + 3);
        return;
    }
    kprint("Uso: mem | mem seg | mem pag <marcos> <páginas...>\n");
}

uint32_t mem_ram_mb(void) {
    return ram_total_kb / 1024u;
}

uint32_t mem_kernel_kb(void) {
    uint32_t ini = (uint32_t)_kernel_start;
    uint32_t fin = (uint32_t)_kernel_end;
    return (fin > ini) ? ((fin - ini) / 1024u) : 0u;
}

uint32_t mem_pf_total(void) {
    return pf_total;
}

int mem_paginacion_activa(void) {
    return (leer_cr0() & 0x80000000u) != 0;
}

int mem_map_mmio(uint32_t phys_base, uint32_t size) {
    uint32_t pde_idx = phys_base >> 22;
    if (pde_idx == 0 || pde_idx == (VBASE >> 22)) return -1;
    uint32_t base_4m = pde_idx << 22;
    for (int i = 0; i < 1024; i++) tabla_mmio[i] = 0;
    uint32_t p_ini = (phys_base - base_4m) >> 12;
    uint32_t n_pags = (size + 4095u) >> 12;
    for (uint32_t i = 0; i < n_pags && (p_ini + i) < 1024; i++) {
        uint32_t addr = base_4m + ((p_ini + i) << 12);
        /* PG_P | PG_RW | PWT (0x08) | PCD (0x10): MMIO sin cache */
        tabla_mmio[p_ini + i] = addr | PG_P | PG_RW | 0x18u;
    }
    dir_paginas[pde_idx] = (uint32_t)tabla_mmio | PG_P | PG_RW | 0x18u;
    __asm__ volatile("mov %0, %%cr3" : : "r"((uint32_t)dir_paginas) : "memory");
    return 0;
}
