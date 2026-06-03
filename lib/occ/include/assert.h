#ifndef _OCC_ASSERT_H
#define _OCC_ASSERT_H

#include <stdio.h>
#include <stdlib.h>

extern void __occ_assert_fail(const char *expr, const char *file, int line);

#ifdef NDEBUG
#  define assert(e) ((void)0)
#else
#  define assert(e) \
     ((e) ? (void)0 : (__occ_assert_fail(#e, __FILE__, __LINE__), (void)0))
#endif

#define static_assert _Static_assert

#endif /* _OCC_ASSERT_H */
