#ifndef _OCC_STDDEF_H
#define _OCC_STDDEF_H

typedef unsigned long size_t;
typedef long          ptrdiff_t;
typedef long          ssize_t;

#define NULL     ((void *)0)
#define offsetof(type, member) ((size_t)&((type *)0)->member)

#endif /* _OCC_STDDEF_H */
