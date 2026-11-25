#ifndef PCI_H
#define PCI_H
#include <stdint.h>

typedef struct {
    uint8_t  bus;
    uint8_t  dev;
    uint8_t  func;
    uint16_t vendor_id;
    uint16_t device_id;
    uint32_t bar0;
    uint8_t  irq_line;
} pci_dev_t;

uint32_t pci_read32(uint8_t bus, uint8_t dev, uint8_t func, uint8_t offset);
void     pci_write32(uint8_t bus, uint8_t dev, uint8_t func, uint8_t offset, uint32_t val);
uint16_t pci_read16(uint8_t bus, uint8_t dev, uint8_t func, uint8_t offset);
void     pci_write16(uint8_t bus, uint8_t dev, uint8_t func, uint8_t offset, uint16_t val);
int      pci_buscar_nic_intel(pci_dev_t *out);

#endif
