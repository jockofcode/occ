#ifndef _OCC_SYS_TIME_H
#define _OCC_SYS_TIME_H

#include <time.h>

extern int gettimeofday(struct timeval *tv, void *tz);
extern int utimes(const char *path, const struct timeval times[2]);
extern int futimes(int fd, const struct timeval times[2]);

#endif /* _OCC_SYS_TIME_H */
