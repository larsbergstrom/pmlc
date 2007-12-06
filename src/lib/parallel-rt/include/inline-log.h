/* inline-log.h
 *
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Inline operations for recording log entries.
 */

#ifndef _INLINE_LOG_H_
#define _INLINE_LOG_H_

#ifdef ENABLE_LOGGING
#include "log.h"
#include "atomic-ops.h"
#include "vproc.h"
#ifdef HAVE_MACH_ABSOLUTE_TIME
#  include <mach/mach_time.h>
#endif

// get the pointer to the next log entry
STATIC_INLINE LogEvent_t *NextLogEvent (VProc_t *vp)
{
    LogBuffer_t *buf;

    do {
	buf = vp->log;
	int index = FetchAndInc(&(buf->next));
	if (index < LOGBUF_SZ) {
	    return &(buf->log[index]);
	    break;
	}
	SwapLogBuffers (vp);
    } while (true);

}

STATIC_INLINE void LogTimestamp (LogTS_t *ts)
{
#if HAVE_MACH_ABSOLUTE_TIME
    ts->ts_mach = mach_absolute_time();
#elif HAVE_CLOCK_GETTIME
    clock_gettime (CLOCK_REALTIME, &(ts->ts_timespec));
#else
    gettimeofday (&(ts->ts_timeval), 0);
#endif
}

STATIC_INLINE void LogEvent0 (VProc_t *vp, uint32_t evt)
{
    LogEvent_t *ep = NextLogEvent(vp);

    LogTimestamp (&(ep->timestamp));
    ep->event = evt;

}

STATIC_INLINE void LogEvent1 (VProc_t *vp, uint32_t evt, uint32_t a)
{
    LogEvent_t *ep = NextLogEvent(vp);

    LogTimestamp (&(ep->timestamp));
    ep->event = evt;
    ep->data[0] = a;

}

STATIC_INLINE void LogEvent2 (VProc_t *vp, uint32_t evt, uint32_t a, uint32_t b)
{
    LogEvent_t *ep = NextLogEvent(vp);

    LogTimestamp (&(ep->timestamp));
    ep->event = evt;
    ep->data[0] = a;
    ep->data[1] = b;

}

STATIC_INLINE void LogEvent3 (
    VProc_t *vp, uint32_t evt,
    uint32_t a, uint32_t b, uint32_t c)
{
    LogEvent_t *ep = NextLogEvent(vp);

    LogTimestamp (&(ep->timestamp));
    ep->event = evt;
    ep->data[0] = a;
    ep->data[1] = b;
    ep->data[2] = c;

}

#else /* !ENABLE_LOGGING */

#define LogEvent0(VP, EVT)
#define LogEvent1(VP, EVT, A)
#define LogEvent2(VP, EVT, A, B)
#define LogEvent3(VP, EVT, A, B, C)

#endif
#endif /* !_INLINE_LOG_H_ */
