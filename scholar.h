#ifndef SCHOLAR_H
#define SCHOLAR_H
#include <stdint.h>

void scholar_init(void);
void scholar_cmd(const char *args);
const char *scholar_gateway_str(void);
void scholar_abrir_desde_menu(void);
int  scholar_probar_salud(void);

#endif
