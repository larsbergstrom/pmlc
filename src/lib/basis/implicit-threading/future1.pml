(* future1.pml
 *
 * COPYRIGHT (c) 2008 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Runtime support for futures where at most one fiber can perform a touch operation.
 *)

(* state values *)
#define EMPTY_F  $0
#define STOLEN_F $1
#define EVAL_F   $2

(* offsets *)
#define STATE_OFF            0
#define THUNK_OFF            1
#define CANCELABLE_OFF       2
#define FGS_OFF              3

structure Future1 : FUTURE = 
  struct

    structure PT = PrimTypes
    structure FLS = FiberLocalStorage
    structure C = Cancelation
    structure LQ = LockedQueue
    structure O = Option

    type thunk = unit -> 'a
    _primcode ( typedef thunk = fun (PT.unit / PT.exh -> any); )

    _primcode (

      typedef future = ![
		   any,                    (* a state word, with one of the following values *)
		   thunk,                  (* a thunk word *)
		   C.cancelable,           (* cancelable *)
		   FLS.fls                 (* fiber-local storage for the future (tracks parent->child relationships) *)
               ];

    (* possible values for the state word
     *          EMPTY_F
     *          STOLEN_F
     *          EVAL_F
     *          FULL      value
     *          WAITING   cont
     *)
    (* get a handle on the ready queue *)
      define @get-ready-queue ( / exh : PT.exh) : LockedQueue.queue =
        let readyQ : any = ThreadCapabilities.@get-from-fls(tag(future1GangSched) / exh)
	return((LockedQueue.queue)readyQ)
      ;

    (* evaluate a future's thunk and store the result *)
      define @eval (fut : future / exh : PT.exh) : any =
	let f : thunk = SELECT(THUNK_OFF, fut)
       (* clear the thunk pointer to avoid a space leak *)
	do UPDATE(THUNK_OFF, fut, (thunk) $0)
	let result : any = apply f (UNIT / exh)
        let result : any = promote(result)
	return(result)
      ;

    (* steal a future, evaluate it, and store the result *)
      define @steal (fut : future / exh : PT.exh) : () =
	let tmp : any = CAS (&STATE_OFF(fut), EMPTY_F, STOLEN_F)
	if Equal (tmp, EMPTY_F) 
	   then let result : any = @eval(fut / exh)
		let tmpX : any = CAS(&STATE_OFF(fut), STOLEN_F, result)
		if Equal (tmpX, STOLEN_F)
		   then return ()
		   else (* unblock the future *)
			do UPDATE(STATE_OFF, fut, result)
			let k : PT.fiber = (PT.fiber) tmpX
                        let readyQ : LockedQueue.queue = @get-ready-queue(/ exh)
(* FIXME: re-wrap for cancelation *)
                        LockedQueue.@enqueue(readyQ, k / exh)
	    else (* future cell is already full *)
		 return ()
      ;

    (* takes a ready queue and the host vproc and returns an instance of the scheduler. the ready queue
     * contains _fibers_ that, when invoked, evaluate futures. we chose this representation to support
     * our unified cancelation mechanism.
     *)
      define @gang-sched (readyQ : LockedQueue.queue, self : vproc / exh : PT.exh) : PT.sched_act =
	cont switch (s : PT.signal) =
	(* sanity check *)
	  do assert(Equal(self, host_vproc))

	cont run (k : PT.fiber) =
	  do SchedulerAction.@run(self, switch, k / exh)
	  do assert(PT.false)
	  throw switch(PT.STOP)

	(* get the next available future *)
	  cont dispatch () =
	      let k : Option.option = LockedQueue.@dequeue(readyQ / exh)
	      case k
	       of O.NONE =>
		(* nothing on the queue; so, we yield *)
		  let _ : PT.unit = Control.@atomic-yield(/exh)
		  throw dispatch()
		| O.SOME(k : PT.fiber) =>
		  throw run(k)
	      end
	(* handle signals *)
	  case s
	   of PT.STOP => 
	      throw dispatch()
	    | PT.PREEMPT(k : PT.fiber) =>
	    (* mugging policy: other workers can steal k *)
	    (* QUESTION: does this policy work well for a shared FIFO queue? *)
	      do LockedQueue.@enqueue(readyQ, k / exh)
	      let _ : PT.unit = Control.@atomic-yield(/exh)
	      throw dispatch()
	    | _ => 
	      let e : exn = Match
     	      throw exh(e)
	  end
	return(switch)                
      ;

    (* initialize the gang scheduler on each vproc *)
      define @init-gang-sched ( / exh : PT.exh) : LockedQueue.queue =
	  let fls : FLS.fls = FLS.@get()
	(* create the ready queue *)
	  let readyQ : LockedQueue.queue = LockedQueue.@new(/exh)
	  let vps : List.list = SchedulerUtils.@all-vprocs()
	  fun mkAct (self : vproc / exh : PT.exh) : PT.sched_act =
		@gang-sched(readyQ, self / exh)
	  do SchedulerUtils.@scheduler-startup(mkAct, fls, vps / exh)
	  return(readyQ)
      ;

      define @touch (fut : future / exh : PT.exh) : any =
        let tmp : any = CAS (&0(fut), EMPTY_F, EVAL_F)
        if Equal (tmp, EMPTY_F)
           then (* the future is ready for evaluation *)
             let result : any = @eval(fut / exh)
             let result : any = promote (result)
             do UPDATE(STATE_OFF, fut, result)
             return (result)
	else if Equal (tmp, STOLEN_F)
           then (* another fiber is evaluating the future; we need to block *)
                cont kLocal (_ : PT.unit) = 
                    (* resume the future *)
		     return (SELECT(STATE_OFF, fut))
                let kLocal : PT.fiber = (PT.fiber)kLocal
              (* re-wrap the fiber for cancelation *)
                let kLocal : PT.fiber = C.@wrap(SELECT(CANCELABLE_OFF, fut), kLocal / exh)
                let k : PT.fiber = promote (kLocal)
   	        let tmpX : any = CAS (&STATE_OFF(fut), STOLEN_F, k)
 	        if Equal (tmpX, STOLEN_F)
	           then (* transfer control to the futures scheduler *)
                        SchedulerAction.@stop ()
	          else (* the future value is ready *)
                       return (tmpX)
        else (* the future value is ready *)	       
            return (tmp)
      ;

    (* takes a future and the ready queue and returns a fiber that, when invoked, makes the future manifest *)
      define @future-to-fiber (fut : future / exh : PT.exh) : PT.fiber =
	fun f (x : PT.unit / exh : PT.exh) : PT.unit =
	    do @steal(fut / exh)
	    return(UNIT)
	let k : PT.fiber = Control.@fiber(f / exh)
     (* make the future cancelable *)
        let k : PT.fiber = C.@wrap(SELECT(CANCELABLE_OFF, fut), k / exh)
	return(k)
      ;

    (* spawn a future *)
      define @future (thunk : thunk / exh : PT.exh) : future =
        let readyQ : LockedQueue.queue = @get-ready-queue(/ exh)
        let c : C.cancelable = C.@new(tag(future1Cancelation) / exh)
        let fls : FLS.fls = FLS.@get()
        let fut : future = alloc(EMPTY_F, thunk, c, fls)
        let fut : future = promote(fut)
        let stealableK : PT.fiber = @future-to-fiber(fut / exh)
        do LockedQueue.@enqueue(readyQ, stealableK / exh)
        return(fut)
      ;

    (* cancel a future and all of its descendants *)
      define @cancel (fut : future / exh : PT.exh) : PT.unit =
        do C.@cancel(SELECT(CANCELABLE_OFF, fut) / exh)
	return(UNIT)
      ;

    )

    type 'a future = _prim (future)

    val touch : 'a future -> 'a = _prim(@touch)
    val future : 'a thunk -> 'a future = _prim(@future)
    val cancel : 'a future -> unit = _prim(@cancel)

  end (* Future1 *)