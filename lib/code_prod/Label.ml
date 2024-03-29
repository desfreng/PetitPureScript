type label = string

let existing_lbl = Hashtbl.create 17

let main_lbl =
  let () = Hashtbl.add existing_lbl "main" () in
  "main"

let fresh_lbl ~atomic txt =
  let final_lbl =
    if (not atomic) || Hashtbl.mem existing_lbl txt then (
      let cpt = ref 1 in
      let l = ref (txt ^ "_" ^ string_of_int !cpt) in
      while Hashtbl.mem existing_lbl !l do
        incr cpt ;
        l := txt ^ "_" ^ string_of_int !cpt
      done ;
      !l )
    else txt
  in
  Hashtbl.add existing_lbl final_lbl () ;
  final_lbl

module LabelMap = Map.Make (String)

let local_lbl fid =
  Ids.Function.name fid ^ "_do_block" |> fresh_lbl ~atomic:false

let function_lbl fid schema_prefix =
  let fname =
    match schema_prefix with
    | Some prefix ->
        Format.sprintf "fun_%s_%s" prefix (Ids.Function.name fid)
    | None ->
        Format.sprintf "fun_%s" (Ids.Function.name fid)
  in
  fresh_lbl ~atomic:true fname

let schema_lbl sid =
  "schema_" ^ string_of_int (Ids.Schema.unique_int sid)
  |> fresh_lbl ~atomic:true

let string_lbl () = fresh_lbl ~atomic:false "string"

let code_lbl () = fresh_lbl ~atomic:false "L"

let jmp_lbl () = fresh_lbl ~atomic:false "JMP"

let pp = Format.pp_print_string

let with_prefix s = fresh_lbl ~atomic:true s
