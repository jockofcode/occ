#ifndef _OCC_SIGNAL_H
#define _OCC_SIGNAL_H

#include <sys/types.h>

typedef void (*sighandler_t)(int);
typedef sighandler_t sig_t;
typedef int sig_atomic_t;

/* Standard signals */
#define SIGHUP    1
#define SIGINT    2
#define SIGQUIT   3
#define SIGILL    4
#define SIGTRAP   5
#define SIGABRT   6
#define SIGBUS    7
#define SIGFPE    8
#define SIGKILL   9
#define SIGUSR1   10
#define SIGSEGV   11
#define SIGUSR2   12
#define SIGPIPE   13
#define SIGALRM   14
#define SIGTERM   15
#define SIGCHLD   17
#define SIGCONT   18
#define SIGSTOP   19
#define SIGTSTP   20
#define SIGTTIN   21
#define SIGTTOU   22
#define SIGURG    23
#define SIGXCPU   24
#define SIGXFSZ   25
#define SIGVTALRM 26
#define SIGPROF   27
#define SIGWINCH  28
#define SIGIO     29
#define SIGPWR    30
#define SIGSYS    31
#define NSIG      32

/* Special handler values */
#define SIG_DFL ((sighandler_t)0)
#define SIG_IGN ((sighandler_t)1)
#define SIG_ERR ((sighandler_t)(-1))

/* sigset_t */
typedef unsigned long sigset_t;

/* sigval — used inside siginfo_t */
union sigval {
    int   sival_int;
    void *sival_ptr;
};

/* siginfo_t — signal information structure */
typedef struct __siginfo {
    int           si_signo;
    int           si_errno;
    int           si_code;
    int           si_pid;
    unsigned int  si_uid;
    int           si_status;
    void         *si_addr;
    union sigval  si_value;
    long          si_band;
    unsigned long __pad[7];
} siginfo_t;

/* signal() installs handler and returns previous; raise() sends signal to self */
extern sighandler_t signal(int signum, sighandler_t handler);
extern int          raise(int sig);
extern int          kill(pid_t pid, int sig);
extern int          killpg(pid_t pgrp, int sig);

/* sigaction */
struct sigaction {
    union {
        sighandler_t  sa_handler;
        void        (*sa_sigaction)(int, siginfo_t *, void *);
    };
    sigset_t     sa_mask;
    int          sa_flags;
};

extern int sigaction(int signum, const struct sigaction *act,
                     struct sigaction *oldact);
extern int sigemptyset(sigset_t *set);
extern int sigfillset(sigset_t *set);
extern int sigaddset(sigset_t *set, int signum);
extern int sigdelset(sigset_t *set, int signum);
extern int sigismember(const sigset_t *set, int signum);
extern int sigprocmask(int how, const sigset_t *set, sigset_t *oldset);
extern int sigpending(sigset_t *set);
extern int sigsuspend(const sigset_t *mask);

/* alternate signal stack */
typedef struct {
    void  *ss_sp;
    int    ss_flags;
    size_t ss_size;
} stack_t;

#define MINSIGSTKSZ 2048
#define SIGSTKSZ    8192
#define SS_DISABLE  4

extern int sigaltstack(const stack_t *ss, stack_t *oss);

/* si_code values for SI_USER and other sources */
#define SI_USER     0x10001
#define SI_QUEUE    0x10002
#define SI_TIMER    0x10003
#define SI_ASYNCIO  0x10004
#define SI_MESGQ    0x10005
#define SI_KERNEL   0x10006

#define SA_NOCLDSTOP  1
#define SA_NOCLDWAIT  2
#define SA_SIGINFO    4
#define SA_ONSTACK    0x08000000
#define SA_RESTART    0x10000000
#define SA_NODEFER    0x40000000
#define SA_RESETHAND  0x80000000

#define SIG_BLOCK   0
#define SIG_UNBLOCK 1
#define SIG_SETMASK 2

#endif /* _OCC_SIGNAL_H */
