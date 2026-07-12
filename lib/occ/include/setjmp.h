#ifndef _OCC_SETJMP_H
#define _OCC_SETJMP_H

/* Match the platform ABI: these buffers are passed directly to libc setjmp. */
#if defined(__APPLE__) && defined(__aarch64__)
typedef int jmp_buf[48];     /* 192 bytes, 4-byte alignment */
typedef int sigjmp_buf[49];  /* 196 bytes, 4-byte alignment */
#else
typedef long jmp_buf[38];
typedef long sigjmp_buf[38];
#endif

extern int  setjmp(jmp_buf env);
extern void longjmp(jmp_buf env, int val);
extern int  _setjmp(jmp_buf env);
extern void _longjmp(jmp_buf env, int val);

extern int  sigsetjmp(sigjmp_buf env, int savesigs);
extern void siglongjmp(sigjmp_buf env, int val);

#define setjmp(env)  setjmp(env)

#endif /* _OCC_SETJMP_H */
