local
(* definitions to match the Manticore basis *)
type double = real
val sqrtd = Math.sqrt
fun fail msg = raise Fail msg
val powd = Math.pow
val itod = real
val dtos = Real.toString
val tand = Math.tan
val gettimeofday = Time.toReal o Time.now
val deq = Real.==

abstype image = IMG of (Word8.word * Word8.word * Word8.word) Array2.array
with
fun newImage (wid, ht) = IMG(Array2.array(ht, wid, (0w0, 0w0, 0w0)))
fun updateImage3d (IMG img, i, j, r, g, b) = let
      fun cvt x = Word8.fromInt(Real.round(x * 255.0))
      in
	Array2.update(img, j, i, (cvt r, cvt g, cvt b))
      end
fun freeImage _ = ()
fun outputImage (IMG img, outFile) = let
      val outS = BinIO.openOut outFile
      fun out x = BinIO.output1(outS, x)
      fun outRGB (r, g, b) = (out r; out g; out b)
      fun pr s = BinIO.output(outS, Byte.stringToBytes s)
      val (h, w) = Array2.dimensions img
      in
        pr "P6\n";
	pr(concat[Int.toString w, " ", Int.toString h, "\n"]);
	pr "255\n";
	Array2.app Array2.RowMajor outRGB img;
	BinIO.closeOut outS
      end
end

val sqrt = sqrtd;
fun expt a = let fun expt' b = powd(a, b) in expt' end;
val pi : double = 3.14159265359;
(*
 *
 * generally handy stuff
 *)
val EPSILON : double = 1.0e~6;
val INFINITY : double = 1.0e20;
fun map f = let
      fun mapf l = (case l of nil => nil | x::xs => f x :: mapf xs)
      in
	mapf
      end;
fun fold f = let
      fun foldf s0 = let
	    fun fold' l = (case l of nil => s0 | x::xs => f (x, foldf s0 xs))
	    in
	      fold'
	    end
      in
	foldf
      end;
fun hd l = (case l
       of nil => fail("expecting a head")
	| x::xs => x);
fun tl l = (case l
       of nil => fail("expecting a tail")
	| x::xs => xs);
(*
 * convenient vector operations
 *)
type vec = (double * double * double);
fun vecadd ((x1,y1,z1) : vec) = let fun add (x2,y2,z2) = (x1+x2, y1+y2, z1+z2) in add end;
fun vecsum (x : vec list) = let
      fun f (a, b) = vecadd a b
      in
	fold f (0.0,0.0,0.0) x
      end;
fun vecsub ((x1,y1,z1) : vec) = let fun sub (x2,y2,z2) = (x1-x2, y1-y2, z1-z2) in sub end;
fun vecmult ((x1,y1,z1) : vec) = let fun mul (x2,y2,z2) = (x1*x2, y1*y2, z1*z2) in mul end;
fun vecnorm ((x,y,z) : vec) = let
      val len = sqrt (x*x + y*y + z*z)
      in ((x/len, y/len, z/len), len) end;
fun vecscale ((x,y,z) : vec) = let fun scale a = (a*x, a*y, a*z) in scale end;
fun vecdot ((x1,y1,z1) : vec) = let fun dot (x2,y2,z2) = x1*x2 + y1*y2 + z1*z2 in dot end;
fun veccross ((x1,y1,z1) : vec) = let fun cross (x2,y2,z2) = (y1*z2-y2*z1, z1*x2-z2*x1, x1*y2-x2*y1) in cross end;
(* Note the following code is broken for negative vectors, but it was in the original
 * version.
 *)
fun zerovector ((x,y,z) : vec) =
      (x < EPSILON andalso y < EPSILON andalso z < EPSILON);

type point = (double * double);
fun pointsub  ((x1,y1): point) = let fun sub (x2,y2) = (x1-x2, y1-y2) in sub end;
fun pointdot ((x1,y1): point) = let fun dot (x2,y2) = x1*x2 + y1*y2 in dot end;
(*
 * type declarations
 *)
datatype Light
  = Directional of (vec * vec)		(* direction, color *)
  | Point of (vec * vec)		(* position, color *)
  ;
