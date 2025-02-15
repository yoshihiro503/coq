(************************************************************************)
(*         *   The Coq Proof Assistant / The Coq Development Team       *)
(*  v      *         Copyright INRIA, CNRS and contributors             *)
(* <O___,, * (see version control and CREDITS file for authors & dates) *)
(*   \VV/  **************************************************************)
(*    //   *    This file is distributed under the terms of the         *)
(*         *     GNU Lesser General Public License Version 2.1          *)
(*         *     (see LICENSE file for the text of the license)         *)
(************************************************************************)

module type ValueS =
sig
  type 'a t
end

module type MapS =
sig
  type t
  type 'a key
  type 'a value
  val empty : t
  val add : 'a key -> 'a value -> t -> t
  val remove : 'a key -> t -> t
  val find : 'a key -> t -> 'a value
  val mem : 'a key -> t -> bool
  val modify : 'a key -> ('a value -> 'a value) -> t -> t

  type map = { map : 'a. 'a key -> 'a value -> 'a value }
  val map : map -> t -> t

  type any = Any : 'a key * 'a value -> any
  val iter : (any -> unit) -> t -> unit
  val fold : (any -> 'r -> 'r) -> t -> 'r -> 'r

  type filter = { filter : 'a. 'a key -> 'a value -> bool }
  val filter : filter -> t -> t
end

module type PreS =
sig
  type 'a tag
  type t = Dyn : 'a tag * 'a -> t

  val create : string -> 'a tag
  val anonymous : int -> 'a tag
  val eq : 'a tag -> 'b tag -> ('a, 'b) CSig.eq option
  val repr : 'a tag -> string

  val dump : unit -> (int * string) list

  type any = Any : 'a tag -> any
  val name : string -> any option

  module Map(Value : ValueS) :
    MapS with type 'a key = 'a tag and type 'a value = 'a Value.t

  module HMap (V1 : ValueS)(V2 : ValueS) :
    sig
      type map = { map : 'a. 'a tag -> 'a V1.t -> 'a V2.t }
      val map : map -> Map(V1).t -> Map(V2).t

      type filter = { filter : 'a. 'a tag -> 'a V1.t -> bool }
      val filter : filter -> Map(V1).t -> Map(V1).t
    end

end

module type S =
sig
  include PreS

  module Easy : sig
    val make_dyn_tag : string -> ('a -> t) * (t -> 'a) * 'a tag
    val make_dyn : string -> ('a -> t) * (t -> 'a)
    val inj : 'a -> 'a tag -> t
    val prj : t -> 'a tag -> 'a option
  end
end

module Make () = struct

module Self : PreS = struct
  (* Dynamics, programmed with DANGER !!! *)

  type 'a tag = int

  type t = Dyn : 'a tag * 'a -> t

  type any = Any : 'a tag -> any

  let dyntab = ref (Int.Map.empty : string Int.Map.t)
  (** Instead of working with tags as strings, which are costly, we use their
      hash. We ensure unicity of the hash in the [create] function. If ever a
      collision occurs, which is unlikely, it is sufficient to tweak the offending
      dynamic tag. *)

  let create (s : string) =
    let hash = Hashtbl.hash s in
    if Int.Map.mem hash !dyntab then begin
      let old = Int.Map.find hash !dyntab in
      Printf.eprintf "Dynamic tag collision: %s vs. %s\n%!" s old;
      assert false
    end;
    dyntab := Int.Map.add hash s !dyntab;
    hash

  let anonymous n =
    if Int.Map.mem n !dyntab then begin
      Printf.eprintf "Dynamic tag collision: %d\n%!" n;
      assert false
    end;
    dyntab := Int.Map.add n "<anonymous>" !dyntab;
    n

  let eq : 'a 'b. 'a tag -> 'b tag -> ('a, 'b) CSig.eq option =
    fun h1 h2 -> if Int.equal h1 h2 then Some (Obj.magic CSig.Refl) else None

  let repr s =
    try Int.Map.find s !dyntab
    with Not_found ->
      let () = Printf.eprintf "Unknown dynamic tag %i\n%!" s in
      assert false

  let name s =
    let hash = Hashtbl.hash s in
    if Int.Map.mem hash !dyntab then Some (Any hash) else None

  let dump () = Int.Map.bindings !dyntab

  module Map(Value: ValueS) =
  struct
    type t = Obj.t Value.t Int.Map.t
    type 'a key = 'a tag
    type 'a value = 'a Value.t
    let cast : 'a value -> 'b value = Obj.magic
    let empty = Int.Map.empty
    let add tag v m = Int.Map.add tag (cast v) m
    let remove tag m = Int.Map.remove tag m
    let find tag m = cast (Int.Map.find tag m)
    let mem = Int.Map.mem
    let modify tag f m = Int.Map.modify tag (fun _ v -> cast (f (cast v))) m

    type map = { map : 'a. 'a tag -> 'a value -> 'a value }
    let map f m = Int.Map.mapi f.map m

    type any = Any : 'a tag * 'a value -> any
    let iter f m = Int.Map.iter (fun k v -> f (Any (k, v))) m
    let fold f m accu = Int.Map.fold (fun k v accu -> f (Any (k, v)) accu) m accu

    type filter = { filter : 'a. 'a tag -> 'a value -> bool }
    let filter f m = Int.Map.filter f.filter m
  end

  module HMap (V1 : ValueS) (V2 : ValueS) =
  struct
    type map = { map : 'a. 'a tag -> 'a V1.t -> 'a V2.t }

    let map (f : map) (m : Map(V1).t) : Map(V2).t =
      Int.Map.mapi f.map m

    type filter = { filter : 'a. 'a tag -> 'a V1.t -> bool }

    let filter (f : filter) (m : Map(V1).t) : Map(V1).t =
      Int.Map.filter f.filter m

  end

end
include Self

module Easy = struct
  (* now tags are opaque, we can do the trick *)
  let make_dyn_tag (s : string) =
   (fun (type a) (tag : a tag) ->
    let infun : (a -> t) = fun x -> Dyn (tag, x) in
    let outfun : (t -> a) = fun (Dyn (t, x)) ->
      match eq tag t with
      | None -> assert false
      | Some CSig.Refl -> x
    in
    infun, outfun, tag)
   (create s)

  let make_dyn (s : string) =
    let inf, outf, _ = make_dyn_tag s in inf, outf

  let inj x tag = Dyn(tag,x)
  let prj : type a. t -> a tag -> a option =
    fun (Dyn(tag',x)) tag ->
      match eq tag tag' with
      | None -> None
      | Some CSig.Refl -> Some x
end

end

