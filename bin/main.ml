    open Polaris
open Polaris.Syntax
open Polaris.Eval  (* Required for exceptions *)
open Polaris.Lexer (* Required for exceptions *)
open Polaris.Types (* Required for exceptions *)
open Polaris.Driver

let usage_message = 
  "Usage: polaris [options] [file] [program options]
    
    Options
      -i, --interactive         Run in interactive mode (default if no file is specified)
      -c <expr>, --eval <expr>  Eval <expr> and print the result

    Debugging options (these are only useful if you are trying to debug the interpreter)
      --print-ast         Print the parsed abstract syntax tree. 
      --print-renamed     Print the renamed syntax tree.
      --print-tokens      Print the tokens generated by the lexer without running the code.
      --trace <category>  Enable traces for a given category.
                          Possible values: " ^ String.concat ", " (Trace.get_categories ())

let fail_usage : 'a. string -> 'a =
  fun msg ->
    print_endline (msg ^ "\n\n" ^ usage_message);
    exit 1

let fatal_error (message : string) = 
  print_endline "~~~~~~~~~~~~~~ERROR~~~~~~~~~~~~~~";
  print_endline message;
  print_endline "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~";
  exit 1

let warning (message : string) =
  print_endline "~~~~~~~~~~~~~WARNING~~~~~~~~~~~~~~";
  print_endline message;
  print_endline "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

let repl_error (message : string) = 
  print_endline ("\x1b[38;2;255;0;0m\x02ERROR\x1b[0m\x02:\n" ^ message);

type run_options = {
  interactive   : bool;
  eval          : string option;
  print_ast     : bool;
  print_renamed : bool;
  print_tokens  : bool;
}

let pretty_call_trace (locs : loc list) =
  match locs with
  | [] -> ""
  | _ -> "Call trace:"
       ^ "\n    " ^ String.concat "\n    " (List.map Loc.pretty locs)

