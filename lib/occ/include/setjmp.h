#ifndef _OCC_SETJMP_H
#define _OCC_SETJMP_H

/* jmp_buf must be large enough for all callee-saved registers + sp + pc.
   Use a conservative 38-long array (matches glibc/musl on most platforms). */
typedef long jmp_buf[38];
typedef long sigjmp_buf[38];

extern int  setjmp(jmp_buf env);
extern void longjmp(jmp_buf env, int val);

extern int  sigsetjmp(sigjmp_buf env, int savesigs);
extern void siglongjmp(sigjmp_buf env, int val);

#define setjmp(env)  setjmp(env)

#endif /* _OCC_SETJMP_H */
