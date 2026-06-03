#ifndef _OCC_TIME_H
#define _OCC_TIME_H

#include <stddef.h>

typedef long time_t;
typedef long clock_t;
typedef long suseconds_t;

#define CLOCKS_PER_SEC 1000000L
#define TIME_UTC       1

struct tm {
    int tm_sec;
    int tm_min;
    int tm_hour;
    int tm_mday;
    int tm_mon;
    int tm_year;
    int tm_wday;
    int tm_yday;
    int tm_isdst;
};

struct timespec {
    time_t tv_sec;
    long   tv_nsec;
};

struct timeval {
    time_t      tv_sec;
    suseconds_t tv_usec;
};

extern time_t   time(time_t *tloc);
extern clock_t  clock(void);
extern double   difftime(time_t t1, time_t t0);
extern time_t   mktime(struct tm *tm);
extern struct tm *gmtime(const time_t *timep);
extern struct tm *localtime(const time_t *timep);
extern struct tm *gmtime_r(const time_t *timep, struct tm *result);
extern struct tm *localtime_r(const time_t *timep, struct tm *result);
extern size_t   strftime(char *s, size_t max, const char *fmt,
                         const struct tm *tm);
extern char    *asctime(const struct tm *tm);
extern char    *ctime(const time_t *timep);

extern int      nanosleep(const struct timespec *req, struct timespec *rem);
extern int      clock_gettime(int clk_id, struct timespec *tp);
extern int      clock_settime(int clk_id, const struct timespec *tp);

#define CLOCK_REALTIME  0
#define CLOCK_MONOTONIC 1

#endif /* _OCC_TIME_H */