let handle_errors print_fun f = 
  let open Rename.RenameError in 
  let open Eval.EvalError in
  try 
    f ()
  with 
  | ParseError (loc, msg) -> print_fun ("Parse Error at " ^ Loc.pretty loc ^ ": " ^ msg)
  | Sys_error msg -> print_fun ("System error: " ^ msg)
  (* RenameError *)
  | VarNotFound (x, loc) -> print_fun (Loc.pretty loc ^ ": Variable not found: '" ^ x ^ "'")
  | LetSeqInNonSeq (expr, loc) -> print_fun (
        Loc.pretty loc ^ ": Let expression without 'in' found outside a sequence expression.\n"
      ^ "    Expression: " ^ Parsed.pretty expr
      )
  (* EvalError *)
  | DynamicVarNotFound (x, loc::locs) -> print_fun (
        Loc.pretty loc ^ ": Variable not found during execution: '" ^ Name.pretty x ^ "'\n"
      ^ "This is definitely a bug in the interpreter"
      ^ pretty_call_trace locs
      )
  | NotAValueOfType(ty, value, cxt, loc :: locs) -> print_fun (
        Loc.pretty loc ^ ": Not a value of type " ^ ty ^ "."
      ^ "\n    Context: " ^ cxt
      ^ "\n      Value: " ^ Value.pretty value
      ^ "\n" ^ pretty_call_trace locs
      )  
  | TryingToApplyNonFunction (value, loc::locs) -> print_fun (
      Loc.pretty loc ^ ": Trying to apply a value that is not a function: " ^ Value.pretty value
      ^ "\n" ^ pretty_call_trace locs
    )
  | TryingToLookupInNonMap (value, key, loc::locs) -> print_fun (
      Loc.pretty loc ^ ": Trying to lookup key '" ^ key ^ "' in non-map value: " ^ Value.pretty value
      ^ "\n" ^ pretty_call_trace locs
    )
  | TryingToLookupDynamicInNonMap (value, loc::locs) -> print_fun (
      Loc.pretty loc ^ ": Trying to lookup dynamic key in non map or list value: " ^ Value.pretty value
      ^ "\n" ^ pretty_call_trace locs
    )
  | InvalidMapKey (key, map, loc::locs) -> print_fun (
      Loc.pretty loc ^ ": Invalid key '" ^ Value.pretty key ^ "' in dynamic lookup in map: " ^ Value.pretty (MapV map)
      ^ "\n" ^ pretty_call_trace locs
    )
  | InvalidListKey (key, list, loc::locs) -> print_fun (
      Loc.pretty loc ^ ": Invalid key '" ^ Value.pretty key ^ "' in dynamic lookup in list: " ^ Value.pretty (ListV list)
      ^ "\n" ^ pretty_call_trace locs
    )

  | MapDoesNotContain (map, key, loc::locs) -> print_fun (
      Loc.pretty loc ^ ": Map does not contain key '" ^ key ^ "': " ^ Value.pretty (MapV map)
      ^ "\n" ^ pretty_call_trace locs
    )
  | InvalidNumberOfArguments (params, vals, loc::locs) -> print_fun (
      Loc.pretty loc ^ ": Invalid number of arguments in function call.\n"
                     ^ "Expected " ^ Int.to_string (List.length params) ^ " arguments, but received " ^ Int.to_string (List.length vals) ^ ".\n"
                     ^ "    Expected: (" ^ String.concat ", " (List.map Renamed.pretty_pattern params) ^ ")\n"
                     ^ "      Actual: (" ^ String.concat ", " (List.map Value.pretty vals) ^ ")"
                     ^ "\n" ^ pretty_call_trace locs
      )
  | PrimOpArgumentError (primop_name, vals, msg, loc::locs) -> print_fun (
      Loc.pretty loc ^ ": Invalid arguments to builtin function '" ^ primop_name ^ "': " ^ msg ^ "\n"
                     ^ "    Arguments: " ^ Value.pretty (ListV vals)
                     ^ "\n" ^ pretty_call_trace locs
    )
  | InvalidOperatorArgs (op_name, vals, loc::locs) -> print_fun (
      Loc.pretty loc ^ ": Invalid arguments for operator '" ^ op_name ^ "'\n"
                      ^ "    Arguments: " ^ Value.pretty (ListV vals)
                      ^ "\n" ^ pretty_call_trace locs
    )
  | NonNumberInRangeBounds (start_val, end_val, loc::locs) -> print_fun (
      Loc.pretty loc ^ ": Non-number in range bounds.\n"
                     ^ "    Range: [" ^ Value.pretty start_val ^ " .. " ^ Value.pretty end_val ^ "]"
                     ^ "\n" ^ pretty_call_trace locs
    )
  | NonBoolInListComp (value, loc::locs) -> print_fun (
    Loc.pretty loc ^ ": Non-boolean in list comprehension condition: " ^ Value.pretty value
                   ^ "\n" ^ pretty_call_trace locs
  )
  | NonListInListComp (value, loc::locs) -> print_fun (
    Loc.pretty loc ^ ": Trying to draw from a non-list in a list comprehension: " ^ Value.pretty value
                   ^ "\n" ^ pretty_call_trace locs
  )
  | InvalidProcessArg (value, loc::locs) -> print_fun (
      Loc.pretty loc ^ ": Argument cannot be passed to an external process in an !-Expression.\n"
                     ^ "    Argument: " ^ Value.pretty value
                     ^ "\n" ^ pretty_call_trace locs
    )
  | NonProgCallInPipe (expr, loc::locs) -> print_fun (
      Loc.pretty loc ^ ": Non-program call expression found in pipe: " ^ Renamed.pretty expr
      ^ "\n" ^ pretty_call_trace locs
    )
  | RuntimeError (msg, loc::locs) -> print_fun (
    Loc.pretty loc ^ ": Runtime error: " ^ msg
    ^ "\n" ^ pretty_call_trace locs
  )
  | ModuleNotFound (modName, triedPaths) -> print_fun (
      "Module not found: " ^ modName ^ "\n"
    ^ "Tried paths:"
    ^ "\n    " ^ String.concat "\n    " triedPaths
  )
  | AwaitNonPromise (value, loc::locs) -> print_fun (
    Loc.pretty loc ^ ": Trying to await non-promise: " ^ Value.pretty value
    ^ "\n" ^ pretty_call_trace locs
  )
  | NonExhaustiveMatch (value, loc::locs) -> print_fun (
    Loc.pretty loc ^ ": Non-exhaustive pattern match does not cover value: " ^ Value.pretty value
  )
  | LexError err -> begin match err with
    | InvalidOperator (loc, name) -> print_fun (
        Loc.pretty loc ^ ": Invalid operator: '" ^ name ^ "'"
      )
    | UnterminatedString -> print_fun (
        "Unterminated string"
      )
    | InvalidChar (loc, char) -> print_fun (
        Loc.pretty loc ^ ": Invalid char '" ^ string_of_char char ^ "'"
      )
  end
  (* We can safely abort the program, since this can only ever happen when directly
     running a script *)
  | ArgParseError msg -> print_endline msg; exit 1

  | EnsureFailed (path, loc :: locs) -> print_fun (
    Loc.pretty loc ^ ": Required command not installed: '" ^ path ^  "'"
    ^ "\n" ^ pretty_call_trace locs
  )
  | TypeError (loc, err) -> print_fun begin match err with
    | UnableToUnify ((ty1, ty2), (original_ty1, original_ty2)) -> 
      Loc.pretty loc ^ ": Unable to unify types '" ^ Renamed.pretty_type ty1 ^ "'\n"
                     ^ "                    and '" ^ Renamed.pretty_type ty2 ^ "'\n"
                     ^ "While trying to unify '" ^ Renamed.pretty_type original_ty1 ^ "'\n"
                     ^ "                  and '" ^ Renamed.pretty_type original_ty2 ^ "'"
    | Impredicative ((ty1, ty2), (original_ty1, original_ty2)) ->
      Loc.pretty loc ^ ": Impredicative instantiation attempted when matching types '" ^ Renamed.pretty_type ty1 ^ "'\n"
      ^ "                    and '" ^ Renamed.pretty_type ty2 ^ "'\n"
      ^ "While trying to unify '" ^ Renamed.pretty_type original_ty1 ^ "'\n"
      ^ "                  and '" ^ Renamed.pretty_type original_ty2 ^ "'\n"
      ^ "Unification involving ∀-types is not supported (and most likely a bug)"
    | OccursCheck (u, name, ty, original_ty1, original_ty2) -> 
      Loc.pretty loc ^ ": Unable to construct the infinite type '" ^ Renamed.pretty_type (Unif (u, name)) ^ "'\n"
                      ^ "                    ~ '" ^ Renamed.pretty_type ty ^ "'\n"
                      ^ "While trying to unify '" ^ Renamed.pretty_type original_ty1 ^ "'\n"
                      ^ "                  and '" ^ Renamed.pretty_type original_ty2 ^ "'"    
    | WrongNumberOfArgs (tys1, tys2, original_ty1, original_ty2) ->
      Loc.pretty loc ^ ": Wrong number of arguments supplied to function.\n"
                      ^ "Unable to unify argument types '" ^ String.concat ", " (List.map Renamed.pretty_type tys1) ^ "'\n"
                      ^ "                           and '" ^ String.concat ", " (List.map Renamed.pretty_type tys2) ^ "'\n"
                      ^ "While trying to unify '" ^ Renamed.pretty_type original_ty1 ^ "'\n"
                      ^ "                  and '" ^ Renamed.pretty_type original_ty2 ^ "'\n"                             
    | NonProgCallInPipe expr ->
      (* TODO: Is this even possible? *)
      Loc.pretty loc ^ ": Non program call expression in a pipe."
  end
