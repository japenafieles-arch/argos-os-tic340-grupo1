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
