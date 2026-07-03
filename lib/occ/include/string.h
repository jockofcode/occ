#ifndef _OCC_STRING_H
#define _OCC_STRING_H

#include <stddef.h>

/* Memory functions — calloc is in stdlib.h and calls malloc internally */
extern void *memcpy(void *dest, const void *src, size_t n);
extern void *memmove(void *dest, const void *src, size_t n);
extern void *memset(void *s, int c, size_t n);
extern int   memcmp(const void *s1, const void *s2, size_t n);
extern void *memchr(const void *s, int c, size_t n);

/* String copy */
extern char *strcpy(char *dest, const char *src);
extern char *strncpy(char *dest, const char *src, size_t n);
extern char *strcat(char *dest, const char *src);
extern char *strncat(char *dest, const char *src, size_t n);

/* String comparison */
extern int strcmp(const char *s1, const char *s2);
extern int strncmp(const char *s1, const char *s2, size_t n);
extern int strcasecmp(const char *s1, const char *s2);
extern int strncasecmp(const char *s1, const char *s2, size_t n);

/* String search */
extern char *strchr(const char *s, int c);
extern char *strrchr(const char *s, int c);
extern char *strstr(const char *haystack, const char *needle);
extern char *strpbrk(const char *s, const char *accept);
extern size_t strspn(const char *s, const char *accept);
extern size_t strcspn(const char *s, const char *reject);
extern char *strtok(char *s, const char *delim);
extern char *strtok_r(char *s, const char *delim, char **saveptr);

/* String length */
extern size_t strlen(const char *s);
extern size_t strnlen(const char *s, size_t maxlen);

/* String duplication — calls malloc internally */
extern char *strdup(const char *s);
extern char *strndup(const char *s, size_t n);

/* Error string */
extern char *strerror(int errnum);
extern int   strerror_r(int errnum, char *buf, size_t buflen);

/* Locale-sensitive comparison */
extern int    strcoll(const char *s1, const char *s2);
extern size_t strxfrm(char *dest, const char *src, size_t n);

/* BSD extensions */
extern size_t strlcpy(char *dst, const char *src, size_t size);
extern size_t strlcat(char *dst, const char *src, size_t size);

#endif /* _OCC_STRING_H */
