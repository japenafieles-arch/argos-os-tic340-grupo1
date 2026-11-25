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
