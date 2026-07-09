#ifndef __STDCKDINT_H
#define __STDCKDINT_H

#define __STDC_VERSION_STDCKDINT_H__ 202311L

#define ckd_add(result, a, b) ((int)__builtin_add_overflow((a), (b), (result)))
#define ckd_sub(result, a, b) ((int)__builtin_sub_overflow((a), (b), (result)))
#define ckd_mul(result, a, b) ((int)__builtin_mul_overflow((a), (b), (result)))

#endif
