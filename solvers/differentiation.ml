open Core

open Type
open Program
open Utils

open Owl
module AD = Algodiff.D
    
type variable = {mutable gradient : float option;
                 mutable data : float option;
                 volatile : bool; (* whether this depends on something which is a function of learned parameters *)
                 arguments : variable list;
                 forwardProcedure : float list -> float;
                 backwardProcedure : float list -> float list;
                 (* descendents: every variable that takes this variable as input *)
                 (* the additional float parameter is d Descendent / d This *)
                 mutable descendents : (variable*float) list}

let variable_value v = v.data |> get_some

let make_variable forward backward arguments =
  let values = List.map ~f:(fun v -> v.data |> get_some) arguments in
  let initial_value = forward values in
  let s = {gradient = None;
           arguments = arguments;
           volatile = List.exists arguments ~f:(fun a -> a.volatile);
           descendents = [];
           forwardProcedure = forward;
           backwardProcedure = backward;
           data = Some(initial_value);}
  in
  let initial_partials = backward values in
  List.iter2_exn initial_partials arguments ~f:(fun p a ->
      if a.volatile then
        a.descendents <- (s,p)::a.descendents);
  s

let make_binary_variable forward backward a b =
  make_variable (fun x -> match x with
      |[a;b] -> forward a b
      |_ -> raise (Failure "Binary variable did not get 2 arguments"))
    (fun x -> match x with
      |[a;b] -> backward a b
      |_ -> raise (Failure "Binary variable did not get 2 backward arguments"))
    [a;b;]

let forward_fun forward = fun x -> match x with
      |[a;b] -> forward a b
      |_ -> raise (Failure "Binary variable did not get 2 arguments")

let backward_fun backward = fun x -> match x with
      |[a;b] -> backward a b
      |_ -> raise (Failure "Binary variable did not get 2 backward arguments")

(* Let a and b be variable lists. Return a variable list. Forward/backward are the elementwise operation *)
let make_binary_list_variable forward backward a b =
  match a, b with 
  | ([a1; a2; a3], [b1; b2; b3]) -> [(make_variable (forward_fun forward) (backward_fun backward) [a1;b1]);
                                     (make_variable (forward_fun forward) (backward_fun backward) [a2;b2]);
                                     (make_variable (forward_fun forward) (backward_fun backward) [a3;b3])]
  | _ -> raise (Failure "Binary list variable received wrong arguments")

let make_unitary_variable forward backward a =
  make_variable (fun x -> match x with
      |[a;] -> forward a 
      |_ -> raise (Failure "unitary variable did not get 1 arguments"))
    (fun x -> match x with
      |[a;] -> backward a 
      |_ -> raise (Failure "urinary variable did not get 1 backward arguments"))
    [a;]

let (~$) x =
  let rec s = {gradient = None;
               arguments = [];
               volatile = false;
               descendents = [];
               data = Some(x);
               forwardProcedure = (fun _ -> s.data |> get_some);
               backwardProcedure = (fun _ -> []);
              }
  in s

let placeholder () =
  let rec s = {gradient = None;
               arguments = [];
               descendents = [];
               volatile = true;
               data = None;
               forwardProcedure = (fun _ -> s.data |> get_some);
               backwardProcedure = (fun _ -> []);
              }
  in s

let random_variable ?mean:(mean = 0.) ?standard_deviation:(standard_deviation = 1.) () =
  let rec s = {gradient = None;
               arguments = [];
               descendents = [];
               volatile = true;
               data = Some(normal standard_deviation mean);
               forwardProcedure = (fun _ -> s.data |> get_some);
               backwardProcedure = (fun _ -> []);
              }
  in s

(* Currently incompatible with single-dimensional variable type
  let random_variable_vector ?mean:(mean = 0.) ?standard_deviation:(standard_deviation = 1.) () =
  let normals = normal_vector standard_deviation mean in 

  let rec s = {gradient = None;
               arguments = [];
               descendents = [];
               volatile = true;
               data = Some(normal_vector standard_deviation mean);
               forwardProcedure = (fun _ -> s.data |> get_some);
               backwardProcedure = (fun _ -> []);
              }
  in s*)

