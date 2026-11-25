# Rutinas de bajo nivel: GDT, IDT, excepciones (0-31), IRQ (32-47) y cambio de contexto
.section .text

.global gdt_flush
gdt_flush:
    mov 4(%esp), %eax
    lgdt (%eax)
    mov $0x10, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %fs
    mov %ax, %gs
    mov %ax, %ss
    ljmp $0x08, $1f
1:  ret

.global idt_load
idt_load:
    mov 4(%esp), %eax
    lidt (%eax)
    ret

# void ctx_switch(uint32_t *old_esp, uint32_t new_esp)
# Guarda registros preservados en la pila actual, cambia ESP y restaura el nuevo contexto
.global ctx_switch
ctx_switch:
    push %ebp
    push %ebx
    push %esi
    push %edi
    mov 20(%esp), %eax
    mov %esp, (%eax)
    mov 24(%esp), %esp
    pop %edi
    pop %esi
    pop %ebx
    pop %ebp
    ret

.macro ISR_SIN_ERR n
isr\n:
    push $0
    push $\n
    jmp isr_comun
.endm

.macro ISR_CON_ERR n
isr\n:
    push $\n
    jmp isr_comun
.endm

.macro IRQ_STUB n, v
irq\n:
    push $0
    push $\v
    jmp irq_comun
.endm

ISR_SIN_ERR 0
ISR_SIN_ERR 1
ISR_SIN_ERR 2
ISR_SIN_ERR 3
ISR_SIN_ERR 4
ISR_SIN_ERR 5
ISR_SIN_ERR 6
ISR_SIN_ERR 7
ISR_CON_ERR 8
ISR_SIN_ERR 9
ISR_CON_ERR 10
ISR_CON_ERR 11
ISR_CON_ERR 12
ISR_CON_ERR 13
ISR_CON_ERR 14
ISR_SIN_ERR 15
ISR_SIN_ERR 16
ISR_CON_ERR 17
ISR_SIN_ERR 18
ISR_SIN_ERR 19
ISR_SIN_ERR 20
ISR_CON_ERR 21
ISR_SIN_ERR 22
ISR_SIN_ERR 23
ISR_SIN_ERR 24
ISR_SIN_ERR 25
ISR_SIN_ERR 26
ISR_SIN_ERR 27
ISR_SIN_ERR 28
ISR_CON_ERR 29
ISR_CON_ERR 30
ISR_SIN_ERR 31

IRQ_STUB 0,  32
IRQ_STUB 1,  33
IRQ_STUB 2,  34
IRQ_STUB 3,  35
IRQ_STUB 4,  36
IRQ_STUB 5,  37
IRQ_STUB 6,  38
IRQ_STUB 7,  39
IRQ_STUB 8,  40
IRQ_STUB 9,  41
IRQ_STUB 10, 42
IRQ_STUB 11, 43
IRQ_STUB 12, 44
IRQ_STUB 13, 45
IRQ_STUB 14, 46
IRQ_STUB 15, 47

isr_comun:
    cld
    pusha
    push %esp
    call isr_manejador
    add $4, %esp
    popa
    add $8, %esp
    iret

irq_comun:
    cld
    pusha
    push %esp
    call irq_manejador
    add $4, %esp
    popa
    add $8, %esp
    iret

.section .data
.global isr_tabla
isr_tabla:
.irp i,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    .long isr\i
.endr

.global irq_tabla
irq_tabla:
.irp i,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
    .long irq\i
.endr

.section .note.GNU-stack,"",@progbits
