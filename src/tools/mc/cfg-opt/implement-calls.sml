(* implement-calls.sml
 *
 * COPYRIGHT (c) 2007 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Implement calling conventions.
 *)

structure ImplementCalls : 
   sig
      val transform : CFG.module -> CFG.module
   end = 
struct

   structure Label = CFG.Label
   structure Var = CFG.Var

   fun transform (m as CFG.MODULE{name, externs, code}) =
      let
         fun transTyArgs (args : CFGTy.ty list) : CFGTy.ty =
            case args of
               [] => CFGTy.unitTy
             | [arg] => 
                  (case arg of
                      CFGTy.T_Raw rt => CFGTy.T_Wrap rt
                    | _ => arg)
             | args => CFGTy.T_Tuple (false, List.map transTy args)
         and transTy (ty : CFGTy.ty) : CFGTy.ty =
            case ty of
               CFGTy.T_Any => CFGTy.T_Any
             | CFGTy.T_Enum w => CFGTy.T_Enum w
             | CFGTy.T_Raw rt => CFGTy.T_Raw rt
             | CFGTy.T_Wrap rt => CFGTy.T_Wrap rt
             | CFGTy.T_Tuple (m, tys) => CFGTy.T_Tuple (m, List.map transTy tys)
             | CFGTy.T_OpenTuple tys => CFGTy.T_OpenTuple (List.map transTy tys)
             | CFGTy.T_Addr ty => CFGTy.T_Addr (transTy ty)
             | CFGTy.T_CFun cp => CFGTy.T_CFun cp
             | CFGTy.T_VProc => CFGTy.T_VProc
             | CFGTy.T_StdFun {clos, args, ret, exh} =>
                  CFGTy.T_StdFun {clos = transTy clos, args = [transTyArgs args],
                                  ret = transTy ret, exh = transTy exh}
             | CFGTy.T_StdCont {clos, args} =>
                  CFGTy.T_StdCont {clos = transTy clos, args = [transTyArgs args]}
             | CFGTy.T_Code tys => CFGTy.T_Code (List.map transTy tys)

         local
            val {getFn, peekFn, setFn, clrFn, ...} = 
               Var.newProp (fn v => let
                                       val oldTy = Var.typeOf v
                                       val newTy = transTy oldTy
                                    in
                                       Var.setType (v, newTy);
                                       {oldTy = oldTy,
                                        newTy = newTy}
                                    end)
         in
            val getVarOldType = #oldTy o getFn
            val getVarNewType = #newTy o getFn
            val updVarType = ignore o getFn
         end
         local
            val {getFn, peekFn, setFn, clrFn, ...} = 
               Label.newProp (fn l => let
                                         val oldTy = Label.typeOf l
                                         val newTy = transTy oldTy
                                      in
                                         Label.setType (l, newTy);
                                         {oldTy = oldTy,
                                          newTy = newTy}
                                      end)
         in
            val getLabelOldType = #oldTy o getFn
            val getLabelNewType = #newTy o getFn
            val updLabelType = ignore o getFn
         end

         fun transFormalArgs (args : CFG.var list) : (CFG.var * CFG.exp list) =
            case args of
               [] => 
                  let
                     val newArgTy = CFGTy.unitTy
                     val newArg = CFG.Var.new ("argFormalUnit", newArgTy)
                  in
                     (newArg, [])
                  end
             | [arg] => 
                  (case getVarOldType arg of
                      CFGTy.T_Raw rt => 
                         let
                            val newArgTy = CFGTy.T_Wrap rt
                            val newArg = CFG.Var.new ("argFormalWrap", newArgTy)
                         in 
                            (newArg, [CFG.mkUnwrap(arg,newArg)])
                         end 
                    | _ => (arg, []))
             | args => 
                  let
                     val newArgTy = CFGTy.T_Tuple (false, List.map getVarNewType args)
                     val newArg = CFG.Var.new ("argFormalTuple", newArgTy)
                     val (_, sels) =
                        List.foldl
                        (fn (arg, (i, sels)) => 
                         (i + 1, (CFG.mkSelect (arg, i, newArg)) :: sels))
                        (0, [])
                        args
                  in
                     (newArg, List.rev sels)
                  end
         fun transConvention (c : CFG.convention) : (CFG.convention * CFG.exp list) =
            (List.app updVarType (CFG.paramsOfConv c);
             case c of
                CFG.StdFunc {clos, args, ret, exh} =>
                   let
                      val (arg, binds) = transFormalArgs args
                   in
                      (CFG.StdFunc {clos = clos, args = [arg], ret = ret, exh = exh}, 
                       binds)
                   end
              | CFG.StdCont {clos, args} =>
                   let
                      val (arg, binds) = transFormalArgs args
                   in
                      (CFG.StdCont {clos = clos, args = [arg]}, 
                       binds)
                   end
              | _ => (c, []))
         fun transExp (exp : CFG.exp) : CFG.exp =
            (List.app updVarType (CFG.lhsOfExp exp);
             case exp of
                CFG.E_Cast (x, ty, y) => CFG.mkCast (x, transTy ty, y)
              | _ => exp)
         fun transActualArgs (args : CFG.var list) : (CFG.exp list * CFG.var) =
            case args of
               [] => 
                  let
                     val newArgTy = CFGTy.unitTy
                     val newArg = CFG.Var.new ("argActualUnit", newArgTy)
                  in
                     ([CFG.mkConst (newArg, Literal.unitLit)], newArg)
                  end
             | [arg] => 
                  (case getVarOldType arg of
                      CFGTy.T_Raw rt => 
                         let
                            val newArgTy = CFGTy.T_Wrap rt
                            val newArg = CFG.Var.new ("argActualWrap", newArgTy)
                         in 
                            ([CFG.mkWrap(newArg, arg)], newArg)
                         end 
                    | _ => ([], arg))
             | args => 
                  let
                     val newArgTy = CFGTy.T_Tuple (false, List.map getVarNewType args)
                     val newArg = CFG.Var.new ("argActualTuple", newArgTy)
                  in
                     ([CFG.mkAlloc (newArg, args)], newArg)
                  end
         fun transTransfer (t : CFG.transfer) : (CFG.exp list * CFG.transfer) =
            case t of
               CFG.StdApply {f, clos, args, ret, exh} => 
                  let
                     val (binds, arg) = transActualArgs args
                  in
                     (binds, CFG.StdApply {f = f, clos = clos, args = [arg], ret = ret, exh = exh})
                  end
             | CFG.StdThrow {k, clos, args} => 
                  let
                     val (binds, arg) = transActualArgs args
                  in
                     (binds, CFG.StdThrow {k = k, clos = clos, args = [arg]})
                  end
             | _ => ([], t)
         fun transFunc (CFG.FUNC {lab, entry, body, exit} : CFG.func) : CFG.func =
            let
               val () = updLabelType lab
               val (entry, entryBinds) = transConvention entry
               val body = List.map transExp body
               val (exitBinds, exit) = transTransfer exit
            in
               CFG.mkFunc (lab, entry, entryBinds @ body @ exitBinds, exit)
            end
         val module = CFG.mkModule (name, externs, List.map transFunc code)
      in
         module
      end
   
   val transform =
      BasicControl.mkKeepPassSimple
      {output = PrintCFG.output {types=true},
       ext = "cfg",
       passName = "implementCalls",
       pass = transform,
       registry = CFGOptControls.registry}
      
end