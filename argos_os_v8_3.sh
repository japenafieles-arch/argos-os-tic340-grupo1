#!/bin/bash
# ARGOS - Sistema Operativo (Tecnológico Universitario Argos)
# Versión: v8.3 (Bloque 3: Sala de Juegos - Snake, 2048 y Ahorcado con Récords Persistentes en /records.txt)
# Uso nube  : bash argos_os_v8_3.sh argos-scholar-tuusuario.fly.dev 80
# Uso local : bash argos_os_v8_3.sh
# Requisitos: sudo apt install -y build-essential gcc-multilib grub-pc-bin grub-common xorriso mtools
set -e
SCHOLAR_HOST="${1:-auto}"
SCHOLAR_PORT="${2:-8080}"
if [ "$SCHOLAR_HOST" != "auto" ] && [ -z "$2" ]; then
    SCHOLAR_PORT="80"
fi
mkdir -p ~/argos_os/nube && cd ~/argos_os

cat << 'EOF' > boot.s
.set ALIGN,    1<<0
.set MEMINFO,  1<<1
.set FLAGS,    ALIGN | MEMINFO
.set MAGIC,    0x1BADB002
.set CHECKSUM, -(MAGIC + FLAGS)

.section .multiboot
.align 4
.long MAGIC
.long FLAGS
.long CHECKSUM

.section .bss
.align 16
stack_bottom:
.skip 16384
stack_top:

.section .text
.global _start
.type _start, @function
_start:
    mov $stack_top, %esp
    push %ebx                 # direccion de la estructura multiboot (RAM detectada)
    push %eax                 # numero magico de GRUB
    call kernel_main
    cli
1:  hlt
    jmp 1b

.section .note.GNU-stack,"",@progbits
EOF

cat << 'EOF' > cpu.s
# Rutinas de bajo nivel: GDT, IDT, excepciones (0-31), IRQ (32-47) y cambio de contexto
.section .text

.global gdt_flush
gdt_flush:
    mov 4(%esp), %eax
    lgdt (%eax)
    mov $0x10, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %fs
    mov %ax, %gs
    mov %ax, %ss
    ljmp $0x08, $1f
1:  ret

.global idt_load
idt_load:
    mov 4(%esp), %eax
    lidt (%eax)
    ret

# void ctx_switch(uint32_t *old_esp, uint32_t new_esp)
# Guarda registros preservados en la pila actual, cambia ESP y restaura el nuevo contexto
.global ctx_switch
ctx_switch:
    push %ebp
    push %ebx
    push %esi
    push %edi
    mov 20(%esp), %eax
    mov %esp, (%eax)
    mov 24(%esp), %esp
    pop %edi
    pop %esi
    pop %ebx
    pop %ebp
    ret

.macro ISR_SIN_ERR n
isr\n:
    push $0
    push $\n
    jmp isr_comun
.endm

.macro ISR_CON_ERR n
isr\n:
    push $\n
    jmp isr_comun
.endm

.macro IRQ_STUB n, v
irq\n:
    push $0
    push $\v
    jmp irq_comun
.endm

ISR_SIN_ERR 0
ISR_SIN_ERR 1
ISR_SIN_ERR 2
ISR_SIN_ERR 3
ISR_SIN_ERR 4
ISR_SIN_ERR 5
ISR_SIN_ERR 6
ISR_SIN_ERR 7
ISR_CON_ERR 8
ISR_SIN_ERR 9
ISR_CON_ERR 10
ISR_CON_ERR 11
ISR_CON_ERR 12
ISR_CON_ERR 13
ISR_CON_ERR 14
ISR_SIN_ERR 15
ISR_SIN_ERR 16
ISR_CON_ERR 17
ISR_SIN_ERR 18
ISR_SIN_ERR 19
ISR_SIN_ERR 20
ISR_CON_ERR 21
ISR_SIN_ERR 22
ISR_SIN_ERR 23
ISR_SIN_ERR 24
ISR_SIN_ERR 25
ISR_SIN_ERR 26
ISR_SIN_ERR 27
ISR_SIN_ERR 28
ISR_CON_ERR 29
ISR_CON_ERR 30
ISR_SIN_ERR 31

IRQ_STUB 0,  32
IRQ_STUB 1,  33
IRQ_STUB 2,  34
IRQ_STUB 3,  35
IRQ_STUB 4,  36
IRQ_STUB 5,  37
IRQ_STUB 6,  38
IRQ_STUB 7,  39
IRQ_STUB 8,  40
IRQ_STUB 9,  41
IRQ_STUB 10, 42
IRQ_STUB 11, 43
IRQ_STUB 12, 44
IRQ_STUB 13, 45
IRQ_STUB 14, 46
IRQ_STUB 15, 47

isr_comun:
    cld
    pusha
    push %esp
    call isr_manejador
    add $4, %esp
    popa
    add $8, %esp
    iret

irq_comun:
    cld
    pusha
    push %esp
    call irq_manejador
    add $4, %esp
    popa
    add $8, %esp
    iret

.section .data
.global isr_tabla
isr_tabla:
.irp i,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    .long isr\i
.endr

.global irq_tabla
irq_tabla:
.irp i,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
    .long irq\i
.endr

.section .note.GNU-stack,"",@progbits
EOF

cat << 'EOF' > linker.ld
ENTRY(_start)
SECTIONS
{
    . = 1M;
    _kernel_start = .;
    .text BLOCK(4K) : ALIGN(4K) { *(.multiboot) *(.text*) }
    .rodata BLOCK(4K) : ALIGN(4K) { *(.rodata*) }
    .data BLOCK(4K) : ALIGN(4K) { *(.data*) }
    .bss BLOCK(4K) : ALIGN(4K) { *(COMMON) *(.bss*) }
    _kernel_end = .;
}
EOF

cat << 'EOF' > reloj.h
#ifndef RELOJ_H
#define RELOJ_H
#include <stdint.h>

#define PIT_HZ 100

typedef struct {
    uint8_t seg;
    uint8_t min;
    uint8_t hora;
    uint8_t dia;
    uint8_t mes;
    uint16_t anio;
} fecha_hora_t;

void reloj_init(void);
int reloj_activo(void);
uint32_t reloj_ticks(void);
uint32_t reloj_uptime_seg(void);
void reloj_leer_rtc(fecha_hora_t *fh);
void reloj_refrescar_barra(void);
void reloj_obtener_hora_barra(uint8_t *h, uint8_t *m, uint8_t *s);
void reloj_cmd_date(const char *args);
void reloj_cmd_uptime(void);
void reloj_set_tz(int tz);
int  reloj_get_tz(void);

#endif
EOF

cat << 'EOF' > reloj.c
/*
 * Modulo 1: Reloj hardware (CMOS/RTC) + Temporizador PIT en IRQ0 (vector 32)
 */
#include "reloj.h"

#define PIC1_CMD   0x20
#define PIC1_DATA  0x21
#define PIC2_CMD   0xA0
#define PIC2_DATA  0xA1
#define PIC_EOI    0x20

#define PIT_CH0    0x40
#define PIT_CMD    0x43
#define PIT_BASE   1193182u

#define CMOS_ADDR  0x70
#define CMOS_DATA  0x71

typedef struct {
    uint32_t edi, esi, ebp, esp, ebx, edx, ecx, eax;
    uint32_t vector, error;
    uint32_t eip, cs, eflags;
} irq_regs_t;

extern void kprint(const char *s);
extern void kputc(char c);
extern void kset_color(uint8_t c);
extern void kprint_dec(uint32_t v);
extern void kdibujar_reloj_barra(uint8_t h, uint8_t m, uint8_t s);
extern void kernel_guardar_prefs(void);

static volatile uint32_t pit_ticks = 0;
static volatile uint32_t sub_ticks = 0;
static volatile uint32_t uptime_segundos = 0;
static volatile int irq_encendido = 0;

static volatile uint8_t barra_h = 0;
static volatile uint8_t barra_m = 0;
static volatile uint8_t barra_s = 0;
static int tz_horas = 0;

static inline void outb(uint16_t port, uint8_t val) {
    __asm__ volatile("outb %0, %1" : : "a"(val), "Nd"(port));
}
static inline uint8_t inb(uint16_t port) {
    uint8_t r;
    __asm__ volatile("inb %1, %0" : "=a"(r) : "Nd"(port));
    return r;
}
static inline void io_wait(void) {
    outb(0x80, 0);
}

static uint8_t cmos_leer(uint8_t reg) {
    outb(CMOS_ADDR, (uint8_t)(reg & 0x7F));
    return inb(CMOS_DATA);
}

static int cmos_actualizando(void) {
    outb(CMOS_ADDR, 0x0A);
    return (inb(CMOS_DATA) & 0x80) != 0;
}

static uint8_t bcd_a_bin(uint8_t v) {
    return (uint8_t)(((v >> 4) * 10) + (v & 0x0F));
}

static int es_bisiesto(uint16_t y) {
    return ((y % 4 == 0 && y % 100 != 0) || (y % 400 == 0));
}

static uint8_t dias_en_mes(uint8_t m, uint16_t y) {
    static const uint8_t dm[12] = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    if (m < 1 || m > 12) return 30;
    if (m == 2 && es_bisiesto(y)) return 29;
    return dm[m - 1];
}

static void aplicar_tz(fecha_hora_t *fh, int offset) {
    int h = (int)fh->hora + offset;
    if (h >= 24) {
        h -= 24;
        fh->dia++;
        if (fh->dia > dias_en_mes(fh->mes, fh->anio)) {
            fh->dia = 1;
            fh->mes++;
            if (fh->mes > 12) { fh->mes = 1; fh->anio++; }
        }
    } else if (h < 0) {
        h += 24;
        if (fh->dia > 1) {
            fh->dia--;
        } else {
            if (fh->mes > 1) fh->mes--;
            else { fh->mes = 12; fh->anio--; }
            fh->dia = dias_en_mes(fh->mes, fh->anio);
        }
    }
    fh->hora = (uint8_t)h;
}

void reloj_leer_rtc(fecha_hora_t *fh) {
    uint8_t s1, m1, h1, d1, mo1, y1;
    uint8_t s2, m2, h2, d2, mo2, y2;

    do {
        while (cmos_actualizando()) {}
        s1  = cmos_leer(0x00);
        m1  = cmos_leer(0x02);
        h1  = cmos_leer(0x04);
        d1  = cmos_leer(0x07);
        mo1 = cmos_leer(0x08);
        y1  = cmos_leer(0x09);

        while (cmos_actualizando()) {}
        s2  = cmos_leer(0x00);
        m2  = cmos_leer(0x02);
        h2  = cmos_leer(0x04);
        d2  = cmos_leer(0x07);
        mo2 = cmos_leer(0x08);
        y2  = cmos_leer(0x09);
    } while (s1 != s2 || m1 != m2 || h1 != h2 || d1 != d2 || mo1 != mo2 || y1 != y2);

    uint8_t regB = cmos_leer(0x0B);
    int es_pm = (h1 & 0x80) != 0;
    h1 &= 0x7F;

    if (!(regB & 0x04)) {
        s1  = bcd_a_bin(s1);
        m1  = bcd_a_bin(m1);
        h1  = bcd_a_bin(h1);
        d1  = bcd_a_bin(d1);
        mo1 = bcd_a_bin(mo1);
        y1  = bcd_a_bin(y1);
    }

    if (!(regB & 0x02)) {
        if (es_pm && h1 < 12) h1 = (uint8_t)(h1 + 12);
        else if (!es_pm && h1 == 12) h1 = 0;
    }

    fh->seg  = s1 % 60;
    fh->min  = m1 % 60;
    fh->hora = h1 % 24;
    fh->dia  = (d1 >= 1 && d1 <= 31) ? d1 : 1;
    fh->mes  = (mo1 >= 1 && mo1 <= 12) ? mo1 : 1;
    fh->anio = (uint16_t)(2000 + y1);

    if (tz_horas != 0) aplicar_tz(fh, tz_horas);

    barra_h = fh->hora;
    barra_m = fh->min;
    barra_s = fh->seg;
}

static void pic_init(void) {
    outb(PIC1_CMD, 0x11); io_wait();
    outb(PIC2_CMD, 0x11); io_wait();

    outb(PIC1_DATA, 0x20); io_wait();
    outb(PIC2_DATA, 0x28); io_wait();

    outb(PIC1_DATA, 0x04); io_wait();
    outb(PIC2_DATA, 0x02); io_wait();

    outb(PIC1_DATA, 0x01); io_wait();
    outb(PIC2_DATA, 0x01); io_wait();

    outb(PIC1_DATA, 0xFE); io_wait();
    outb(PIC2_DATA, 0xFF); io_wait();
}

static void pit_init(uint32_t hz) {
    uint32_t div = PIT_BASE / hz;
    outb(PIT_CMD, 0x36);
    outb(PIT_CH0, (uint8_t)(div & 0xFF));
    outb(PIT_CH0, (uint8_t)((div >> 8) & 0xFF));
}

void reloj_refrescar_barra(void) {
    kdibujar_reloj_barra(barra_h, barra_m, barra_s);
}

void reloj_obtener_hora_barra(uint8_t *h, uint8_t *m, uint8_t *s) {
    if (h) *h = barra_h;
    if (m) *m = barra_m;
    if (s) *s = barra_s;
}

void reloj_init(void) {
    fecha_hora_t fh;
    reloj_leer_rtc(&fh);
    pic_init();
    pit_init(PIT_HZ);
    irq_encendido = 1;
    __asm__ volatile("sti");
}

int reloj_activo(void) {
    return irq_encendido;
}

uint32_t reloj_ticks(void) {
    return pit_ticks;
}

uint32_t reloj_uptime_seg(void) {
    return uptime_segundos;
}

void irq_manejador(irq_regs_t *r) {
    uint32_t vec = r->vector;

    if (vec == 39) {
        outb(PIC1_CMD, 0x0B);
        if (!(inb(PIC1_CMD) & 0x80)) return;
    } else if (vec == 47) {
        outb(PIC2_CMD, 0x0B);
        if (!(inb(PIC2_CMD) & 0x80)) {
            outb(PIC1_CMD, PIC_EOI);
            return;
        }
    }

    if (vec == 32) {
        pit_ticks++;
        sub_ticks++;
        if (sub_ticks >= PIT_HZ) {
            sub_ticks = 0;
            uptime_segundos++;
            barra_s++;
            if (barra_s >= 60) {
                barra_s = 0;
                barra_m++;
                if (barra_m >= 60) {
                    barra_m = 0;
                    barra_h++;
                    if (barra_h >= 24) barra_h = 0;
                }
            }
            kdibujar_reloj_barra(barra_h, barra_m, barra_s);
        }
    }

    if (vec >= 40) outb(PIC2_CMD, PIC_EOI);
    outb(PIC1_CMD, PIC_EOI);
}

static void imprimir_2dig(uint32_t v) {
    if (v < 10) kputc('0');
    kprint_dec(v);
}

