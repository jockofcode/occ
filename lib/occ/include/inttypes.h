#ifndef _OCC_INTTYPES_H
#define _OCC_INTTYPES_H

#include <stdint.h>

/* printf format macros for intN_t types */
#define PRId8   "d"
#define PRId16  "d"
#define PRId32  "d"
#define PRId64  "ld"

#define PRIu8   "u"
#define PRIu16  "u"
#define PRIu32  "u"
#define PRIu64  "lu"

#define PRIx8   "x"
#define PRIx16  "x"
#define PRIx32  "x"
#define PRIx64  "lx"

#define PRIX8   "X"
#define PRIX16  "X"
#define PRIX32  "X"
#define PRIX64  "lX"

#define PRIo8   "o"
#define PRIo16  "o"
#define PRIo32  "o"
#define PRIo64  "lo"

#define PRIi8   "i"
#define PRIi16  "i"
#define PRIi32  "i"
#define PRIi64  "li"

/* scanf format macros */
#define SCNd8   "hhd"
#define SCNd16  "hd"
#define SCNd32  "d"
#define SCNd64  "ld"

#define SCNu8   "hhu"
#define SCNu16  "hu"
#define SCNu32  "u"
#define SCNu64  "lu"

/* pointer-width format macros (uintptr_t is 64-bit on ARM64/x86-64) */
#define PRIdPTR  "ld"
#define PRIiPTR  "li"
#define PRIoPTR  "lo"
#define PRIuPTR  "lu"
#define PRIxPTR  "lx"
#define PRIXptr  "lX"
#define PRIXPTR  "lX"

#define SCNdPTR  "ld"
#define SCNiPTR  "li"
#define SCNoPTR  "lo"
#define SCNuPTR  "lu"
#define SCNxPTR  "lx"

/* LEAST / FAST width-printf macros (common subset) */
#define PRId32LEAST  "d"
#define PRId64LEAST  "ld"
#define PRIu32LEAST  "u"
#define PRIu64LEAST  "lu"
#define PRIx32LEAST  "x"
#define PRIx64LEAST  "lx"

#define PRId32FAST   "d"
#define PRId64FAST   "ld"
#define PRIu32FAST   "u"
#define PRIu64FAST   "lu"
#define PRIx32FAST   "x"
#define PRIx64FAST   "lx"

#define PRIdMAX  "ld"
#define PRIiMAX  "li"
#define PRIoMAX  "lo"
#define PRIuMAX  "lu"
#define PRIxMAX  "lx"
#define PRIXMAX  "lX"

#define SCNdMAX  "ld"
#define SCNiMAX  "li"
#define SCNoMAX  "lo"
#define SCNuMAX  "lu"
#define SCNxMAX  "lx"

#endif /* _OCC_INTTYPES_H */
