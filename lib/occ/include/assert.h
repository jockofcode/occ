#ifndef _OCC_ASSERT_H
#define _OCC_ASSERT_H

#include <stdio.h>
#include <stdlib.h>

#ifdef NDEBUG
#  define assert(e) ((void)0)
#else
#  define assert(e) \
     ((e) ? (void)0 : (fprintf(stderr, "%s:%d: Assertion `%s' failed.\n", \
                                __FILE__, __LINE__, #e), abort(), (void)0))
#endif

#define static_assert _Static_assert

#endif /* _OCC_ASSERT_H */
