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
