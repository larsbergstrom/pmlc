(* seq-sig.sml
 *
 * COPYRIGHT (c) 2008 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Sequences of elements. 
 *)

signature SEQ = 
  sig

    type 'a seq

    val null       : 'a seq -> bool
    val length     : 'a seq -> int
    val empty      : 'a seq
    val singleton  : 'a -> 'a seq
    val sub        : 'a seq * int -> 'a
    val concat     : 'a seq * 'a seq -> 'a seq
    val splitAt    : 'a seq * int -> ('a seq * 'a seq)

    val rev        : 'a seq -> 'a seq
    val map        : ('a -> 'b) * 'a seq -> 'b seq
    val filter     : ('a -> bool) * 'a seq -> 'a seq
    val reduce     : ('a * 'a -> 'a) * 'a * 'a seq -> 'a

    val take       : 'a seq * int -> 'a seq
    val drop       : 'a seq * int -> 'a seq
    val cut        : 'a seq * int -> 'a seq * 'a seq

    val fromList   : 'a list -> 'a seq
    val toList     : 'a seq -> 'a list

  end