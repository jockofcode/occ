#ifndef _OCC_LOCALE_H
#define _OCC_LOCALE_H

#define LC_ALL      0
#define LC_COLLATE  1
#define LC_CTYPE    2
#define LC_MONETARY 3
#define LC_NUMERIC  4
#define LC_TIME     5
#define LC_MESSAGES 6

extern char *setlocale(int category, const char *locale);

#endif /* _OCC_LOCALE_H */