static int dia_semana(uint16_t y, uint8_t m, uint8_t d) {
    static const int t[12] = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 };
    if (m < 3) y--;
    return (y + y / 4 - y / 100 + y / 400 + t[m - 1] + d) % 7;
}

static void imprimir_tz(int tz) {
    if (tz == 0) {
        kprint("hora del reloj virtual (offset 0)");
    } else {
        kprint("offset ");
        if (tz > 0) kputc('+');
        else { kputc('-'); tz = -tz; }
        kprint_dec((uint32_t)tz);
        kprint(" h");
    }
}

void reloj_cmd_date(const char *args) {
    while (*args == ' ') args++;
    if (args[0] == 't' && args[1] == 'z' && (args[2] == ' ' || args[2] == '\0')) {
        const char *p = args + 2;
        while (*p == ' ') p++;
        if (!*p) {
            kprint("Uso: date tz <-12..+12>  (ej: date tz -5 para Ecuador si la VM usa UTC)\n");
            return;
        }
        int signo = 1;
        if (*p == '-') { signo = -1; p++; }
        else if (*p == '+') { p++; }
        if (*p < '0' || *p > '9') {
            kprint("Error: especifica un número de horas entre -12 y +12.\n");
            return;
        }
        int val = 0;
        while (*p >= '0' && *p <= '9') { val = val * 10 + (*p - '0'); p++; }
        if (*p != '\0' || val > 12) {
            kprint("Error: el ajuste debe estar entre -12 y +12 horas.\n");
            return;
        }
        tz_horas = signo * val;
        kernel_guardar_prefs();
    } else if (*args != '\0') {
        kprint("Uso: date | date tz <-12..+12>\n");
        return;
    }

    static const char *dias[7] = {
        "Domingo", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado"
    };
    fecha_hora_t fh;
    reloj_leer_rtc(&fh);
    reloj_refrescar_barra();

    kset_color(0x0B); kprint("Fecha y hora (CMOS/RTC 0x70/0x71): ");
    kset_color(0x0F);
    kprint(dias[dia_semana(fh.anio, fh.mes, fh.dia)]);
    kprint(" ");
    imprimir_2dig(fh.dia); kputc('/');
    imprimir_2dig(fh.mes); kputc('/');
    kprint_dec(fh.anio);
    kprint("  ");
    imprimir_2dig(fh.hora); kputc(':');
    imprimir_2dig(fh.min);  kputc(':');
    imprimir_2dig(fh.seg);
    kset_color(0x08);
    kprint("  ("); imprimir_tz(tz_horas); kprint(")\n");
    kset_color(0x07);
}

void reloj_cmd_uptime(void) {
    uint32_t seg_tot = uptime_segundos;
    uint32_t h = seg_tot / 3600;
    uint32_t m = (seg_tot % 3600) / 60;
    uint32_t s = seg_tot % 60;

    kset_color(0x0B); kprint("Tiempo encendido: ");
    kset_color(0x0F);
    imprimir_2dig(h); kputc(':');
    imprimir_2dig(m); kputc(':');
    imprimir_2dig(s);
    kset_color(0x07);
    kprint("  ("); kprint_dec(seg_tot); kprint(" segundos)\n");

    kset_color(0x0B); kprint("Temporizador PIT: ");
    kset_color(0x07);
    kprint_dec(PIT_HZ); kprint(" Hz (10 ms/tic) | ");
    kprint("Vector IDT 32 (IRQ0) | Tics atendidos: ");
    kset_color(0x0A);
    kprint_dec(pit_ticks);
    kset_color(0x07);
    kprint("\n");
}

void reloj_set_tz(int tz) {
    if (tz < -12) tz = -12;
    if (tz > 12) tz = 12;
    tz_horas = tz;
    fecha_hora_t fh;
    reloj_leer_rtc(&fh);
    reloj_refrescar_barra();
}

int reloj_get_tz(void) {
    return tz_horas;
}
EOF

cat << 'EOF' > proc.h
#ifndef PROC_H
#define PROC_H
#include <stdint.h>

#define MAX_PROCS  10

#define PROC_LIBRE 0
#define PROC_NUEVO 1
#define PROC_LISTO 2
#define PROC_EJEC  3
#define PROC_BLOQ  4
#define PROC_TERM  5

typedef struct {
    uint32_t pid;
    uint32_t ppid;
    uint8_t  estado;
    uint8_t  prioridad;
    uint32_t esp;
    uint32_t eip;
    uint32_t cr3;
    uint32_t tics_cpu;
    uint32_t cambios_ctx;
    char     nombre[16];
} pcb_t;

void proc_init(void);
void proc_cmd_ps(const char *args);
void proc_cmd_demo(void);
void proc_cmd_sched(const char *args);
uint32_t proc_activos(void);

#endif
EOF

cat << 'EOF' > proc.c
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
EOF

cat << 'EOF' > audit.h
#ifndef AUDIT_H
#define AUDIT_H
#include <stdint.h>

#define LOG_INFO  0
#define LOG_OK    1
#define LOG_WARN  2
#define LOG_ALERT 3

void audit_init(void);
void audit_registrar(uint8_t nivel, const char *usuario, const char *evento, const char *detalle);
void audit_cmd_log(const char *args, int rol_actual);
uint32_t audit_total(void);

#endif
EOF

cat << 'EOF' > audit.c
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
EOF

cat << 'EOF' > pci.h
#ifndef PCI_H
#define PCI_H
#include <stdint.h>

typedef struct {
    uint8_t  bus;
    uint8_t  dev;
    uint8_t  func;
    uint16_t vendor_id;
    uint16_t device_id;
    uint32_t bar0;
    uint8_t  irq_line;
} pci_dev_t;

uint32_t pci_read32(uint8_t bus, uint8_t dev, uint8_t func, uint8_t offset);
void     pci_write32(uint8_t bus, uint8_t dev, uint8_t func, uint8_t offset, uint32_t val);
uint16_t pci_read16(uint8_t bus, uint8_t dev, uint8_t func, uint8_t offset);
void     pci_write16(uint8_t bus, uint8_t dev, uint8_t func, uint8_t offset, uint16_t val);
int      pci_buscar_nic_intel(pci_dev_t *out);

#endif
EOF

cat << 'EOF' > pci.c
/*
 * Escaner de Bus PCI (puertos 0xCF8 / 0xCFC)
 * Permite detectar la tarjeta de red Intel PRO/1000 (e1000) en VirtualBox/QEMU
 */
#include "pci.h"

#define PCI_ADDR 0xCF8
#define PCI_DATA 0xCFC

static inline void outl(uint16_t port, uint32_t val) {
    __asm__ volatile("outl %0, %1" : : "a"(val), "Nd"(port));
}
static inline uint32_t inl(uint16_t port) {
    uint32_t r;
    __asm__ volatile("inl %1, %0" : "=a"(r) : "Nd"(port));
    return r;
}

static uint32_t pci_addr(uint8_t bus, uint8_t dev, uint8_t func, uint8_t offset) {
    return 0x80000000u |
           ((uint32_t)bus << 16) |
           ((uint32_t)(dev & 0x1F) << 11) |
           ((uint32_t)(func & 0x07) << 8) |
           ((uint32_t)(offset & 0xFC));
}

uint32_t pci_read32(uint8_t bus, uint8_t dev, uint8_t func, uint8_t offset) {
    outl(PCI_ADDR, pci_addr(bus, dev, func, offset));
    return inl(PCI_DATA);
}

void pci_write32(uint8_t bus, uint8_t dev, uint8_t func, uint8_t offset, uint32_t val) {
    outl(PCI_ADDR, pci_addr(bus, dev, func, offset));
    outl(PCI_DATA, val);
}

uint16_t pci_read16(uint8_t bus, uint8_t dev, uint8_t func, uint8_t offset) {
    uint32_t v = pci_read32(bus, dev, func, offset);
    return (uint16_t)((v >> ((offset & 2) * 8)) & 0xFFFFu);
}

void pci_write16(uint8_t bus, uint8_t dev, uint8_t func, uint8_t offset, uint16_t val) {
    uint32_t cur = pci_read32(bus, dev, func, offset);
    uint32_t shift = (uint32_t)((offset & 2) * 8);
    cur &= ~(0xFFFFu << shift);
    cur |= ((uint32_t)val << shift);
    pci_write32(bus, dev, func, offset, cur);
}

static int es_e1000(uint16_t vendor, uint16_t device) {
    if (vendor != 0x8086u) return 0;
    return (device == 0x100Eu || /* 82540EM: Intel PRO/1000 MT Desktop (VirtualBox/QEMU) */
            device == 0x100Fu || /* 82545EM: Intel PRO/1000 MT Server */
            device == 0x1004u || /* 82543GC: Intel PRO/1000 T Server */
            device == 0x10D3u);  /* 82574L */
}

int pci_buscar_nic_intel(pci_dev_t *out) {
    for (uint8_t bus = 0; bus < 4; bus++) {
        for (uint8_t dev = 0; dev < 32; dev++) {
            uint16_t vendor = pci_read16(bus, dev, 0, 0x00);
            if (vendor == 0xFFFFu) continue;
            uint8_t header = (uint8_t)(pci_read32(bus, dev, 0, 0x0C) >> 16);
            int max_func = (header & 0x80) ? 8 : 1;
            for (uint8_t func = 0; func < max_func; func++) {
                uint16_t vid = pci_read16(bus, dev, func, 0x00);
                if (vid == 0xFFFFu) continue;
                uint16_t did = pci_read16(bus, dev, func, 0x02);
                if (es_e1000(vid, did)) {
                    out->bus = bus;
                    out->dev = dev;
                    out->func = func;
                    out->vendor_id = vid;
                    out->device_id = did;
                    out->bar0 = pci_read32(bus, dev, func, 0x10) & ~0xFu;
                    out->irq_line = (uint8_t)(pci_read32(bus, dev, func, 0x3C) & 0xFFu);
                    return 0;
                }
            }
        }
    }
    return -1;
}
EOF

cat << 'EOF' > e1000.h
#ifndef E1000_H
#define E1000_H
#include <stdint.h>

int  e1000_init(void);
int  e1000_presente(void);
int  e1000_enlace_activo(void);
void e1000_obtener_mac(uint8_t mac[6]);
uint32_t e1000_mmio_base(void);
uint16_t e1000_device_id(void);
int  e1000_enviar(const uint8_t *datos, uint16_t len);
int  e1000_recibir(uint8_t *buf, uint16_t max_len);
void e1000_stats(uint32_t *tx_ok, uint32_t *rx_ok);

#endif
EOF

cat << 'EOF' > e1000.c
/*
 * Driver Bare-Metal para tarjeta de red Intel PRO/1000 (82540EM / e1000)
 *  - Mapea MMIO (BAR0, 128 KB) en la paginacion x86
 *  - Activa PCI Bus Master para DMA
 *  - Anillos de descriptores RX (16 x 2 KB) y TX (8 x 2 KB) en RAM identidad
 */
#include "e1000.h"
#include "pci.h"
#include "mem.h"

#define NUM_RX 16
#define NUM_TX 8
#define PKT_BUF_SZ 2048

#define REG_CTRL    0x0000
#define REG_STATUS  0x0008
#define REG_EERD    0x0014
#define REG_ICR     0x00C0
#define REG_IMC     0x00D8
#define REG_RCTL    0x0100
#define REG_TCTL    0x0400
#define REG_TIPG    0x0410
#define REG_RDBAL   0x2800
#define REG_RDBAH   0x2804
#define REG_RDLEN   0x2808
#define REG_RDH     0x2810
#define REG_RDT     0x2818
#define REG_TDBAL   0x3800
#define REG_TDBAH   0x3804
#define REG_TDLEN   0x3808
#define REG_TDH     0x3810
#define REG_TDT     0x3818
#define REG_MTA     0x5200
#define REG_RAL0    0x5400
#define REG_RAH0    0x5404

typedef struct __attribute__((packed)) {
    uint64_t addr;
    uint16_t length;
    uint16_t checksum;
    uint8_t  status;
    uint8_t  errors;
    uint16_t special;
} e1000_rx_desc_t;

typedef struct __attribute__((packed)) {
    uint64_t addr;
    uint16_t length;
    uint8_t  cso;
    uint8_t  cmd;
    uint8_t  status;
    uint8_t  css;
    uint16_t special;
} e1000_tx_desc_t;

static volatile e1000_rx_desc_t rx_descs[NUM_RX] __attribute__((aligned(16)));
static volatile e1000_tx_desc_t tx_descs[NUM_TX] __attribute__((aligned(16)));
static uint8_t rx_bufs[NUM_RX][PKT_BUF_SZ] __attribute__((aligned(16)));
static uint8_t tx_bufs[NUM_TX][PKT_BUF_SZ] __attribute__((aligned(16)));

static volatile uint8_t *mmio = 0;
static uint32_t mmio_phys = 0;
static uint16_t nic_dev_id = 0;
static int nic_ok = 0;
static uint8_t nic_mac[6] = { 0 };
static uint32_t rx_cur = 0;
static uint32_t tx_cur = 0;
static uint32_t cnt_tx = 0;
static uint32_t cnt_rx = 0;

static inline uint32_t mmio_r(uint32_t reg) {
    return *(volatile uint32_t *)(mmio + reg);
}

static inline void mmio_w(uint32_t reg, uint32_t val) {
    *(volatile uint32_t *)(mmio + reg) = val;
}

static int eeprom_leer(uint8_t addr, uint16_t *out) {
    mmio_w(REG_EERD, ((uint32_t)addr << 8) | 1u);
    for (int t = 0; t < 50000; t++) {
        uint32_t v = mmio_r(REG_EERD);
        if (v & (1u << 4)) {
            *out = (uint16_t)((v >> 16) & 0xFFFFu);
            return 0;
        }
    }
    return -1;
}

static int mac_valida(const uint8_t m[6]) {
    int todos0 = 1, todosF = 1;
    for (int i = 0; i < 6; i++) {
        if (m[i] != 0x00) todos0 = 0;
        if (m[i] != 0xFF) todosF = 0;
    }
    return !todos0 && !todosF;
}

