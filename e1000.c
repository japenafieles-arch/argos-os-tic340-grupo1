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
