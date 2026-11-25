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
