/* vproc.c
 *
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 */

#include "manticore-rt.h"
#include <signal.h>
#include <ucontext.h>
#if defined (OPSYS_DARWIN)
#  include <CoreServices/CoreServices.h>	/* for MPProcessors */
#endif
#include "os-memory.h"
#include "os-threads.h"
#include "vproc.h"
#include "heap.h"
#include "gc.h"
#include "options.h"
#include "value.h"

static void *VProcMain (void *_data);
static void SigHandler (int sig, siginfo_t *si, void *_sc);
static int GetNumCPUs ();

static pthread_key_t	VProcInfoKey;

/********** Globals **********/
int			NumHardwareProcs;
int			NumVProcs;
VProc_t			*Procs[MAX_NUM_VPROCS];


/* VProcInit:
 *
 * Initialization for the VProc management system.
 */
void VProcInit (Options_t *opts)
{
    NumHardwareProcs = GetNumCPUs();

  /* get command-line options */
    int nProcs = GetIntOpt (opts, "-p", NumHardwareProcs);
    if ((NumHardwareProcs > 0) && (nProcs > NumHardwareProcs))
	Warning ("%d processors requested on a %d processor machine\n",
	    nProcs, NumHardwareProcs);

    if (pthread_key_create (&VProcInfoKey, 0) != 0) {
	Die ("unable to create VProcInfoKey");
    }

} /* end of VProcInit */


/* VProcCreate:
 *
 * Create the data structures and underlying system thread to
 * implement a vproc.
 */
VProc_t *VProcCreate ()
{
    if (NumVProcs >= MAX_NUM_VPROCS)
	Die ("too many vprocs\n");

  /* allocate the VProc heap; we store the VProc representation in the base
   * of the heap area.
   */
    int nBlocks = 1;
    VProc_t *vproc = (VProc_t *)AllocMemory (&nBlocks, VP_HEAP_SZB);
    if ((vproc == 0) || (nBlocks != 1))
	Die ("unable to allocate vproc heap");

  /* initialize the vproc structure */
    vproc->inManticore = false;
    vproc->atomic = false;
    vproc->sigPending = false;
    vproc->stdArg = M_UNIT;
    vproc->stdEnvPtr = M_UNIT;
    vproc->stdCont = M_UNIT;
    vproc->stdExnCont = M_UNIT;
    vproc->allocBase = (Addr_t)vproc + sizeof(VProc_t);
    vproc->limitPtr = (Addr_t)vproc + VP_HEAP_SZB - ALLOC_BUF_SZB;
    vproc->oldTop = vproc->allocBase;
    SetAllocPtr (vproc);
    MutexInit (&(vproc->lock));
    CondInit (&(vproc->wait));
    vproc->idle = true;

    vproc->id = NumVProcs;
    VProcs[NumVProcs++] = vproc;

    InitVProcHeap (vproc);

  /* start the vproc's pthread */
    ThreadCreate (&(vproc->hostID), VProcMain, vproc);

    return vproc;

} /* VProcCreate */


/*! \brief return a pointer to the VProc that the caller is running on.
 *  \return the VProc that the caller is running on.
 */
VProc_t *VProcSelf ()
{
    return (VProc_t *)pthread_getspecific (VProcInfoKey);

} /* VProcSelf */


/*! \brief send an asynchronous signal to another VProc.
 *  \param vp the target VProc.
 *  \param sig the signal.
 */
void VProcSignal (VProc_t *vp, VPSignal_t sig)
{
    if (sig == GCSignal) pthread_kill (vp->hostID, SIGUSR1);
    else if (sig == PreemptSignal) pthread_kill (vp->hostID, SIGUSR2);
    else Die("bogus signal");

} /* end of VProcSignal */

/*! \brief put an idle vproc to sleep.
 *  \param vp the vproc that is being put to sleep.
 */
void VProcSleep (VProc_t *vp)
{
    assert (vp == VProcSelf());

    MutexLock (&(vp->lock));
	vp->idle = true;
	while (vp->idle) {
	    CondWait (&(vp->wait), &(vp->lock));
	}
    MutexUnlock (&(vp->lock));

}

/* VProcMain:
 */
static void *VProcMain (void *_data)
{
    VProc_t		*self = (VProc_t *)_data;
    struct sigaction	sa;

  /* store a pointer to the VProc info as thread-specific data */
    pthread_setspecific (VProcInfoKey, self);

  /* initialize this pthread's handler. */
    sa.sa_sigaction = SigHandler;
    sa.sa_flags = SA_SIGINFO | SA_RESTART;
    sigfillset (&(sa.sa_mask));
    sigaction (SIGUSR1, &sa, 0);
    sigaction (SIGUSR2, &sa, 0);

/* FIXME: what do we do now?? */

} /* VProcMain */

/* SigHandler:
 *
 * A per-vproc handler for SIGUSR1 and SIGUSR2 signals.
 */
static void SigHandler (int sig, siginfo_t *si, void *_sc)
{
    ucontext_t	*uc = (ucontext_t *)_sc;
    VProc_t	*self = VProcSelf();

    if (! self->inManticore) {
    }
    else if (self->atomic) {
    }
    else {
    }

} /* SignHandler */

static int GetNumCPUs ()
{
#if defined(HAVE_PROC_CPUINFO)
  /* Get the number of hardware processors on systems that have /proc/cpuinfo */
    FILE *cpuinfo = fopen("/proc/cpuinfo", "r");
    char buf[1024];
    if (cpuinfo != NULL) {
	int n = 0;
	while (fgets(sizeof(buf), buf, cpuinfo) != 0) {
	    int id;
	    if (sscanf(buf, "processor : %d", &id) == 1)
		n++;
	}
	fclose (cpuinfo);
	return n;
    }
#elif defined(OPSYS_DARWIN)
    return MPProcessors ();
#else
    return 0;
}
#endif
