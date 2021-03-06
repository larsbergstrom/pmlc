(* translate.sml
 *
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *)

structure Translate : sig

    val translate : (TranslateEnv.env * AST.exp) -> BOM.module

  end = struct

    structure A = AST
    structure V = Var
    structure B = BOM
    structure BV = B.Var
    structure BTy = BOMTy
    structure Lit = Literal
    structure E = TranslateEnv
    structure PTVar = ProgramParseTree.Var

    structure LambdaSet = RedBlackSetFn (
      struct
	type ord_key = B.lambda
	fun compare (B.FB{f, ...}, B.FB{f=g, ...}) = BV.compare (f, g)
      end)

    local
	val rewrites = ref ([] : Rewrites.rewrite list)
    in
    fun addRewrites rs = rewrites := rs @ (!rewrites)
    fun listRewrites () = let
          val rewrites' = !rewrites
          in
	    rewrites := [];
	    rewrites'
          end
    end

    val ropeMapSet = ref(LambdaSet.empty)

    val trTy = TranslateTypes.tr

    val rawIntTy = BTy.T_Raw BTy.T_Int
    fun rawInt(n) = B.E_Const(Literal.Int(IntInf.fromInt n), rawIntTy)

    fun findCFun name = (case E.findBOMCFun name
            of NONE => raise Fail(concat["Unknown C function ", PTVar.toString name])
	     | SOME(cf as CFunctions.CFun{var, ...}) => var
            (* end case *))

  (* prune out overload nodes.
   * NOTE: we should probably have a pass that does this before
   * AST optimization.
   *)
    fun prune (AST.OverloadExp(ref(AST.Instance x))) = AST.VarExp(x, [])
      | prune (AST.OverloadExp _) = raise Fail "unresolved overloading"
      | prune e = e

  (* translate a binding occurrence of an AST variable to a BOM variable *)
    fun trVar (env, x) = let
	  val x' = BV.new(V.nameOf x, TranslateTypes.trScheme(env, V.typeOf x))
	  in
	    (x', E.insertVar(env, x, x'))
	  end

    local
      fun mkCasts (x::xs, ty::tys) = let
	    val (xs', casts) = mkCasts (xs, tys)
	    in
	      if BOMTyUtil.match (ty, BV.typeOf x)
		then (x::xs', casts)
		else let
		  val x' = BV.new("_t", ty)
		  in
		    (x'::xs', ([x], B.E_Cast(BV.typeOf x, x'))::casts)
		  end
	    end
	| mkCasts ([], []) = ([], [])
	| mkCasts ([], _::_) = raise Fail "rhs/lhs arity mismatch, more lhs than rhs"
	| mkCasts (xs, []) = raise Fail "rhs/lhs arity mismatch, more rhs than lhs" 
    in
    fun mkStmt (lhs, rhs, e) = let
	  val (xs, casts) = mkCasts (lhs, BOMUtil.typeOfRHS rhs)
	  in
	    B.mkStmts ((xs, rhs)::casts, e)
	  end

    fun mkLet (lhs, rhs, e) = let
	  val (xs, casts) = mkCasts (lhs, BOMUtil.typeOfExp rhs)
	  in
	    B.mkLet (xs, rhs, B.mkStmts(casts, e))
	  end
    end (* local *)

  (* the yield of translating an AST expression *)
    datatype bom_code
      = BIND of (B.var list * B.rhs)
      | EXP of B.exp

    fun toExp (BIND(xs, rhs)) = mkStmt(xs, rhs, B.mkRet xs)
      | toExp (EXP e) = e

  (* translate datatype constructors and constants in expressions *)
    fun trDConExp (env, dc) : bom_code = (case TranslateTypes.trDataCon(env, dc)
	   of E.Const dc' => let
		val t = BV.new("con_" ^ DataCon.nameOf dc, BOMTyCon.dconResTy dc')
		in
		  BIND([t], B.E_DCon(dc', []))
		end
	    | E.ExnConst dc' => let
		val t = BV.new("exn_" ^ DataCon.nameOf dc, BTy.exnTy)
		in
		  BIND([t], B.E_DCon(dc', []))
		end
	    | E.DCon(dc', repTr) => let
		val (exh, env) = E.newHandler env
		val dataTy = BOMTyCon.dconResTy dc'
		val (fb as B.FB{f, ...}) = (case BOMTyCon.dconArgTy dc'
		       of [ty] => let
			  (* constructor with a single argument *)
			    val [srcTy] = FlattenRep.srcTys repTr
			    val srcArg = BV.new("arg", srcTy)
			    val res = BV.new("data", dataTy)
			    val f = BV.new(BOMTyCon.dconName dc',
				    BTy.T_Fun([srcTy], [BTy.exhTy], [dataTy]))
			    val (binds', [dstArg]) = FlattenRep.flatten (repTr, [srcArg]) 
			    val body = B.mkStmts(
				    binds' @ [([res], B.E_DCon(dc', [dstArg]))],
				    B.mkRet[res])
			    in
			      B.FB{f = f, params = [srcArg], exh = [exh], body = body}
			    end
			| dstTys => let
			  (* constructor with multiple arguments (or zero arguments); the
			   * lambda will take a tuple and deconstruct it to build the data value.
			   *)
			    val srcTys = FlattenRep.srcTys repTr
			    val argTy = BTy.tupleTy srcTys
			    val arg = BV.new("arg", argTy)
			    val (srcArgs, binds) = let
				  fun f (ty, (i, xs, binds)) = let
					val x = BV.new("_t"^Int.toString i, ty)
					val b = ([x], B.E_Select(i, arg))
					in
					  (i+1, x::xs, b::binds)
					end
				  val (_, xs, binds) = List.foldl f (0, [], []) srcTys
				  in
				    (List.rev xs, List.rev binds)
				  end
			    val (binds', dstArgs) = FlattenRep.flatten (repTr, srcArgs)
			    val res = BV.new("data", dataTy)
			    val f = BV.new(BOMTyCon.dconName dc',
				    BTy.T_Fun([argTy], [BTy.exhTy], [dataTy]))
			    in
			      B.FB{
				  f = f, params = [arg], exh = [exh],
				  body = B.mkStmts(
				    binds @ binds' @ [([res], B.E_DCon(dc', dstArgs))],
				    B.mkRet[res])
				}
			    end
		      (* end case *))
		in
		  EXP(B.mkFun([fb], B.mkRet[f]))
		end
	    | E.Lit lit => let
		val t = BV.new("lit_" ^ DataCon.nameOf dc, #2 lit)
		in
		  BIND([t], B.E_Const lit)
		end
	  (* end case *))

    fun trExp (env, exp) : bom_code = (case prune exp
	   of AST.LetExp (AST.PValBind (AST.VarPat x, e1), e2) =>
	        if ExpansionOpts.isEnabled(ExpansionOpts.PVAL[ExpansionOpts.CILK5_WORK_STEALING])
		  then EXP(TranslatePValCilk5.tr{
		      env=env, trVar=trVar, trExp=trExpToV,
		      x=x, e1=e1, e2=e2
		    })
		  else raise Fail "no suitable translation for pval"
	    | AST.LetExp(b, e) =>
		EXP(trBind (env, b, fn env' => trExpToExp(env', e)))
	    | AST.IfExp(e1, e2, e3, ty) =>
		EXP(trExpToV (env, e1, fn x =>
		  BOMUtil.mkBoolCase(x, trExpToExp(env, e2), trExpToExp(env, e3))))
	    | AST.CaseExp(e, rules, ty) =>
		EXP(trExpToV (env, e, fn x => trCase(env, x, rules)))
	    | AST.PCaseExp _ => raise Fail "PCaseExp" (* FIXME *)
	    | AST.HandleExp(e, mc, ty) => let
		val (exn, body) = (case mc
		       of [AST.PatMatch(AST.VarPat exn, e')] => let
			    val (exn', env') = trVar (env, exn)
			    in
			      (exn', trExpToExp(env', e'))
			    end
			| [AST.PatMatch(AST.WildPat _, e')] => let
			    val exn' = BV.new ("exn", BTy.exnTy)
			    in
			      (exn', trExpToExp(env, e'))
			    end
			| _ => raise Fail "non-simple exception handler"
		      (* end case *))
		val (exh, env') = E.newHandler env
		val handler = B.FB{f = exh, params = [exn], exh = [], body = body}
		in
		  EXP(B.mkCont(handler, trExpToExp(env', e)))
		end
	    | AST.RaiseExp(Error.UNKNOWN, e, ty) =>
		EXP(trExpToV (env, e, fn exn => B.mkThrow(E.handlerOf env, [exn])))
	    | AST.RaiseExp(Error.LOC {file, l1, c1, l2, c2}, e, ty) => let
                  fun mkThrow exn =
		      if not(Controls.get BasicControl.debug) then
                         B.mkThrow(E.handlerOf env, [exn])
                      else (let
                                val msg = concat["Exception raised at: ", file, " ", Int.toString l1, ".",
                                                 Int.toString c1, "-", Int.toString l2, ".",
                                                 Int.toString c2]
                                val msgVar = BV.new("exnLocStr", BTy.T_Any)
	                        val self = BV.new("exnLocStr", BTy.T_VProc)
                            in
                                mkStmt ([msgVar], BOM.E_Const(Literal.String (msg), BTy.T_Any),
                                        mkStmt([self], BOM.E_HostVProc,
                                               mkStmt([],
                                                      BOM.E_CCall(findCFun(BasisEnv.getCFunFromBasis ["DebugThrow"]), [self, msgVar]),
                                                      B.mkThrow(E.handlerOf env, [exn]))))
                            end)
              in
		EXP(trExpToV (env, e, mkThrow))
              end
	    | AST.FunExp(x, body, ty) => let
		val ty' = trTy(env, ty)
		val (x', env) = trVar(env, x)
		val f = BV.new("anon", BTy.T_Fun([BV.typeOf x'], [BTy.exhTy], [ty']))
		val (exh, env) = E.newHandler env
		val fb = B.FB{f = f, params = [x'], exh = [exh], body = trExpToExp(env, body)}
		in
		  EXP(B.mkFun([fb], B.mkRet[f]))
		end
	    | AST.ApplyExp(e1, e2, ty) => 
	        EXP(trExpToV (env, e1, fn f =>
		  trExpToV (env, e2, fn arg =>
		    B.mkApply(f, [arg], [E.handlerOf env]))))
	    | AST.VarArityOpExp (oper, i, ty) => trVarArityOp(env, oper, i)
	    | AST.TupleExp[] => let
		val t = BV.new("_unit", BTy.unitTy)
		in
		  BIND([t], B.E_Const(Lit.unitLit, BTy.unitTy))
		end
	    | AST.TupleExp es =>
		EXP(trExpsToVs (env, es, fn xs => let
		  val ty = BTy.T_Tuple(false, List.map BV.typeOf xs)
		  val t = BV.new("_tpl", ty)
		  in
		    B.mkStmt([t], B.E_Alloc(ty, xs), B.mkRet [t])
		  end))
                (*Ranges should already be rewritten in terms of Rope.tabFromToP (see translate-range.sml for details)*)
	    | AST.RangeExp (lo, hi, optStep, ty) => raise Fail "FIXME (range construction)"
(*let
                (* FIXME This assumes int ranges for the time being. *)
                val step = Option.getOpt (optStep, ASTUtil.mkInt(1))
		fun rawIntV name = BV.new (name, rawIntTy)
		val loV = rawIntV "lo"
		val hiV = rawIntV "hi"
		val stepV = rawIntV "step"
		val maxLfSzV = rawIntV "maxLeafSize"
	        in
                  EXP(trExpToV (env, lo, fn loW =>
                      trExpToV (env, hi, fn hiW =>
                      trExpToV (env, step, fn stepW =>
                      B.mkStmt ([loV], B.unwrap(loW),
                      B.mkStmt ([hiV], B.unwrap(hiW),
                      B.mkStmt ([stepV], B.unwrap(stepW),
                      B.mkStmt ([maxLfSzV], rawInt(Rope.maxLeafSize()),
                      B.mkHLOp(HLOpEnv.ropeFromRangeOp, 
			       [loV, hiV, stepV, maxLfSzV],
			       [E.handlerOf env])))))))))
                end
*)
	    | AST.PTupleExp exps => let
		val exps' = List.map (fn e => trExpToExp (env, e)) exps
	        in 
		  EXP(TranslatePTup.tr{supportsExceptions=false, env=env, es=exps'})
	        end
	    | AST.PArrayExp(exps, ty) => raise Fail "unexpected PArrayExp"
	    | AST.PCompExp _ => raise Fail "unexpected PCompExp"
	    | AST.PChoiceExp _ => raise Fail "unexpected PChoiceExp"
	    | AST.SpawnExp e => let
		val (exh, env') = E.newHandler env
		val e' = trExpToExp(env', e)
		val param = BV.new("unused", BTy.unitTy)
		val thd = BV.new("_thd", BTy.T_Fun([BTy.unitTy], [BTy.exhTy], [BTy.unitTy]))
	      (* get the HLOp for thread spawning *)
		val spawnOp = E.findBOMHLOpByPath ["Threads", "local-spawn"]
		in
		  EXP(B.mkFun([B.FB{f=thd, params=[param], exh=[exh], body=e'}],
		    B.mkHLOp(spawnOp, [thd], [E.handlerOf env])))
		end
	    | AST.ConstExp(AST.DConst(dc, tys)) => trDConExp (env, dc)
	    | AST.ConstExp(AST.LConst(lit as Literal.String s, _)) => let
		val t1 = BV.new("_data", BTy.T_Any)
		val t2 = BV.new("_len", TranslateTypes.stringLenBOMTy())
		val t3 = BV.new("_slit", TranslateTypes.stringBOMTy())
		in
		  EXP(BOM.mkStmts([
		      ([t1], BOM.E_Const(Literal.String s, BTy.T_Any)),
		      ([t2], BOM.E_Const(Literal.Int(IntInf.fromInt(size s)), TranslateTypes.stringLenBOMTy())),
		      ([t3], BOM.E_Alloc(TranslateTypes.stringBOMTy(), [t1, t2]))
		    ], BOM.mkRet[t3]))
		end
	    | AST.ConstExp(AST.LConst(lit, ty)) => (case trTy(env, ty)
		 of ty' as BTy.T_Tuple(false, [rty as BTy.T_Raw _]) => let
		      val t1 = BV.new("_lit", rty)
		      val t2 = BV.new("_wlit", ty')
		      in
			EXP(B.mkStmts([
			    ([t1], B.E_Const(lit, rty)),
			    ([t2], B.wrap t1)
			  ], B.mkRet [t2]))
		      end
		  | ty' => let
		      val t = BV.new("_lit", ty')
		      in
			BIND([t], B.E_Const(lit, ty'))
		      end
		(* end case *))
	    | AST.VarExp(x, tys) => EXP(trVtoV(env, x, tys, fn x' => B.mkRet[x']))
	    | AST.SeqExp _ => let
	      (* note: the typechecker puts sequences in right-recursive form *)
		fun tr (AST.SeqExp(e1, e2)) = (
		      case trExp(env, e1)
		       of BIND(lhs, rhs) => B.mkStmt(lhs, rhs, tr e2)                                                          
			| EXP e1' => B.mkLet([BV.new("unused", BTy.T_Any)], e1', tr e2)
		      (* end case *))
		  | tr e = trExpToExp(env, e)
		in
		  EXP(tr exp)
		end
	    | AST.OverloadExp _ => raise Fail "unresolved overloading"
	    | AST.ExpansionOptsExp (opts, e) => 
	        ExpansionOpts.withExpansionOpts(fn () => EXP(trExpToExp(env, e)), opts)
	  (* end case *))

    and trExpToExp (env, exp) = toExp(trExp(env, exp))

    and trVarArityOp (env, oper, n) = (case oper
           of AST.MapP => let
		val mapn as B.FB{f, ...} = RopeMapMaker.gen n
		in
		  ropeMapSet := LambdaSet.add (!ropeMapSet, mapn);
		  EXP(B.mkRet [f])
		end
	  (* end case *))

    and trBind (env, bind, k : TranslateEnv.env -> B.exp) = (case bind
	   of AST.ValBind(AST.TuplePat pats, exp) => let
		val (env', xs) = trVarPats (env, pats)
		fun sel (t, i, x::xs, p::ps) =
		      mkStmt([x], B.E_Select(i, t), sel(t, i+1, xs, ps))
		  | sel (t, _, [], []) = k env'
		in
		  case trExp(env, exp)
		   of BIND([y], rhs) => mkStmt([y], rhs, sel(y, 0, xs, pats))
		    | EXP e => let
			val ty = BTy.tupleTy(List.map BV.typeOf xs)
			val t = BV.new("_tpl", ty)
			in
			  mkLet([t], e, sel(t, 0, xs, pats))
			end
		  (* end case *)
		end
	    | AST.ValBind(AST.VarPat x, exp) => (case trExp(env, exp)
		   of BIND([x'], rhs) =>
			mkStmt([x'], rhs, k(E.insertVar(env, x, x')))
		    | EXP e => let
			val (x', env') = trVar(env, x)
			in
			  mkLet([x'], e, k env')
			end
		(* end case *))
	    | AST.ValBind(AST.WildPat ty, exp) => (case trExp(env, exp)
		   of BIND([x'], rhs) =>
			mkStmt([x'], rhs, k env)
		    | EXP e => let
			val x' = BV.new("_wild_", trTy(env, ty))
			in
			  mkLet([x'], e, k env)
			end
		(* end case *))
	    | AST.ValBind _ => raise Fail "unexpected complex pattern"
	    | AST.PValBind _ => raise Fail "impossible"
	    | AST.FunBind fbs => let
		fun bindFun (AST.FB(f, x, e), (env, fs)) = let
		      val (f', env) = trVar(env, f)
		      in
			(env, (f', x, e) :: fs)
		      end
		val (env, fs) = List.foldr bindFun (env, []) fbs
		fun trFun (f', x, e) = let
		      val (x', env) = trVar(env, x)
		      val (exh', env) = E.newHandler env
		      val e' = trExpToExp (env, e)
		      in
			B.FB{f = f', params = [x'], exh = [exh'], body = e'}
		      end
		in
		  B.mkFun(List.map trFun fs, k env)
		end
	    | AST.PrimVBind (x, rhs) => (
	        case TranslatePrim.cvtRhs (env, x, Var.typeOf x, rhs)
		 of SOME (env', x', e) => mkLet([x'], e, k env')
		  | NONE => k env
		(* end case *))
	    | AST.PrimCodeBind code => let
		val (lambdas, rewrites) = TranslatePrim.cvtCode (env, code)
		fun mk [] = k env
		  | mk (fb::fbs) = B.mkFun([fb], mk fbs)
		in
		  addRewrites rewrites;
		  mk lambdas
		end
	  (* end case *))

  (* translation of the body of a case expression. *) 
    and trCase (env, arg, rules) = let
	(* translation of nullary constructors *)
	  fun trDConst (dc, exp) = (case TranslateTypes.trDataCon(env, dc)
		 of E.Const dc' => (B.P_DCon(dc', []), trExpToExp(env, exp))
		  | E.Lit lit => (B.P_Const lit, trExpToExp(env, exp))
		  | E.ExnConst dc' => (B.P_DCon(dc', nil), trExpToExp(env, exp))
		(* end case *))
	(* translation of a constructor applied to a pattern *)
	  fun trConPat (dc, tyArgs, pat, exp) = let
		val E.DCon(dc', repTr) = TranslateTypes.trDataCon(env, dc)
		fun mkArgs tys = List.map (fn ty => BV.new("_t", ty)) tys
		fun mkTuple (x, tys) = let
		      val args = mkArgs tys
		      in
			(args, ([x], B.E_Alloc(BTy.tupleTy tys, args)))
		      end
		fun finish (env, args, binds) =
		      (B.P_DCon(dc', args), BOM.mkStmts(binds, trExpToExp(env, exp)))
		in
		(* Since the argument pattern might be a single variable, we may need to generate
		 * some glue to agree with the arity of the BOM constructor.
		 *)
		  case (pat, BOMTyCon.dconArgTy dc')
		   of (AST.TuplePat pats, _) => let
			val (env', srcArgs) = trVarPats (env, pats)
			val (dstArgs, binds) = FlattenRep.unflatten(repTr, srcArgs)
			in
			  finish (env', dstArgs, binds)
			end
		    | (AST.VarPat x, [_]) => let
			val (x', env') = trVar(env, x)
			val (dstArgs, binds) = FlattenRep.unflatten(repTr, [x'])
			in
			  finish (env', dstArgs, binds)
			end
		    | (AST.VarPat x, tys) => let
			val (x', env') = trVar(env, x)
			val (srcArgs, alloc) = mkTuple (x', FlattenRep.srcTys repTr)
			val (dstArgs, binds) = FlattenRep.unflatten(repTr, srcArgs)
			in
			  finish (env', dstArgs, binds@[alloc])
			end
		    | (AST.WildPat _, tys) => finish (env, mkArgs tys, [])
		    | _ => raise Fail "expected simple pattern"
		  (* end case *)
		end
	(* translate the type of a literal; if it is wrapped, then replace the wrapped
	 * type with a raw type.
	 *)
	  fun trLitTy ty = (case BV.typeOf arg
		 of BTy.T_Tuple(false, [ty as BTy.T_Raw _]) => ty
		  | ty => ty
		(* end case *))
	  fun trRules ([AST.PatMatch(pat, exp)], cases) = (case pat (* last rule *)
		 of AST.ConPat(dc, tyArgs, pat) =>
		      (trConPat (dc, tyArgs, pat, exp) :: cases, NONE)
		  | AST.TuplePat[] =>
		      ((B.P_Const B.unitConst, trExpToExp (env, exp))::cases, NONE)
		  | AST.TuplePat ps => let
		      val (env, xs) = trVarPats (env, ps)
		      fun bind (_, []) = trExpToExp (env, exp)
			| bind (i, x::xs) = B.mkStmt([x], B.E_Select(i, arg), bind(i+1, xs))
		      in
			(cases, SOME(bind(0, xs)))
		      end
		  | AST.VarPat x =>(* default case: map x to the argument *)
		      (cases, SOME(trExpToExp(E.insertVar(env, x, arg), exp)))
		  | AST.WildPat ty => (* default case *)
		      (cases, SOME(trExpToExp(env, exp)))
		  | AST.ConstPat(AST.DConst(dc, tyArgs)) =>
		      (trDConst (dc, exp)::cases, NONE)
		  | AST.ConstPat(AST.LConst(lit, ty)) =>
		      ((B.P_Const(lit, trLitTy ty), trExpToExp (env, exp))::cases, NONE)
		(* end case *))
	    | trRules (AST.PatMatch(pat, exp)::rules, cases) = let
		val rule' = (case pat
		       of AST.ConPat(dc, tyArgs, p) => trConPat (dc, tyArgs, p, exp)
			| AST.ConstPat(AST.DConst(dc, tyArgs)) => trDConst (dc, exp)
			| AST.ConstPat(AST.LConst(lit, ty)) =>
			    (B.P_Const(lit, trLitTy ty), trExpToExp (env, exp))
			| _ => raise Fail "exhaustive pattern in case"
		      (* end case *))
		in
		  trRules (rules, rule'::cases)
		end
	    | trRules (AST.CondMatch _ :: _, _) = raise Fail "unexpected CondMatch"
	  fun mkCase (arg, (cases, dflt)) = B.mkCase(arg, List.rev cases, dflt)
	  in
	    case BV.typeOf arg
	     of BTy.T_Tuple(false, [ty as BTy.T_Raw rty]) => let
		  val ty = BTy.T_Raw rty
		  val arg' = BV.new("_raw", ty)
		  in
		    B.mkStmt([arg'], B.unwrap arg, mkCase (arg', trRules (rules, [])))
		  end
	      | _ => mkCase (arg, trRules (rules, []))
	    (* end case *)
	  end

    and trVarPats (env, pats) = let
	  fun tr ([], env, xs) = (env, List.rev xs)
	    | tr (AST.VarPat x :: pats, env, xs) = let
		val (x', env') = trVar(env, x)
		in
		  tr (pats, env', x'::xs)
		end
	    | tr (AST.WildPat ty :: pats, env, xs) = let
		val x' = BV.new("_wild_", trTy(env, ty))
		in
		  tr (pats, env, x'::xs)
		end
	    | tr _ = raise Fail "expected VarPat"
	  in
	    tr (pats, env, [])
	  end

  (* translate the expression exp to
   *
   *	let t = exp in cxt[t]
   *)
    and trExpToV (env, AST.VarExp(x, tys), cxt : B.var -> B.exp) =
	  trVtoV (env, x, tys, cxt)
      | trExpToV (env, exp, cxt : B.var -> B.exp) = (case trExp(env, exp)
	   of BIND([x], rhs) => mkStmt([x], rhs, cxt x) (*if rhs is a null exception constructor this breaks*)
	    | EXP e => let
		val t = BV.new ("_t", trTy(env, TypeOf.exp exp))
		in
		  mkLet([t], e, cxt t)
		end
	  (* end case *))

    and trVtoV (env, x, tys, cxt : B.var -> B.exp) = (
	  case E.lookupVar(env, x)
	   of E.Var x' => cxt x' (* pass x' directly to the context *)
	    | E.Lambda mkLambda => let
                val sigma = Var.typeOf x (* actually a type scheme *)
		val rangeTy = (case TypeUtil.prune(TypeUtil.apply(sigma, tys))
		       of A.FunTy (_, r) => r
			| _ => raise Fail (Var.nameOf x^": expected function type is "^TypeUtil.toString(TypeUtil.apply(sigma, tys)))
		      (* end case *))
		val rangeTy' = trTy (env, rangeTy)
		val fb as B.FB{f, ...} = mkLambda rangeTy'
	        in
		  B.mkFun ([fb], cxt f)
                end
                (* let val lambda as B.FB{f, ...} = BOMUtil.copyLambda lambda
		   in B.mkFun([lambda], cxt f) end *)
	    | E.EqOp => let
		val [ty] = tys
		val lambda as B.FB{f, ...} = Equality.mkEqual(env, x, ty)
		in
		  B.mkFun([lambda], cxt f)
		end
	  (* end case *))

  (* translate a list of expressions to a BOM let binding *)
    and trExpsToVs (env, exps, cxt : B.var list -> B.exp) : B.exp = let
	  fun tr ([], xs) = cxt(List.rev xs)
	    | tr (exp::exps, xs) =
		trExpToV (env, exp, fn x => tr(exps, x::xs))
	  in
	    tr (exps, [])
	  end

  (* get the list of imported C functions from the environment *)
    val listImports = AtomTable.listItems o E.getImportEnv

    fun translate (env0, body) = let
          val argTy = BTy.T_Raw RawTypes.T_Int
          val arg = BV.new("_arg", argTy)
	  val (exh, env) = E.newHandler env0
	  val _ = ropeMapSet := LambdaSet.empty
	  val body' = trExpToExp (env, body)
	  val body'' = (case LambdaSet.listItems(!ropeMapSet)
		 of [] => body'
		  | fbs => (
		      ropeMapSet := LambdaSet.empty;
		      B.mkFun(fbs, body'))
		(* end case *))
	  val mainFun = B.FB{
		  f = BV.new("main", BTy.T_Fun([argTy], [BTy.exhTy], [trTy(env, TypeOf.exp body)])),
		  params = [arg],
		  exh = [exh],
		  body = body''
		}
	  val imports = listImports env
	  val hlops = HLOpEnv.listHLOps()
	  val rewrites = listRewrites()
	  val module = B.mkModule(Atom.atom "Main", imports, hlops, rewrites, mainFun)
	  in
	    if (Controls.get TranslateControls.keepEnv)
	      then let
		val outName = (case Controls.get BasicControl.keepPassBaseName
		       of NONE => "translate.env"
			| SOME baseName => concat [
			      baseName, ".", "translate.env"
			    ]
		      (* end case *))
		val outFile = TextIO.openOut outName
		in
		  E.dump (outFile, env);
		  TextIO.closeOut outFile
		end
	      else ();
	    module
	  end

    val translate = BasicControl.mkKeepPass {
	    preOutput = fn (outS, (_, ast)) => PrintAST.outputExp(outS, ast),
	    preExt = "ast",
	    postOutput = PrintBOM.output,
	    postExt = "bom",
	    passName = "translate",
	    pass = translate,
	    registry = TranslateControls.registry
	  }

  end
