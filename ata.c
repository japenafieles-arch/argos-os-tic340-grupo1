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
