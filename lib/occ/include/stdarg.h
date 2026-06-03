#ifndef _OCC_STDARG_H
#define _OCC_STDARG_H

/*
 * va_list — a char* pointer to the next variadic argument on the stack.
 *
 * occ's variadic calling convention on both ARM64 and AMD64: named args go
 * in registers, unnamed (variadic) args are pushed to the stack before the
 * call instruction.  __occ_va_first_arg() returns the address of the first
 * such stack argument.
 *
 * This simple char* representation is compatible with Apple's ARM64 libc
 * (which also treats va_list as a plain stack pointer) and with occ's own
 * va_arg expansion on both platforms.
 */
typedef char *va_list;

extern char *__occ_va_first_arg(void);

#define va_start(ap, last) ((ap) = __occ_va_first_arg())
#define va_arg(ap, T)      (*(T *)(((ap) += 8), ((ap) - 8)))
#define va_end(ap)         ((ap) = (char *)0)
#define va_copy(d, s)      ((d) = (s))

#endif /* _OCC_STDARG_H */
