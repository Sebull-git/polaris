
let run_polaris ~filename lexbuf = 
  let driver_options = Polaris.Driver.{
    filename;
    argv = [];
    print_ast = false;
    print_renamed = false;
    print_tokens = false;
  } in

  Polaris.Driver.parse_rename_typecheck 
    driver_options
    lexbuf 
    Polaris.Rename.RenameScope.empty
    Polaris.Types.empty_env


let try_update_model ~filename lexbuf =

  let on_error err = 

    let text_style = Polaris.Errormessage.make_text_style ~enable_color:false in

    let (mloc, message) = Polaris.Error.pretty_error text_style (fun loc msg -> (loc, msg)) err in
    let loc = Option.value ~default:Polaris.Loc.internal mloc in


    [Diagnostic.{
      loc;
      severity = `Error;
      source = "polaris";
      message;
    }], None in

  Polaris.Error.handle_errors on_error (fun () -> 
    let typed_header, typed_exprs, _rename_scope, _global_type_env = 
      run_polaris ~filename lexbuf
    in
    [], Some (Model.build typed_exprs))