fun lightcolor l = (case l
       of (Directional(_, c)) => c
	| (Point(_, c)) => c
      (* end case *));
datatype Surfspec
  = Ambient of vec	(* all but specpow default to zero *)
  | Diffuse of vec
  | Specular of vec
  | Specpow of double	(* default 8. *)
  | Reflect of double
  | Transmit of double
  | Refract of double	(* default 1, like air == no refraction *)
  | Body of vec		(* body color, default 1.,1.,1. *)
  ;
fun ambientsurf surf = (case surf
       of nil => (0.0, 0.0, 0.0)
	| (Ambient v :: ss) => v
	| (_ :: ss) => ambientsurf ss
      (* end case *));
fun diffusesurf surf = (case surf
       of nil => (0.0, 0.0, 0.0)
	| (Diffuse v :: ss) => v
	| (_ :: ss) => diffusesurf ss
      (* end case *));
fun specularsurf surf = (case surf
       of nil => (0.0, 0.0, 0.0)
	| (Specular v :: ss) => v
	| (_ :: ss) => (specularsurf ss)
      (* end case *));
fun specpowsurf surf = (case surf
       of nil => 8.0
	| (Specpow r :: ss) => r
	| (_ :: ss) => specpowsurf ss
      (* end case *));
fun reflectsurf surf = (case surf
       of nil => 0.0
	| (Reflect r :: ss) => r
	| (_ :: ss) => reflectsurf ss
      (* end case *));
fun transmitsurf surf = (case surf
       of nil => 0.0
	| (Transmit r :: ss) => r
	| (_ :: ss) => transmitsurf ss
      (* end case *));
fun refractsurf surf = (case surf
       of nil => 1.0
	| (Refract r :: ss) => r
	| (_ :: ss) => refractsurf ss
      (* end case *));
fun bodysurf surf = (case surf
       of nil => (1.0,1.0,1.0)
	| (Body v :: ss) => v
	| (_ :: ss) => bodysurf ss
      (* end case *));

datatype Prim = 
(*  pos, radius, surface type  *)
Sphere of vec * double * Surfspec list
(* pos ,[(a,b,c),d, vertices], surface type *)
| Polyhedron of (vec * double * (double * double) list) list * Surfspec list
(* pos, skirt radius, height surface type*)
| Hyperboloid of vec * double * double * Surfspec list
(* pos, rmax, [zmin, zmax], thetamax, surface type *)
| Paraboloid of vec * double * (double * double) * double * Surfspec list
(* pos, [majorrad,minorrad], [phimin,phimax], thetamax, surface type *)
| Torus of vec * (double * double) * (double * double) * double * Surfspec list
(* pos, (width, height, depth), surface type *)
| Cuboid of vec * vec * Surfspec list


datatype CSG = 
  prim of Prim
| Union of Prim * CSG
| Intersection of Prim * CSG
| Difference of Prim * CSG


fun polygonX (x,y) = x;
fun polygonY (x,y) = y;

fun pointInPolygon (p : (double * double),g : (double * double) list,b) = if List.length(g) < 2 then b 
  else let val u0 = List.hd g;
           val u1 = List.hd (List.tl g);
        in
          (if (polygonY(p) < polygonY(u1)) andalso (polygonY(u0) <= polygonY(p)) andalso ( (polygonY(p) - polygonY(u0))*(polygonX(u1)-polygonX(u0))  > ( (polygonX(p) - polygonX(u0)) * (polygonY(u1) - polygonY(u0)) )) then pointInPolygon(p,(List.tl(g)), not b)   
           else if (polygonY(p) < polygonY(u0)) andalso ( (polygonY(p) - polygonY(u0))*(polygonX(u1) -polygonX(u0)) <  ((polygonX(p) - polygonX(u0)) * (polygonY(u1) - polygonY(u0))) ) then pointInPolygon(p,(List.tl(g)), not b)  
           else pointInPolygon(p,(List.tl(g)),b)
          )
      end; 

fun project2D (norm : vec) = let val (x0,y0,z0) = norm
                                 val (x,y,z) = (abs(x0),abs(y0),abs(z0)) 
 in (if x >= y andalso x >= z then (fn (a : double,b : double,c : double) => (b,c)) else if y >= x andalso y >= z then (fn (a : double,b : double,c : double) => (a,c)) else (fn (a : double,b : double,c : double) => (a,b)) ) end;

