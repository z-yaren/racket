#include "rktio.h"
#include "rktio_private.h"
#include <stdlib.h>
#ifdef RKTIO_SYSTEM_UNIX
# include <unistd.h>
# ifdef RKTIO_HAS_CLOEXEC
#  if defined(__linux__)
#   include <fcntl.h>
extern int pipe2(int pipefd[2], int flags);
#  endif
# endif
#endif

#ifdef RKTIO_SYSTEM_WINDOWS
# ifndef USE_CYGWIN_PIPES
#  define _EXTRA_PIPE_ARGS , rktio
static int MyPipe(intptr_t *ph, int flags, rktio_t *rktio)
{
  HANDLE r, w;
  SECURITY_ATTRIBUTES saAttr;
  int retval;

  /* Set the bInheritHandle flag so pipe handles are inherited. */
  saAttr.nLength = sizeof(SECURITY_ATTRIBUTES);
  saAttr.bInheritHandle = TRUE;
  saAttr.lpSecurityDescriptor = NULL;

  if (flags & (RKTIO_NO_INHERIT_INPUT | RKTIO_NO_INHERIT_OUTPUT))
    rktio_cloexec_lock();

  if (CreatePipe(&r, &w, &saAttr, 0)) {
    HANDLE a[2], naya;
    int near_index;

    a[0] = r;
    a[1] = w;

    for (near_index = 0; near_index < 2; near_index++) {
      if (flags & (!near_index ? RKTIO_NO_INHERIT_INPUT : RKTIO_NO_INHERIT_OUTPUT)) {
        /* Change the near end to make it non-inheritable, then
           close the inheritable one: */
        if (!DuplicateHandle(GetCurrentProcess(), a[near_index],
                             GetCurrentProcess(), &naya, 0,
                             0, /* not inherited */
                             DUPLICATE_SAME_ACCESS)) {
          get_windows_error();
          CloseHandle(a[0]);
          CloseHandle(a[1]);
          return 1;
        } else {
          CloseHandle(a[near_index]);
          a[near_index] = naya;
        }
      }
    }

    ph[0] = (intptr_t)a[0];
    ph[1] = (intptr_t)a[1];

    retval = 0;
  } else {
    get_windows_error();
    retval = 1;
  }

  if (flags & (RKTIO_NO_INHERIT_INPUT | RKTIO_NO_INHERIT_OUTPUT))
    rktio_cloexec_unlock();

  return retval;
}
#  define PIPE_FUNC MyPipe
#  define PIPE_HANDLE_t intptr_t
#  define GET_PIPE_ERROR() /* nothing */
# else
#  include <Process.h>
#  include <fcntl.h>
#  define PIPE_FUNC(pa, flags) MSC_IZE(pipe)(pa)
#  define PIPE_HANDLE_t int
#  define _EXTRA_PIPE_ARGS , 256, _O_BINARY
#  define GET_PIPE_ERROR() get_posix_error()
# endif
#else
# define _EXTRA_PIPE_ARGS
# ifdef RKTIO_HAS_CLOEXEC
#  define PIPE_FUNC(pa, flags) pipe_cloexec(pa, flags, rktio)
#  define GET_PIPE_ERROR() /* nothing */
# else
#  define PIPE_FUNC(pa, flags) MSC_IZE(pipe)(pa)
#  define GET_PIPE_ERROR() get_posix_error()
# endif
# define PIPE_HANDLE_t int
#endif

#ifdef RKTIO_HAS_CLOEXEC
static int pipe_cloexec(PIPE_HANDLE_t *la, int flags, rktio_t *rktio)
{
  int retval;

# if defined(__linux__)
  if ((flags & RKTIO_NO_INHERIT_INPUT) && (flags & RKTIO_NO_INHERIT_OUTPUT)) {
    /* simpler: create the pipe atomically with O_CLOEXEC on both ends */
    if (pipe2(la, O_CLOEXEC)) {
      get_posix_error();
      return 1;
    } else
      return 0;
  }
# endif

  if (flags & (RKTIO_NO_INHERIT_INPUT | RKTIO_NO_INHERIT_OUTPUT))
    rktio_cloexec_lock();

  if (pipe(la)) {
    get_posix_error();
    retval = 1;
  } else {
    if (flags & RKTIO_NO_INHERIT_INPUT)
      rktio_fd_cloexec(la[0]);
    if (flags & RKTIO_NO_INHERIT_OUTPUT)
      rktio_fd_cloexec(la[1]);
    retval = 0;
  }

  if (flags & (RKTIO_NO_INHERIT_INPUT | RKTIO_NO_INHERIT_OUTPUT))
    rktio_cloexec_unlock();

  return retval;
}
#endif

/* Internal variant for use by rktio_process: */
int rktio_make_os_pipe(rktio_t *rktio, intptr_t *a, int flags)
{
  PIPE_HANDLE_t la[2];

  if (PIPE_FUNC(la, flags _EXTRA_PIPE_ARGS)) {
    GET_PIPE_ERROR();
    return 1;
  }
  a[0] = la[0];
  a[1] = la[1];
  return 0;
}

rktio_fd_t **rktio_make_pipe(rktio_t *rktio, int flags)
{
  intptr_t a[2];
  rktio_fd_t **rfds;
  
  if (rktio_make_os_pipe(rktio, a, flags))
    return NULL;

  rfds = malloc(sizeof(rktio_fd_t*) * 2);

  rfds[0] = rktio_system_fd(rktio, a[0], RKTIO_OPEN_READ | RKTIO_OPEN_NOT_REGFILE);
  rfds[1] = rktio_system_fd(rktio, a[1], RKTIO_OPEN_WRITE | RKTIO_OPEN_NOT_REGFILE);

  return rfds;
}
