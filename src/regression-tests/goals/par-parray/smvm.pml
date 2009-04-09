(* cheating...these names are supposed to be bound already... *)

fun sumP_float a = let
  fun add (x, y) = x + y
  in
    Ropes.reduceP (add, 0.0, a)
  end
val sumP = sumP_float

fun sub (v, i) = Ropes.sub (v, i) (* supposed to be infix ! *)

fun lenP a = Ropes.length a

(* real stuff *)

val itos = Int.toString
val ftos = Float.toString

(*
type vector = float parray
type sparse_vector = (int * float) parray
type sparse_matrix = sparse_vector parray
*)

fun dotp (sv, v) = let
  val thing1 = () (* {?mapP?} mapP (fn (i, x) => x * (v!i)) sv *)
  val thing2 = [| x * sub (v, i) | (i,x) in sv |]
  val it = thing2
  in
    sumP it
  end

val sv0 = [| (0, 1.1), (5, 1.2) |]
val sv1 = [| (1, 1.3) |]
val v0  = [| 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 |]

val dotp0 = dotp (sv0, v0)

val _ = Print.printLn ("Testing dotp: expecting 2.3 => " ^ (ftos dotp0))

fun smvm (sm, v) = [| dotp (row, v) | row in sm |]

val sm0 = [| sv0, sv1 |]

val smvm0 = smvm (sm0, v0)

fun vtos v =
   let val n = lenP v
       fun build (m, acc) =
         if (m >= n) then
           acc
         else if (m = (n - 1)) then 
           build (m+1, acc ^ (ftos (sub (v, m))))
	 else
	   build (m+1, acc ^ (ftos (sub (v, m))) ^ ",")
   in
     "[|" ^ (build (0, "")) ^ "|]"
   end

val _ = Print.printLn ("smvm0 => " ^ (vtos smvm0))

val _ = Print.printLn "Done."