(*let random_variable_matrix ?mean:(mean = 0.) ?standard_deviation:(standard_deviation = 1.) () =
  let rec s = {gradient = None;
               arguments = [];
               descendents = [];
               volatile = true;
               data = Some(normal_matrix standard_deviation mean);
               forwardProcedure = (fun _ -> s.data |> get_some);
               backwardProcedure = (fun _ -> []);
              }
  in s*)

let update_variable v x =
  assert (Poly.(=) v.arguments []);
  v.data <- Some(x)


let (+&) =
  make_binary_variable (+.) (fun _ _ -> [1.;1.]) 

let add_vector =
  make_binary_list_variable (+.) (fun _ _ -> [1.;1.])

let (-&) =
  make_binary_variable (-.) (fun _ _ -> [1.;-1.]) 

let ( *& ) =
  make_binary_variable ( *. ) (fun a b -> [b;a])

let ( /& ) =
  make_binary_variable ( /. ) (fun a b -> [1./.b;0.-.a/.(b*.b)])

let sigmoid = 
  make_unitary_variable (fun x -> 
    1.0 /. (1.0 +. (exp (-1.0 *. x))))
  (fun x -> 
    let sigma = 1.0 /. (1.0 +. (exp (-1.0 *. x))) in
    [sigma *. (1.-.sigma)])

let tanh = 
  make_unitary_variable Float.tanh (fun z -> 
    let a = Float.tanh z in
    [1.-.a*.a])

let relu = 
  make_unitary_variable (fun x -> 
    if (Poly.(>) x 0.) then x else 0.)
  (fun x -> 
    if (Poly.(>) x 0.) then [1.] else [0.])

let power =
  make_binary_variable ( ** ) (fun a b -> [b*.(a**(b-.1.));
                                          (a**b) *. (log a)])

let logarithm =
  make_unitary_variable log (fun a -> [1./.a])

let exponential =
  make_unitary_variable exp (fun a -> [exp a])

let square =
  make_unitary_variable (fun a -> a*.a) (fun a -> [2.*.a])

let square_float = AD.Maths.sqr

let square_root =
  make_unitary_variable sqrt (fun a -> [0.5/.(sqrt a)])

let clamp ~l ~u =
  make_unitary_variable (fun a ->
      if Poly.(>) a u then u else
      if Poly.(<) a l then l else
        a)
    (fun a ->
       if Poly.(>) a u || Poly.(<) a l then [0.] else [1.])
    
let clamp_float ~l ~u = 
  fun a ->
      if Poly.(>) a u then u else
      if Poly.(<) a l then l else 
      a

let log_soft_max xs =
  make_variable (fun vs -> 
      let m : float = List.fold_right vs ~init:Float.neg_infinity  ~f:Float.max in
      let zm = List.fold_right ~init:0. ~f:(fun x a -> exp (x -. m) +. a) vs in
      m+. (log zm))
    (fun vs -> 
      let m : float = List.fold_right vs ~init:Float.neg_infinity  ~f:Float.max in
      let zm = List.fold_right ~init:0. ~f:(fun x a -> exp (x -. m) +. a) vs in
      List.map vs ~f:(fun x -> (exp (x-.m)) /. zm))
    xs


let rec differentiate z =
  match z.gradient with
  | Some(g) -> g
  | None ->
    let g = List.fold_right z.descendents  ~init:0.0 ~f:(fun (d,partial) a -> a +. differentiate d *. partial) in
    z.gradient <- Some(g);
    g

let rec zero_gradients z =
  match z.gradient with
  | None -> ()
  | Some(_) -> begin
      List.iter z.arguments ~f:(fun a -> zero_gradients a);
      z.gradient <- None;
      z.descendents <- [];
      if Poly.(=) z.arguments [] then () else z.data <- None
    end

