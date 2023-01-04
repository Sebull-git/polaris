open Syntax
open Syntax.Renamed

type type_error = UnableToUnify of (ty * ty) * (ty * ty)
                                 (* ^           ^ full original types *)
                                 (* | specific mismatch               *)
                | MismatchedTyCon of name * name * ty * ty
                | Impredicative of (ty * ty) * (ty * ty)
                | OccursCheck of Unique.t * name * ty * ty * ty
                | WrongNumberOfArgs of ty list * ty list * ty * ty
                | NonProgCallInPipe of expr
                | MissingRecordFields of (string * ty) list * (string * ty) list * ty * ty
                | MissingVariantConstructors of (string * ty list) list * (string * ty list) list * ty * ty
                | ArgCountMismatchInDefinition of name * ty list * int
                | NonFunTypeInLetRec of name * ty
                | CannotUnwrapNonData of ty

exception TypeError of loc * type_error


type global_env = {
  var_types : ty NameMap.t;
  module_var_contents : global_env NameMap.t;
  data_definitions : (name list * ty) NameMap.t;
  type_aliases : (name list * ty) NameMap.t;
}


(* Might throw 'TypeError' *)
val typecheck : header -> expr list -> global_env