let run_repl_with (scope : Rename.RenameScope.t) (env : eval_env) (options : run_options) : unit =
  Sys.catch_break true;
  let driver_options = {
      filename = "<interactive>"
      (* argv.(0) is "", to signify that this is a repl process.
         This is in line with what python does. *)
    ; argv = env.argv
    ; print_ast = options.print_ast
    ; print_renamed = options.print_renamed
    ; print_tokens = options.print_tokens
    } in
  let env, scope, continue = match options.eval with
  | Some expr ->
    let result, env, scope = Driver.run_env driver_options (Lexing.from_string expr) env scope in
    begin match result with
    | UnitV -> ()
    | _ -> print_endline (Value.pretty result)
    end;
    env, scope, options.interactive
  | None -> env, scope, true
  in
  if continue 
  then begin
    print_endline "Welcome to Polaris! Press Ctrl+D or type \"exit(0)\" to exit.";
    let rec go env scope =
      try
        handle_errors (fun msg -> repl_error msg; go env scope)
          (fun _ -> 
            let prompt = "\x1b[38;5;160mλ>\x1b[0m " in
            match Bestline.bestline prompt with
            | None -> 
              exit 0
            | Some input -> 
              let _ = Bestline.history_add input in
              let result, new_env, new_scope = Driver.run_env driver_options (Lexing.from_string input) env scope in

              begin match result with
              | UnitV -> ()
              | _ -> print_endline (" - " ^ Value.pretty result)
              end;
              go new_env new_scope)
      with
      | Sys.Break -> 
        print_newline ();
        go env scope
    in
    go env scope
  end

