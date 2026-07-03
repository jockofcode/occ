#ifndef _OCC_SYS_SELECT_H
#define _OCC_SYS_SELECT_H

#include <sys/types.h>
#include <time.h>
#include <string.h>

#define FD_SETSIZE 1024

typedef struct {
    unsigned long fds_bits[FD_SETSIZE / (8 * sizeof(unsigned long))];
} fd_set;

#define FD_ZERO(set)   memset((set), 0, sizeof(fd_set))
#define FD_SET(fd,set) ((set)->fds_bits[(fd)/(8*sizeof(unsigned long))] |= (1UL << ((fd)%(8*sizeof(unsigned long)))))
#define FD_CLR(fd,set) ((set)->fds_bits[(fd)/(8*sizeof(unsigned long))] &= ~(1UL << ((fd)%(8*sizeof(unsigned long)))))
#define FD_ISSET(fd,set) (!!((set)->fds_bits[(fd)/(8*sizeof(unsigned long))] & (1UL << ((fd)%(8*sizeof(unsigned long))))))

extern int select(int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, struct timeval *timeout);

#endif /* _OCC_SYS_SELECT_H */