static void leer_mac_hw(void) {
    uint16_t w0 = 0, w1 = 0, w2 = 0;
    if (eeprom_leer(0, &w0) == 0 && eeprom_leer(1, &w1) == 0 && eeprom_leer(2, &w2) == 0) {
        uint8_t tmp[6];
        tmp[0] = (uint8_t)(w0 & 0xFF);
        tmp[1] = (uint8_t)(w0 >> 8);
        tmp[2] = (uint8_t)(w1 & 0xFF);
        tmp[3] = (uint8_t)(w1 >> 8);
        tmp[4] = (uint8_t)(w2 & 0xFF);
        tmp[5] = (uint8_t)(w2 >> 8);
        if (mac_valida(tmp)) {
            for (int i = 0; i < 6; i++) nic_mac[i] = tmp[i];
            return;
        }
    }
    /* Respaldo: registros RAL0 / RAH0 precargados por el hipervisor */
    uint32_t ral = mmio_r(REG_RAL0);
    uint32_t rah = mmio_r(REG_RAH0);
    nic_mac[0] = (uint8_t)(ral & 0xFF);
    nic_mac[1] = (uint8_t)((ral >> 8) & 0xFF);
    nic_mac[2] = (uint8_t)((ral >> 16) & 0xFF);
    nic_mac[3] = (uint8_t)((ral >> 24) & 0xFF);
    nic_mac[4] = (uint8_t)(rah & 0xFF);
    nic_mac[5] = (uint8_t)((rah >> 8) & 0xFF);

    if (!mac_valida(nic_mac)) {
        nic_mac[0] = 0x52; nic_mac[1] = 0x54; nic_mac[2] = 0x00;
        nic_mac[3] = 0x12; nic_mac[4] = 0x34; nic_mac[5] = 0x56;
    }
}

int e1000_init(void) {
    pci_dev_t dev;
    nic_ok = 0;
    if (pci_buscar_nic_intel(&dev) != 0 || dev.bar0 == 0) {
        return -1;
    }

    /* Habilitar Memory Space (bit 1) y Bus Master DMA (bit 2) en PCI */
    uint16_t cmd = pci_read16(dev.bus, dev.dev, dev.func, 0x04);
    cmd |= 0x0007u;
    pci_write16(dev.bus, dev.dev, dev.func, 0x04, cmd);

    if (mem_map_mmio(dev.bar0, 0x20000u) != 0) {
        return -1;
    }

    mmio_phys = dev.bar0;
    mmio = (volatile uint8_t *)dev.bar0;
    nic_dev_id = dev.device_id;

    /* Deshabilitar interrupciones y reiniciar chip */
    mmio_w(REG_IMC, 0xFFFFFFFFu);
    mmio_w(REG_CTRL, mmio_r(REG_CTRL) | (1u << 26));
    for (volatile int d = 0; d < 200000; d++) {}
    mmio_w(REG_IMC, 0xFFFFFFFFu);
    (void)mmio_r(REG_ICR);

    /* Activar enlace (Set Link Up) */
    uint32_t ctrl = mmio_r(REG_CTRL);
    ctrl |= (1u << 6);      /* SLU */
    ctrl &= ~(1u << 3);     /* quitar LRST */
    ctrl &= ~(1u << 31);    /* quitar PHY_RST */
    mmio_w(REG_CTRL, ctrl);

    leer_mac_hw();

    /* Programar direccion MAC en RAL0/RAH0 y limpiar tabla multicast */
    uint32_t ral = (uint32_t)nic_mac[0] | ((uint32_t)nic_mac[1] << 8) |
                   ((uint32_t)nic_mac[2] << 16) | ((uint32_t)nic_mac[3] << 24);
    uint32_t rah = (uint32_t)nic_mac[4] | ((uint32_t)nic_mac[5] << 8) | (1u << 31);
    mmio_w(REG_RAL0, ral);
    mmio_w(REG_RAH0, rah);
    for (int i = 0; i < 128; i++) mmio_w(REG_MTA + (uint32_t)i * 4u, 0);

    /* Configurar anillo RX */
    for (int i = 0; i < NUM_RX; i++) {
        rx_descs[i].addr = (uint64_t)(uint32_t)&rx_bufs[i][0];
        rx_descs[i].length = 0;
        rx_descs[i].checksum = 0;
        rx_descs[i].status = 0;
        rx_descs[i].errors = 0;
        rx_descs[i].special = 0;
    }
    rx_cur = 0;
    mmio_w(REG_RDBAL, (uint32_t)rx_descs);
    mmio_w(REG_RDBAH, 0);
    mmio_w(REG_RDLEN, (uint32_t)(NUM_RX * sizeof(e1000_rx_desc_t)));
    mmio_w(REG_RDH, 0);
    mmio_w(REG_RDT, NUM_RX - 1);
    /* EN | BAM (aceptar broadcast) | SECRC (quitar CRC) | BSIZE=2048 */
    mmio_w(REG_RCTL, (1u << 1) | (1u << 15) | (1u << 26));

    /* Configurar anillo TX */
    for (int i = 0; i < NUM_TX; i++) {
        tx_descs[i].addr = (uint64_t)(uint32_t)&tx_bufs[i][0];
        tx_descs[i].length = 0;
        tx_descs[i].cso = 0;
        tx_descs[i].cmd = 0;
        tx_descs[i].status = 1; /* DD libre */
        tx_descs[i].css = 0;
        tx_descs[i].special = 0;
    }
    tx_cur = 0;
    mmio_w(REG_TDBAL, (uint32_t)tx_descs);
    mmio_w(REG_TDBAH, 0);
    mmio_w(REG_TDLEN, (uint32_t)(NUM_TX * sizeof(e1000_tx_desc_t)));
    mmio_w(REG_TDH, 0);
    mmio_w(REG_TDT, 0);
    mmio_w(REG_TIPG, 10u | (8u << 10) | (6u << 20));
    /* EN | PSP (padding minimo 64B) | CT=0x10 | COLD=0x40 */
    mmio_w(REG_TCTL, (1u << 1) | (1u << 3) | (0x10u << 4) | (0x40u << 12));

    cnt_tx = 0;
    cnt_rx = 0;
    nic_ok = 1;
    return 0;
}

int e1000_presente(void) {
    return nic_ok;
}

int e1000_enlace_activo(void) {
    if (!nic_ok) return 0;
    return (mmio_r(REG_STATUS) & (1u << 1)) != 0;
}

void e1000_obtener_mac(uint8_t mac[6]) {
    for (int i = 0; i < 6; i++) mac[i] = nic_mac[i];
}

uint32_t e1000_mmio_base(void) {
    return mmio_phys;
}

uint16_t e1000_device_id(void) {
    return nic_dev_id;
}

int e1000_enviar(const uint8_t *datos, uint16_t len) {
    if (!nic_ok || len == 0 || len > 1518) return -1;
    uint32_t idx = tx_cur;
    for (uint16_t i = 0; i < len; i++) tx_bufs[idx][i] = datos[i];

    tx_descs[idx].length = len;
    tx_descs[idx].cmd = 0x0B;   /* EOP | IFCS | RS */
    tx_descs[idx].status = 0;
    __asm__ volatile("" ::: "memory");

    tx_cur = (tx_cur + 1) % NUM_TX;
    mmio_w(REG_TDT, tx_cur);

    for (int t = 0; t < 400000; t++) {
        if (tx_descs[idx].status & 0x01) {
            cnt_tx++;
            return 0;
        }
    }
    return -1;
}

int e1000_recibir(uint8_t *buf, uint16_t max_len) {
    if (!nic_ok) return 0;
    uint32_t idx = rx_cur;
    if (!(rx_descs[idx].status & 0x01)) return 0;

    __asm__ volatile("" ::: "memory");
    uint16_t len = rx_descs[idx].length;
    uint16_t copiar = (len > max_len) ? max_len : len;
    for (uint16_t i = 0; i < copiar; i++) buf[i] = rx_bufs[idx][i];

    rx_descs[idx].status = 0;
    rx_descs[idx].errors = 0;
    __asm__ volatile("" ::: "memory");

    mmio_w(REG_RDT, idx);
    rx_cur = (rx_cur + 1) % NUM_RX;
    cnt_rx++;
    return (int)copiar;
}

void e1000_stats(uint32_t *tx_ok, uint32_t *rx_ok) {
    if (tx_ok) *tx_ok = cnt_tx;
    if (rx_ok) *rx_ok = cnt_rx;
}
EOF

cat << 'EOF' > net.h
#ifndef NET_H
#define NET_H
#include <stdint.h>

int  net_init(void);
int  net_listo(void);
int  net_tiene_ip(void);
uint32_t net_mi_ip(void);
uint32_t net_mi_gw(void);
void net_imprimir_ip(uint32_t ip);
int  net_dhcp(int silencioso);
int  net_resolver_dns(const char *dominio, uint32_t *ip_out);
int  net_http_get(const char *host, uint16_t port, const char *ruta, char *out_buf, int max_len, int *http_code);

void net_cmd_net(const char *args);
void net_cmd_ping(const char *args);
void net_cmd_dns(const char *args);
void net_cmd_http(const char *args);

#endif
EOF

cat << 'EOF' > net.c
/*
 * Modulo 5: Pila de Red TCP/IP Real en ARGOS OS
 *  - Capas: Ethernet II -> ARP -> IPv4 -> ICMP (ping) / UDP (DHCP, DNS) / TCP -> HTTP/1.1
 *  - Compatible con VirtualBox NAT (Intel PRO/1000 MT Desktop 82540EM) y QEMU
 *  - Expone net_http_get() para el futuro motor de busqueda academico (Modulo 6)
 */
#include "net.h"
#include "e1000.h"
#include "reloj.h"
#include "audit.h"

extern void kprint(const char *s);
extern void kputc(char c);
extern void kset_color(uint8_t c);
extern void kprint_dec(uint32_t v);
extern void kprint_hex(uint32_t v, int digitos);
extern void kprint_pad(const char *s, int ancho);
extern const char *kernel_usuario_corto(void);

#define ETH_ARP   0x0806u
#define ETH_IPV4  0x0800u
#define IP_ICMP   1
#define IP_TCP    6
#define IP_UDP    17

#define TCP_FIN   0x01
#define TCP_SYN   0x02
#define TCP_RST   0x04
#define TCP_PSH   0x08
#define TCP_ACK   0x10

typedef struct __attribute__((packed)) {
    uint8_t  dst[6];
    uint8_t  src[6];
    uint16_t tipo;
} eth_hdr_t;

typedef struct __attribute__((packed)) {
    uint16_t htype;
    uint16_t ptype;
    uint8_t  hlen;
    uint8_t  plen;
    uint16_t oper;
    uint8_t  sha[6];
    uint32_t spa;
    uint8_t  tha[6];
    uint32_t tpa;
} arp_pkt_t;

typedef struct __attribute__((packed)) {
    uint8_t  ihl_ver;
    uint8_t  tos;
    uint16_t tot_len;
    uint16_t id;
    uint16_t frag_off;
    uint8_t  ttl;
    uint8_t  proto;
    uint16_t checksum;
    uint32_t src;
    uint32_t dst;
} ip_hdr_t;

typedef struct __attribute__((packed)) {
    uint8_t  tipo;
    uint8_t  codigo;
    uint16_t checksum;
    uint16_t id;
    uint16_t seq;
} icmp_hdr_t;

typedef struct __attribute__((packed)) {
    uint16_t src_port;
    uint16_t dst_port;
    uint16_t len;
    uint16_t checksum;
} udp_hdr_t;

typedef struct __attribute__((packed)) {
    uint16_t src_port;
    uint16_t dst_port;
    uint32_t seq;
    uint32_t ack;
    uint8_t  off_res;
    uint8_t  flags;
    uint16_t window;
    uint16_t checksum;
    uint16_t urg_ptr;
} tcp_hdr_t;

typedef struct {
    uint32_t ip;
    uint8_t  mac[6];
    int      valido;
} arp_ent_t;

#define ARP_MAX 8
static arp_ent_t arp_cache[ARP_MAX];

static uint8_t  mi_mac[6];
static uint32_t mi_ip      = 0; /* en orden de host: 0x0A00020F = 10.0.2.15 */
static uint32_t mi_mask    = 0;
static uint32_t mi_gw      = 0;
static uint32_t mi_dns     = 0;
static uint16_t ip_id_seq  = 1;
static uint16_t eph_port   = 49152;
static int      net_up     = 0;

static uint8_t rx_frame[1600];
static uint8_t tx_frame[1600];

/* Estado de captura para respuestas sincronas */
static int      ping_esperando = 0;
static uint16_t ping_id_esp = 0, ping_seq_esp = 0;
static uint32_t ping_ip_esp = 0;
static int      ping_recibido = 0;
static uint8_t  ping_ttl_rec = 0;

static int      dhcp_esperando = 0;
static uint32_t dhcp_xid_esp = 0;
static int      dhcp_msg_rec = 0;
static uint32_t dhcp_yiaddr = 0, dhcp_srv = 0, dhcp_mask = 0, dhcp_gw = 0, dhcp_dns = 0;

static int      dns_esperando = 0;
static uint16_t dns_id_esp = 0;
static int      dns_ok_rec = 0;
static uint32_t dns_ip_rec = 0;

/* Estado de conexion TCP cliente */
static int      tcp_activo = 0;
static int      tcp_conectado = 0;
static int      tcp_cerrado = 0;
static int      tcp_reset = 0;
static uint32_t tcp_rem_ip = 0;
static uint16_t tcp_rem_port = 0;
static uint16_t tcp_loc_port = 0;
static uint32_t tcp_snd_nxt = 0;
static uint32_t tcp_rcv_nxt = 0;
static char    *tcp_user_buf = 0;
static int      tcp_user_max = 0;
static int      tcp_user_len = 0;

/* Buffer para comando http */
#define HTTP_BUF_SZ 12288
static char http_rx_buf[HTTP_BUF_SZ];

/* ---------- Utilidades de endianness y cadenas ---------- */
static uint16_t htons(uint16_t v) { return (uint16_t)((v << 8) | (v >> 8)); }
static uint16_t ntohs(uint16_t v) { return htons(v); }
static uint32_t htonl(uint32_t v) {
    return ((v & 0x000000FFu) << 24) | ((v & 0x0000FF00u) << 8) |
           ((v & 0x00FF0000u) >> 8)  | ((v & 0xFF000000u) >> 24);
}
static uint32_t ntohl(uint32_t v) { return htonl(v); }

static uint32_t ip4(uint8_t a, uint8_t b, uint8_t c, uint8_t d) {
    return ((uint32_t)a << 24) | ((uint32_t)b << 16) | ((uint32_t)c << 8) | (uint32_t)d;
}

static int n_slen(const char *s) { int n = 0; while (s[n]) n++; return n; }
static int n_igual(const char *a, const char *b) {
    while (*a && *a == *b) { a++; b++; }
    return *a == *b;
}

static uint16_t cksum16(const void *data, int len) {
    const uint8_t *p = (const uint8_t *)data;
    uint32_t sum = 0;
    while (len > 1) {
        sum += ((uint32_t)p[0] << 8) | (uint32_t)p[1];
        p += 2;
        len -= 2;
    }
    if (len == 1) sum += ((uint32_t)p[0] << 8);
    while (sum >> 16) sum = (sum & 0xFFFFu) + (sum >> 16);
    return (uint16_t)(~sum & 0xFFFFu);
}

