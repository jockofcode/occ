#ifndef _MALLOC_MALLOC_H_
#define _MALLOC_MALLOC_H_

#include <stddef.h>

extern size_t malloc_size(const void *ptr);
extern size_t malloc_good_size(size_t size);

typedef struct _malloc_zone_t {
    void *reserved1;
    void *reserved2;
    size_t (*size)(struct _malloc_zone_t *zone, const void *ptr);
    void *(*malloc)(struct _malloc_zone_t *zone, size_t size);
    void *(*calloc)(struct _malloc_zone_t *zone, size_t num_items, size_t size);
    void *(*valloc)(struct _malloc_zone_t *zone, size_t size);
    void (*free)(struct _malloc_zone_t *zone, void *ptr);
    void *(*realloc)(struct _malloc_zone_t *zone, void *ptr, size_t size);
    void (*destroy)(struct _malloc_zone_t *zone);
    const char *zone_name;
} malloc_zone_t;

extern malloc_zone_t *malloc_default_zone(void);
extern malloc_zone_t *malloc_create_zone(size_t start_size, unsigned flags);
extern void malloc_set_zone_name(malloc_zone_t *zone, const char *name);
extern malloc_zone_t *malloc_zone_from_ptr(const void *ptr);
extern void malloc_zone_free(malloc_zone_t *zone, void *ptr);
extern void *malloc_zone_malloc(malloc_zone_t *zone, size_t size);
extern void *malloc_zone_realloc(malloc_zone_t *zone, void *ptr, size_t size);

#endif /* _MALLOC_MALLOC_H_ */
