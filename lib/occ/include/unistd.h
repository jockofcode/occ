#ifndef _OCC_UNISTD_H
#define _OCC_UNISTD_H

#include <sys/types.h>
#include <stddef.h>

/* Standard file descriptors */
#define STDIN_FILENO  0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2

/* access() mode flags */
#define F_OK 0
#define X_OK 1
#define W_OK 2
#define R_OK 4

/* lseek() whence values */
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2

/* I/O */
extern ssize_t read(int fd, void *buf, size_t count);
extern ssize_t write(int fd, const void *buf, size_t count);
extern int     close(int fd);
extern off_t   lseek(int fd, off_t offset, int whence);

/* File */
extern int  unlink(const char *path);
extern int  rmdir(const char *path);
extern int  access(const char *path, int mode);
extern int  chdir(const char *path);
extern char *getcwd(char *buf, size_t size);
extern int  truncate(const char *path, off_t length);
extern int  ftruncate(int fd, off_t length);
extern int  fsync(int fd);
extern int  fdatasync(int fd);
extern int  dup(int oldfd);
extern int  dup2(int oldfd, int newfd);
extern int  pipe(int pipefd[2]);

/* Links */
extern int  link(const char *oldpath, const char *newpath);
extern int  symlink(const char *target, const char *linkpath);
extern ssize_t readlink(const char *path, char *buf, size_t bufsiz);

/* Process */
extern pid_t getpid(void);
extern pid_t getppid(void);
extern uid_t getuid(void);
extern uid_t geteuid(void);
extern gid_t getgid(void);
extern gid_t getegid(void);
extern int   setuid(uid_t uid);
extern int   setgid(gid_t gid);
extern pid_t fork(void);
extern int   execl(const char *path, const char *arg, ...);
extern int   execlp(const char *file, const char *arg, ...);
extern int   execle(const char *path, const char *arg, ...);
extern int   execv(const char *path, char *const argv[]);
extern int   execvp(const char *file, char *const argv[]);
extern int   execve(const char *path, char *const argv[], char *const envp[]);

/* Terminal */
extern int isatty(int fd);

/* Misc */
extern unsigned int sleep(unsigned int seconds);
extern int  usleep(unsigned int usec);
extern long sysconf(int name);
extern long pathconf(const char *path, int name);
extern char *optarg;
extern int   optind, opterr, optopt;
extern int   getopt(int argc, char *const argv[], const char *optstring);

/* sysconf constants */
#define _SC_CLK_TCK       2
#define _SC_PAGESIZE       30
#define _SC_PAGE_SIZE      _SC_PAGESIZE
#define _SC_NPROCESSORS_ONLN 84

#endif /* _OCC_UNISTD_H */
