#ifndef ATA_H
#define ATA_H
#include <stdint.h>

int ata_read_sector(uint32_t lba, uint8_t *buf);
int ata_write_sector(uint32_t lba, const uint8_t *buf);
int ata_write_sector_raw(uint32_t lba, const uint8_t *buf);
int ata_flush(void);

#endif
