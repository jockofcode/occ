#ifndef _OCC_MACH_MACH_TIME_H
#define _OCC_MACH_MACH_TIME_H

#include <stdint.h>

typedef struct mach_timebase_info {
    uint32_t numer;
    uint32_t denom;
} mach_timebase_info_data_t;

typedef mach_timebase_info_data_t *mach_timebase_info_t;

extern uint64_t mach_absolute_time(void);
extern int mach_timebase_info(mach_timebase_info_t info);

#endif /* _OCC_MACH_MACH_TIME_H */