fun implicitPolyhedron (norm : vec,d : double,polygon : (double * double) list, pos : vec,dir : vec) = (let 
    val denom = vecdot norm dir;
    val numer = vecdot norm pos + d;
    val polygonlist = List.last(polygon)::polygon
  in 
    (if (denom < EPSILON) andalso (numer > 0.0) then (false,0.0)
     else (let 
             val t = ~numer / denom;
	     val tFar = if denom > 0.0  andalso t < INFINITY then t else INFINITY;
             val tNear = if denom < 0.0 andalso t > ~INFINITY then t else ~INFINITY;
          in 
            (if (tNear > tFar) then (false,0.0) 
             else  
                  let val f = project2D(norm);          
                      val p = f(vecadd pos (vecscale dir t))
		      val b = pointInPolygon(p,polygonlist,false)
                 in
                   (b,t) 

              end)
           end)
    ) end)



fun polyhedronIntersect (lyst) = let val x = List.hd lyst
                                     val y = List.tl lyst
                                     val f = (fn ((b0, d0), (b1,d1)) => if b0 andalso b1 then (if (d0 < d1 andalso d0 > 0.0) then (true,d0) else (true, d1))
                                                                        else if b0 then (b0,d0)
									else if b1 then (b1,d1)
									else (false,0.0))
                                   in
                                     (List.foldr f x y) end;

fun implicit (pos,dir,obj : CSG) = case obj of
  prim p => (case p of
    Sphere (center,rad,surf) => (let val m = vecsub pos center;  (* x - center *)
    val m2 = vecdot m m;    (* (x-center).(x-center) *)
    val bm = vecdot m dir;  (* (x-center).dir *)
    val disc = bm * bm - m2 + rad * rad;  (* discriminant *)
    in
      if (disc < 0.0) then (false, 0.0)  (* imaginary solns only *)
      else let
	  val slo = ~bm - (sqrt disc);
	  val shi = ~bm + (sqrt disc);
	  in
	  if (slo < 0.0) then  (* pick smallest positive intersection *)
	      if (shi < 0.0) then (false, 0.0)
	      else (true, shi)
	  else (true, slo)
	  end
    end)
  | Polyhedron (poly,surf) =>  polyhedronIntersect (List.map implicitPolyhedron (List.map (fn (x,d,polygon) => (x,d,polygon,pos,dir)) poly))
  | Hyperboloid (center,skirt,height,s)=> (let 
         val (x0,y0,z0) = vecsub pos center
	 val bm = vecdot (x0,y0,z0) dir
	 val (x1,y1,z1) = dir
	 val a = x1*x1 + y1*y1 - z1*z1;
	 val b = x0*x1 + y0*y1 - z0*z1;
	 val c = x0*x0 + y0*y0 - z0*z0;
	 val disc = b*b - 4.0*a*c;
       in
        if (disc < 0.0) then (false,0.0)
        else let 
            val slo = ~bm - (sqrt disc);
	  val shi = ~bm + (sqrt disc);
	  in
	  if (slo < 0.0) then  (* pick smallest positive intersection *)
	      if (shi < 0.0) then (false, 0.0)
	      else (true, shi)
	  else (true, slo)
	  end
    end)
  | Paraboloid (center,rad,(zmin,zmax),t,s) => (let 
         val (x0,y0,z0) = vecsub pos center
         val bm = vecdot (x0,y0,z0) dir
	 val (x1,y1,z1) = dir
	 val a = x1*x1 + y1*y1
	 val b = x0*x1 + y0*y1 + z1
	 val c = x0*x0 + y0*y0 + z0
	 val disc = b*b - 4.0*a*c
        in
        if (disc < 0.0) then (false,0.0)
        else let 
            val slo = ~bm - (sqrt disc);
	  val shi = ~bm + (sqrt disc);
	  in
	  if (slo < 0.0) then  (* pick smallest positive intersection *)
	      if (shi < 0.0) then (false, 0.0)
	      else (true, shi)
	  else (true, slo)
	  end
    end)
  | Torus (p,(majorrad,minorrad),(phimin,phimax),t,s) => (true,0.0)
  | Cuboid (p,(width,height,depth),s) => (true,0.0)
  )
