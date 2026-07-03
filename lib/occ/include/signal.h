#ifndef _OCC_SIGNAL_H
#define _OCC_SIGNAL_H

#include <sys/types.h>

typedef void (*sighandler_t)(int);
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

/* signal() installs handler and returns previous; raise() sends signal to self */
extern sighandler_t signal(int signum, sighandler_t handler);
extern int          raise(int sig);
extern int          kill(pid_t pid, int sig);

/* sigaction */
struct sigaction {
    sighandler_t sa_handler;
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
