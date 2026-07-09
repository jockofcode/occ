#ifndef _OCC_FCNTL_H
#define _OCC_FCNTL_H

#include <sys/types.h>

/* open() flags */
#define O_RDONLY    0
#define O_WRONLY    1
#define O_RDWR      2
#if defined(__APPLE__)
#define O_NONBLOCK  0x0004
#define O_APPEND    0x0008
#define O_CREAT     0x0200
#define O_TRUNC     0x0400
#define O_EXCL      0x0800
#define O_NOCTTY    0x20000
#define O_CLOEXEC   0x1000000
#define O_DSYNC     0x400000
#define O_SYNC      0x80400000
#else
/* Linux values */
#define O_CREAT     0100
#define O_EXCL      0200
#define O_NOCTTY    0400
#define O_TRUNC     01000
#define O_APPEND    02000
#define O_NONBLOCK  04000
#define O_DSYNC     010000
#define O_SYNC      04010000
#define O_CLOEXEC   02000000
#endif

/* fcntl() commands */
#define F_DUPFD     0
#define F_GETFD     1
#define F_SETFD     2
#define F_GETFL     3
#define F_SETFL     4
#define F_GETLK     5
#define F_SETLK     6
#define F_SETLKW    7
#define F_DUPFD_CLOEXEC 67

#define FD_CLOEXEC  1

/* flock l_type values */
#define F_RDLCK     1
#define F_WRLCK     2
#define F_UNLCK     8

/* struct flock for fcntl(F_SETLK/F_GETLK) */
struct flock {
    short   l_type;     /* F_RDLCK, F_WRLCK, F_UNLCK */
    short   l_whence;   /* SEEK_SET, SEEK_CUR, SEEK_END */
    off_t   l_start;    /* byte offset of lock region */
    off_t   l_len;      /* length of lock region; 0=EOF */
    pid_t   l_pid;      /* PID holding lock (F_GETLK only) */
};

/* openat() directory file descriptor constants */
#define AT_FDCWD            (-2)
#define AT_SYMLINK_NOFOLLOW 0x0020
#define AT_SYMLINK_FOLLOW   0x0040
#define AT_REMOVEDIR        0x0080
#define AT_REALDEV          0x0200
#define AT_FDONLY           0x0400

extern int open(const char *path, int flags, ...);
extern int creat(const char *path, mode_t mode);
extern int fcntl(int fd, int cmd, ...);
extern int openat(int dirfd, const char *path, int flags, ...);
extern int fstatat(int dirfd, const char *path, void *statbuf, int flags);
extern int unlinkat(int dirfd, const char *path, int flags);
extern int linkat(int olddirfd, const char *oldpath, int newdirfd, const char *newpath, int flags);
extern int renameat(int olddirfd, const char *oldpath, int newdirfd, const char *newpath);

#include <unistd.h>

#endif /* _OCC_FCNTL_H */
