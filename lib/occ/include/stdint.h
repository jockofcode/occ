#ifndef _OCC_STDINT_H
#define _OCC_STDINT_H

typedef signed char        int8_t;
typedef unsigned char      uint8_t;
typedef short              int16_t;
typedef unsigned short     uint16_t;
typedef int                int32_t;
typedef unsigned int       uint32_t;
typedef long               int64_t;
typedef unsigned long      uint64_t;
typedef long               intptr_t;
typedef unsigned long      uintptr_t;
typedef long               intmax_t;
typedef unsigned long      uintmax_t;

typedef __int128           __int128_t;
typedef unsigned __int128  __uint128_t;

/* Least-width integer types */
typedef signed char        int_least8_t;
typedef unsigned char      uint_least8_t;
typedef short              int_least16_t;
typedef unsigned short     uint_least16_t;
typedef int                int_least32_t;
typedef unsigned int       uint_least32_t;
typedef long               int_least64_t;
typedef unsigned long      uint_least64_t;

/* Fast integer types */
typedef signed char        int_fast8_t;
typedef unsigned char      uint_fast8_t;
typedef long               int_fast16_t;
typedef unsigned long      uint_fast16_t;
typedef long               int_fast32_t;
typedef unsigned long      uint_fast32_t;
typedef long               int_fast64_t;
typedef unsigned long      uint_fast64_t;

#ifndef _OCC_STDDEF_H
typedef unsigned long size_t;
#endif

#define INT8_MIN    (-128)
#define INT8_MAX    127
#define UINT8_MAX   255U
#define INT16_MIN   (-32768)
#define INT16_MAX   32767
#define UINT16_MAX  65535U
#define INT32_MIN   (-2147483647 - 1)
#define INT32_MAX   2147483647
#define UINT32_MAX  4294967295U
#define INT64_MIN   (-9223372036854775807L - 1L)
#define INT64_MAX   9223372036854775807L
#define UINT64_MAX  18446744073709551615UL

#define SIZE_MAX    UINT64_MAX
#define INTPTR_MIN  INT64_MIN
#define INTPTR_MAX  INT64_MAX
#define UINTPTR_MAX UINT64_MAX
#define INTMAX_MIN  INT64_MIN
#define INTMAX_MAX  INT64_MAX
#define UINTMAX_MAX UINT64_MAX

/* Integer constant macros */
#define INT8_C(c)   c
#define UINT8_C(c)  c ## U
#define INT16_C(c)  c
#define UINT16_C(c) c ## U
#define INT32_C(c)  c
#define UINT32_C(c) c ## U
#define INT64_C(c)  c ## L
#define UINT64_C(c) c ## UL
#define INTMAX_C(c)  c ## L
#define UINTMAX_C(c) c ## UL

/* Convenience macros for printf format strings */
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

#endif /* _OCC_STDINT_H */
