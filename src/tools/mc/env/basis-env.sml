(* basis-env.sml
 *
 * COPYRIGHT (c) 2008 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * This module provides the AST transfomations access to the environment produced
 * by compiling the basis code.  
 *)

structure BasisEnv : sig

    val saveBasisEnv : BindingEnv.env -> unit

    val getValFromBasis : string list -> ModuleEnv.val_bind
    val getTyFromBasis : string list -> ModuleEnv.ty_def
    val getBOMTyFromBasis : string list -> ProgramParseTree.PML2.BOMParseTree.ty

  end = struct

    structure N = BasisNames
    structure PPT = ProgramParseTree
    structure BEnv = BindingEnv
    structure MEnv = ModuleEnv

    val basis : BindingEnv.env option ref = ref NONE

    fun saveBasisEnv bEnv = (basis := SOME bEnv)

    val pathToString = String.concatWith "."

    fun getModule path = let
	  fun get (bEnv, [x]) = SOME(bEnv, Atom.atom x)
	    | get (bEnv, x::r) = (case BEnv.findMod(bEnv, Atom.atom x)
		 of SOME(_, bEnv) => get (bEnv, r)
		  | NONE => NONE
		(* end case *))
	    | get _ = NONE
	  in
	    case !basis
	     of NONE => raise Fail(concat["getModule(", pathToString path, "): basis not initialized"])
	      | SOME bEnv => get(bEnv, path)
	    (* end case *)
	  end

    fun notFound path = raise Fail ("Unable to locate "^pathToString path)

  (* use a path (or qualified name) to look up a variable, i.e., 
   *      getValFromBasis(Atom.atom "Future1.future") 
   *)
    fun getValFromBasis path = (case getModule path
	   of SOME(bEnv, x) => (case BEnv.findVar(bEnv, x)
		 of SOME(BEnv.Var v) =>  (case ModuleEnv.getValBind v
		       of SOME vb => vb
			| NONE => notFound path
		      (* end case *))
		  | NONE => notFound path
		(* end case *))
	    | _ => notFound path
	  (* end case *))

  (* use a path (or qualified name) to look up a type *)
    fun getTyFromBasis path = (case getModule path
	   of SOME(bEnv, x) => (case BEnv.findVar(bEnv, x)
		 of SOME(BEnv.Var v) =>  (case ModuleEnv.getTyDef v
		       of SOME tyd => tyd
			| NONE => notFound path
		      (* end case *))
		  | NONE => notFound path
		(* end case *))
	    | _ => notFound path
	  (* end case *))

  (* use a path (or qualified name) to look up a BOM type *)
    fun getBOMTyFromBasis path = (case getModule path
	   of SOME(bEnv, x) => (case BEnv.findBOMVar(bEnv, x)
		 of SOME v =>  (case ModuleEnv.getPrimTyDef v
		       of SOME ty => ty
			| NONE => raise Fail(concat[
			      "Unable to locate ", pathToString path, " at ",
			      ProgramParseTree.Var.toString v
			    ])
		      (* end case *))
		  | NONE => notFound path
		(* end case *))
	    | _ => notFound path
	  (* end case *))

  end