static uint16_t tcp_cksum(uint32_t src_ip, uint32_t dst_ip, const uint8_t *seg, int len) {
    uint32_t sum = 0;
    sum += (src_ip >> 16) & 0xFFFFu;
    sum += src_ip & 0xFFFFu;
    sum += (dst_ip >> 16) & 0xFFFFu;
    sum += dst_ip & 0xFFFFu;
    sum += (uint32_t)IP_TCP;
    sum += (uint32_t)len;

    const uint8_t *p = seg;
    int rem = len;
    while (rem > 1) {
        sum += ((uint32_t)p[0] << 8) | (uint32_t)p[1];
        p += 2;
        rem -= 2;
    }
    if (rem == 1) sum += ((uint32_t)p[0] << 8);
    while (sum >> 16) sum = (sum & 0xFFFFu) + (sum >> 16);
    return (uint16_t)(~sum & 0xFFFFu);
}

void net_imprimir_ip(uint32_t ip) {
    kprint_dec((ip >> 24) & 0xFFu); kputc('.');
    kprint_dec((ip >> 16) & 0xFFu); kputc('.');
    kprint_dec((ip >> 8)  & 0xFFu); kputc('.');
    kprint_dec(ip & 0xFFu);
}

static void imprimir_mac(const uint8_t m[6]) {
    static const char hx[] = "0123456789ABCDEF";
    for (int i = 0; i < 6; i++) {
        if (i > 0) kputc(':');
        kputc(hx[(m[i] >> 4) & 0xF]);
        kputc(hx[m[i] & 0xF]);
    }
}

static int parsear_ip(const char *s, uint32_t *out) {
    uint32_t partes[4];
    const char *p = s;
    for (int i = 0; i < 4; i++) {
        if (*p < '0' || *p > '9') return -1;
        uint32_t v = 0;
        while (*p >= '0' && *p <= '9') {
            v = v * 10 + (uint32_t)(*p - '0');
            if (v > 255) return -1;
            p++;
        }
        partes[i] = v;
        if (i < 3) {
            if (*p != '.') return -1;
            p++;
        }
    }
    if (*p != '\0') return -1;
    *out = ip4((uint8_t)partes[0], (uint8_t)partes[1], (uint8_t)partes[2], (uint8_t)partes[3]);
    return 0;
}

/* ---------- Capa ARP ---------- */
static void arp_guardar(uint32_t ip, const uint8_t mac[6]) {
    if (ip == 0) return;
    for (int i = 0; i < ARP_MAX; i++) {
        if (arp_cache[i].valido && arp_cache[i].ip == ip) {
            for (int j = 0; j < 6; j++) arp_cache[i].mac[j] = mac[j];
            return;
        }
    }
    int slot = 0;
    for (int i = 0; i < ARP_MAX; i++) {
        if (!arp_cache[i].valido) { slot = i; break; }
    }
    arp_cache[slot].ip = ip;
    for (int j = 0; j < 6; j++) arp_cache[slot].mac[j] = mac[j];
    arp_cache[slot].valido = 1;
}

static int arp_buscar(uint32_t ip, uint8_t mac_out[6]) {
    for (int i = 0; i < ARP_MAX; i++) {
        if (arp_cache[i].valido && arp_cache[i].ip == ip) {
            for (int j = 0; j < 6; j++) mac_out[j] = arp_cache[i].mac[j];
            return 0;
        }
    }
    return -1;
}

static void arp_enviar(uint16_t oper, uint32_t dst_ip, const uint8_t dst_mac[6]) {
    eth_hdr_t *eth = (eth_hdr_t *)tx_frame;
    arp_pkt_t *arp = (arp_pkt_t *)(tx_frame + sizeof(eth_hdr_t));
    for (int i = 0; i < 6; i++) {
        eth->dst[i] = (oper == 1) ? 0xFF : dst_mac[i];
        eth->src[i] = mi_mac[i];
        arp->sha[i] = mi_mac[i];
        arp->tha[i] = (oper == 1) ? 0x00 : dst_mac[i];
    }
    eth->tipo  = htons(ETH_ARP);
    arp->htype = htons(1);
    arp->ptype = htons(ETH_IPV4);
    arp->hlen  = 6;
    arp->plen  = 4;
    arp->oper  = htons(oper);
    arp->spa   = htonl(mi_ip);
    arp->tpa   = htonl(dst_ip);
    e1000_enviar(tx_frame, (uint16_t)(sizeof(eth_hdr_t) + sizeof(arp_pkt_t)));
}

static void net_poll(void);

static int arp_resolver(uint32_t ip_dest, uint8_t mac_out[6]) {
    if (ip_dest == 0xFFFFFFFFu) {
        for (int i = 0; i < 6; i++) mac_out[i] = 0xFF;
        return 0;
    }
    uint32_t next_hop = ip_dest;
    if (mi_ip != 0 && mi_mask != 0 && mi_gw != 0) {
        if ((ip_dest & mi_mask) != (mi_ip & mi_mask)) next_hop = mi_gw;
    }
    if (arp_buscar(next_hop, mac_out) == 0) return 0;

    static const uint8_t cero[6] = { 0 };
    uint32_t t0 = reloj_ticks();
    uint32_t ult = 0;
    while (reloj_ticks() - t0 < 150) {
        if (ult == 0 || reloj_ticks() - ult >= 35) {
            arp_enviar(1, next_hop, cero);
            ult = reloj_ticks();
        }
        net_poll();
        if (arp_buscar(next_hop, mac_out) == 0) return 0;
        if (reloj_activo()) __asm__ volatile("hlt");
    }
    return -1;
}

/* ---------- Envio IPv4 / UDP / TCP ---------- */
static int ip_enviar(uint32_t dst_ip, uint8_t proto, const uint8_t *payload, uint16_t plen) {
    if (plen > 1480) return -1;
    uint8_t dst_mac[6];
    if (arp_resolver(dst_ip, dst_mac) != 0) return -1;

    eth_hdr_t *eth = (eth_hdr_t *)tx_frame;
    ip_hdr_t  *ip  = (ip_hdr_t *)(tx_frame + sizeof(eth_hdr_t));
    uint8_t   *dat = tx_frame + sizeof(eth_hdr_t) + sizeof(ip_hdr_t);

    for (int i = 0; i < 6; i++) { eth->dst[i] = dst_mac[i]; eth->src[i] = mi_mac[i]; }
    eth->tipo = htons(ETH_IPV4);

    ip->ihl_ver  = 0x45;
    ip->tos      = 0;
    ip->tot_len  = htons((uint16_t)(sizeof(ip_hdr_t) + plen));
    ip->id       = htons(ip_id_seq++);
    ip->frag_off = htons(0x4000u); /* Don't Fragment */
    ip->ttl      = 64;
    ip->proto    = proto;
    ip->checksum = 0;
    ip->src      = htonl(mi_ip);
    ip->dst      = htonl(dst_ip);
    ip->checksum = htons(cksum16(ip, sizeof(ip_hdr_t)));

    for (uint16_t i = 0; i < plen; i++) dat[i] = payload[i];
    return e1000_enviar(tx_frame, (uint16_t)(sizeof(eth_hdr_t) + sizeof(ip_hdr_t) + plen));
}

static int udp_enviar(uint32_t dst_ip, uint16_t src_p, uint16_t dst_p, const uint8_t *data, uint16_t dlen) {
    uint8_t buf[1480];
    if (dlen + sizeof(udp_hdr_t) > sizeof(buf)) return -1;
    udp_hdr_t *u = (udp_hdr_t *)buf;
    u->src_port = htons(src_p);
    u->dst_port = htons(dst_p);
    u->len      = htons((uint16_t)(sizeof(udp_hdr_t) + dlen));
    u->checksum = 0;
    for (uint16_t i = 0; i < dlen; i++) buf[sizeof(udp_hdr_t) + i] = data[i];
    return ip_enviar(dst_ip, IP_UDP, buf, (uint16_t)(sizeof(udp_hdr_t) + dlen));
}

static int tcp_enviar_seg(uint8_t flags, const uint8_t *data, uint16_t dlen) {
    uint8_t seg[1460];
    if (dlen + sizeof(tcp_hdr_t) > sizeof(seg)) return -1;
    tcp_hdr_t *t = (tcp_hdr_t *)seg;
    t->src_port = htons(tcp_loc_port);
    t->dst_port = htons(tcp_rem_port);
    t->seq      = htonl(tcp_snd_nxt);
    t->ack      = htonl(tcp_rcv_nxt);
    t->off_res  = 0x50; /* 20 bytes */
    t->flags    = flags;
    t->window   = htons(8192);
    t->checksum = 0;
    t->urg_ptr  = 0;
    for (uint16_t i = 0; i < dlen; i++) seg[sizeof(tcp_hdr_t) + i] = data[i];
    t->checksum = htons(tcp_cksum(mi_ip, tcp_rem_ip, seg, (int)(sizeof(tcp_hdr_t) + dlen)));
    return ip_enviar(tcp_rem_ip, IP_TCP, seg, (uint16_t)(sizeof(tcp_hdr_t) + dlen));
}

/* ---------- Procesamiento de paquetes entrantes ---------- */
static void manejar_dhcp_rx(const uint8_t *p, int len) {
    if (!dhcp_esperando || len < 244) return;
    if (p[0] != 2) return; /* BOOTREPLY */
    uint32_t xid = ((uint32_t)p[4] << 24) | ((uint32_t)p[5] << 16) |
                   ((uint32_t)p[6] << 8)  | (uint32_t)p[7];
    if (xid != dhcp_xid_esp) return;
    if (p[236] != 99 || p[237] != 130 || p[238] != 83 || p[239] != 99) return;

    uint32_t yi = ((uint32_t)p[16] << 24) | ((uint32_t)p[17] << 16) |
                  ((uint32_t)p[18] << 8)  | (uint32_t)p[19];

    int msg_type = 0;
    uint32_t mask = ip4(255, 255, 255, 0), gw = 0, dns = 0, srv = 0;
    int i = 240;
    while (i < len) {
        uint8_t opt = p[i++];
        if (opt == 0) continue;
        if (opt == 255) break;
        if (i >= len) break;
        uint8_t olen = p[i++];
        if (i + olen > len) break;
        if (opt == 53 && olen >= 1) msg_type = p[i];
        else if (opt == 1 && olen >= 4) mask = ip4(p[i], p[i+1], p[i+2], p[i+3]);
        else if (opt == 3 && olen >= 4) gw   = ip4(p[i], p[i+1], p[i+2], p[i+3]);
        else if (opt == 6 && olen >= 4) dns  = ip4(p[i], p[i+1], p[i+2], p[i+3]);
        else if (opt == 54 && olen >= 4) srv = ip4(p[i], p[i+1], p[i+2], p[i+3]);
        i += olen;
    }

    if (msg_type == 2 || msg_type == 5) {
        dhcp_msg_rec = msg_type;
        dhcp_yiaddr  = yi;
        dhcp_mask    = mask;
        if (gw)  dhcp_gw  = gw;
        if (dns) dhcp_dns = dns;
        if (srv) dhcp_srv = srv;
    }
}

static int dns_saltar_nombre(const uint8_t *p, int len, int off) {
    int guarda = 0;
    while (off < len && guarda++ < 64) {
        uint8_t b = p[off];
        if (b == 0) return off + 1;
        if ((b & 0xC0) == 0xC0) return (off + 2 <= len) ? (off + 2) : -1;
        off += 1 + (int)b;
    }
    return -1;
}

static void manejar_dns_rx(const uint8_t *p, int len) {
    if (!dns_esperando || len < 12) return;
    uint16_t id = (uint16_t)(((uint16_t)p[0] << 8) | p[1]);
    if (id != dns_id_esp) return;
    if (!(p[2] & 0x80)) return; /* debe ser respuesta */
    uint8_t rcode = p[3] & 0x0F;
    if (rcode != 0) { dns_ok_rec = -1; return; }

    uint16_t qdcount = (uint16_t)(((uint16_t)p[4] << 8) | p[5]);
    uint16_t ancount = (uint16_t)(((uint16_t)p[6] << 8) | p[7]);

    int off = 12;
    for (uint16_t q = 0; q < qdcount; q++) {
        off = dns_saltar_nombre(p, len, off);
        if (off < 0 || off + 4 > len) return;
        off += 4;
    }
    for (uint16_t a = 0; a < ancount; a++) {
        off = dns_saltar_nombre(p, len, off);
        if (off < 0 || off + 10 > len) return;
        uint16_t tipo  = (uint16_t)(((uint16_t)p[off] << 8) | p[off + 1]);
        uint16_t clase = (uint16_t)(((uint16_t)p[off + 2] << 8) | p[off + 3]);
        uint16_t rdlen = (uint16_t)(((uint16_t)p[off + 8] << 8) | p[off + 9]);
        off += 10;
        if (off + rdlen > len) return;
        if (tipo == 1 && clase == 1 && rdlen == 4) {
            dns_ip_rec = ip4(p[off], p[off + 1], p[off + 2], p[off + 3]);
            dns_ok_rec = 1;
            return;
        }
        off += rdlen;
    }
    dns_ok_rec = -1;
}

static void manejar_tcp_rx(uint32_t src_ip, const uint8_t *p, int len) {
    if (!tcp_activo || len < (int)sizeof(tcp_hdr_t)) return;
    const tcp_hdr_t *t = (const tcp_hdr_t *)p;
    if (src_ip != tcp_rem_ip) return;
    if (ntohs(t->src_port) != tcp_rem_port || ntohs(t->dst_port) != tcp_loc_port) return;

    int hdr_len = ((t->off_res >> 4) & 0xF) * 4;
    if (hdr_len < 20 || hdr_len > len) return;

    uint32_t seg_seq = ntohl(t->seq);
    uint32_t seg_ack = ntohl(t->ack);
    uint8_t  fl      = t->flags;
    const uint8_t *payload = p + hdr_len;
    int plen = len - hdr_len;

    if (fl & TCP_RST) {
        tcp_reset = 1;
        tcp_cerrado = 1;
        return;
    }

    if (!tcp_conectado) {
        if ((fl & (TCP_SYN | TCP_ACK)) == (TCP_SYN | TCP_ACK) && seg_ack == tcp_snd_nxt) {
            tcp_rcv_nxt = seg_seq + 1;
            tcp_conectado = 1;
            tcp_enviar_seg(TCP_ACK, 0, 0);
        }
        return;
    }

    int enviar_ack = 0;
    if (plen > 0) {
        if (seg_seq == tcp_rcv_nxt) {
            for (int i = 0; i < plen; i++) {
                if (tcp_user_buf && tcp_user_len < tcp_user_max - 1) {
                    tcp_user_buf[tcp_user_len++] = (char)payload[i];
                }
            }
            if (tcp_user_buf) tcp_user_buf[tcp_user_len] = '\0';
            tcp_rcv_nxt += (uint32_t)plen;
            enviar_ack = 1;
        } else if (seg_seq < tcp_rcv_nxt) {
            /* Retransmision o solapamiento parcial */
            uint32_t diff = tcp_rcv_nxt - seg_seq;
            if ((int)diff < plen) {
                for (int i = (int)diff; i < plen; i++) {
                    if (tcp_user_buf && tcp_user_len < tcp_user_max - 1) {
                        tcp_user_buf[tcp_user_len++] = (char)payload[i];
                    }
                }
                if (tcp_user_buf) tcp_user_buf[tcp_user_len] = '\0';
                tcp_rcv_nxt += (uint32_t)(plen - (int)diff);
            }
            enviar_ack = 1;
        }
    }

    if (fl & TCP_FIN) {
        if (seg_seq + (uint32_t)plen == tcp_rcv_nxt) tcp_rcv_nxt++;
        tcp_cerrado = 1;
        tcp_enviar_seg(TCP_FIN | TCP_ACK, 0, 0);
        tcp_snd_nxt++;
        return;
    }

    if (enviar_ack) {
        tcp_enviar_seg(TCP_ACK, 0, 0);
    }
}

