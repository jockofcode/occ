#ifndef _OCC_MATH_H
#define _OCC_MATH_H

/* Mathematical constants */
#define M_E         2.7182818284590452354
#define M_LOG2E     1.4426950408889634074
#define M_LOG10E    0.43429448190325182766
#define M_LN2       0.69314718055994530942
#define M_LN10      2.30258509299404568402
#define M_PI        3.14159265358979323846
#define M_PI_2      1.57079632679489661923
#define M_PI_4      0.78539816339744830962
#define M_1_PI      0.31830988618379067154
#define M_2_PI      0.63661977236758134308
#define M_2_SQRTPI  1.12837916709551257390
#define M_SQRT2     1.41421356237309504880
#define M_SQRT1_2   0.70710678118654752440

/* Special values */
#define HUGE_VAL  (1.0/0.0)
#define HUGE_VALF (1.0f/0.0f)
#define INFINITY  (1.0f/0.0f)
#define NAN       (0.0f/0.0f)
#define MATH_ERRNO      1
#define MATH_ERREXCEPT  2
#define math_errhandling MATH_ERRNO

/* FP classification */
#define FP_INFINITE  1
#define FP_NAN       2
#define FP_NORMAL    3
#define FP_SUBNORMAL 4
#define FP_ZERO      5

/* Trigonometric */
extern double sin(double x);
extern double cos(double x);
extern double tan(double x);
extern double asin(double x);
extern double acos(double x);
extern double atan(double x);
extern double atan2(double y, double x);

/* Hyperbolic */
extern double sinh(double x);
extern double cosh(double x);
extern double tanh(double x);
extern double asinh(double x);
extern double acosh(double x);
extern double atanh(double x);

/* Exponential / logarithmic */
extern double exp(double x);
extern double exp2(double x);
extern double expm1(double x);
extern double log(double x);
extern double log2(double x);
extern double log10(double x);
extern double log1p(double x);
extern double logb(double x);
extern double nan(const char *tagp);
extern float nanf(const char *tagp);

/* Power */
extern double pow(double x, double y);
extern double sqrt(double x);
extern double cbrt(double x);
extern double hypot(double x, double y);

/* Rounding */
extern double ceil(double x);
extern double floor(double x);
extern double round(double x);
extern double trunc(double x);
extern double rint(double x);
extern double nearbyint(double x);
extern long   lround(double x);
extern long long llround(double x);
extern long   lrint(double x);
extern long long llrint(double x);

/* Absolute value */
extern double fabs(double x);
extern float  fabsf(float x);

/* Remainder */
extern double fmod(double x, double y);
extern double remainder(double x, double y);
extern double remquo(double x, double y, int *quo);

/* Float manipulation */
extern double frexp(double x, int *exp);
extern double ldexp(double x, int exp);
extern double modf(double x, double *iptr);
extern double scalbn(double x, int n);
extern int    ilogb(double x);

/* Min / max / dim */
extern double fmax(double x, double y);
extern double fmin(double x, double y);
extern double fdim(double x, double y);
extern double fma(double x, double y, double z);

/* Float versions */
extern float sinf(float x);
extern float cosf(float x);
extern float tanf(float x);
extern float expf(float x);
extern float logf(float x);
extern float powf(float x, float y);
extern float sqrtf(float x);
extern float fabsf(float x);
extern float floorf(float x);
extern float ceilf(float x);
extern float roundf(float x);
extern float fmodf(float x, float y);
extern float fmaxf(float x, float y);
extern float fminf(float x, float y);

/* Error function */
extern double erf(double x);
extern double erfc(double x);
extern float  erff(float x);
extern float  erfcf(float x);

/* Bessel functions */
extern double j0(double x);
extern double j1(double x);
extern double y0(double x);
extern double y1(double x);

/* Classification macros (simplified) */
#define isnan(x)    ((x) != (x))
#define isinf(x)    (!isnan(x) && isnan((x) - (x)))
#define isfinite(x) (!isinf(x) && !isnan(x))
#define isnormal(x) (isfinite(x) && (x) != 0.0)
#define signbit(x)  ((x) < 0.0)

#endif /* _OCC_MATH_H */
