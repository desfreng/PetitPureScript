open TypedAst
open PP
open Ast

exception TypeError of string * position option

let unknown_type_var n pos =
  let txt =
    Format.sprintf "The type variable '%s' is not defined is this declaration."
      n
  in
  raise (TypeError (txt, Some pos.pos))

let unknown_symbol n pos =
  let txt =
    Format.sprintf "The type symbol '%s' is not defined in this declaration." n
  in
  raise (TypeError (txt, Some pos.pos))

let symbol_arity_mismatch symbid ar_expected ar_found pos =
  let txt =
    Format.asprintf
      "The type symbol '%a' expects %i arguments, but is applied here to %i \
       arguments."
      Symbol.pp symbid ar_expected ar_found
  in
  raise (TypeError (txt, Some pos.pos))

let invalid_anonymous pos =
  let txt = "Wildcard '_' not expected here." in
  raise (TypeError (txt, Some pos.pos))

let variable_not_declared n pos =
  let txt =
    Format.sprintf "The variable '%s' is not defined in this expression." n
  in
  raise (TypeError (txt, Some pos.pos))

let expected_type_in lenv found expected_list pos =
  let pp = PP.setup_pp_ttyp lenv (found :: expected_list) in
  let rec _pp ppf = function
    | [] ->
        (* The type list cannot be empty. *)
        assert false
    | [x] ->
        pp ppf x
    | [x; y] ->
        Format.fprintf ppf "%a or %a." pp x pp y
    | hd :: tl ->
        Format.fprintf ppf "%a, %a" pp hd _pp tl
  in
  let txt =
    Format.asprintf
      "This expression is of type %a. However, one of the following types is \
       expected here: %a"
      pp found _pp expected_list
  in
  raise (TypeError (txt, Some pos.pos))

(** An error occured during the unification of [t1] and [t2]. *)
let unification_error lenv uerr t1 t2 pos =
  let txt =
    match uerr with
    | SymbolMismatch v ->
        let pp = setup_pp_ttyp lenv [t1; t2] in
        Format.asprintf
          "Impossible to match type %a with type %a, type symbols '%a' and \
           '%a' are different."
          pp t1 pp t2 Symbol.pp v.symb1 Symbol.pp v.symb2
    | NotSameTypes v ->
        let pp = setup_pp_ttyp lenv [t1; t2; v.t1; v.t2] in
        Format.asprintf
          "Impossible to match type %a with type %a, the type %a is different \
           from the type %a."
          pp t1 pp t2 pp v.t1 pp v.t2
    | VariableOccuring v ->
        let pp = setup_pp_ttyp lenv [t1; t2; v.var; v.typ] in
        Format.asprintf
          "Unable to match type %a with type %a, variable of type %a appears \
           in type %a."
          pp t1 pp t2 pp v.var pp v.typ
  in
  raise (TypeError (txt, Some pos.pos))

let constr_arity_mismatch constr (_, constr_arity) found pos =
  let txt =
    Format.asprintf
      "The constructor '%a' expects %i arguments, but is applied here to %i \
       arguments."
      Constructor.pp constr constr_arity found
  in
  raise (TypeError (txt, Some pos.pos))

let unknown_constructor n pos =
  let txt =
    Format.sprintf "The constructor '%s' is not defined in this expression." n
  in
  raise (TypeError (txt, Some pos.pos))

let same_variable_in_pat n pos =
  let txt =
    Format.sprintf
      "The variable '%s' is tied to several values in this case expression." n
  in
  raise (TypeError (txt, Some pos.pos))

let variable_not_a_function lenv var_name typ ex_arity pos =
  let pp = setup_pp_ttyp lenv [typ] in
  let txt =
    Format.asprintf
      "The variable '%s' of type %a cannot be interpreted as a function with \
       %i arguments."
      var_name pp typ ex_arity
  in
  raise (TypeError (txt, Some pos.pos))

