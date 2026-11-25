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
