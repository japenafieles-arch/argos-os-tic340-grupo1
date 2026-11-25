#ifndef MEM_H
#define MEM_H
#include <stdint.h>

void gdt_init(void);
void idt_init(void);
void paginacion_init(uint32_t ram_kb);
void mem_comando(const char *args);
uint32_t mem_ram_mb(void);
uint32_t mem_kernel_kb(void);
uint32_t mem_pf_total(void);
int mem_paginacion_activa(void);
int mem_map_mmio(uint32_t phys_base, uint32_t size);

#endif