| Union (p,c) => (true,0.0)
| Intersection (p,c) => (true,0.0)
| Difference (p,c) => (true,0.0)


fun Primsurf (p) = (case p of
    Sphere (center,rad,surf) => surf
  | Polyhedron (poly,surf) => surf
  | Hyperboloid (center,skirt,height,s)=> s
  | Paraboloid (center,rad,(zmin,zmax),t,s) => s
  | Torus (p,(majorrad,minorrad),(phimin,phimax),t,s) => s
  | Cuboid (p,(width,height,depth),s) => s
  )

fun CSGsurf (obj) = case obj of prim p => Primsurf(p)
| Union (p,c) => Primsurf(p)
| Intersection (p,c) => Primsurf(p)
| Difference (p,c) => Primsurf(p)


fun greaterThan (x,d0 : double,v) = (fn (y,d1 : double,v) => d0 > d1)
fun eqwal  (x,d0 : double,v) =  (fn (y,d1 : double,v) => deq (d0,d1))
fun lessThan (x,d0 : double,v) = (fn (y,d1 : double,v) => d0 < d1)

fun polySortByDistance xs = (
	  case xs
	   of nil => nil
	    | p :: xs => let
		  val lt = List.filter (greaterThan p) xs
		  val eq = p :: List.filter (eqwal p) xs
		  val gt = List.filter (lessThan p) xs
	          in
		    polySortByDistance lt @ eq @ polySortByDistance gt
		  end);


fun polyNorm (poly : (vec * double * (double * double) list) list,pos) = 
    let val veclist = (List.map (fn ((a,b,c),d) => (a,b,c)) (List.filter (fn ((a,b,c),d) => let  val pt = if abs(a) > 0.0 then (~d/a,0.0,0.0) else if abs(b) > 0.0 then (0.0,~d/b,0.0) else (0.0,0.0,~d/c)  in
                     (EPSILON >= vecdot (a,b,c) (vecsub pt pos)  ) end)   
                 (List.map (fn (n,d0,v) => (n,d0)) (polySortByDistance poly))) )
       in
       case veclist of
       nil => pos
      | vlist => List.hd vlist
      end


fun Primnorm (pos,p) = (case p of
    Sphere (center,rad,surf) => vecscale (vecsub pos center) (1.0/rad)
  | Polyhedron (poly,surf) => polyNorm(poly,pos)
  | Hyperboloid (center,skirt,height,s)=> vecscale (vecsub pos center) (1.0/skirt)
  | Paraboloid (center,rad,(zmin,zmax),t,s) => vecscale (vecsub pos center) (1.0)
  | Torus (p,(majorrad,minorrad),(phimin,phimax),t,s) => vecscale (vecsub pos p) (1.0)
  | Cuboid (p,(width,height,depth),s) => vecscale (vecsub pos p) (1.0)
  )

fun CSGnorm (pos, obj) = case obj of prim p => Primnorm(pos, p)
| Union (p,c) => Primnorm(pos,p)
| Intersection (p,c) => Primnorm(pos,p)
| Difference (p,c) => Primnorm(pos,p)






(*
% camera static:
%   lookfrom = 0 -10 0   <--- Camera.pos
%   lookat = 0 0 0
%   vup = 0 0 1
%   fov = 45
% yields
%   dir = norm(lookat - lookfrom) = 0 1 0
%   lookdist = length(lookat-lookfrom) = 10
*)
(*
 * test conditions
 *)
(*val lookfrom = (0.0, (-10.0), 0.0);*)
val lookat = (0.0, 0.0, 0.0);
val vup = (0.0, 0.0, 1.0);
val fov = 45.0;
(*val background = (0.1, 0.1, 0.2);*)

val redsurf = (Ambient (0.1,0.0,0.0)) ::(Diffuse (0.3,0.0,0.0)) ::
	   (Specular (0.8,0.4,0.4)) :: (Transmit 0.7) :: nil;
