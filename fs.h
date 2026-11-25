#ifndef FS_H
#define FS_H
#include <stdint.h>

#define MAX_NODOS 128
#define MAX_NOMBRE 33
#define MAX_DATOS 4096

#define NODO_LIBRE 0
#define NODO_ARCH  1
#define NODO_DIR   2

#define PERM_R 0400
#define PERM_W 0200
#define PERM_X 0100

#define ROL_ADMIN    0
#define ROL_USUARIO  1
#define ROL_INVITADO 2

typedef struct {
    uint8_t tipo;
    int16_t padre;
    uint32_t tam;
    uint16_t permisos;
    char nombre[MAX_NOMBRE];
    char datos[MAX_DATOS];
} nodo_t;

typedef struct {
    int16_t  id;
    uint8_t  tipo;
    uint16_t permisos;
    uint32_t tam;
    char     nombre[MAX_NOMBRE];
} fs_item_t;

typedef struct {
    int16_t id;
    int16_t padre;
    uint8_t tipo;
    uint8_t por_contenido;
    char    nombre[MAX_NOMBRE];
    char    ruta[72];
} fs_find_hit_t;

int fs_init(void);
void fs_set_rol(int rol);
void fs_reset_dir(void);
int fs_mkdir(const char *nombre);
int fs_touch(const char *nombre);
int fs_write(const char *nombre, const char *contenido);
int fs_cat(const char *nombre);
int fs_edit(const char *nombre);
int fs_chmod(const char *modo_str, const char *nombre);
int fs_cp(const char *origen, const char *destino);
int fs_mv(const char *origen, const char *destino);
void fs_find(const char *patron);
int fs_stat(const char *nombre);
void fs_df(void);
void fs_ls(const char *ruta);
void fs_tree(int16_t padre, int nivel);
int fs_cd(const char *nombre);
int fs_rma(const char *nombre);
int fs_rme(const char *nombre);
int fs_save(void);
int fs_copiar_a_clip(const char *nombre);
int fs_guardar_silencioso(const char *nombre, const char *contenido, const char **err_out);
void fs_pwd(void);

int fs_hay_cambios(void);
int fs_estado_disco(void);
int fs_fue_migrado_v1(void);
void fs_contar_nodos(int *usados, int *archivos, int *dirs, uint32_t *bytes);
int fs_listar_candidatos(const char *prefijo, int solo_dirs, int solo_archs, const char *out[], int max_out);

/* Helpers para Modo Facil (Explorador Visual y Buscador) */
int fs_get_rol(void);
int fs_en_raiz(void);
int fs_ir_a_dir(int16_t dir_id);
int fs_listar_dir_actual(fs_item_t *out, int max_out);
int fs_leer_archivo_buf(const char *nombre, char *out, int max_len);
int fs_mkdir_silencioso(const char *nombre, const char **err_out);
int fs_renombrar_silencioso(const char *origen, const char *nuevo_nombre, const char **err_out);
int fs_copiar_silencioso(const char *origen, const char *destino, const char **err_out);
int fs_mover_silencioso(const char *origen, const char *destino, const char **err_out);
int fs_eliminar_silencioso(const char *nombre, const char **err_out);
int fs_save_silencioso(const char **err_out);
int fs_buscar_resultados(const char *patron, fs_find_hit_t *out, int max_out);
void fs_ruta_actual_str(char *out, int max_len);
int  fs_leer_raiz_archivo(const char *nombre, char *out, int max_len);
int  fs_guardar_raiz_archivo(const char *nombre, const char *contenido, const char **err_out);

/* Preferencias persistentes en el superbloque del disco ATA */
int  fs_tiene_prefs_guardadas(void);
void fs_obtener_prefs(uint8_t *kbd, int8_t *tz, uint8_t *tema);
int  fs_guardar_prefs(uint8_t kbd, int8_t tz, uint8_t tema);

#endif
