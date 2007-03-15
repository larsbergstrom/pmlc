(* free-vars.sml
 *
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *)

structure FreeVars : sig

    val analyze : CPS.module -> unit

  (* return the free variables of a function or continuation variable *)
    val envOfFun : CPS.var -> CPS.Var.Set.set

  (* return the free variables of an expression.  This function should only be
   * called after analyze has been called.
   *)
    val freeVarsOfExp : CPS.exp -> CPS.Var.Set.set

  end = struct

    structure V = CPS.Var

    val {getFn = getFV, setFn = setFV, ...} = V.newProp (fn _ => V.Set.empty)

    fun remove (s, x) = V.Set.delete (s, x) handle _ => s
    fun removes (s, xs) = List.foldl (fn (x, s) => remove (s, x)) s xs

  (* extend a set of free variables by the variables in a RHS *)
    fun fvOfRHS (fv, CPS.Var xs) = V.Set.addList(fv, xs)
      | fvOfRHS (fv, CPS.Enum _) = fv
      | fvOfRHS (fv, CPS.Cast(_, y)) = V.Set.add(fv, y)
      | fvOfRHS (fv, CPS.Literal _) = fv
      | fvOfRHS (fv, CPS.Select(_, x)) = V.Set.add(fv, x)
      | fvOfRHS (fv, CPS.Alloc xs) = V.Set.addList(fv, xs)
      | fvOfRHS (fv, CPS.Wrap x) = V.Set.add(fv, x)
      | fvOfRHS (fv, CPS.Unwrap x) = V.Set.add(fv, x)
      | fvOfRHS (fv, CPS.Prim p) = V.Set.addList(fv, PrimUtil.varsOf p)
      | fvOfRHS (fv, CPS.CCall(f, args)) = V.Set.addList(fv, f::args)

    fun analExp (fv, e) = (case e
	   of CPS.Let(xs, rhs, e) => removes(analExp (fvOfRHS (fv, rhs), e), xs)
	    | CPS.Fun(fbs, e) => let
	      (* first, compute the union of the free variables of the lambdas *)
		fun f (fb, fv) = V.Set.union(analFB fb, fv)
		val fbEnv = List.foldl f V.Set.empty fbs
	      (* then remove the function names from the free variable set *)
		fun g ((f, _, _), fv) = remove(fv, f)
		val fbEnv = List.foldl g fbEnv fbs
		in
		(* record the environment for the lambdas *)
		  List.app (fn fb => setFV (#1 fb, fbEnv)) fbs;
		(* also remove the function names from the free variables of e *)
		  List.foldl g (analExp (V.Set.union(fv, fbEnv), e)) fbs
		end
	    | CPS.Cont(fb, e) => let
		val fbEnv = analFB fb
		in
		  setFV (#1 fb, fbEnv);
		  remove (analExp (V.Set.union (fv, fbEnv), e), #1 fb)
		end
	    | CPS.If(x, e1, e2) => analExp (analExp (V.Set.add (fv, x), e1), e2)
	    | CPS.Switch(x, cases, dflt) => 
                List.foldl (fn ((_,e), fv) => analExp (fv, e))
                           (let
                               val fv = V.Set.add (fv, x)
                            in 
                               case dflt of
                                  SOME e => analExp (fv, e)
                                | NONE => fv
                            end)
                           cases
	    | CPS.Apply(f, args) => V.Set.addList(fv, f::args)
	    | CPS.Throw(k, args) => V.Set.addList(fv, k::args)
	    | CPS.Run{act, fiber} => V.Set.addList(fv, [act, fiber])
	    | CPS.Forward sign => V.Set.add(fv, sign)
	  (* end case *))

  (* compute the free variables of a lambda; the resulting set may include
   * the lambda's name.
   *)
    and analFB (f, params, body) = V.Set.difference (
	  analExp (V.Set.empty, body),
	  V.Set.addList(V.Set.empty, params))

    fun analyze (CPS.MODULE lambda) = if V.Set.isEmpty(analFB lambda)
	  then ()
	  else raise Fail "non-closed module"

    fun envOfFun f = let
	  val fv = getFV f
	  in
(*DEBUG*)print(concat["FV(", V.toString f, ") = {"]);
(*DEBUG*)V.Set.foldl
(*DEBUG*)    (fn (x, false) => (print("," ^ V.toString x); false)
(*DEBUG*)      | (x, true) => (print(V.toString x); false)
(*DEBUG*)    ) true fv;
(*DEBUG*)print "}\n";
	    fv
	  end

    fun freeVarsOfExp exp = let
	  fun analFB (f, _, _) = getFV f
	  fun analExp (fv, e) = (case e
		 of CPS.Let(xs, rhs, e) => removes(analExp (fvOfRHS (fv, rhs), e), xs)
		  | CPS.Fun(fbs, e) => let
		    (* first add the free variables of the lambdas to fv *)
		      fun f (fb, fv) = V.Set.union(analFB fb, fv)
		      val fv = List.foldl f fv fbs
		      in
		      (* remove the function names from the free variables of e *)
			List.foldl (fn (fb, fv) => remove(fv, #1 fb)) (analExp (fv, e)) fbs
		      end
		  | CPS.Cont(fb, e) =>
		      remove (analExp (V.Set.union (fv, analFB fb), e), #1 fb)
		  | CPS.If(x, e1, e2) => analExp (analExp (V.Set.add (fv, x), e1), e2)
		  | CPS.Switch(x, cases, dflt) => 
                      List.foldl (fn ((_,e), fv) => analExp (fv, e))
                                 (let
                                     val fv = V.Set.add (fv, x)
                                  in
                                     case dflt of
                                        SOME e => analExp (fv, e)
                                      | NONE => fv
                                  end)
                                 cases
		  | CPS.Apply(f, args) => V.Set.addList(fv, f::args)
		  | CPS.Throw(k, args) => V.Set.addList(fv, k::args)
		(* end case *))
	  in
	    analExp (V.Set.empty, exp)
	  end

  end
