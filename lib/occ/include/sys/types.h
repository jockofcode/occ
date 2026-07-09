#ifndef _OCC_SYS_TYPES_H
#define _OCC_SYS_TYPES_H

#include <stddef.h>

typedef long          ssize_t;
typedef long          off_t;
typedef unsigned int  mode_t;
typedef int           pid_t;
typedef unsigned int  uid_t;
typedef unsigned int  gid_t;
typedef unsigned long ino_t;
typedef unsigned long dev_t;
typedef long          blksize_t;
typedef long          blkcnt_t;
typedef unsigned long nlink_t;

typedef unsigned char  u_char;
typedef unsigned short u_short;
typedef unsigned int   u_int;
typedef unsigned long  u_long;
typedef unsigned char  u_int8_t;
typedef unsigned short u_int16_t;
typedef unsigned int   u_int32_t;
typedef unsigned long  u_int64_t;
typedef char          *caddr_t;

typedef struct { int val[2]; } fsid_t;

typedef unsigned char uuid_t[16];

#endif /* _OCC_SYS_TYPES_H */
