#ifndef _OCC_STDIO_H
#define _OCC_STDIO_H

#include <stddef.h>
#include <stdarg.h>

/* Opaque FILE type */
typedef struct _occ_file FILE;

#if defined(__APPLE__)
extern FILE *__stdinp;
extern FILE *__stdoutp;
extern FILE *__stderrp;
#define stdin  __stdinp
#define stdout __stdoutp
#define stderr __stderrp
#else
extern FILE *stdin;
extern FILE *stdout;
extern FILE *stderr;
#endif

#define EOF     (-1)
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
#define BUFSIZ  8192
#define FILENAME_MAX 4096
#define FOPEN_MAX    20

/* Formatted output */
extern int printf(const char *fmt, ...);
extern int fprintf(FILE *stream, const char *fmt, ...);
extern int sprintf(char *buf, const char *fmt, ...);
extern int snprintf(char *buf, size_t n, const char *fmt, ...);
extern int vprintf(const char *fmt, va_list ap);
extern int vfprintf(FILE *stream, const char *fmt, va_list ap);
extern int vsprintf(char *buf, const char *fmt, va_list ap);
extern int vsnprintf(char *buf, size_t n, const char *fmt, va_list ap);

/* Formatted input */
extern int scanf(const char *fmt, ...);
extern int fscanf(FILE *stream, const char *fmt, ...);
extern int sscanf(const char *buf, const char *fmt, ...);

/* Character I/O */
extern int fgetc(FILE *stream);
extern int fputc(int c, FILE *stream);
extern int getc(FILE *stream);
extern int putc(int c, FILE *stream);
extern int getchar(void);
extern int putchar(int c);
extern int ungetc(int c, FILE *stream);

/* String I/O */
extern char *fgets(char *s, int n, FILE *stream);
extern int   fputs(const char *s, FILE *stream);
extern int   puts(const char *s);

/* File operations */
extern FILE *fopen(const char *path, const char *mode);
extern FILE *freopen(const char *path, const char *mode, FILE *stream);
extern int   fclose(FILE *stream);
extern int   fflush(FILE *stream);
extern size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream);
extern size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream);
extern int   fseek(FILE *stream, long offset, int whence);
extern long  ftell(FILE *stream);
extern void  rewind(FILE *stream);
extern int   feof(FILE *stream);
extern int   ferror(FILE *stream);
extern void  clearerr(FILE *stream);
extern int   fileno(FILE *stream);

/* File management */
extern int   remove(const char *path);
extern int   rename(const char *oldpath, const char *newpath);
extern FILE *tmpfile(void);
extern char *tmpnam(char *s);

/* Error */
extern void perror(const char *s);

#endif /* _OCC_STDIO_H */
