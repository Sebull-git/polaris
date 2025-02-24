open Syntax

type pattern_error = 
  | ListWithoutNil
  | ListWithoutCons
  | ExceptionWithoutWildcard
  | NumWithoutWildcard
  | StringWithoutWildcard
  | VariantNonExhaustive of string list

exception PatternError of pattern_error

val check_exhaustiveness_and_close_variants 
  :  close_variant:(Typed.ty -> unit)
  -> Typed.pattern list
  -> unit