val greensurf = (Ambient (0.0,0.1,0.0)) :: (Diffuse (0.0,0.3,0.0)) ::
	     (Specular (0.4,0.8,0.4)) :: nil;
val bluesurf = (Ambient (0.0,0.0,0.1)) :: (Diffuse (0.0,0.0,0.3)) ::
	    (Specular (0.4,0.4,0.8)) :: nil;
(*
val testspheres = ((Sphere ((0.0,0.0,0.0), 2.0, redsurf))::
 	       (Sphere (((~2.1),(~2.0),(~2.2)), 0.5, bluesurf))::
 	       (Sphere (((~2.8),3.5,(~1.8)), 1.7, greensurf)::nil));
val testlights = (Directional ((1.0,(~1.0),1.0), (1.0,1.0,1.0)))::
 	     (Point (((~3.0),(~3.0),(~3.0)), (1.0,1.0,1.0))::nil);
*)
(*%%%%%
%% trivial transmission test
% testspheres = ((Sphere ((-1.5),0.,0.) 3. redsurf)::
% 	       (Sphere (1.5, 7.5, 0.) 4. greensurf)::nil);
%%%%%%%
%% reflection test
% mirrorsurf = ((Ambient (.04,.04,.04))::(Diffuse (.05,.05,.05))::
% 	      (Specular (.8,.8,.8))::(Specpow 60.)::(Reflect 1.)::nil);
% testspheres = ((Sphere ((-1.5),0.,0.) 2. mirrorsurf)::
% 	       (Sphere (1.,(-2.),(-.5)) 1. greensurf)::nil);
*)
(*%%%%%%
%% standard balls
*)
val s2 = (Ambient (0.035,0.0325,0.025)) :: (Diffuse(0.5,0.45,0.35)) ::
       (Specular(0.8,0.8,0.8)) :: (Specpow 3.0) :: (Reflect 0.5) :: nil;
val s3 = (Ambient (0.1,0.0,0.0)) :: (Diffuse (0.3,0.0,0.0)) ::
	   (Specular (0.8,0.4,0.4)) :: (Transmit 0.7) :: nil;
val testspheres =
     Sphere((0.0,0.0,0.0), 0.5, s3) ::
     Sphere((0.272166,0.272166,0.544331), 0.166667, s2) ::
     Sphere((0.643951,0.172546,0.0), 0.166667, s2) ::
     Sphere((0.172546,0.643951,0.0), 0.166667, s2) ::
     Sphere(((~0.371785),0.0996195,0.544331), 0.166667, s2) ::
     Sphere(((~0.471405),0.471405,0.0), 0.166667, s2) ::
     Sphere(((~0.643951),(~0.172546),0.0), 0.166667, s2) ::
     Sphere((0.0996195,(~0.371785),0.544331), 0.166667, s2) ::
     Sphere(((~0.172546),(~0.643951),0.0), 0.166667, s2) ::
     Sphere((0.471405,(~0.471405),0.0), 0.166667, s2) :: nil;
val testlights = Point((4.0,3.0,2.0), (0.288675,0.288675,0.288675)) ::
              Point((1.0, ~4.0,4.0), (0.288675,0.288675,0.288675)) ::
              Point((~3.0,1.0,5.0), (0.288675,0.288675,0.288675)) :: nil;

val lookfrom = (2.0, 2.0, 2.0);
val background = (0.078, 0.361, 0.753);
val testpolyhedron = Polyhedron (  ( (~1.0,0.0,0.0), 1.0, ( (0.0,0.0)::(0.0,1.0)::(1.0,1.0)::(1.0,0.0)::nil  ) )::
                                   ( (0.0,~1.0,0.0), 1.0, ( (1.0,0.0)::(1.0,1.0)::(0.0,1.0)::(0.0,0.0)::nil  ) )::
                                   ( (0.0,0.0,1.0),  1.0, ( (0.0,0.0)::(1.0,0.0)::(1.0,1.0)::(0.0,1.0)::nil  ) )::
                                   ( (1.0,0.0,0.0),  1.0, ( (1.0,0.0)::(1.0,1.0)::(0.0,1.0)::(0.0,0.0)::nil  ) )::
                                   ( (0.0,1.0,0.0),  1.0, ( (0.0,0.0)::(0.0,1.0)::(1.0,1.0)::(1.0,0.0)::nil  ) )::
				   ( (0.0,0.0,~1.0), 1.0, ( (1.0,0.0)::(0.0,0.0)::(0.0,1.0)::(1.0,1.0)::nil  ) )::nil,  
                                s2)::nil

