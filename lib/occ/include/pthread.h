#ifndef _OCC_PTHREAD_H
#define _OCC_PTHREAD_H

#include <sys/types.h>
#include <signal.h>
#include <time.h>

/* pthread_t is a pointer-sized opaque handle on macOS */
typedef unsigned long pthread_t;

/* macOS ARM64 opaque pthread types — sizes must match the real SDK structs
   so that any embedding struct (e.g. rb_vm_t) gets the same layout as clang.
   pthread_mutex_t : long __sig + char[56] = 64 bytes
   pthread_cond_t  : long __sig + char[40] = 48 bytes
   pthread_rwlock_t: long __sig + char[192] = 200 bytes
   pthread_attr_t  : long __sig + char[56] = 64 bytes  */
typedef struct { long __sig; char __opaque[56];  } pthread_mutex_t;
typedef struct { long __sig; char __opaque[8];   } pthread_mutexattr_t;
typedef struct { long __sig; char __opaque[40];  } pthread_cond_t;
typedef struct { long __sig; char __opaque[4];   } pthread_condattr_t;
typedef struct { long __sig; char __opaque[192]; } pthread_rwlock_t;
typedef struct { long __sig; char __opaque[16];  } pthread_rwlockattr_t;
typedef struct { long __sig; char __opaque[56];  } pthread_attr_t;
typedef unsigned long pthread_key_t;
typedef long          pthread_once_t;

#define PTHREAD_MUTEX_INITIALIZER  {0x32AAABA7, {0}}
#define PTHREAD_COND_INITIALIZER   {0x3CB0B1BB, {0}}
#define PTHREAD_RWLOCK_INITIALIZER {0x2DA8B3B4, {0}}
#define PTHREAD_ONCE_INIT          0L
#define PTHREAD_MUTEX_NORMAL       0
#define PTHREAD_MUTEX_ERRORCHECK   1
#define PTHREAD_MUTEX_RECURSIVE    2
#define PTHREAD_MUTEX_DEFAULT      PTHREAD_MUTEX_NORMAL
#define PTHREAD_CREATE_JOINABLE    1
#define PTHREAD_CREATE_DETACHED    2
#define PTHREAD_INHERIT_SCHED      1
#define PTHREAD_EXPLICIT_SCHED     2
#define PTHREAD_SCOPE_SYSTEM       1
#define PTHREAD_SCOPE_PROCESS      2
#define PTHREAD_CANCEL_ENABLE      0
#define PTHREAD_CANCEL_DISABLE     1
#define PTHREAD_CANCEL_DEFERRED    0
#define PTHREAD_CANCEL_ASYNCHRONOUS 1

extern int pthread_create(pthread_t *thread, const pthread_attr_t *attr,
                          void *(*start)(void *), void *arg);
extern int pthread_join(pthread_t thread, void **retval);
extern int pthread_detach(pthread_t thread);
extern pthread_t pthread_self(void);
extern int pthread_equal(pthread_t t1, pthread_t t2);
extern void pthread_exit(void *retval);

extern int pthread_mutexattr_init(pthread_mutexattr_t *attr);
extern int pthread_mutexattr_destroy(pthread_mutexattr_t *attr);
extern int pthread_mutexattr_settype(pthread_mutexattr_t *attr, int type);
extern int pthread_mutexattr_gettype(const pthread_mutexattr_t *attr, int *type);

extern int pthread_mutex_init(pthread_mutex_t *m, const pthread_mutexattr_t *a);
extern int pthread_mutex_destroy(pthread_mutex_t *m);
extern int pthread_mutex_lock(pthread_mutex_t *m);
extern int pthread_mutex_trylock(pthread_mutex_t *m);
extern int pthread_mutex_unlock(pthread_mutex_t *m);

extern int pthread_cond_init(pthread_cond_t *c, const pthread_condattr_t *a);
extern int pthread_cond_destroy(pthread_cond_t *c);
extern int pthread_cond_wait(pthread_cond_t *c, pthread_mutex_t *m);
extern int pthread_cond_timedwait(pthread_cond_t *c, pthread_mutex_t *m,
                                  const struct timespec *abstime);
extern int pthread_cond_signal(pthread_cond_t *c);
extern int pthread_cond_broadcast(pthread_cond_t *c);

extern int pthread_key_create(pthread_key_t *key, void (*destructor)(void *));
extern int pthread_key_delete(pthread_key_t key);
extern void *pthread_getspecific(pthread_key_t key);
extern int pthread_setspecific(pthread_key_t key, const void *value);

extern int pthread_once(pthread_once_t *once, void (*init)(void));

extern int pthread_attr_init(pthread_attr_t *attr);
extern int pthread_attr_destroy(pthread_attr_t *attr);
extern int pthread_attr_setdetachstate(pthread_attr_t *attr, int state);
extern int pthread_attr_getdetachstate(const pthread_attr_t *attr, int *state);
extern int pthread_attr_setstacksize(pthread_attr_t *attr, size_t stacksize);
extern int pthread_attr_getstacksize(const pthread_attr_t *attr, size_t *stacksize);
extern int pthread_attr_setinheritsched(pthread_attr_t *attr, int inheritsched);
extern int pthread_attr_getinheritsched(const pthread_attr_t *attr, int *inheritsched);
extern int pthread_attr_setscope(pthread_attr_t *attr, int scope);

extern int pthread_rwlock_init(pthread_rwlock_t *rwlock, const pthread_rwlockattr_t *attr);
extern int pthread_rwlock_destroy(pthread_rwlock_t *rwlock);
extern int pthread_rwlock_rdlock(pthread_rwlock_t *rwlock);
extern int pthread_rwlock_wrlock(pthread_rwlock_t *rwlock);
extern int pthread_rwlock_tryrdlock(pthread_rwlock_t *rwlock);
extern int pthread_rwlock_trywrlock(pthread_rwlock_t *rwlock);
extern int pthread_rwlock_unlock(pthread_rwlock_t *rwlock);

extern int pthread_cancel(pthread_t thread);
extern int pthread_setcancelstate(int state, int *oldstate);
extern int pthread_setcanceltype(int type, int *oldtype);
extern void pthread_testcancel(void);

extern int pthread_sigmask(int how, const sigset_t *set, sigset_t *oldset);

#endif /* _OCC_PTHREAD_H */