let rec forward z =
  match z.data with
  | Some(v) -> v
  | None ->
    let argument_values = List.map z.arguments ~f:forward in
    let v = z.forwardProcedure argument_values in
    let partials = z.backwardProcedure argument_values in
    List.iter2_exn partials z.arguments ~f:(fun p a ->
        a.descendents <- (z,p)::a.descendents);
    z.data <- Some(v);
    v

let backward z =
  z.gradient <- Some(1.0);
  let rec b v =
    let x = differentiate v in
    List.iter ~f:b v.arguments
  in b z

let update_network loss =
  zero_gradients loss;
  let l = forward loss in
  backward loss;
  l

let rec run_optimizer opt ?update:(update = 1000)
    ?iterations:(iterations = 10000) parameters loss =
  let l = update_network loss in
  if iterations = 0 then l else begin

    if update > 0 && iterations mod update = 0 then begin 
      Printf.eprintf "LOSS: %f\n" l;
      parameters |> List.iter ~f:(fun p -> Printf.eprintf "parameter %f\t" (p.data |> get_some));
      Printf.eprintf "\n";
    end else ();

    parameters |> List.map ~f:differentiate |> opt |> 
    List.iter2_exn parameters ~f:(fun x dx ->
        let v = x.data |> get_some in
        update_variable x (v +. dx));
    run_optimizer opt ~update:update ~iterations:(iterations - 1) parameters loss
  end

let restarting_optimize opt ?update:(update = 1000)
    ?attempts:(attempts=1)
    ?iterations:(iterations = 10000) parameters loss =
  (0--attempts) |> List.map ~f:(fun _ ->
      parameters |> List.iter ~f:(fun parameter ->
          update_variable parameter (uniform_interval ~l:(-5.) ~u:5.));
      run_optimizer opt ~update:update ~iterations:iterations parameters loss) |>
  fold1 Float.min

let gradient_descent ?lr:(lr = 0.001) =
  List.map ~f:(fun dx -> ~-. (lr*.dx))

let rprop ?lr:(lr=0.1) ?decay:(decay=0.5) ?grow:(grow=1.2) = 
  let first_iteration = ref true in
  let previous_signs = ref [] in
  let individual_rates = ref [] in

  fun dxs ->
    let new_signs = dxs |> List.map ~f:(fun dx -> Poly.(>) dx 0.) in
    if !first_iteration then begin
      first_iteration := false;
      (* First iteration: ignore the previous signs, which have not yet been recorded *)
      let updates = dxs |> List.map ~f:(fun dx -> ~-. dx*.lr) in

      previous_signs := new_signs;
      individual_rates := dxs |> List.map ~f:(fun _ -> lr);

      updates      
    end else begin 
      individual_rates := List.map3_exn !individual_rates !previous_signs new_signs
          ~f:(fun individual_rate previous_sign new_sign ->
              if Poly.(=) previous_sign new_sign
              then individual_rate*.grow
              else individual_rate*.decay);
      
      let updates = List.map2_exn !individual_rates dxs
          ~f:(fun individual_rate dx ->
              if Poly.(>) dx 0.
              then ~-. individual_rate
              else if Poly.(<) dx 0. then individual_rate else 0.)
      in
      previous_signs := new_signs;
      updates
    end


let proportional_optimize parameters loss_pairs =
  parameters |> List.iter ~f:(fun p -> update_variable p 1.);
  let prediction_variables = loss_pairs |> List.map ~f:fst in
  prediction_variables |> List.iter ~f:zero_gradients;
  let predictions = prediction_variables |> List.map ~f:forward in
  assert (false) (* TODO *)

