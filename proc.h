#ifndef PROC_H
#define PROC_H
#include <stdint.h>

#define MAX_PROCS  10

#define PROC_LIBRE 0
#define PROC_NUEVO 1
#define PROC_LISTO 2
#define PROC_EJEC  3
#define PROC_BLOQ  4
#define PROC_TERM  5

typedef struct {
    uint32_t pid;
    uint32_t ppid;
    uint8_t  estado;
    uint8_t  prioridad;
    uint32_t esp;
    uint32_t eip;
    uint32_t cr3;
    uint32_t tics_cpu;
    uint32_t cambios_ctx;
    char     nombre[16];
} pcb_t;

void proc_init(void);
void proc_cmd_ps(const char *args);
void proc_cmd_demo(void);
void proc_cmd_sched(const char *args);
uint32_t proc_activos(void);

#endif
