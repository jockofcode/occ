#ifndef _OCC_STDLIB_H
#define _OCC_STDLIB_H

#include <stddef.h>

#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1
#define RAND_MAX     2147483647

/* Memory — calloc calls malloc internally (in libc); realloc calls malloc+memcpy */
extern void *malloc(size_t size);
extern void *calloc(size_t nmemb, size_t size);
extern void *realloc(void *ptr, size_t size);
extern void  free(void *ptr);
extern int   posix_memalign(void **memptr, size_t alignment, size_t size);
extern void *aligned_alloc(size_t alignment, size_t size);
extern void *memalign(size_t alignment, size_t size);

/* Program control */
extern void  exit(int status);
extern void  abort(void);
extern int   atexit(void (*func)(void));
extern void  _exit(int status);

/* Environment */
extern char *getenv(const char *name);
extern int   setenv(const char *name, const char *value, int overwrite);
extern int   unsetenv(const char *name);
extern int   putenv(char *string);
extern int   system(const char *command);
extern char *realpath(const char *restrict path, char *restrict resolved_path);

/* Number conversion */
extern int    atoi(const char *s);
extern long   atol(const char *s);
extern long long atoll(const char *s);
extern double atof(const char *s);
extern long   strtol(const char *s, char **endptr, int base);
extern unsigned long strtoul(const char *s, char **endptr, int base);
extern long long strtoll(const char *s, char **endptr, int base);
extern unsigned long long strtoull(const char *s, char **endptr, int base);
extern double strtod(const char *s, char **endptr);
extern float  strtof(const char *s, char **endptr);
extern long double strtold(const char *s, char **endptr);

/* Integer arithmetic */
extern int  abs(int x);
extern long labs(long x);
extern long long llabs(long long x);

typedef struct { int quot; int rem; }       div_t;
typedef struct { long quot; long rem; }     ldiv_t;
typedef struct { long long quot; long long rem; } lldiv_t;
extern div_t   div(int numer, int denom);
extern ldiv_t  ldiv(long numer, long denom);
extern lldiv_t lldiv(long long numer, long long denom);

/* Sorting and searching */
extern void  qsort(void *base, size_t nmemb, size_t size,
                   int (*compar)(const void *, const void *));
extern void *bsearch(const void *key, const void *base,
                     size_t nmemb, size_t size,
                     int (*compar)(const void *, const void *));

/* Random numbers */
extern int   rand(void);
extern void  srand(unsigned int seed);
extern long  random(void);
extern void  srandom(unsigned int seed);
extern void  srandomdev(void);

/* Multibyte / wide char (stubs) */
extern int   mblen(const char *s, size_t n);
extern size_t mbstowcs(void *dest, const char *src, size_t n);

#endif /* _OCC_STDLIB_H */