let test_differentiation () =
  let x = ~$ 10.0 in
  let y = ~$ 2. in
  let z = x -& log_soft_max [x;y;] in
  backward z;
  Printf.printf "dL/dx = %f\tdL/dy = %f\n" (differentiate x) (differentiate y);

  update_variable x 2.;
  update_variable y 10.;

  let ignore = update_network z in

  Printf.printf "dL/dx = %f\tdL/dy = %f\n" (differentiate x) (differentiate y);  

  update_variable x 2.;
  update_variable y 2.;

  let ignore2 = update_network z in

  Printf.printf "z = %f\n" (z.data |> get_some);

  Printf.printf "dL/dx = %f\tdL/dy = %f\n" (differentiate x) (differentiate y);

  (*let l = ((~$ 0.) -& z) in
  ignore(run_optimizer (gradient_descent ~lr:0.001) [x;y] l))*)
  ;;

(* Integration with programs *)
let differentiable_zero = primitive "0." treal (AD.F 0.);;
let differentiable_one = primitive "1." treal (AD.F 1.);;
let differentiable_pi = primitive "pi" treal (AD.F 3.14);;
let differentiable_add = primitive "+." (treal @> treal @> treal) (Maths.(add));;
let differentiable_vector_add = primitive "add_vector" (tlist treal @> tlist treal @> tlist treal) (add_vector);;
let differentiable_subtract = primitive "-." (treal @> treal @> treal) (Maths.(sub));;
let differentiable_multiply = primitive "*." (treal @> treal @> treal) (Maths.(mul));;
let differentiable_division = primitive "/." (treal @> treal @> treal) (Maths.(div));;
let differentiable_power = primitive "power" (treal @> treal @> treal) (power);;
let differentiable_placeholder = primitive "REAL" treal ();;
let differentiable_placeholder_vector = primitive "REAL_VECTOR" (tlist treal) ();;
(*let differentiable_placeholder_matrix = primitive "REAL_MATRIX" (tlist (tlist treal)) ();;*)
let differentiable_sigmoid = primitive "sigmoid" (treal @> treal) (Maths.(sigmoid));;
let differentiable_tanh = primitive "tanh" (treal @> treal) (Maths.(tanh));;
let differentiable_relu = primitive "relu" (treal @> treal) (relu);;

