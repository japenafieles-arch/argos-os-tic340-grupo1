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
