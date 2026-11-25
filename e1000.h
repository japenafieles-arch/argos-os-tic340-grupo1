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