static void net_poll(void) {
    for (int iter = 0; iter < 12; iter++) {
        int flen = e1000_recibir(rx_frame, sizeof(rx_frame));
        if (flen < (int)sizeof(eth_hdr_t)) break;

        const eth_hdr_t *eth = (const eth_hdr_t *)rx_frame;
        uint16_t tipo = ntohs(eth->tipo);

        if (tipo == ETH_ARP && flen >= (int)(sizeof(eth_hdr_t) + sizeof(arp_pkt_t))) {
            const arp_pkt_t *arp = (const arp_pkt_t *)(rx_frame + sizeof(eth_hdr_t));
            uint32_t spa = ntohl(arp->spa);
            uint32_t tpa = ntohl(arp->tpa);
            uint16_t op  = ntohs(arp->oper);
            arp_guardar(spa, arp->sha);
            if (op == 1 && mi_ip != 0 && tpa == mi_ip) {
                arp_enviar(2, spa, arp->sha);
            }
        } else if (tipo == ETH_IPV4 && flen >= (int)(sizeof(eth_hdr_t) + sizeof(ip_hdr_t))) {
            const ip_hdr_t *ip = (const ip_hdr_t *)(rx_frame + sizeof(eth_hdr_t));
            int ihl = (ip->ihl_ver & 0x0F) * 4;
            int tot = ntohs(ip->tot_len);
            if (ihl < 20 || tot < ihl || (int)sizeof(eth_hdr_t) + tot > flen) continue;

            uint32_t src_ip = ntohl(ip->src);
            uint32_t dst_ip = ntohl(ip->dst);
            const uint8_t *pl = rx_frame + sizeof(eth_hdr_t) + ihl;
            int plen = tot - ihl;

            if (mi_ip != 0 && dst_ip != mi_ip && dst_ip != 0xFFFFFFFFu) continue;
            if (src_ip != 0) arp_guardar(src_ip, eth->src);

            if (ip->proto == IP_ICMP && plen >= (int)sizeof(icmp_hdr_t)) {
                const icmp_hdr_t *ic = (const icmp_hdr_t *)pl;
                if (ic->tipo == 0 && ping_esperando) {
                    if (src_ip == ping_ip_esp &&
                        ntohs(ic->id) == ping_id_esp &&
                        ntohs(ic->seq) == ping_seq_esp) {
                        ping_recibido = 1;
                        ping_ttl_rec = ip->ttl;
                    }
                } else if (ic->tipo == 8 && mi_ip != 0 && dst_ip == mi_ip && plen <= 1480) {
                    uint8_t rep[1480];
                    for (int i = 0; i < plen; i++) rep[i] = pl[i];
                    icmp_hdr_t *ric = (icmp_hdr_t *)rep;
                    ric->tipo = 0;
                    ric->checksum = 0;
                    ric->checksum = htons(cksum16(rep, plen));
                    ip_enviar(src_ip, IP_ICMP, rep, (uint16_t)plen);
                }
            } else if (ip->proto == IP_UDP && plen >= (int)sizeof(udp_hdr_t)) {
                const udp_hdr_t *u = (const udp_hdr_t *)pl;
                uint16_t sport = ntohs(u->src_port);
                uint16_t dport = ntohs(u->dst_port);
                int ulen = (int)ntohs(u->len) - (int)sizeof(udp_hdr_t);
                if (ulen < 0 || ulen > plen - (int)sizeof(udp_hdr_t)) continue;
                const uint8_t *udat = pl + sizeof(udp_hdr_t);
                if (sport == 67 && dport == 68) manejar_dhcp_rx(udat, ulen);
                else if (sport == 53) manejar_dns_rx(udat, ulen);
            } else if (ip->proto == IP_TCP) {
                manejar_tcp_rx(src_ip, pl, plen);
            }
        }
    }
}

/* ---------- DHCP Client ---------- */
static void dhcp_enviar_pkt(uint8_t msg_type, uint32_t xid, uint32_t req_ip, uint32_t srv_ip) {
    uint8_t pkt[300];
    for (int i = 0; i < (int)sizeof(pkt); i++) pkt[i] = 0;

    pkt[0] = 1; /* BOOTREQUEST */
    pkt[1] = 1; /* Ethernet */
    pkt[2] = 6; /* MAC len */
    pkt[4] = (uint8_t)(xid >> 24);
    pkt[5] = (uint8_t)(xid >> 16);
    pkt[6] = (uint8_t)(xid >> 8);
    pkt[7] = (uint8_t)(xid & 0xFF);
    pkt[10] = 0x80; /* Broadcast flag */
    for (int i = 0; i < 6; i++) pkt[28 + i] = mi_mac[i];

    /* Magic cookie */
    pkt[236] = 99; pkt[237] = 130; pkt[238] = 83; pkt[239] = 99;
    int o = 240;
    pkt[o++] = 53; pkt[o++] = 1; pkt[o++] = msg_type;
    if (msg_type == 3) {
        pkt[o++] = 50; pkt[o++] = 4;
        pkt[o++] = (uint8_t)(req_ip >> 24); pkt[o++] = (uint8_t)(req_ip >> 16);
        pkt[o++] = (uint8_t)(req_ip >> 8);  pkt[o++] = (uint8_t)(req_ip & 0xFF);
        if (srv_ip) {
            pkt[o++] = 54; pkt[o++] = 4;
            pkt[o++] = (uint8_t)(srv_ip >> 24); pkt[o++] = (uint8_t)(srv_ip >> 16);
            pkt[o++] = (uint8_t)(srv_ip >> 8);  pkt[o++] = (uint8_t)(srv_ip & 0xFF);
        }
    }
    pkt[o++] = 55; pkt[o++] = 3; pkt[o++] = 1; pkt[o++] = 3; pkt[o++] = 6;
    pkt[o++] = 255;

    uint32_t ip_prev = mi_ip;
    mi_ip = 0;
    udp_enviar(0xFFFFFFFFu, 68, 67, pkt, (uint16_t)o);
    mi_ip = ip_prev;
}

int net_dhcp(int silencioso) {
    if (!net_up) return -1;
    uint32_t xid = 0xA9050001u ^ (reloj_ticks() + 17u);
    dhcp_xid_esp = xid;
    dhcp_esperando = 1;
    dhcp_msg_rec = 0;
    dhcp_yiaddr = 0; dhcp_srv = 0; dhcp_mask = 0; dhcp_gw = 0; dhcp_dns = 0;

    /* 1) DISCOVER -> OFFER */
    uint32_t t0 = reloj_ticks(), ult = 0;
    while (reloj_ticks() - t0 < 200) {
        if (ult == 0 || reloj_ticks() - ult >= 65) {
            dhcp_enviar_pkt(1, xid, 0, 0);
            ult = reloj_ticks();
        }
        net_poll();
        if (dhcp_msg_rec == 2 && dhcp_yiaddr != 0) break;
        if (reloj_activo()) __asm__ volatile("hlt");
    }
    if (dhcp_msg_rec != 2 || dhcp_yiaddr == 0) {
        dhcp_esperando = 0;
        if (!silencioso) kprint("DHCP: no se recibió oferta (verifica Red -> NAT + Intel PRO/1000).\n");
        return -1;
    }

    /* 2) REQUEST -> ACK */
    uint32_t ofrecida = dhcp_yiaddr;
    uint32_t servidor = dhcp_srv;
    dhcp_msg_rec = 0;
    t0 = reloj_ticks(); ult = 0;
    while (reloj_ticks() - t0 < 200) {
        if (ult == 0 || reloj_ticks() - ult >= 65) {
            dhcp_enviar_pkt(3, xid, ofrecida, servidor);
            ult = reloj_ticks();
        }
        net_poll();
        if (dhcp_msg_rec == 5) break;
        if (reloj_activo()) __asm__ volatile("hlt");
    }
    dhcp_esperando = 0;
    if (dhcp_msg_rec != 5) {
        if (!silencioso) kprint("DHCP: no se recibió confirmación (ACK).\n");
        return -1;
    }

    mi_ip   = dhcp_yiaddr;
    mi_mask = dhcp_mask ? dhcp_mask : ip4(255, 255, 255, 0);
    mi_gw   = dhcp_gw   ? dhcp_gw   : ip4(10, 0, 2, 2);
    mi_dns  = dhcp_dns  ? dhcp_dns  : ip4(10, 0, 2, 3);

    audit_registrar(LOG_OK, "red", "DHCP_OK", "IP asignada por DHCP");
    if (!silencioso) {
        kset_color(0x0A); kprint("DHCP OK: ");
        kset_color(0x0F); net_imprimir_ip(mi_ip);
        kset_color(0x07); kprint("  GW="); net_imprimir_ip(mi_gw);
        kprint("  DNS="); net_imprimir_ip(mi_dns);
        kprint("\n");
    }
    return 0;
}

/* ---------- Inicializacion ---------- */
int net_init(void) {
    for (int i = 0; i < ARP_MAX; i++) arp_cache[i].valido = 0;
    mi_ip = 0; mi_mask = 0; mi_gw = 0; mi_dns = 0;
    net_up = 0;

    if (e1000_init() != 0) return -1;
    e1000_obtener_mac(mi_mac);
    net_up = 1;

    /* Esperar brevemente a que la NIC virtual levante el enlace antes del primer DHCP */
    uint32_t t0 = reloj_ticks();
    while (!e1000_enlace_activo() && (reloj_ticks() - t0) < 60) {
        if (reloj_activo()) __asm__ volatile("hlt");
    }
    if (net_dhcp(1) != 0) {
        net_dhcp(1);
    }
    return 0;
}

int net_listo(void) { return net_up; }
int net_tiene_ip(void) { return net_up && mi_ip != 0; }
uint32_t net_mi_ip(void) { return mi_ip; }
uint32_t net_mi_gw(void) { return mi_gw ? mi_gw : ip4(10, 0, 2, 2); }

/* ---------- DNS Resolver (UDP 53) ---------- */
static int dns_consultar_servidor(uint32_t dns_ip, const char *dominio, uint32_t *ip_out) {
    uint8_t q[256];
    uint16_t id = (uint16_t)(0x4100u + (reloj_ticks() & 0xFFu) + ip_id_seq++);
    for (int i = 0; i < 12; i++) q[i] = 0;
    q[0] = (uint8_t)(id >> 8); q[1] = (uint8_t)(id & 0xFF);
    q[2] = 0x01; /* RD = 1 (recursion deseada) */
    q[5] = 1;    /* QDCOUNT = 1 */

    int off = 12;
    const char *p = dominio;
    while (*p) {
        int lbl_pos = off++;
        int lbl_len = 0;
        while (*p && *p != '.' && off < 240) {
            q[off++] = (uint8_t)*p++;
            lbl_len++;
        }
        if (lbl_len == 0 || lbl_len > 63 || off >= 240) return -1;
        q[lbl_pos] = (uint8_t)lbl_len;
        if (*p == '.') p++;
    }
    q[off++] = 0;
    q[off++] = 0; q[off++] = 1; /* QTYPE = A */
    q[off++] = 0; q[off++] = 1; /* QCLASS = IN */

    dns_id_esp = id;
    dns_esperando = 1;
    dns_ok_rec = 0;
    dns_ip_rec = 0;

    uint16_t sport = eph_port++;
    if (eph_port > 60000) eph_port = 49152;

    uint32_t t0 = reloj_ticks(), ult = 0;
    while (reloj_ticks() - t0 < 220) {
        if (ult == 0 || reloj_ticks() - ult >= 80) {
            udp_enviar(dns_ip, sport, 53, q, (uint16_t)off);
            ult = reloj_ticks();
        }
        net_poll();
        if (dns_ok_rec != 0) break;
        if (reloj_activo()) __asm__ volatile("hlt");
    }
    dns_esperando = 0;
    if (dns_ok_rec == 1 && dns_ip_rec != 0) {
        *ip_out = dns_ip_rec;
        return 0;
    }
    return -1;
}

int net_resolver_dns(const char *dominio, uint32_t *ip_out) {
    if (!net_tiene_ip()) return -1;
    if (parsear_ip(dominio, ip_out) == 0) return 0;
    if (mi_dns && dns_consultar_servidor(mi_dns, dominio, ip_out) == 0) return 0;
    uint32_t google_dns = ip4(8, 8, 8, 8);
    if (mi_dns != google_dns && dns_consultar_servidor(google_dns, dominio, ip_out) == 0) return 0;
    return -1;
}

