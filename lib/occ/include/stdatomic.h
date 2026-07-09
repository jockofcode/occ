#ifndef _OCC_STDATOMIC_H
#define _OCC_STDATOMIC_H

/* Minimal stdatomic.h stub for OCC — covers the subset used by CRuby. */

typedef int              atomic_int;
typedef unsigned int     atomic_uint;
typedef long             atomic_long;
typedef unsigned long    atomic_ulong;
typedef int              atomic_bool;
typedef char             atomic_char;
typedef unsigned char    atomic_uchar;
typedef short            atomic_short;
typedef unsigned short   atomic_ushort;
typedef long long        atomic_llong;
typedef unsigned long long atomic_ullong;
typedef unsigned long    atomic_size_t;
typedef long             atomic_ptrdiff_t;
typedef long             atomic_intptr_t;
typedef unsigned long    atomic_uintptr_t;
typedef long             atomic_intmax_t;
typedef unsigned long    atomic_uintmax_t;

#define _Atomic(T) T

#define ATOMIC_VAR_INIT(v) (v)

#define atomic_init(obj, val)     (*(obj) = (val))
#define atomic_load(obj)          (*(obj))
#define atomic_store(obj, val)    (*(obj) = (val))
#define atomic_exchange(obj, val) __sync_lock_test_and_set(obj, val)

#define atomic_load_explicit(obj, order)          atomic_load(obj)
#define atomic_store_explicit(obj, val, order)    atomic_store(obj, val)
#define atomic_exchange_explicit(obj, val, order) atomic_exchange(obj, val)

#define atomic_fetch_add(obj, arg)  __sync_fetch_and_add(obj, arg)
#define atomic_fetch_sub(obj, arg)  __sync_fetch_and_sub(obj, arg)
#define atomic_fetch_and(obj, arg)  __sync_fetch_and_and(obj, arg)
#define atomic_fetch_or(obj, arg)   __sync_fetch_and_or(obj, arg)
#define atomic_fetch_xor(obj, arg)  __sync_fetch_and_xor(obj, arg)

#define atomic_fetch_add_explicit(obj, arg, order) atomic_fetch_add(obj, arg)
#define atomic_fetch_sub_explicit(obj, arg, order) atomic_fetch_sub(obj, arg)

#define atomic_compare_exchange_strong(obj, exp, des) \
    __sync_bool_compare_and_swap(obj, *(exp), des)
#define atomic_compare_exchange_weak(obj, exp, des) \
    atomic_compare_exchange_strong(obj, exp, des)
#define atomic_compare_exchange_strong_explicit(obj, exp, des, succ, fail) \
    atomic_compare_exchange_strong(obj, exp, des)
#define atomic_compare_exchange_weak_explicit(obj, exp, des, succ, fail) \
    atomic_compare_exchange_strong(obj, exp, des)

#define atomic_thread_fence(order)  __sync_synchronize()
#define atomic_signal_fence(order)  __sync_synchronize()

typedef enum {
    memory_order_relaxed = 0,
    memory_order_consume = 1,
    memory_order_acquire = 2,
    memory_order_release = 3,
    memory_order_acq_rel = 4,
    memory_order_seq_cst = 5
} memory_order;

#define ATOMIC_BOOL_LOCK_FREE     2
#define ATOMIC_CHAR_LOCK_FREE     2
#define ATOMIC_SHORT_LOCK_FREE    2
#define ATOMIC_INT_LOCK_FREE      2
#define ATOMIC_LONG_LOCK_FREE     2
#define ATOMIC_LLONG_LOCK_FREE    2
#define ATOMIC_POINTER_LOCK_FREE  2

#define atomic_flag_test_and_set(obj)   __sync_lock_test_and_set(obj, 1)
#define atomic_flag_clear(obj)          __sync_lock_release(obj)

typedef struct { int __val; } atomic_flag;

#endif /* _OCC_STDATOMIC_H */
