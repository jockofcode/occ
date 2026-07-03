#ifndef _OCC_PTHREAD_H
#define _OCC_PTHREAD_H

#include <sys/types.h>

typedef unsigned long pthread_t;
typedef unsigned long pthread_attr_t;
typedef unsigned long pthread_mutex_t;
typedef unsigned long pthread_mutexattr_t;
typedef unsigned long pthread_cond_t;
typedef unsigned long pthread_condattr_t;
typedef unsigned long pthread_rwlock_t;
typedef unsigned long pthread_rwlockattr_t;
typedef unsigned long pthread_key_t;
typedef unsigned long pthread_once_t;

#define PTHREAD_MUTEX_INITIALIZER  0UL
#define PTHREAD_COND_INITIALIZER   0UL
#define PTHREAD_RWLOCK_INITIALIZER 0UL
#define PTHREAD_ONCE_INIT          0UL
#define PTHREAD_MUTEX_NORMAL       0
#define PTHREAD_MUTEX_ERRORCHECK   1
#define PTHREAD_MUTEX_RECURSIVE    2
#define PTHREAD_MUTEX_DEFAULT      PTHREAD_MUTEX_NORMAL

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
extern int pthread_cond_signal(pthread_cond_t *c);
extern int pthread_cond_broadcast(pthread_cond_t *c);

extern int pthread_key_create(pthread_key_t *key, void (*destructor)(void *));
extern int pthread_key_delete(pthread_key_t key);
extern void *pthread_getspecific(pthread_key_t key);
extern int pthread_setspecific(pthread_key_t key, const void *value);

extern int pthread_once(pthread_once_t *once, void (*init)(void));

#endif /* _OCC_PTHREAD_H */