/* ---------- Cliente TCP + HTTP/1.1 ---------- */
int net_http_get(const char *host, uint16_t port, const char *ruta, char *out_buf, int max_len, int *http_code) {
    if (!net_tiene_ip()) return -1;
    uint32_t dst_ip = 0;
    if (net_resolver_dns(host, &dst_ip) != 0) return -2;

    uint8_t dummy_mac[6];
    if (arp_resolver(dst_ip, dummy_mac) != 0) return -3;

    tcp_activo    = 1;
    tcp_conectado = 0;
    tcp_cerrado   = 0;
    tcp_reset     = 0;
    tcp_rem_ip    = dst_ip;
    tcp_rem_port  = port;
    tcp_loc_port  = eph_port++;
    if (eph_port > 60000) eph_port = 49152;
    tcp_snd_nxt   = 0x12340000u ^ (reloj_ticks() * 257u);
    tcp_rcv_nxt   = 0;
    tcp_user_buf  = out_buf;
    tcp_user_max  = max_len;
    tcp_user_len  = 0;
    if (out_buf && max_len > 0) out_buf[0] = '\0';

    /* 1) Handshake TCP: SYN -> SYN+ACK -> ACK */
    uint32_t syn_seq = tcp_snd_nxt;
    uint32_t t0 = reloj_ticks(), ult = 0;
    while (reloj_ticks() - t0 < 350) {
        if (ult == 0 || reloj_ticks() - ult >= 100) {
            tcp_snd_nxt = syn_seq;
            tcp_enviar_seg(TCP_SYN, 0, 0);
            tcp_snd_nxt = syn_seq + 1;
            ult = reloj_ticks();
        }
        net_poll();
        if (tcp_conectado || tcp_reset) break;
        if (reloj_activo()) __asm__ volatile("hlt");
    }
    if (!tcp_conectado) {
        tcp_activo = 0;
        return -4;
    }

    /* 2) Construir y enviar peticion HTTP/1.1 */
    char req[512];
    int r = 0;
    const char *p1 = "GET ";
    const char *p2 = " HTTP/1.1\r\nHost: ";
    const char *p3 = "\r\nUser-Agent: ARGOS-OS/6.0\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n";
    for (int i = 0; p1[i] && r < 500; i++) req[r++] = p1[i];
    if (!ruta || !ruta[0]) { req[r++] = '/'; }
    else {
        if (ruta[0] != '/') req[r++] = '/';
        for (int i = 0; ruta[i] && r < 350; i++) req[r++] = ruta[i];
    }
    for (int i = 0; p2[i] && r < 420; i++) req[r++] = p2[i];
    for (int i = 0; host[i] && r < 460; i++) req[r++] = host[i];
    for (int i = 0; p3[i] && r < 511; i++) req[r++] = p3[i];
    req[r] = '\0';

    tcp_enviar_seg(TCP_PSH | TCP_ACK, (const uint8_t *)req, (uint16_t)r);
    tcp_snd_nxt += (uint32_t)r;

    /* 3) Recibir segmentos hasta FIN o inactividad */
    t0 = reloj_ticks();
    uint32_t ult_dato = t0;
    int prev_len = 0;
    while (reloj_ticks() - t0 < 1200) {
        net_poll();
        if (tcp_user_len != prev_len) {
            prev_len = tcp_user_len;
            ult_dato = reloj_ticks();
        }
        if (tcp_cerrado || tcp_user_len >= max_len - 1) break;
        if (tcp_user_len > 0 && (reloj_ticks() - ult_dato) > 150) break;
        if (reloj_activo()) __asm__ volatile("hlt");
    }

    if (!tcp_cerrado) {
        tcp_enviar_seg(TCP_FIN | TCP_ACK, 0, 0);
        tcp_snd_nxt++;
    }
    tcp_activo = 0;

    if (http_code) {
        *http_code = 0;
        if (tcp_user_len >= 12 && out_buf[0] == 'H' && out_buf[1] == 'T' &&
            out_buf[2] == 'T' && out_buf[3] == 'P') {
            int k = 0;
            while (k < tcp_user_len && out_buf[k] != ' ') k++;
            while (k < tcp_user_len && out_buf[k] == ' ') k++;
            int code = 0;
            for (int d = 0; d < 3 && k + d < tcp_user_len; d++) {
                if (out_buf[k + d] >= '0' && out_buf[k + d] <= '9')
                    code = code * 10 + (out_buf[k + d] - '0');
            }
            *http_code = code;
        }
    }
    return tcp_user_len;
}

/* ==================== COMANDOS DE CONSOLA ==================== */

void net_cmd_net(const char *args) {
    while (*args == ' ') args++;

    if (n_igual(args, "dhcp")) {
        if (!net_up) {
            if (e1000_init() == 0) { e1000_obtener_mac(mi_mac); net_up = 1; }
            else {
                kset_color(0x0C);
                kprint("No se detectó NIC Intel PRO/1000 (82540EM).\n");
                kset_color(0x07);
                kprint("En VirtualBox: Configuración -> Red -> Adaptador 1 -> NAT ->\n");
                kprint("Avanzadas -> Tipo: Intel PRO/1000 MT Desktop (82540EM).\n");
                return;
            }
        }
        kprint("Solicitando IP por DHCP...\n");
        net_dhcp(0);
        return;
    }

    if (n_igual(args, "arp")) {
        kset_color(0x0D); kprint("=== Tabla ARP en memoria ===\n");
        kset_color(0x0B); kprint("  IP                MAC\n");
        kset_color(0x07);
        int hay = 0;
        for (int i = 0; i < ARP_MAX; i++) {
            if (!arp_cache[i].valido) continue;
            hay = 1;
            kprint("  ");
            net_imprimir_ip(arp_cache[i].ip);
            kprint("        ");
            imprimir_mac(arp_cache[i].mac);
            kprint("\n");
        }
        if (!hay) kprint("  (caché ARP vacía)\n");
        return;
    }

    if (args[0] != '\0' && !n_igual(args, "info")) {
        kprint("Uso: net | net info | net dhcp | net arp\n");
        return;
    }

    kset_color(0x0D); kprint("=== Estado de Red (ARGOS TCP/IP) ===\n");
    if (!net_up) {
        kset_color(0x0C); kprint("  NIC      : No detectada\n");
        kset_color(0x07);
        kprint("  Configura en VirtualBox -> Red -> Adaptador 1: NAT + Intel PRO/1000 MT Desktop.\n");
        return;
    }

    uint32_t tx = 0, rx = 0;
    e1000_stats(&tx, &rx);

    kset_color(0x0B); kprint("  NIC      : ");
    kset_color(0x0F); kprint("Intel PRO/1000 e1000 (PCI 0x8086:");
    kprint_hex(e1000_device_id(), 4); kprint(")  MMIO=");
    kprint_hex(e1000_mmio_base(), 8); kprint("\n");

    kset_color(0x0B); kprint("  Enlace   : ");
    if (e1000_enlace_activo()) { kset_color(0x0A); kprint("ACTIVO (Link Up)"); }
    else { kset_color(0x0C); kprint("CAÍDO (Sin cable)"); }
    kset_color(0x07); kprint("  |  MAC: "); imprimir_mac(mi_mac); kprint("\n");

    kset_color(0x0B); kprint("  IPv4     : ");
    if (mi_ip) {
        kset_color(0x0F); net_imprimir_ip(mi_ip);
        kset_color(0x07); kprint("  Máscara: "); net_imprimir_ip(mi_mask); kprint("\n");
        kset_color(0x0B); kprint("  Gateway  : ");
        kset_color(0x07); net_imprimir_ip(mi_gw);
        kprint("  |  DNS: "); net_imprimir_ip(mi_dns); kprint("\n");
    } else {
        kset_color(0x0E); kprint("Sin asignar (ejecuta 'net dhcp')\n");
    }

    kset_color(0x0B); kprint("  Tráfico  : ");
    kset_color(0x07); kprint("TX="); kprint_dec(tx);
    kprint(" tramas  |  RX="); kprint_dec(rx); kprint(" tramas\n");
    kset_color(0x08);
    kprint("  Comandos: net dhcp | net arp | ping <host> | dns <dominio> | http <host> [ruta]\n");
    kset_color(0x07);
}

void net_cmd_ping(const char *args) {
    while (*args == ' ') args++;
    if (!*args) {
        kprint("Uso: ping <ip | dominio>   (ej: ping 10.0.2.2  o  ping google.com)\n");
        return;
    }
    if (!net_tiene_ip()) {
        kprint("Sin IP configurada. Ejecuta 'net dhcp' o revisa la tarjeta de red en VirtualBox.\n");
        return;
    }

    uint32_t dst_ip = 0;
    if (parsear_ip(args, &dst_ip) != 0) {
        kprint("Resolviendo DNS para '"); kprint(args); kprint("'...\n");
        if (net_resolver_dns(args, &dst_ip) != 0) {
            kset_color(0x0C); kprint("Error: no se pudo resolver el dominio.\n");
            kset_color(0x07);
            return;
        }
    }

    kprint("PING "); kprint(args); kprint(" ("); net_imprimir_ip(dst_ip); kprint(") 32 bytes de datos:\n");

    int recibidos = 0;
    uint16_t pid = (uint16_t)(0x3400u + (reloj_ticks() & 0xFFu));

    for (uint16_t seq = 1; seq <= 4; seq++) {
        uint8_t pkt[sizeof(icmp_hdr_t) + 32];
        icmp_hdr_t *ic = (icmp_hdr_t *)pkt;
        ic->tipo = 8; /* Echo Request */
        ic->codigo = 0;
        ic->checksum = 0;
        ic->id = htons(pid);
        ic->seq = htons(seq);
        for (int i = 0; i < 32; i++) pkt[sizeof(icmp_hdr_t) + i] = (uint8_t)('A' + (i % 26));
        ic->checksum = htons(cksum16(pkt, (int)sizeof(pkt)));

        ping_esperando = 1;
        ping_id_esp = pid;
        ping_seq_esp = seq;
        ping_ip_esp = dst_ip;
        ping_recibido = 0;

        uint32_t t_env = reloj_ticks();
        if (ip_enviar(dst_ip, IP_ICMP, pkt, (uint16_t)sizeof(pkt)) != 0) {
            ping_esperando = 0;
            kset_color(0x0C); kprint("  Error enviando paquete (ARP/red).\n");
            kset_color(0x07);
            continue;
        }

        while (reloj_ticks() - t_env < 150) {
            net_poll();
            if (ping_recibido) break;
            if (reloj_activo()) __asm__ volatile("hlt");
        }
        ping_esperando = 0;

        if (ping_recibido) {
            uint32_t ms = (reloj_ticks() - t_env) * 10u;
            recibidos++;
            kprint("  Respuesta desde "); net_imprimir_ip(dst_ip);
            kprint(": seq="); kprint_dec(seq);
            kprint(" ttl="); kprint_dec(ping_ttl_rec);
            kprint(" tiempo=");
            if (ms == 0) kprint("<10 ms\n");
            else { kprint_dec(ms); kprint(" ms\n"); }
        } else {
            kset_color(0x0E);
            kprint("  Tiempo de espera agotado (seq="); kprint_dec(seq); kprint(")\n");
            kset_color(0x07);
        }

        if (seq < 4) {
            uint32_t tw = reloj_ticks();
            while (reloj_ticks() - tw < 50) {
                net_poll();
                if (reloj_activo()) __asm__ volatile("hlt");
            }
        }
    }

    kset_color(0x0B); kprint("Estadísticas: ");
    kset_color(0x07); kprint("4 enviados, ");
    kset_color(recibidos > 0 ? 0x0A : 0x0C); kprint_dec((uint32_t)recibidos);
    kset_color(0x07); kprint(" recibidos (");
    kprint_dec((uint32_t)(((4 - recibidos) * 100) / 4));
    kprint("% perdidos)\n");
}

void net_cmd_dns(const char *args) {
    while (*args == ' ') args++;
    if (!*args) {
        kprint("Uso: dns <dominio>   (ej: dns scholar.google.com)\n");
        return;
    }
    if (!net_tiene_ip()) {
        kprint("Sin IP configurada. Ejecuta 'net dhcp' primero.\n");
        return;
    }

    kprint("Consultando DNS ("); net_imprimir_ip(mi_dns); kprint(") para ");
    kprint(args); kprint("...\n");

    uint32_t ip = 0;
    if (net_resolver_dns(args, &ip) == 0) {
        kset_color(0x0A); kprint("  Nombre : "); kset_color(0x0F); kprint(args); kprint("\n");
        kset_color(0x0A); kprint("  IPv4   : "); kset_color(0x0F); net_imprimir_ip(ip); kprint("\n");
        kset_color(0x07);
    } else {
        kset_color(0x0C); kprint("  Error: no se pudo resolver '"); kprint(args); kprint("'.\n");
        kset_color(0x07);
    }
}

void net_cmd_http(const char *args) {
    while (*args == ' ') args++;
    if (!*args) {
        kprint("Uso: http <host[:puerto]> [ruta]   (ej: http example.com /)\n");
        return;
    }
    if (!net_tiene_ip()) {
        kprint("Sin IP configurada. Ejecuta 'net dhcp' primero.\n");
        return;
    }

    char host[80];
    char ruta[120];
    uint16_t port = 80;
    int hi = 0;
    const char *p = args;

    /* Quitar http:// si el usuario lo escribe */
    if (p[0]=='h' && p[1]=='t' && p[2]=='t' && p[3]=='p' && p[4]==':' && p[5]=='/' && p[6]=='/') p += 7;

    while (*p && *p != ' ' && *p != '/' && *p != ':' && hi < 79) host[hi++] = *p++;
    host[hi] = '\0';

    if (*p == ':') {
        p++;
        uint32_t pv = 0;
        while (*p >= '0' && *p <= '9') { pv = pv * 10 + (uint32_t)(*p - '0'); p++; }
        if (pv >= 1 && pv <= 65535) port = (uint16_t)pv;
    }

    while (*p == ' ') p++;
    int ri = 0;
    while (*p && *p != ' ' && ri < 119) ruta[ri++] = *p++;
    ruta[ri] = '\0';
    if (ri == 0) { ruta[0] = '/'; ruta[1] = '\0'; }

    kprint("Conectando TCP a "); kprint(host); kputc(':'); kprint_dec(port);
    kprint(" "); kprint(ruta); kprint("...\n");

    int code = 0;
    int n = net_http_get(host, port, ruta, http_rx_buf, HTTP_BUF_SZ, &code);
    if (n < 0) {
        kset_color(0x0C);
        if (n == -2) kprint("Error: no se pudo resolver el host por DNS.\n");
        else if (n == -3) kprint("Error: no se obtuvo respuesta ARP de la puerta de enlace.\n");
        else kprint("Error: no se pudo establecer la conexión TCP (puerto cerrado o sin respuesta).\n");
        kset_color(0x07);
        return;
    }

    audit_registrar(LOG_INFO, kernel_usuario_corto(), "HTTP_GET", host);

    kset_color(0x0A); kprint("HTTP "); kprint_dec((uint32_t)code);
    kset_color(0x07); kprint(" | Recibidos "); kprint_dec((uint32_t)n); kprint(" bytes\n");

    /* Buscar separador entre cabeceras y cuerpo (\r\n\r\n) */
    int body = -1;
    for (int i = 0; i + 3 < n; i++) {
        if (http_rx_buf[i] == '\r' && http_rx_buf[i+1] == '\n' &&
            http_rx_buf[i+2] == '\r' && http_rx_buf[i+3] == '\n') {
            body = i + 4;
            break;
        }
    }

    /* Mostrar linea de estado y Location si es redireccion 301/302 */
    int lineas = 0;
    kset_color(0x08);
    int fin_hdr = (body > 0) ? body - 4 : (n < 300 ? n : 300);
    for (int i = 0; i < fin_hdr && lineas < 4; ) {
        int j = i;
        while (j < fin_hdr && http_rx_buf[j] != '\n') j++;
        if (i == 0 ||
            (http_rx_buf[i] == 'L' && http_rx_buf[i+1] == 'o' && http_rx_buf[i+2] == 'c') ||
            (http_rx_buf[i] == 'C' && http_rx_buf[i+1] == 'o' && http_rx_buf[i+2] == 'n' && http_rx_buf[i+7] == '-')) {
            kprint("  ");
            for (int c = i; c < j && c - i < 74; c++) {
                if (http_rx_buf[c] >= 32 && http_rx_buf[c] < 127) kputc(http_rx_buf[c]);
            }
            kputc('\n');
            lineas++;
        }
        i = j + 1;
    }
    kset_color(0x07);

    if (body >= 0 && body < n) {
        kset_color(0x0B); kprint("--- Vista previa del cuerpo ---\n");
        kset_color(0x07);
        int impresos = 0, nl = 0;
        for (int i = body; i < n && impresos < 600 && nl < 12; i++) {
            char ch = http_rx_buf[i];
            if (ch == '\r') continue;
            if (ch == '\n') { kputc('\n'); nl++; impresos++; }
            else if ((uint8_t)ch >= 32 && (uint8_t)ch < 127) { kputc(ch); impresos++; }
        }
        kputc('\n');
        if (n - body > impresos) {
            kset_color(0x08); kprint("(salida truncada para pantalla 80x25)\n"); kset_color(0x07);
        }
    }
    (void)n_slen;
}
EOF

