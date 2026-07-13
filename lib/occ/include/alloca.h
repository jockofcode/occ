#ifndef _ALLOCA_H_
#define _ALLOCA_H_
#include <stddef.h>
void *alloca(size_t __size);
#define alloca(size) __builtin_alloca(size)
#endif
