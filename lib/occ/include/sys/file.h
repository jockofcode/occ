#ifndef _SYS_FILE_H_
#define _SYS_FILE_H_

#include <fcntl.h>

#define LOCK_SH  0x01   /* shared file lock */
#define LOCK_EX  0x02   /* exclusive file lock */
#define LOCK_NB  0x04   /* do not block when locking */
#define LOCK_UN  0x08   /* unlock file */

extern int flock(int fd, int operation);

#endif /* _SYS_FILE_H_ */
