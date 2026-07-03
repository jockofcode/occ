#ifndef _SYS_PARAM_H_
#define _SYS_PARAM_H_

#define MAXPATHLEN  1024
#define MAXNAMLEN   255
#define NBBY        8
#define NBPG        4096

#ifndef NULL
#define NULL ((void *)0)
#endif

#define MIN(a,b) ((a)<(b)?(a):(b))
#define MAX(a,b) ((a)>(b)?(a):(b))

#endif /* _SYS_PARAM_H_ */