cat << 'EOF' > scholar.h
#ifndef SCHOLAR_H
#define SCHOLAR_H
#include <stdint.h>

void scholar_init(void);
void scholar_cmd(const char *args);
const char *scholar_gateway_str(void);
void scholar_abrir_desde_menu(void);
int  scholar_probar_salud(void);

#endif
EOF

cat << 'EOF' > scholar.c
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
EOF

cat << 'EOF' > apps.h
#ifndef APPS_H
#define APPS_H

void apps_menu(void);
void apps_calculadora(void);
void apps_agenda(void);
void apps_timer(void);
void apps_cmd_calc(const char *args);

#endif
EOF

cat << 'EOF' > apps.c
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
EOF

cat << 'EOF' > juegos.h
#ifndef JUEGOS_H
#define JUEGOS_H

void juegos_menu(void);
void juegos_snake(void);
void juegos_2048(void);
void juegos_ahorcado(void);

#endif
EOF

cat << 'EOF' > juegos.c
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
EOF

cat << 'EOF' > ui.h
#ifndef UI_H
#define UI_H

/* Devuelve: 0 = ir a consola avanzada, 1 = cerrar sesion (logout), 2 = reiniciar, 3 = apagar */
int ui_menu_principal(void);
void ui_explorador_archivos(void);

#endif
EOF

cat << 'EOF' > ui.c
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
EOF

cat << 'EOF' > teclado.h
#ifndef TECLADO_H
#define TECLADO_H

#define KEY_BS       '\b'
#define KEY_TAB      '\t'
#define KEY_ENTER    '\n'
#define KEY_ESC      27

#define KEY_UP       0x100
#define KEY_DOWN     0x101
#define KEY_LEFT     0x102
#define KEY_RIGHT    0x103
#define KEY_HOME     0x104
#define KEY_END      0x105
#define KEY_DEL      0x106
#define KEY_PGUP     0x107
#define KEY_PGDN     0x108
#define KEY_INS      0x109

#define KEY_S_UP     0x110
#define KEY_S_DOWN   0x111
#define KEY_S_LEFT   0x112
#define KEY_S_RIGHT  0x113
#define KEY_S_HOME   0x114
#define KEY_S_END    0x115

#define KEY_CTRL_A   0x120
#define KEY_CTRL_C   0x121
#define KEY_CTRL_V   0x122
#define KEY_CTRL_X   0x123
#define KEY_CTRL_L   0x124

#define KBD_LATAM    0
#define KBD_ES       1
#define KBD_US       2

#define CLIP_MAX     2048

int  teclado_poll_key(void);
int  teclado_getkey(void);
char teclado_getchar(void);
void teclado_readline(char *destino, int max_len);
void teclado_hist_clear(void);

void        teclado_set_layout(int layout);
int         teclado_get_layout(void);
const char *teclado_layout_nombre(void);
void        teclado_cmd_kbd(const char *args);

void        clip_copiar(const char *src, int len);
const char *clip_obtener(void);
int         clip_largo(void);
void        clip_limpiar(void);

#endif
EOF

cat << 'EOF' > teclado.c
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
EOF

cat << 'EOF' > ata.h
#ifndef ATA_H
#define ATA_H
#include <stdint.h>

int ata_read_sector(uint32_t lba, uint8_t *buf);
int ata_write_sector(uint32_t lba, const uint8_t *buf);
int ata_write_sector_raw(uint32_t lba, const uint8_t *buf);
int ata_flush(void);

#endif
EOF

cat << 'EOF' > ata.c
#include "ata.h"

#define ATA_DATA    0x1F0
#define ATA_SECCNT  0x1F2
#define ATA_LBA0    0x1F3
#define ATA_LBA1    0x1F4
#define ATA_LBA2    0x1F5
#define ATA_DRIVE   0x1F6
#define ATA_STATUS  0x1F7
#define ATA_CMD     0x1F7

static inline uint8_t inb(uint16_t port) {
    uint8_t r;
    __asm__ volatile("inb %1, %0" : "=a"(r) : "Nd"(port));
    return r;
}

static inline void outb(uint16_t port, uint8_t val) {
    __asm__ volatile("outb %0, %1" : : "a"(val), "Nd"(port));
}

static inline uint16_t inw(uint16_t port) {
    uint16_t r;
    __asm__ volatile("inw %1, %0" : "=a"(r) : "Nd"(port));
    return r;
}

static inline void outw(uint16_t port, uint16_t val) {
    __asm__ volatile("outw %0, %1" : : "a"(val), "Nd"(port));
}

static void ata_delay(void) {
    inb(ATA_STATUS); inb(ATA_STATUS); inb(ATA_STATUS); inb(ATA_STATUS);
}

static int ata_wait_bsy(void) {
    for (int t = 0; t < 200000; t++) {
        uint8_t st = inb(ATA_STATUS);
        if (st == 0xFF) return -1;
        if (!(st & 0x80)) return 0;
    }
    return -1;
}

static int ata_wait_drq(void) {
    for (int t = 0; t < 200000; t++) {
        uint8_t st = inb(ATA_STATUS);
        if (st == 0xFF || (st & 0x21)) return -1;
        if (!(st & 0x80) && (st & 0x08)) return 0;
    }
    return -1;
}

int ata_read_sector(uint32_t lba, uint8_t *buf) {
    if (ata_wait_bsy() != 0) return -1;
    outb(ATA_DRIVE, (uint8_t)(0xE0 | ((lba >> 24) & 0x0F)));
    ata_delay();
    outb(ATA_SECCNT, 1);
    outb(ATA_LBA0, (uint8_t)(lba & 0xFF));
    outb(ATA_LBA1, (uint8_t)((lba >> 8) & 0xFF));
    outb(ATA_LBA2, (uint8_t)((lba >> 16) & 0xFF));
    outb(ATA_CMD, 0x20);

    if (ata_wait_drq() != 0) return -1;
    for (int i = 0; i < 256; i++) {
        uint16_t w = inw(ATA_DATA);
        buf[i * 2] = (uint8_t)(w & 0xFF);
        buf[i * 2 + 1] = (uint8_t)(w >> 8);
    }
    return 0;
}

int ata_write_sector_raw(uint32_t lba, const uint8_t *buf) {
    if (ata_wait_bsy() != 0) return -1;
    outb(ATA_DRIVE, (uint8_t)(0xE0 | ((lba >> 24) & 0x0F)));
    ata_delay();
    outb(ATA_SECCNT, 1);
    outb(ATA_LBA0, (uint8_t)(lba & 0xFF));
    outb(ATA_LBA1, (uint8_t)((lba >> 8) & 0xFF));
    outb(ATA_LBA2, (uint8_t)((lba >> 16) & 0xFF));
    outb(ATA_CMD, 0x30);

    if (ata_wait_drq() != 0) return -1;
    for (int i = 0; i < 256; i++) {
        uint16_t w = (uint16_t)buf[i * 2] | ((uint16_t)buf[i * 2 + 1] << 8);
        outw(ATA_DATA, w);
    }
    return 0;
}

int ata_flush(void) {
    if (ata_wait_bsy() != 0) return -1;
    outb(ATA_CMD, 0xE7);
    return ata_wait_bsy();
}

int ata_write_sector(uint32_t lba, const uint8_t *buf) {
    if (ata_write_sector_raw(lba, buf) != 0) return -1;
    return ata_flush();
}
EOF

cat << 'EOF' > fs.h
#ifndef FS_H
#define FS_H
#include <stdint.h>

#define MAX_NODOS 128
#define MAX_NOMBRE 33
#define MAX_DATOS 4096

#define NODO_LIBRE 0
#define NODO_ARCH  1
#define NODO_DIR   2

#define PERM_R 0400
#define PERM_W 0200
#define PERM_X 0100

#define ROL_ADMIN    0
#define ROL_USUARIO  1
#define ROL_INVITADO 2

typedef struct {
    uint8_t tipo;
    int16_t padre;
    uint32_t tam;
    uint16_t permisos;
    char nombre[MAX_NOMBRE];
    char datos[MAX_DATOS];
} nodo_t;

typedef struct {
    int16_t  id;
    uint8_t  tipo;
    uint16_t permisos;
    uint32_t tam;
    char     nombre[MAX_NOMBRE];
} fs_item_t;

typedef struct {
    int16_t id;
    int16_t padre;
    uint8_t tipo;
    uint8_t por_contenido;
    char    nombre[MAX_NOMBRE];
    char    ruta[72];
} fs_find_hit_t;

int fs_init(void);
void fs_set_rol(int rol);
void fs_reset_dir(void);
int fs_mkdir(const char *nombre);
int fs_touch(const char *nombre);
int fs_write(const char *nombre, const char *contenido);
int fs_cat(const char *nombre);
int fs_edit(const char *nombre);
int fs_chmod(const char *modo_str, const char *nombre);
int fs_cp(const char *origen, const char *destino);
int fs_mv(const char *origen, const char *destino);
void fs_find(const char *patron);
int fs_stat(const char *nombre);
void fs_df(void);
void fs_ls(const char *ruta);
void fs_tree(int16_t padre, int nivel);
int fs_cd(const char *nombre);
int fs_rma(const char *nombre);
int fs_rme(const char *nombre);
int fs_save(void);
int fs_copiar_a_clip(const char *nombre);
int fs_guardar_silencioso(const char *nombre, const char *contenido, const char **err_out);
void fs_pwd(void);

int fs_hay_cambios(void);
int fs_estado_disco(void);
int fs_fue_migrado_v1(void);
void fs_contar_nodos(int *usados, int *archivos, int *dirs, uint32_t *bytes);
int fs_listar_candidatos(const char *prefijo, int solo_dirs, int solo_archs, const char *out[], int max_out);

/* Helpers para Modo Facil (Explorador Visual y Buscador) */
int fs_get_rol(void);
int fs_en_raiz(void);
int fs_ir_a_dir(int16_t dir_id);
int fs_listar_dir_actual(fs_item_t *out, int max_out);
int fs_leer_archivo_buf(const char *nombre, char *out, int max_len);
int fs_mkdir_silencioso(const char *nombre, const char **err_out);
int fs_renombrar_silencioso(const char *origen, const char *nuevo_nombre, const char **err_out);
int fs_copiar_silencioso(const char *origen, const char *destino, const char **err_out);
int fs_mover_silencioso(const char *origen, const char *destino, const char **err_out);
int fs_eliminar_silencioso(const char *nombre, const char **err_out);
int fs_save_silencioso(const char **err_out);
int fs_buscar_resultados(const char *patron, fs_find_hit_t *out, int max_out);
void fs_ruta_actual_str(char *out, int max_len);
int  fs_leer_raiz_archivo(const char *nombre, char *out, int max_len);
int  fs_guardar_raiz_archivo(const char *nombre, const char *contenido, const char **err_out);

/* Preferencias persistentes en el superbloque del disco ATA */
int  fs_tiene_prefs_guardadas(void);
void fs_obtener_prefs(uint8_t *kbd, int8_t *tz, uint8_t *tema);
int  fs_guardar_prefs(uint8_t kbd, int8_t tz, uint8_t tema);

#endif
EOF

cat << 'EOF' > fs.c
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
EOF

cat << 'EOF' > mem.h
#ifndef MEM_H
#define MEM_H
#include <stdint.h>

void gdt_init(void);
void idt_init(void);
void paginacion_init(uint32_t ram_kb);
void mem_comando(const char *args);
uint32_t mem_ram_mb(void);
uint32_t mem_kernel_kb(void);
uint32_t mem_pf_total(void);
int mem_paginacion_activa(void);
int mem_map_mmio(uint32_t phys_base, uint32_t size);

#endif
EOF

cat << 'EOF' > mem.c
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
EOF

cat << 'EOF' > kernel.c
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
EOF

cat << 'PYEOF' > argos_scholar_gateway.py
#!/usr/bin/env python3
"""
ARGOS OS - Pasarela Académica en la Nube (HTTP -> HTTPS)
--------------------------------------------------------
Servicio multiusuario para ARGOS OS (Tecnológico Universitario Argos).
- Soporta múltiples usuarios simultáneos (ThreadingHTTPServer).
- Lee el puerto desde la variable de entorno PORT (por defecto 8080).
- Consulta Google Académico por HTTPS con respaldo automático a OpenAlex y Crossref.
- Caché en memoria (10 min) para respuestas instantáneas y protección anti-CAPTCHA.
- Devuelve texto plano compacto con Content-Length fijo para la pantalla VGA 80x25.
"""

import html
import json
import os
import re
import ssl
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "0.0.0.0"
PORT = int(os.environ.get("PORT", "8080"))
MAX_RESULTS = 6
TIMEOUT_SCHOLAR = 5
TIMEOUT_API = 7
CACHE_TTL_SEG = 600
CACHE_MAX_ITEMS = 200

_cache = {}
_cache_lock = threading.Lock()


def crear_ssl_ctx():
    try:
        return ssl.create_default_context()
    except Exception:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        return ctx


SSL_CTX = crear_ssl_ctx()


def limpiar_texto(txt, max_len=260):
    if not txt:
        return ""
    txt = html.unescape(str(txt))
    txt = re.sub(r"<[^>]+>", " ", txt)
    reemplazos = {
        "\u2013": "-", "\u2014": "-", "\u2212": "-",
        "\u2018": "'", "\u2019": "'", "\u201c": '"', "\u201d": '"',
        "\u2026": "...", "\u00a0": " ", "\u200b": "", "\ufeff": "",
        "\r": " ", "\n": " ", "\t": " ",
    }
    for k, v in reemplazos.items():
        txt = txt.replace(k, v)
    permitidos = set("áéíóúñüÁÉÍÓÚÑÜ¿¡º°")
    out = []
    for ch in txt:
        code = ord(ch)
        if 32 <= code < 127 or ch in permitidos:
            out.append(ch)
        elif ch in "àâäãå": out.append("a")
        elif ch in "èêë": out.append("e")
        elif ch in "ìîï": out.append("i")
        elif ch in "òôöõ": out.append("o")
        elif ch in "ùû": out.append("u")
        elif ch in "ÀÂÄÃÅ": out.append("A")
        elif ch in "ÈÊË": out.append("E")
        elif ch in "ÌÎÏ": out.append("I")
        elif ch in "ÒÔÖÕ": out.append("O")
        elif ch in "ÙÛ": out.append("U")
        elif ch in "çÇ": out.append("c" if ch == "ç" else "C")
        else:
            out.append(" ")
    txt = re.sub(r"\s+", " ", "".join(out)).strip()
    if len(txt) > max_len:
        txt = txt[: max_len - 3].rstrip() + "..."
    return txt


