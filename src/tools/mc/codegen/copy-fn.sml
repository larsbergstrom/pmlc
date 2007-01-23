(* copy-fn.sml
 * 
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Functions for copying pseudo registers.
 *)

functor CopyFn (
	structure MTy : MLRISC_TYPES
	structure Spec : TARGET_SPEC
	structure Cells : CELLS
) : COPY = struct

  structure MTy = MTy
  structure T = MTy.T

  val ty = Spec.wordSzB * 8

  fun parallelCopy (vs1, vs2) = T.COPY (ty, vs1, vs2)
  fun copyExpr (v, e) = T.MV (ty, v, e)

  fun parallelFCopy (vs1, vs2) = T.FCOPY (ty, vs1, vs2)
  fun copyFExpr (v, e) = T.FMV (ty, v, e)

  fun copy {src, dst} =
      let (* FIXME *)
	  fun mkCopies (MTy.GPReg (_, v1), MTy.GPR (_, v2), 
			(regs, exprs, fregs, fexprs)) =
	      ( (v1,v2) :: regs, exprs, fregs, fexprs)
	    | mkCopies (MTy.GPReg (_, v1), MTy.EXP (_, e), 
			(regs, exprs, fregs, fexprs)) =
	      (regs, (v1,e) :: exprs, fregs, fexprs)
	    | mkCopies (MTy.FPReg (_, v1), MTy.FPR (_, v2), 
			(regs, exprs, fregs, fexprs)) =
	      ( regs, exprs, (v1,v2) :: fregs, fexprs)
	    | mkCopies (MTy.FPReg (_, v1), MTy.FEXP (_, e), 
			(regs, exprs, fregs, fexprs)) =
	      (regs, exprs, fregs, (v1,e) :: fexprs)
	    | mkCopies (_, _, x) = x
	  val (regs, exprs, fregs, fexprs) = 
	      ListPair.foldl mkCopies ([], [], [], []) (dst, src)
	  val cexps = map copyExpr exprs @ map copyFExpr fexprs
      in
	  parallelCopy (ListPair.unzip regs) :: 
	  parallelFCopy (ListPair.unzip fregs) :: cexps
      end (* copy *)

  fun fresh regs = raise Fail ""

end (* CopyFn *)