let unknown_function n pos =
  let txt =
    Format.sprintf "The function '%s' is not defined in this expression." n
  in
  raise (TypeError (txt, Some pos.pos))

let function_arity_mismatch fid expected found pos =
  let txt =
    Format.asprintf
      "The function '%a' expects %i arguments, but is applied here to %i \
       arguments."
      Function.pp fid expected found
  in
  raise (TypeError (txt, Some pos.pos))

let unresolved_instance lenv inst stack pos =
  let pp = setup_pp_inst lenv (inst :: stack) in
  let txt =
    if stack <> [] then
      Format.asprintf
        "The instance '%a' cannot be resolved in the current environment.@.@.%a"
        pp inst
        (Format.pp_print_list
           ~pp_sep:(fun ppf -> Format.pp_force_newline ppf)
           (fun ppf ->
             Format.fprintf ppf "While solving requirement of '%a'." pp ) )
        (List.rev stack)
    else
      Format.asprintf
        "The instance '%a' cannot be resolved in the current environment." pp
        inst
  in
  raise (TypeError (txt, Some pos.pos))

let typ_var_already_decl_in_symb var symbol pos =
  let txt =
    Format.sprintf
      "The type variable '%s' appear several times in the declaration of the \
       type symbol '%s'."
      var symbol
  in
  raise (TypeError (txt, Some pos.pos))

let symbol_already_exists symbol pos =
  let txt =
    Format.sprintf "The type symbol '%s' is declared several times." symbol
  in
  raise (TypeError (txt, Some pos.pos))

let constr_already_in_symb constr symbol pos =
  let txt =
    Format.sprintf
      "The constructor '%s' is defined several times in the declaration of the \
       type symbol '%s'."
      constr symbol
  in
  raise (TypeError (txt, Some pos.pos))

let constr_already_in_genv constr symbid pos =
  let txt =
    Format.asprintf
      "The constructor '%s' is already declared within the type symbol '%a'."
      constr Symbol.pp symbid
  in
  raise (TypeError (txt, Some pos.pos))

let function_already_exists fun_name pos =
  let txt =
    Format.sprintf "The function '%s' is declared several times." fun_name
  in
  raise (TypeError (txt, Some pos.pos))

let class_already_exists class_name pos =
  let txt =
    Format.sprintf "The type class '%s' is declared several times." class_name
  in
  raise (TypeError (txt, Some pos.pos))

let typ_var_already_decl_in_class var class_name pos =
  let txt =
    Format.sprintf
      "The type variable '%s' appear several times in the declaration of the \
       type class '%s'."
      var class_name
  in
  raise (TypeError (txt, Some pos.pos))

let no_qvar_in_class_fun_decl fun_name class_name pos =
  let txt =
    Format.sprintf
      "The function '%s' in the type class '%s' is declared with quantified \
       types variables."
      fun_name class_name
  in
  raise (TypeError (txt, Some pos.pos))

let no_instl_in_class_fun_decl fun_name class_name pos =
  let txt =
    Format.sprintf
      "The function '%s' of the type class '%s' is declared with type class \
       constraints."
      fun_name class_name
  in
  raise (TypeError (txt, Some pos.pos))

let missing_fun_type_decl fun_name pos =
  let txt =
    Format.sprintf "Missing type declaration of function '%s'." fun_name
  in
  raise (TypeError (txt, Some pos.pos))

let typ_var_already_decl_in_fun var fun_name pos =
  let txt =
    Format.sprintf
      "The type variable '%s' appear several times in the declaration of the \
       function '%s'."
      var fun_name
  in
  raise (TypeError (txt, Some pos.pos))

let unknown_class n pos =
  let txt = Format.sprintf "The type class '%s' is not defined." n in
  raise (TypeError (txt, Some pos.pos))

let class_arity_mismatch clsid class_decl ar_found pos =
  let txt =
    Format.asprintf
      "The type class '%a' expects %i arguments, but is applied here to %i \
       arguments."
      TypeClass.pp clsid class_decl.tclass_arity ar_found
  in
  raise (TypeError (txt, Some pos.pos))

