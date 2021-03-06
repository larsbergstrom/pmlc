(* list.pml
 *
 * COPYRIGHT (c) 2008 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *)


structure List =
  struct

    datatype list = datatype list

    structure PT = PrimTypes

    fun hd xs = (
	  case xs
	   of nil => (raise Fail "List.hd")
	    | x :: xs => x
          (* end case *))

    fun tl xs = (
	  case xs
	   of nil => (raise Fail "List.tl")
	    | x :: xs => xs
          (* end case *))

    fun null xs = (
	  case xs
	   of nil => true
	    | _ => false
          (* end case *))

    fun foldl f id xs = let
	    fun lp (xs, acc) = (
		case xs
                 of nil => acc
		  | x :: xs => lp(xs, f(x, acc))
                 (* end case *))
            in
	       lp(xs, id)
	    end

    fun foldr f id xs = let
	    fun lp (xs, acc) = (
		  case xs
		   of nil => acc
		    | CONS(x, xs) => f(x, lp(xs, acc))
                  (* end case *))
            in
	       lp(xs, id)
	    end

    fun rev xs = foldl CONS nil xs

    fun l2s f ls = (
	  case ls
	   of nil => ""
	    | CONS(x, xs) => f x ^ l2s f xs
          (* end case *))

    fun app f ls = let
	  fun lp xs = (
	        case xs 
		 of nil => ()
		  | CONS(x, xs) => (
		      f x;
		      lp xs)
                (* end case *))
          in
	     lp ls
	  end

    fun length xs = let
	  fun lp (xs, acc) = (
	        case xs
		 of nil => acc
		  | x :: xs => lp(xs, acc+1)
	        (* end case *))
          in
	    lp(xs, 0)
	  end

    fun nth (l, n) = let
	fun loop (es, n) = 
	    if n = 0 then hd es
	    else loop(tl es, n-1)          
         in
            if n >= 0 then loop (l,n) else raise Fail "subscript"
         end

    fun rev ls = let
	fun lp (ls, acc) = (
	    case ls
	     of nil => acc
	      | CONS(x, ls) => lp(ls, CONS(x, acc))
            (* end case *))
        in
	  lp(ls, nil)
	end

    fun map f ls = let
	  fun lp (ls, acc) = (
	      case ls
	       of nil => rev acc
		| CONS(x, ls) => lp(ls, CONS(f x, acc))
              (* end case *))
          in
	    lp(ls, nil)
          end

    fun append (ls1, ls2) = let
	  fun lp ls = (
	      case ls
	       of nil => ls2
		| CONS(x, ls) => CONS(x, lp ls)
 	      (* end case *))
          in
	     lp ls1
	  end

    fun concat xss = foldr append nil xss

    fun all pred xs = let
      fun lp xs =
       (case xs
          of nil => true
	   | h::t => (pred h) andalso (lp t)
         (* end case *))
      in
        lp xs
      end

    fun exists pred xs = let
      fun lp xs = 
       (case xs
	  of nil => false
	   | (h::t) => (pred h) orelse (lp t)
         (* end case *))
      in
        lp xs
      end

    fun zip (xs, ys) = let
      fun lp (xs, ys, acc) =
       (case (xs, ys)
	  of (nil, _) => rev acc
	   | (_, nil) => rev acc
	   | (x::xs, y::ys) => lp (xs, ys, (x,y)::acc)
         (* end case *))
      in
	lp (xs, ys, nil)
      end

    fun unzip xs = let
	fun loop (xs, zs1, zs2) = (case xs
	    of nil => (zs1, zs2)
	     | (x1, x2) :: xs => loop(xs, x1 :: zs1, x2 :: zs2)
	    (* end case *))
	 in
	    loop(rev xs, nil, nil)
	 end

    fun unzip3 xs = let
	fun loop (xs, (zs1, zs2, zs3)) = (case xs
	    of nil => (rev(zs1), rev(zs2), rev(zs3))
	     | (x1, x2, x3) :: xs => loop(xs, (x1 :: zs1, x2 :: zs2, x3 :: zs3))
	    (* end case *))
	 in
	    loop(xs, (nil, nil, nil))
	 end

    fun filter f xs = let
      fun lp arg = 
       (case arg
	  of (nil, acc) => rev acc
	   | (x::xs, acc) => lp (xs, if f x then x::acc else acc)
         (* end case *)) 
      in
        lp (xs, nil)
      end

    fun zipWith (oper, xs, ys) = map oper (zip(xs, ys))

    fun take (l, n) = let
          fun loop (l, n) = (
	        case (l, n)
		 of (l, 0) => nil
		  | (nil, _) => (raise Fail "subscript")
		  | ((x::t), n) => x :: loop (t, n-1)
    	        (* end case *))
          in
            if n >= 0 then loop (l, n) else (raise Fail "subscript")
          end

    fun drop (l, n) = let
          fun loop (l,n) = (
	        case (l, n)
		 of (l, 0) => l
		  | (nil, _) => (raise Fail "subscript")
		  | ((_ :: t), n) => loop(t,n-1)
 	        (* end case *))
          in
            if n >= 0 then loop (l,n) else (raise Fail "subscript")
          end

    fun tabulate (len, genfn) = 
          if len < 0 then raise Fail "size"
          else let
            fun loop n = if n = len then nil
                         else (genfn n)::(loop(n+1))
            in loop 0 end

    fun partition pred l = let
          fun loop (l,trueList,falseList) = 
	      (case l
		of nil => (rev trueList, rev falseList)
		 | h::t =>
                   if pred h then loop(t, h::trueList, falseList)
                   else loop(t, trueList, h::falseList))
          in loop (l,nil,nil) end

    fun last xs = (case xs
      of nil => (raise Fail "empty")
       | x::nil => x
       | x::xs => last xs)

    fun collate cmp = let
          fun loop (xs,ys) = (
                case (xs,ys)
                 of (nil, nil) => EQUAL
                  | (nil, _) => LESS
                  | (_, nil) => GREATER
                  | (x::xs, y::ys) => (case cmp (x,y)
                                        of EQUAL => loop (xs, ys)
                                         | ans => ans))
          in loop end
  end
