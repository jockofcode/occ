#ifndef _OCC_STRINGS_H
#define _OCC_STRINGS_H

#include <stddef.h>

extern int strcasecmp(const char *s1, const char *s2);
extern int strncasecmp(const char *s1, const char *s2, size_t n);

extern int bcmp(const void *b1, const void *b2, size_t len);
extern void bcopy(const void *src, void *dst, size_t len);
extern void bzero(void *b, size_t len);

#endif /* _OCC_STRINGS_H */