let replace_placeholders program =
  let placeholders = ref [] in
  let rec r = function
    | Index(j) -> Index(j)
    | Abstraction(b) -> Abstraction(r b)
    | Apply(f,x) -> Apply(r f, r x)
    | Invented(t,b) -> Invented(t,r b)
    | Primitive(t,"REAL",_) -> begin
        let x = AD.Mat.uniform 1 1 in
        let x' = AD.make_reverse x (AD.tag ()) in
        placeholders := x' :: !placeholders;
        Primitive(t,"REAL", ref (x |> AD.unpack_flt) |> magical) (* ref (x |> unpack_flt instead of ref x' so !x returns value, not container *)
      end
    | Primitive(t,"REAL_VECTOR",_) -> begin
        let x = AD.Mat.uniform 1 3 in
        let x' = AD.make_reverse x (AD.tag ()) in
        placeholders := x' :: !placeholders;
        Primitive(t,"REAL_VECTOR", ref (x |> AD.unpack_arr) |> magical)
      end
    | p -> p
  in
  let program = r program in
  (program, !placeholders)

(* reverse the parameters list *)
(* should mutate the parameters list *)
let update_placeholders program (parameters : AD.t list Core.ref) ?lr:(lr=0.1) =
  let new_placeholders = ref [] in
  let rec r program (parameters : AD.t list Core.ref) = 
    match program with
    | Index(j) -> Index(j)
    | Abstraction(b) -> Abstraction(r b parameters)
    | Apply(f,x) -> Apply(r f parameters, r x parameters)
    | Invented(t,b) -> Invented(t,r b parameters)
    | Primitive(t,"REAL",_) -> begin
        let x = (List.hd_exn !parameters) -. (lr *. (List.hd_exn !parameters |> AD.adjval |> AD.unpack_flt)) in
        let x' = AD.make_reverse (AD.F x) (AD.tag ()) in
        new_placeholders := x' :: !new_placeholders;
        parameters := List.tl_exn !parameters;
        Primitive(t,"REAL", ref x |> magical)
      end
    | Primitive(t,"REAL_VECTOR",_) -> begin
        let x = (List.hd_exn !parameters) -. (lr *. (List.hd_exn !parameters |> AD.adjval |> AD.unpack_arr)) in
        let x' = AD.make_reverse (AD.Arr x) (AD.tag ()) in
        new_placeholders := x' :: !new_placeholders;
        parameters := List.tl_exn !parameters;
        Primitive(t,"REAL_VECTOR", ref x |> magical)
      end
    | p -> p
  in
  let program = r program parameters in
  (program, !new_placeholders)

let rec placeholder_data t x =
  match t with
  | TCon("real",_,_) -> magical (~$ (magical x))
  | TCon("list",[tp],_) ->
    magical x |> List.map ~f:(placeholder_data tp) |> magical
  | _ -> raise (Failure ("placeholder_data: bad type "^(string_of_type t)))


exception DifferentiableBadShape

(* Takes as input a type *)
(* Returns a function from (prediction, target) to [(prediction_variable, target_variable)] *)
let rec polymorphic_loss_pairs : tp -> 'a -> 'b = function
  | TCon("vector",_,_) -> polymorphic_loss_pairs (tlist treal)
  | TCon("real",_,_) -> magical (fun p y -> [(AD.F p, AD.F y)])
  | TCon("list",[tp],_) ->
    let e = polymorphic_loss_pairs tp in
    magical (fun p y ->
        try
          List.fold2_exn p y ~init:[] ~f:(fun a _p _y -> a @ (e _p _y))
        with _ -> raise DifferentiableBadShape)
  | t -> raise (Failure ("placeholder_data: bad type "^(string_of_type t)))


let rec polymorphic_sse ?clipOutput:(clipOutput=None) ?clipLoss:(clipLoss=None) t =
  let get_pairs = polymorphic_loss_pairs t in
  fun p y ->
    let loss_pairs = get_pairs p y in
    loss_pairs |> List.map ~f:(fun (p,y) ->
        let p = match clipOutput with
          | None -> p
          | Some(clip) -> clamp_float ~l:AD.Maths.(AD.F (-.clip)) ~u:(AD.F clip) p
        in
        let l = square_float AD.Maths.(p - y) in
        match clipLoss with
        | None -> l
        | Some(clip) -> clamp_float ~l:(AD.F 0.) ~u:(AD.F clip) l) |>
    List.reduce_exn ~f:(AD.Maths.add)
(* let rec polymorphic_sse ?clipOutput:(clipOutput=None) ?clipLoss:(clipLoss=None) = function *)
(*   | TCon("vector",_,_) -> polymorphic_sse ~clipOutput ~clipLoss (tlist treal) *)
(*   | TCon("real",_,_) -> magical (fun p y -> *)
(*       let p = match clipOutput with *)
(*         | None -> p *)
(*         | Some(clip) -> clamp ~l:(-.clip) ~u:clip p *)
(*       in *)
(*       let l = square (p -& y) in *)
(*       match clipLoss with *)
(*       | None -> l *)
(*       | Some(clip) -> clamp ~l:0. ~u:clip l) *)
(*   | TCon("list",[tp],_) -> *)
(*     let e = polymorphic_sse ~clipOutput ~clipLoss tp in *)
(*     magical (fun p y -> *)
(*         try *)
(*           List.fold2_exn p y ~init:(~$0.) ~f:(fun a _p _y -> a +& (e _p _y)) *)
(*         with _ -> raise DifferentiableBadShape) *)
(*   | t -> raise (Failure ("placeholder_data: bad type "^(string_of_type t))) *)
  


let test_program_differentiation() =
  let p = parse_program "(lambda REAL)" |> get_some in
  let (p, parameters) = replace_placeholders p in
  let p = analyze_lazy_evaluation p in

  let g = run_lazy_analyzed_with_arguments p [] in

  Printf.printf "%f" (update_network g);;



(* test_differentiation();; *)

(* type symbolic_expression = *)
(*   | SymbolicUnit | SymbolicZero *)
(*   | SymbolicVariable *)
(*   | SymbolicConstant of int *)
(*   | Summation of symbolic_expression list *)
(*   | Product of symbolic_expression list *)
(*   | Quotient of symbolic_expression*symbolic_expression *)
(* [@@deriving compare] *)

(* let make_summation x y = match x,y with *)
(*   | SymbolicZero,a | a,SymbolicZero -> a *)
(*   | _ -> Summation([x;y;]);; *)
(* let make_product x y = match x,y with *)
(*   | SymbolicUnit,a|a,SymbolicUnit -> a *)
(*   | SymbolicZero,_|_,SymbolicZero -> SymbolicZero *)
(*   | _ -> Product([x;y;]) *)

(* let make_quotient p q = match p,q with *)
(*   | _,SymbolicUnit -> p *)
(*   | _,_ -> Quotient(p,q) *)

(* let rec show_symbolic = function *)
(*   | SymbolicUnit -> "1" | SymbolicZero -> "0" | SymbolicVariable -> "x" *)
(*   | SymbolicConstant(j) -> Printf.sprintf "r%d" j *)
(*   | Summation(ss) -> ss |> List.map ~f:show_symbolic |> join ~separator:" + " |> Printf.sprintf "(%s)" *)
(*   | Product(ss) -> ss |> List.map ~f:show_symbolic |> join ~separator:" * " |> Printf.sprintf "(%s)" *)
(*   | Quotient(n,d) -> Printf.sprintf "(%s / %s)" (show_symbolic n) (show_symbolic d) *)
    


(* let program_to_symbolic_expression p = *)
(*   let counter = ref 0 in *)
(*   let rec annotate = function *)
(*     | Primitive(t,"REAL",_) -> (incr counter; Primitive(t,"REAL",!counter |> ref  |> magical)) *)
(*     | Apply(f,x) -> Apply(annotate f, *)
(*                           annotate x) *)
(*     | Abstraction(b) -> Abstraction(annotate b) *)
(*     | Invented(t,b) -> Invented(t,b |> annotate) *)
(*     | e -> e *)
(*   in  *)
(*   let rec walk = function *)
(*     | Primitive(_,"REAL",c) -> SymbolicConstant(!(c |> magical)) *)
(*     | Index(0) -> SymbolicVariable *)
(*     | Apply(Apply(Primitive(_,"+.",_),x),y) -> *)
(*       make_summation (walk x) (walk y)                  *)
(*     | Apply(Apply(Primitive(_,"*.",_),x),y) -> *)
(*       make_product *)
(*         (walk x) *)
(*         (walk y) *)
(*     | Apply(Apply(Primitive(_,"/.",_),x),y) -> *)
(*       Quotient(walk x, *)
(*                walk y) *)
(*     | Abstraction(b) -> walk b *)
(*     | _ -> assert (false) *)
(*   in *)
(*   annotate p |> beta_normal_form ~reduceInventions:true |> walk *)

(* type canonical_polynomial = symbolic_expression list *)

(* type canonical_expression = canonical_polynomial*canonical_polynomial *)


(* let show_polynomial p = *)
(*   p |> List.mapi ~f:(fun e c -> Printf.sprintf "%sx^%d" (show_symbolic c) e) |> *)
(*   join ~separator:" + ";; *)

(* let show_canonical (n,d) = *)
(*   Printf.sprintf "(%s) / (%s)" (show_polynomial n) (show_polynomial d) *)

(* let rec simplify_symbolic s : canonical_expression = *)
(*   let multiply_polynomial_by_x p = SymbolicZero :: p in *)

(*   let add_polynomials p q = *)
(*     let d = max (List.length p) (List.length q) in *)
(*     let p = p @ (List.range (List.length p) d |> List.map ~f:(fun _ -> SymbolicZero)) in *)
(*     let q = q @ (List.range (List.length q) d |> List.map ~f:(fun _ -> SymbolicZero)) in *)
(*     List.map2_exn p q ~f:make_summation *)
(*   in  *)
  
(*   let rec multiply_polynomials p q = *)
(*     match p with *)
(*     | [] -> [] *)
(*     | k :: p -> *)
(*       add_polynomials *)
(*         (q |> List.map ~f:(fun q' -> make_product k q')) *)
(*         (multiply_polynomials p q |> multiply_polynomial_by_x) *)
(*   in *)
  
(*   let rec simplify_product (components : canonical_polynomial list) = *)
(*     match components with *)
(*     | [] -> assert (false) *)
(*     | [c] -> c *)
(*     | x :: y :: z -> *)
(*       multiply_polynomials x y :: z |> simplify_product *)
(*   in  *)
    
(*   match s with *)
(*   | SymbolicVariable -> [SymbolicZero;SymbolicUnit;], [SymbolicUnit] *)
(*   | SymbolicConstant(_) -> [s], [SymbolicUnit] *)
(*   | Product(ss) -> *)
(*     let ss = ss |> List.map ~f:simplify_symbolic in *)
(*     let numerator = ss |> List.map ~f:fst |> simplify_product in *)
(*     let denominator = ss |> List.map ~f:snd |> simplify_product in *)
(*     (numerator, denominator) *)
(*   | Summation([x;y;]) -> *)
(*     let x = simplify_symbolic x in *)
(*     let y = simplify_symbolic y in *)
(*     let denominator = simplify_product [snd x;snd y] in *)
(*     let numerator = add_polynomials *)
(*         (multiply_polynomials (fst x) (snd y)) *)
(*         (multiply_polynomials (fst y) (snd x)) *)
(*     in *)
(*     numerator, denominator *)
(*   | Quotient(p,q) -> *)
(*     let n,d = simplify_symbolic p in *)
(*     let n',d' = simplify_symbolic q in *)
(*     (multiply_polynomials n d', *)
(*      multiply_polynomials d n') *)
(*   | _ -> assert (false) *)

(* let simplify_canonical_expression (n,d) = *)
(*   let leading_coefficient = List.last_exn d in *)
(*   let d = d |> List.map ~f:(fun d' -> make_quotient d' leading_coefficient) in *)
(*   let n = n |> List.map ~f:(fun d' -> make_quotient d' leading_coefficient) in *)

(*   let rec simplify_coefficient : symbolic_expression -> symbolic_expression = function *)
(*     | SymbolicVariable -> assert (false) *)
(*     | SymbolicUnit -> SymbolicUnit *)
(*     | SymbolicConstant(j) -> SymbolicConstant(j) *)
(*     | Summation(ss) -> *)
(*       let ss = ss |> List.map ~f:simplify_coefficient |> List.map ~f:(function *)
(*           | Summation(ss') -> ss' *)
(*           | SymbolicZero -> [] *)
(*           | z -> [z]) |> List.concat *)
(*       in *)
(*       Summation(ss |> List.sort ~compare:compare_symbolic_expression) *)
(*     | Product(ss) -> *)
(*       let ss = ss |> List.map ~f:simplify_coefficient in *)
(*       assert (false) *)
      

(*   (n |> List.map ~f:simplify_coefficient, *)
(*    d |> List.map ~f:simplify_coefficient) *)

(* let test_simplify() = *)
(*   let p = "(lambda (+. (/. (+. $0 (\*. $0 REAL)) REAL) REAL))" |> parse_program |> get_some in *)
(*   let s = program_to_symbolic_expression p in *)
(*   Printf.printf "%s\n" (show_symbolic s); *)
(*   let c = simplify_symbolic s in *)
(*   Printf.printf "%s\n" *)
(*     (show_canonical c) *)
(*   ; *)
(*   exit *)
(*   0 *)
(* ;; *)

(* test_simplify() *)
    

    
   
