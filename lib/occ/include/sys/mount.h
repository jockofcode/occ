#ifndef _SYS_MOUNT_H_
#define _SYS_MOUNT_H_

#include <sys/types.h>
#include <sys/param.h>

#define MNT_RDONLY      0x00000001
#define MNT_SYNCHRONOUS 0x00000002
#define MNT_NOEXEC      0x00000004
#define MNT_NOSUID      0x00000008
#define MNT_NODEV       0x00000010
#define MNT_LOCAL       0x00001000
#define MNT_QUOTA       0x00002000
#define MNT_ROOTFS      0x00004000

#define MFSTYPENAMELEN  16
#define MNAMELEN        MAXPATHLEN

struct statfs {
    unsigned int  f_bsize;            /* fundamental file system block size */
    unsigned int  f_iosize;           /* optimal transfer block size */
    unsigned long long f_blocks;      /* total data blocks in file system */
    unsigned long long f_bfree;       /* free blocks in fs */
    unsigned long long f_bavail;      /* free blocks avail to non-superuser */
    unsigned long long f_files;       /* total file nodes in file system */
    unsigned long long f_ffree;       /* free file nodes in fs */
    unsigned int  f_type;             /* type of filesystem */
    unsigned int  f_flags;            /* copy of mount exported flags */
    char          f_fstypename[MFSTYPENAMELEN];
    char          f_mntonname[MNAMELEN];
    char          f_mntfromname[MNAMELEN];
};

extern int statfs(const char *path, struct statfs *buf);
extern int fstatfs(int fd, struct statfs *buf);

#endif /* _SYS_MOUNT_H_ */
