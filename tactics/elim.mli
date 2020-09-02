(************************************************************************)
(*         *   The Coq Proof Assistant / The Coq Development Team       *)
(*  v      *         Copyright INRIA, CNRS and contributors             *)
(* <O___,, * (see version control and CREDITS file for authors & dates) *)
(*   \VV/  **************************************************************)
(*    //   *    This file is distributed under the terms of the         *)
(*         *     GNU Lesser General Public License Version 2.1          *)
(*         *     (see LICENSE file for the text of the license)         *)
(************************************************************************)

open Names
open EConstr
open Tactypes

(** Eliminations tactics. *)

val case_tac : bool -> or_and_intro_pattern option ->
  (intro_patterns -> named_context -> unit Proofview.tactic) ->
  constr -> inductive * EInstance.t -> constr * types -> unit Proofview.tactic

val h_decompose       : inductive list -> constr -> unit Proofview.tactic
val h_decompose_or    : constr -> unit Proofview.tactic
val h_decompose_and   : constr -> unit Proofview.tactic
val h_double_induction : quantified_hypothesis -> quantified_hypothesis-> unit Proofview.tactic