let same_variable_in_fun var_name fid pos =
  let txt =
    Format.asprintf
      "The variable '%s' is tied to several values in this implementation of \
       the function '%a'."
      var_name Function.pp fid
  in
  raise (TypeError (txt, Some pos.pos))

let multiples_non_var_in_fun_args fid pos =
  let txt =
    Format.asprintf
      "Several filter patterns that are not variables appear in this \
       implementation of the function '%a'."
      Function.pp fid
  in
  raise (TypeError (txt, Some pos.pos))

let strange_non_var_in_decls fid pos =
  let txt =
    Format.asprintf
      "Not all implementations of the function '%a' have their filter patterns \
       on the same argument."
      Function.pp fid
  in
  raise (TypeError (txt, Some pos.pos))

let missing_fun_impl fun_name pos =
  let txt = Format.sprintf "The function '%s' is not implemented." fun_name in
  raise (TypeError (txt, Some pos.pos))

let not_exhaustive_case pos =
  raise (TypeError ("This pattern matching is not exhaustive.", Some pos.pos))

let not_exhaustive_fun fname (pos : Ast.decl list) =
  let fst = List.hd pos in
  let lst = List.rev pos |> List.hd in
  let pos =
    {fst.pos with end_line= lst.pos.end_line; end_col= lst.pos.end_col}
  in
  let txt =
    Format.asprintf
      "Pattern matching on the arguments of the function '%a' is not \
       exhaustive."
      Function.pp fname
  in
  raise (TypeError (txt, Some pos))

let multiple_const_def cstname pos =
  let txt =
    Format.asprintf "The global constant '%a' is defined several times."
      Function.pp cstname
  in
  raise (TypeError (txt, Some pos.pos))

let missing_main () =
  raise
    (TypeError
       ("Missing declaration and implementation of the function main.", None) )

let same_fun_in_class fun_name class_name pos =
  let txt =
    Format.sprintf
      "The function '%s' is defined several times in the type class '%s'."
      fun_name class_name
  in
  raise (TypeError (txt, Some pos.pos))

let can_unify_instances lenv prod ex pos =
  let pp = setup_pp_inst lenv [prod; ex.schema_prod] in
  let txt =
    Format.asprintf "Instances '%a' and '%a' can be unified." pp prod pp
      ex.schema_prod
  in
  raise (TypeError (txt, Some pos.pos))

let function_already_def_in_inst lenv fname inst pos =
  let pp = setup_pp_inst lenv [inst] in
  let txt =
    Format.asprintf
      "The function '%s' is implemented several times within the instance '%a'."
      fname pp inst
  in
  raise (TypeError (txt, Some pos.pos))

let function_not_in_class fname clsid pos =
  let txt =
    Format.asprintf "The function '%s' is not defined in the type class '%a'."
      fname TypeClass.pp clsid
  in
  raise (TypeError (txt, Some pos.pos))

let missing_functions lenv inst fdone clsid class_decl pos =
  let miss_fun =
    Function.Map.filter
      (fun fid _ -> Function.Set.mem fid fdone)
      class_decl.tclass_decls
  in
  let rec _pp ppf = function
    | [] ->
        (* The type list cannot be empty. *)
        assert false
    | [x] ->
        Function.pp ppf x
    | [x; y] ->
        Format.fprintf ppf "%a and %a" Function.pp x Function.pp y
    | hd :: tl ->
        Format.fprintf ppf "%a, %a" Function.pp hd _pp tl
  in
  let pp = setup_pp_inst lenv [inst] in
  let txt =
    Format.asprintf
      "The '%a' instance is missing the implementation of the functions %a \
       declared in the '%a' type class."
      pp inst _pp
      (Function.Map.bindings miss_fun |> List.map fst)
      TypeClass.pp clsid
  in
  raise (TypeError (txt, Some pos.pos))
