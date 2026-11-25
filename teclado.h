#ifndef TECLADO_H
#define TECLADO_H

#define KEY_BS       '\b'
#define KEY_TAB      '\t'
#define KEY_ENTER    '\n'
#define KEY_ESC      27

#define KEY_UP       0x100
#define KEY_DOWN     0x101
#define KEY_LEFT     0x102
#define KEY_RIGHT    0x103
#define KEY_HOME     0x104
#define KEY_END      0x105
#define KEY_DEL      0x106
#define KEY_PGUP     0x107
#define KEY_PGDN     0x108
#define KEY_INS      0x109

#define KEY_S_UP     0x110
#define KEY_S_DOWN   0x111
#define KEY_S_LEFT   0x112
#define KEY_S_RIGHT  0x113
#define KEY_S_HOME   0x114
#define KEY_S_END    0x115

#define KEY_CTRL_A   0x120
#define KEY_CTRL_C   0x121
#define KEY_CTRL_V   0x122
#define KEY_CTRL_X   0x123
#define KEY_CTRL_L   0x124

#define KBD_LATAM    0
#define KBD_ES       1
#define KBD_US       2

#define CLIP_MAX     2048

int  teclado_poll_key(void);
int  teclado_getkey(void);
char teclado_getchar(void);
void teclado_readline(char *destino, int max_len);
void teclado_hist_clear(void);

void        teclado_set_layout(int layout);
int         teclado_get_layout(void);
const char *teclado_layout_nombre(void);
void        teclado_cmd_kbd(const char *args);

void        clip_copiar(const char *src, int len);
const char *clip_obtener(void);
int         clip_largo(void);
void        clip_limpiar(void);

#endif