let run_file (options : run_options) (filepath : string) (args : string list) = 
  if Option.is_some options.eval then
    fail_usage "The flags '-c' and '--eval' are invalid when executing a file"
  ;

  let driver_options = {
    filename = filepath
  ; argv = filepath :: args
  ; print_ast = options.print_ast
  ; print_renamed = options.print_renamed
  ; print_tokens = options.print_tokens
  } in
  handle_errors fatal_error (fun _ -> 
    let _, env, scope = 
      Driver.run_env 
        driver_options 
        (Lexing.from_channel (open_in filepath))
        (EvalInst.empty_eval_env driver_options.argv)
        Rename.RenameScope.empty
    in
    if options.interactive then
      run_repl_with scope env options 
    )
  

let run_repl options = 
  let argv = [""] in
  run_repl_with Rename.RenameScope.empty (EvalInst.empty_eval_env argv) options

let parse_args () : run_options * string list =
  let default_options : run_options = {
      interactive = false;
      eval = None;
      print_ast = false;
      print_renamed = false;
      print_tokens = false;
  } in
  let rec go options = function
  | ("--help" :: args) ->
    print_endline usage_message;
    exit 0
  | (("-i" | "--interactive") :: args) ->
    go ({options with interactive = true}) args
  | ([("-c" | "--eval") as f]) ->
    fail_usage ("Missing required argument for flag '" ^ f ^ "'")
  | (("-c" | "--eval") :: expr :: args) ->
    go ({options with eval = Some expr}) args
  | ("--print-ast" :: args) -> 
    go ({options with print_ast = true}) args
  | ("--print-renamed" :: args) -> 
    go ({options with print_renamed = true}) args
  | ("--print-tokens" :: args) ->
    go ({options with print_tokens = true}) args
  | ("--trace" :: category :: args) ->
    if Trace.try_set_enabled category true then
      go options args
    else
      fail_usage ("Invalid trace category '" ^ category ^ "'. Possible values: " ^ String.concat ", " (Trace.get_categories ()))
  | (option :: args) when String.starts_with ~prefix:"-" option ->
    fail_usage ("Invalid option: '" ^ option ^ "'.")
  | args -> (options, args) 
  in
  go default_options (List.tl (Array.to_list Sys.argv))


let () =

  let options, args = parse_args () in

  match args with
  | [] -> run_repl options
  | (filepath :: args) -> ignore (run_file options filepath args)
  ;
  Promise.await_remaining ()