val world = List.map (fn x => prim x) (testpolyhedron@testspheres);
(*%%%%%%%*)


(*
% compute camera parameters
*)
fun dtor x = x * pi / 180.0;
fun camparams (lookfrom, lookat, vup, fov, winsize) = let
    val initfirstray = vecsub lookat lookfrom;   (* pre-normalized! *)
    val (lookdir, dist) = vecnorm initfirstray;
    val (scrni, _) = vecnorm (veccross lookdir vup);
    val (scrnj, _) = vecnorm (veccross scrni lookdir);
    val xfov = fov;
    val yfov = fov;
    val xwinsize = (itod winsize);  (* for now, square window *)
    val ywinsize = (itod winsize);
    val magx = 2.0 * dist * (tand (dtor (xfov / 2.0))) / xwinsize;
    val magy = 2.0 * dist * (tand (dtor (yfov / 2.0))) / ywinsize;
    val scrnx = vecscale scrni magx;
    val scrny = vecscale scrnj magy;
    val firstray = (vecsub initfirstray
	  (vecadd
	   (vecscale scrnx (0.5 * xwinsize))
	   (vecscale scrny (0.5 * ywinsize))));
    in
      (firstray, scrnx, scrny)
    end;

(*
% color the given pixel
*)
fun tracepixel (spheres, lights, x, y, firstray, scrnx, scrny) = let
  val pos = lookfrom;
  val (dir, _) = vecnorm (vecadd (vecadd firstray (vecscale scrnx (itod x)))
		    (vecscale scrny (itod y)));
  val (hit, dist, sp) = trace (spheres, pos, dir);  (* pick first intersection *)
						(* return color of the pixel x,y *)
  in
    if hit then
      shade (lights, sp, pos, dir, dist, (1.0,1.0,1.0))
    else
      background
  end

