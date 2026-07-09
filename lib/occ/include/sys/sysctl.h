#ifndef _SYS_SYSCTL_H_
#define _SYS_SYSCTL_H_

#include <sys/types.h>

extern int sysctl(int *name, unsigned int namelen, void *oldp, size_t *oldlenp,
                  void *newp, size_t newlen);
extern int sysctlbyname(const char *name, void *oldp, size_t *oldlenp,
                        void *newp, size_t newlen);
extern int sysctlnametomib(const char *name, int *mibp, size_t *sizep);

/* CTL_* top-level identifiers */
#define CTL_KERN    1
#define CTL_HW      6

/* CTL_KERN identifiers */
#define KERN_OSTYPE     1
#define KERN_OSRELEASE  2
#define KERN_OSREV      3
#define KERN_VERSION    4
#define KERN_HOSTNAME   10
#define KERN_OSRELDATE  211

/* CTL_HW identifiers */
#define HW_NCPU     3
#define HW_MEMSIZE  24

#endif /* _SYS_SYSCTL_H_ */