def construir_apa(titulo, autores, anio, url):
    a = autores if autores else "Autor desconocido"
    y = anio if anio else "s.f."
    t = titulo if titulo else "Sin título"
    u = url if url else ""
    apa = f"{a} ({y}). {t}."
    if u:
        apa += f" {u}"
    return limpiar_texto(apa, 260)


def buscar_google_scholar(query, limit):
    q = urllib.parse.quote_plus(query)
    url = f"https://scholar.google.com/scholar?hl=es&as_sdt=0%2C5&q={q}"
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/124.0.0.0 Safari/537.36"
        ),
        "Accept-Language": "es-EC,es;q=0.9,en;q=0.8",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    }
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=TIMEOUT_SCHOLAR, context=SSL_CTX) as resp:
        raw = resp.read().decode("utf-8", errors="replace")

    low = raw.lower()
    if "gs_captcha" in low or "unusual traffic" in low or "no soy un robot" in low:
        raise RuntimeError("Google Scholar solicitó CAPTCHA")

    bloques = raw.split('class="gs_ri"')
    resultados = []
    for blk in bloques[1:]:
        if len(resultados) >= limit:
            break
        blk = blk[:6000]
        m_title = re.search(r'<h3[^>]*class="gs_rt"[^>]*>(.*?)</h3>', blk, re.S)
        if not m_title:
            continue
        h3 = m_title.group(1)
        m_href = re.search(r'href="([^"]+)"', h3)
        link = html.unescape(m_href.group(1)) if m_href else ""
        h3_clean = re.sub(r'<span[^>]*class="gs_ct[^"]*"[^>]*>.*?</span>', "", h3, flags=re.S)
        titulo = limpiar_texto(h3_clean, 140)
        if not titulo:
            continue

        m_meta = re.search(r'<div[^>]*class="gs_a"[^>]*>(.*?)</div>', blk, re.S)
        meta = limpiar_texto(m_meta.group(1), 160) if m_meta else ""
        m_year = re.search(r"\b(19\d{2}|20\d{2})\b", meta)
        anio = m_year.group(1) if m_year else "s.f."
        autores = meta.split(" - ")[0].strip() if " - " in meta else meta
        autores = limpiar_texto(autores, 100)

        m_snip = re.search(r'<div[^>]*class="gs_rs"[^>]*>(.*?)</div>', blk, re.S)
        snippet = limpiar_texto(m_snip.group(1), 220) if m_snip else "Sin resumen disponible."

        m_cit = re.search(r'(?:Citado por|Cited by)\s+(\d+)', blk, re.I)
        citas = m_cit.group(1) if m_cit else "0"

        if not link:
            link = f"https://scholar.google.com/scholar?q={urllib.parse.quote_plus(titulo)}"

        resultados.append({
            "title": titulo,
            "authors": autores or "Autor no especificado",
            "year": anio,
            "cites": citas,
            "url": limpiar_texto(link, 140),
            "snippet": snippet,
            "apa": construir_apa(titulo, autores, anio, link),
        })

    if not resultados:
        raise RuntimeError("Sin resultados parseables en Google Scholar")
    return "Google Scholar", resultados


def reconstruir_abstract_openalex(inv_idx):
    if not isinstance(inv_idx, dict) or not inv_idx:
        return ""
    palabras = {}
    for palabra, posiciones in inv_idx.items():
        for pos in posiciones:
            if pos < 45:
                palabras[pos] = palabra
    if not palabras:
        return ""
    return " ".join(palabras[k] for k in sorted(palabras.keys()))


def buscar_openalex(query, limit):
    q = urllib.parse.quote_plus(query)
    url = f"https://api.openalex.org/works?search={q}&per-page={limit}&sort=relevance_score:desc"
    headers = {"User-Agent": "ARGOS-OS-Scholar/7.2 (mailto:argos@tecnologicoargos.edu.ec)"}
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=TIMEOUT_API, context=SSL_CTX) as resp:
        data = json.loads(resp.read().decode("utf-8", errors="replace"))

    resultados = []
    for w in data.get("results", [])[:limit]:
        titulo = limpiar_texto(w.get("display_name") or w.get("title") or "", 140)
        if not titulo:
            continue
        anio = str(w.get("publication_year") or "s.f.")
        citas = str(w.get("cited_by_count") or 0)

        auths = []
        for a in w.get("authorships", [])[:4]:
            name = (a.get("author") or {}).get("display_name")
            if name:
                auths.append(name)
        if len(w.get("authorships", [])) > 4:
            auths.append("et al.")
        autores = limpiar_texto(", ".join(auths), 100) or "Autor no especificado"

        link = w.get("doi") or ""
        if not link:
            loc = w.get("primary_location") or {}
            link = loc.get("landing_page_url") or ""
        if not link:
            link = f"https://scholar.google.com/scholar?q={urllib.parse.quote_plus(titulo)}"

        abs_txt = reconstruir_abstract_openalex(w.get("abstract_inverted_index"))
        venue = ((w.get("primary_location") or {}).get("source") or {}).get("display_name") or ""
        if abs_txt:
            snippet = limpiar_texto(abs_txt, 220)
        elif venue:
            snippet = limpiar_texto(f"Publicado en: {venue}.", 220)
        else:
            snippet = "Artículo indexado en índice académico abierto."

        resultados.append({
            "title": titulo,
            "authors": autores,
            "year": anio,
            "cites": citas,
            "url": limpiar_texto(link, 140),
            "snippet": snippet,
            "apa": construir_apa(titulo, autores, anio, link),
        })

    return "Google Scholar / OpenAlex", resultados


def buscar_crossref(query, limit):
    q = urllib.parse.quote_plus(query)
    url = f"https://api.crossref.org/works?query={q}&rows={limit}"
    headers = {"User-Agent": "ARGOS-OS-Scholar/7.2 (mailto:argos@tecnologicoargos.edu.ec)"}
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=TIMEOUT_API, context=SSL_CTX) as resp:
        data = json.loads(resp.read().decode("utf-8", errors="replace"))

    resultados = []
    items = (data.get("message") or {}).get("items", [])
    for it in items[:limit]:
        tit_list = it.get("title") or []
        titulo = limpiar_texto(tit_list[0] if tit_list else "", 140)
        if not titulo:
            continue
        anio = "s.f."
        for campo in ("published-print", "published-online", "created"):
            dp = (it.get(campo) or {}).get("date-parts")
            if dp and dp[0] and dp[0][0]:
                anio = str(dp[0][0])
                break
        citas = str(it.get("is-referenced-by-count") or 0)
        auths = []
        for a in it.get("author", [])[:4]:
            fam = a.get("family") or ""
            giv = a.get("given") or ""
            full = f"{giv} {fam}".strip()
            if full:
                auths.append(full)
        autores = limpiar_texto(", ".join(auths), 100) or "Autor no especificado"
        link = it.get("URL") or f"https://scholar.google.com/scholar?q={urllib.parse.quote_plus(titulo)}"
        pub = limpiar_texto(it.get("publisher") or "", 100)
        snippet = limpiar_texto(it.get("abstract") or (f"Editorial: {pub}." if pub else "Registro Crossref."), 220)

        resultados.append({
            "title": titulo,
            "authors": autores,
            "year": anio,
            "cites": citas,
            "url": limpiar_texto(link, 140),
            "snippet": snippet,
            "apa": construir_apa(titulo, autores, anio, link),
        })

    return "Google Scholar / Crossref", resultados


def buscar_academico(query, limit=MAX_RESULTS):
    key = (query.lower().strip(), limit)
    ahora = time.time()
    with _cache_lock:
        ent = _cache.get(key)
        if ent and (ahora - ent[0]) < CACHE_TTL_SEG:
            return ent[1], ent[2]

    for fn in (buscar_google_scholar, buscar_openalex, buscar_crossref):
        try:
            fuente, res = fn(query, limit)
            if res:
                with _cache_lock:
                    if len(_cache) >= CACHE_MAX_ITEMS:
                        _cache.clear()
                    _cache[key] = (ahora, fuente, res)
                return fuente, res
        except Exception:
            continue
    return "Sin conexión", []


def formatear_respuesta(fuente, resultados):
    lineas = [
        f"SOURCE: {limpiar_texto(fuente, 48)}",
        f"COUNT: {len(resultados)}",
    ]
    for r in resultados:
        lineas.append("---")
        lineas.append(f"TITLE: {limpiar_texto(r['title'], 140)}")
        lineas.append(f"AUTHORS: {limpiar_texto(r['authors'], 100)}")
        lineas.append(f"YEAR: {limpiar_texto(r['year'], 6)}")
        lineas.append(f"CITES: {limpiar_texto(r['cites'], 10)}")
        lineas.append(f"URL: {limpiar_texto(r['url'], 140)}")
        lineas.append(f"SNIPPET: {limpiar_texto(r['snippet'], 220)}")
        lineas.append(f"APA: {limpiar_texto(r['apa'], 260)}")
    lineas.append("END")
    return "\n".join(lineas) + "\n"


class ArgosScholarHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def enviar_texto(self, codigo, texto):
        data = texto.encode("utf-8", errors="replace")
        self.send_response(codigo)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(data)
        self.close_connection = True

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path in ("/", "/health"):
            self.enviar_texto(200, "OK ARGOS-SCHOLAR-GATEWAY v2.0 (Cloud Ready)\n")
            return

        if parsed.path == "/search":
            qs = urllib.parse.parse_qs(parsed.query)
            q = (qs.get("q") or [""])[0].strip()
            try:
                n = int((qs.get("n") or [str(MAX_RESULTS)])[0])
                n = max(1, min(n, MAX_RESULTS))
            except ValueError:
                n = MAX_RESULTS

            if not q:
                self.enviar_texto(400, "ERROR: falta parametro q\n")
                return

            print(f"[ARGOS-GW] '{q}' (n={n}) desde {self.client_address[0]}", flush=True)
            fuente, res = buscar_academico(q, n)
            print(f"[ARGOS-GW] -> {len(res)} resultado(s) via {fuente}", flush=True)
            self.enviar_texto(200, formatear_respuesta(fuente, res))
            return

        self.enviar_texto(404, "Rutas: /health  |  /search?q=tema\n")

    def log_message(self, fmt, *args):
        pass


def main():
    puerto = PORT
    if len(sys.argv) > 1:
        try:
            puerto = int(sys.argv[1])
        except ValueError:
            pass
    srv = ThreadingHTTPServer((HOST, puerto), ArgosScholarHandler)
    print("============================================================", flush=True)
    print("  ARGOS OS - Pasarela Académica v2.0 (Multiusuario + Caché)", flush=True)
    print(f"  Escuchando en http://0.0.0.0:{puerto}", flush=True)
    print("============================================================", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\n[ARGOS-GW] Pasarela detenida.", flush=True)
        srv.server_close()


if __name__ == "__main__":
    main()

PYEOF
chmod +x argos_scholar_gateway.py
cp argos_scholar_gateway.py nube/argos_scholar_gateway.py

cat << 'EOF' > nube/Dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY argos_scholar_gateway.py /app/argos_scholar_gateway.py
ENV PORT=8080
EXPOSE 8080
CMD ["python3", "-u", "/app/argos_scholar_gateway.py"]
EOF

cat << 'EOF' > nube/fly.toml
app = "argos-scholar-gw"
primary_region = "mia"

[build]
  dockerfile = "Dockerfile"

[env]
  PORT = "8080"

# Servicio HTTP puro en puerto 80 (sin forzar HTTPS) para que ARGOS OS conecte directo
[[services]]
  protocol = "tcp"
  internal_port = 8080
  auto_stop_machines = "off"
  auto_start_machines = true
  min_machines_running = 1

  [[services.ports]]
    port = 80
    handlers = ["http"]
    force_https = false

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]

  [[services.http_checks]]
    interval = "30s"
    timeout = "5s"
    path = "/health"
EOF

CFLAGS="-m32 -ffreestanding -fno-pie -fno-pic -fno-stack-protector -fno-tree-loop-distribute-patterns -O2 -Wall -Wextra"
as --32 boot.s -o boot.o
as --32 cpu.s -o cpu.o
gcc $CFLAGS -c reloj.c -o reloj.o
gcc $CFLAGS -c proc.c -o proc.o
gcc $CFLAGS -c audit.c -o audit.o
gcc $CFLAGS -c pci.c -o pci.o
gcc $CFLAGS -c e1000.c -o e1000.o
gcc $CFLAGS -c net.c -o net.o
echo "Configurando pasarela académica: ${SCHOLAR_HOST}:${SCHOLAR_PORT}"
gcc $CFLAGS -DSCHOLAR_DEFAULT_HOST=\"${SCHOLAR_HOST}\" -DSCHOLAR_DEFAULT_PORT=${SCHOLAR_PORT} -c scholar.c -o scholar.o
gcc $CFLAGS -c apps.c -o apps.o
gcc $CFLAGS -c juegos.c -o juegos.o
gcc $CFLAGS -c ui.c -o ui.o
gcc $CFLAGS -c teclado.c -o teclado.o
gcc $CFLAGS -c ata.c -o ata.o
gcc $CFLAGS -c fs.c -o fs.o
gcc $CFLAGS -c mem.c -o mem.o
gcc $CFLAGS -c kernel.c -o kernel.o
ld -m elf_i386 -T linker.ld -o kernel.elf boot.o cpu.o reloj.o proc.o audit.o pci.o e1000.o net.o scholar.o apps.o juegos.o ui.o teclado.o ata.o fs.o mem.o kernel.o

mkdir -p isodir/boot/grub
cp kernel.elf isodir/boot/kernel.elf
cat << 'EOF' > isodir/boot/grub/grub.cfg
set timeout=0
set default=0
menuentry "ARGOS - Sistema Operativo" {
    multiboot /boot/kernel.elf
    boot
}
EOF

grub-mkrescue -o argos_os.iso isodir
echo "Listo: ~/argos_os/argos_os.iso"
if [ -d "/mnt/c/Users/Public" ]; then
    cp argos_os.iso /mnt/c/Users/Public/argos_os.iso
    mkdir -p /mnt/c/Users/Public/argos_nube
    cp nube/argos_scholar_gateway.py nube/Dockerfile nube/fly.toml /mnt/c/Users/Public/argos_nube/
    echo "Copiado a Windows: C:\\Users\\Public\\argos_os.iso"
fi