(*
% find first intersection point in set of all objects
*)
and trace (spheres, pos, dir) = let
    (* make a list of the distances to intersection for each hit object *)
    fun sphmap l = (case l
	   of nil => nil
	    | (x::xs) => let
	      val (hit, where') = implicit (pos, dir, x)
	      in
		if hit then
		  (where', x) :: (sphmap xs)
		else
		  (sphmap xs)
	      end)
    val dists = sphmap spheres;
    (* return a sphere and its distance *)
    in
      case dists
       of nil => (false, INFINITY, (hd spheres))  (* missed all *)
        | first::rest => let
	    fun min ((d1, s1), (d2, s2)) = if (d1 < d2) then (d1,s1) else (d2,s2)
	    val (mindist, sp) = fold min first rest
	    in
	      (true, mindist, sp)
	    end
    end

(*
% complete shader, given set of lights, sphere which was hit, ray which hit
%   that sphere, and at what distance, return a color
% contrib answers "what's the most my result can add to the working pixel?"
%   and will abort a reflected or transmitted ray if it gets too small
*)
(*
def testpos = 0.0,(-10.0),0.0;
def testdir = (-0.23446755301152356),0.9434245773614214,(-0.23446755301152356);
def testhitpos = (-1.9015720859580605), (-2.3486648004165893), (-1.9015720859580605);

def testshade _ =
  {(hit?, dist, sp) = trace world testpos testdir;  % pick first intersection
   in
%     shade testlights sp testpos testdir dist (1.,1.,1.)
%     (hit?, dist, sp)
     spherenormal testhitpos sp
  };
*)

and shade (lights, sp, lookpos, dir, dist, contrib) = let
    val hitpos = vecadd lookpos (vecscale dir dist);
    val ambientlight = (1.0, 1.0, 1.0);  (* full contribution as default *)
    val surf = CSGsurf sp;
    val amb = vecmult ambientlight (ambientsurf surf);
    (*  reflected_ray_dir = incoming_dir - (2 cos theta) norm; *)
    val norm = CSGnorm (hitpos, sp);
    val refl = vecadd dir (vecscale norm ((~2.0)*(vecdot dir norm)));
    (*  diff is diffuse and specular contribution *)
    fun lightray' l = lightray (l, hitpos, norm, refl, surf)
    val diff = vecsum (map lightray' lights);
    val transmitted = transmitsurf surf;
    val simple = vecadd amb diff;
    (* calculate transmitted ray; it adds onto "simple" *)
    val trintensity = vecscale (bodysurf surf) transmitted;
    val (tir, trcol) = if (transmitted < EPSILON) then (false, simple)
                    else let
                      val index = refractsurf surf;
                      in
			transmitray (lights, simple, hitpos, dir, index, trintensity,
			  contrib, norm)
                      end
    (*  reflected ray; in case of TIR, add transmitted component *)
    val reflsurf = vecscale (specularsurf surf) (reflectsurf surf);
    val reflectiv = if tir then (vecadd trintensity reflsurf) else reflsurf;
    val rcol = if (zerovector reflectiv) then
             trcol
           else
             reflectray (hitpos, refl, lights, reflectiv, contrib, trcol);
   in
     rcol
   end

(*
% Transmit a ray through an object
*)
and transmitray (lights, color, pos, dir, index, intens, contrib, norm) = let
    val newcontrib = vecmult intens contrib;
    in
      if (zerovector newcontrib) then (false, color)  (* cutoff *)
      else let
	val (tir, newdir) = refractray (index, dir, norm);
	in
	  if tir then (true, color)
	  else let
	      val nearpos = vecadd pos (vecscale newdir EPSILON);
	      val (hit, dist, sp) = trace (world, nearpos, newdir);
	      val newcol = if hit then
		  shade (lights, sp, nearpos, newdir, dist, newcontrib)
		  else background;
	      in (false, vecadd (vecmult newcol intens) color)
	      end
	end
    end

(*
 * Reflect a ray from an object
*)
and reflectray (pos, newdir, lights, intens, contrib, color) = let
    val newcontrib = vecmult intens contrib;
    in
    if (zerovector newcontrib) then color
    else let
	val nearpos = vecadd pos (vecscale newdir EPSILON);
	val (hit, dist, sp) = trace (world, nearpos, newdir);
	val newcol = if (hit) then shade (lights, sp, nearpos, newdir, dist, newcontrib)
	else background
	in (vecadd color (vecmult newcol intens))
    end
end

(*
 * refract a ray through a surface (ala Foley, vanDamm, p. 757)
 *   outputs a new direction, and if total internal reflection occurred or not
 *)
and refractray (newindex, olddir, innorm) = let
    val dotp = ~(vecdot olddir innorm);
    val (norm, k, nr) = if (dotp < 0.0)
	then (vecscale innorm (~1.0), ~dotp, 1.0/newindex)
	else (innorm, dotp, newindex);   (* trans. only with air *)
    val disc = 1.0 - nr*nr*(1.0-k*k);
    in if (disc < 0.0) then (true, (0.0,0.0,0.0)) (* total internal reflection *)
    else let
	val t = nr * k - (sqrt disc);
	in (false, vecadd (vecscale norm t) (vecscale olddir nr))
    end
end

(*
 * For a given light l, surface hit at pos, with norm and refl components
 * to incoming ray, figure out which side of the surface the light is on,
 * and if it's shadowed by another object in the world.  Return light's
 * contribution to the object's color
*)
and lightray (l, pos, norm, refl, surf) = let
    val (ldir, dist) = lightdirection (l, pos);
    val cosangle = vecdot ldir norm;  (* lightray is this far off normal *)
    val (inshadow, lcolor) = shadowed (pos, ldir, lightcolor l);
    in
    if (inshadow) then (0.0,0.0,0.0)
    else let
	val diff = diffusesurf surf;
	val spow = specpowsurf surf;  (* assumed trans is same as refl *)
	in
	if (cosangle <= 0.0) then let (* opposite side *)
	    val bodycol = bodysurf surf;
	    val cosalpha = ~(vecdot refl ldir);
	    val diffcont = vecmult (vecscale diff (~cosangle)) lcolor;
	    val speccont = if (cosalpha <= 0.0) then (0.0,0.0,0.0)
		else vecmult (vecscale bodycol (expt cosalpha spow)) lcolor;
	    in vecadd diffcont speccont
	end else let
	    val spec = specularsurf surf;
	    val cosalpha = vecdot refl ldir;  (* this far off refl ray (for spec) *)
	    val diffcont = vecmult (vecscale diff cosangle) lcolor;
	    val speccont = if (cosalpha <= 0.0) then (0.0,0.0,0.0)
		else vecmult (vecscale spec (expt cosalpha spow)) lcolor;
	    in vecadd diffcont speccont
	end
    end
end

and lightdirection (dir, pt) = (case dir
       of (Directional(dir, col)) => let
	    val (d,_) = vecnorm dir in (d, INFINITY) end
	| (Point(pos, col)) => vecnorm (vecsub pos pt)
      (* end case *))

and shadowed (pos, dir, lcolor) = let (* need to offset just a bit *)
    val (hit, dist, sp) = trace (world, vecadd pos (vecscale dir EPSILON), dir);
    in
      if (not hit) then (false, lcolor)
      else (true, lcolor)  (* for now *)
    end;

(*
% "main" routine
*)

in

(* sequential version of the code *)
fun ray winsize = let
      val lights = testlights;
      val (firstray, scrnx, scrny) = camparams (lookfrom, lookat, vup, fov, winsize);
      val img = newImage (winsize, winsize)
      fun f (i, j) = let
	    val (r, g, b) = tracepixel (world, lights, i, j, firstray, scrnx, scrny)
	    in
	      updateImage3d (img, i, j, r, g, b)
	    end
      fun lp i = if (i < winsize)
	    then let
	      fun lp' j = if (j < winsize)
		    then (f(i, j); lp'(j+1))
		    else ()
	      in
		lp' 0; lp(i+1)
	      end
	    else ();
      val t0 = Time.now()
      val _ = lp 0;
      val t = Time.-(Time.now(), t0)
      in
	print(concat[
	    Time.fmt 3 t, " seconds\n"
	  ]);
	outputImage(img, "out.ppm"); freeImage img
      end;

(* sequential version of the code that builds the image first as a list *)
fun ray' winsize = let
    val lights = testlights;
    val (firstray, scrnx, scrny) = camparams (lookfrom, lookat, vup, fov, winsize);
    val img = newImage (winsize, winsize)
    fun f (i, j) = tracepixel (world, lights, i, j, firstray, scrnx, scrny)
    fun lp (i, is) = if (i < winsize)
	  then let
	    fun lp' (j, is) = if (j < winsize)
		  then lp'(j+1, (i,j,f(i,j)) :: is)
		  else is
	    in
	      lp(i+1, lp' (0, is))
	    end
	  else is
    val b = gettimeofday ();
    val vs = lp (0, nil)
    val e = gettimeofday ();
    fun output vs = (case vs
        of nil => ()
	 | (i,j,(r,g,b)) :: vs => (updateImage3d (img, i, j, r, g, b); output vs)
        (* end case *))
    in
      output vs; outputImage(img, "out.ppm"); freeImage img;
      print (dtos (e-b) ^ " seconds\n")
    end;

(*
fun run (outFile, sz) = let
      val outS = BinIO.openOut outFile
      fun out x = BinIO.output1(outS, Word8.fromInt(Real.round(x * 255.0)))
      fun outRGB (r, g, b) = (out r; out g; out b)
      fun pr s = BinIO.output(outS, Byte.stringToBytes s)
      val t0 = Time.now()
      val img = ray sz
      val t = Time.-(Time.now(), t0)
      in
	print(concat[
	    Time.fmt 3 t, " seconds\n"
	  ]);
        pr "P6\n";
	pr(concat[Int.toString sz, " ", Int.toString sz, "\n"]);
	pr "255\n";
	Array2.app Array2.RowMajor outRGB img;
	BinIO.closeOut outS
      end;

run ("out.ppm", 1024)
*)

end;

fun run sz = ray sz;
