open TypedAst
open DefaultTypingEnv

type pat_matrix =
  {scrutineers: texpr list; pat_rows: (tpattern list * texpr) Monoid.t}

exception NonExhaustive

(** [get_fields genv expr cst_id] returns the list of expression corresponding
    to each field of [expr] and the list of their type in the case that [expr]
    has [cst_id] as constructor. *)
let get_fields genv (var, var_typ) cst_id =
  match unfold var_typ with
  | TVar _ | TQuantifiedVar _ ->
      (* If it was the case, we would not be filtering by constructors *)
      assert false
  | TSymbol (sid, args) ->
      (* Declaration of the type *)
      let decl = Symbol.Map.find sid genv.symbols in
      let constr_args, constr_arity =
        Constructor.Map.find cst_id decl.symbol_constr
      in
      if constr_arity = 0 then ([], [])
        (* If no argument, no field to retrieve. Small optimisation to avoid
           building a substitution and applying it. *)
      else
        (* [sigma] maps the quantified variables in the symbol to those in the
           expression. *)
        let sigma = Hashtbl.create 17 in
        List.iter2
          (fun qvar typ -> Hashtbl.add sigma qvar typ)
          decl.symbol_tvars args ;
        (* [cst_args] is the list of the type of each argument of the constructor *)
        let cst_args = List.map (subst sigma) constr_args in
        (* For each field, we create the expression that retrieve its value. *)
        ( List.mapi
            (fun index t -> {expr= TGetField (var, index); expr_typ= t})
            cst_args
        , cst_args )

(** [constructor_mat genv m pat_cstr] returns the pattern matrix of the
    constructor [pat_cstr] built from the pattern matrix [m]. *)
let constructor_mat genv m pat_cstr =
  (* [scrut] is the expression we match on (first expression of the scrutineers),
     [scrut_list] is the rest. *)
  let scrut, scrut_typ, scrut_list =
    match m.scrutineers with
    | [] ->
        raise (Invalid_argument "The list of scrutineers must be non-empty.")
    | hd :: tl -> (
      match hd.expr with
      | TVariable v ->
          (v, hd.expr_typ, tl)
      | _ ->
          raise (Invalid_argument "The first scrutineer must be a variable.") )
  in
  (* [n_scrut] is the list of scrutineers of the new matrix
     [cstr_args_typ] is the type of each argument of the constructor *)
  let n_scrut, cstr_args_typ =
    match pat_cstr with
    | Either.Left _ ->
        (* Constant case: the next scrutineers are the same,
           minus the first one.
           We do not have any argument, so empty type list returned. *)
        (scrut_list, [])
    | Either.Right cst_id ->
        (* Constructor symbol case: the next scrutineers are :
           - The fields of the the first scrutineer
           - The rest of the scrutineers *)
        let fields, cst_typ = get_fields genv (scrut, scrut_typ) cst_id in
        (fields @ scrut_list, cst_typ)
  in
  (* We build the sub matrix for this constructor *)
  let pat_rows =
    Monoid.fold_left
      (fun acc pat_row ->
        match pat_row with
        | [], _ ->
            (* [pat_row] cannot be empty here, this is assured by [f] *)
            assert false
        | pat :: pat_row, act -> (
          match (pat.pat, pat_cstr) with
          | TPatWildcard, _ ->
              (* We add as many wildcard as needed to the new row *)
              let new_pat_row =
                List.map
                  (fun t -> {pat= TPatWildcard; pat_typ= t})
                  cstr_args_typ
                @ pat_row
              in
              Monoid.(acc <> of_elm (new_pat_row, act))
          | TPatVar v, _ ->
              (* We add as many wildcard as needed to the new row *)
              let new_pat_row =
                List.map
                  (fun t -> {pat= TPatWildcard; pat_typ= t})
                  cstr_args_typ
                @ pat_row
              in
              (* We bind the variable "v" to the current scrutineer in the action *)
              let new_act =
                {expr= TBind (v, scrut, act); expr_typ= pat.pat_typ}
              in
              Monoid.(acc <> of_elm (new_pat_row, new_act))
          | TPatConstant c, Either.Left c' when c = c' ->
              Monoid.(acc <> of_elm (pat_row, act))
          | TPatConstructor (cstr, patl), Either.Right cid when cid = cstr ->
              (* We add the constructors pattern to the row *)
              let new_pat_row = patl @ pat_row in
              Monoid.(acc <> of_elm (new_pat_row, act))
          | TPatConstant _, _ | TPatConstructor _, _ ->
              (* Not the right constant/constructor. *)
              acc ) )
      Monoid.empty m.pat_rows
  in
  (* We reverse the row to keep the row order (fold_left has reversed it) *)
  {scrutineers= n_scrut; pat_rows}

(** [build_submat genv m] builds the sub-matrix for each pattern constructor of
    the first column of pattern in [m] *)
let build_submat genv m =
  (* For each row, we build the sub-matrix associated with the constructor. *)
  Monoid.fold_left
    (fun acc pat_row ->
      match pat_row with
      | [], _ ->
          (* [pat_row] cannot be empty here, this is assured by [f] *)
          assert false
      | p :: _, _ -> (
        match p.pat with
        | TPatWildcard | TPatVar _ ->
            acc
        | TPatConstant cst_id ->
            let map =
              match acc with
              | None ->
                  Constant.Map.empty
              | Some (Either.Left map) ->
                  map
              | Some _ ->
                  (* The pattern must by well-typed. This case is impossible
                     because we filter on constant here, not constructor. *)
                  assert false
            in
            let map =
              if Constant.Map.mem cst_id map then map
              else
                let cstr_mat = constructor_mat genv m (Either.left cst_id) in
                Constant.Map.add cst_id cstr_mat map
            in
            Some (Either.left map)
        | TPatConstructor (cstr_id, _) ->
            let map =
              match acc with
              | None ->
                  Constructor.Map.empty
              | Some (Either.Right map) ->
                  map
              | Some _ ->
                  (* The pattern must by well-typed. This case is impossible
                     because we filter on constructor here, not constant. *)
                  assert false
            in
            let map =
              if Constructor.Map.mem cstr_id map then map
              else
                let cstr_mat = constructor_mat genv m (Either.right cstr_id) in
                Constructor.Map.add cstr_id cstr_mat map
            in
            Some (Either.right map) ) )
    None m.pat_rows

let constructors_of_symbol genv typ =
  match unfold typ with
  | TSymbol (sid, _) ->
      let sdecl = Symbol.Map.find sid genv.symbols in
      (sid, sdecl.symbol_constr)
  | _ ->
      raise
        (Invalid_argument
           "[constructors_of_symbol] must only be called on a symbol." )

let build_other_submat genv m =
  (* We compute the sub-matrix for the other cases. To do this, we use a
       trick: We filter with the constructor Constant.TUnit.
       Indeed, the unit value cannot be in the pattern. Because:
       - The only way to refer to this constant is by its 'name' : "unit".
       - But, a pattern with "unit" is interpreted as a pattern variable.
       - So no pattern constant can have the type Constant.TUnit. *)
  constructor_mat genv m (Either.left Constant.Unit)

let rec f genv typ m =
  if Monoid.is_empty m.pat_rows then raise NonExhaustive
  else
    match m.scrutineers with
    | [] ->
        let _, act = Monoid.first m.pat_rows in
        act
    | l -> (
        (* All expression must be closed with [close]. It introduces a fresh
           variable if the pattern is not an expression. *)
        let v, v_typ, m, close =
          let e, tl =
            match l with
            | e :: tl ->
                (e, tl)
            | _ ->
                (* Guarded by the first case. *)
                assert false
          in
          match e.expr with
          | TVariable v ->
              (v, e.expr_typ, m, Fun.id)
          | _ ->
              (* e is not a variable. We first bind e to a fresh variable and
                 replace it in the scrutineers list with the freshly introduced
                 variable. *)
              let v = Variable.fresh "" in
              let m =
                { m with
                  scrutineers= {expr= TVariable v; expr_typ= e.expr_typ} :: tl
                }
              in
              let close next_expr =
                {expr= TLet (v, e, next_expr); expr_typ= next_expr.expr_typ}
              in
              (v, e.expr_typ, m, close)
        in
        let constr_mat = build_submat genv m in
        let otherwise_mat = build_other_submat genv m in
        match constr_mat with
        | None ->
            (* We have not constructed any "specialized" pattern matrix,
               So we continue the pattern matching on the otherwise case *)
            close (f genv typ otherwise_mat)
        | Some (Either.Left constant_map) ->
            let branch_expr = Constant.Map.map (f genv typ) constant_map in
            if is_bool_t v_typ then
              (* We replace the pattern matching with a if *)
              let cond_expr = {expr= TVariable v; expr_typ= v_typ} in
              if Constant.Map.cardinal constant_map = 2 then
                (* We do not need the otherwise branch, true and false are present
                   in the pattern matching. *)
                let true_expr = Constant.(Map.find (Bool true) branch_expr) in
                let false_expr = Constant.(Map.find (Bool false) branch_expr) in
                close
                  {expr= TIf (cond_expr, true_expr, false_expr); expr_typ= typ}
              else
                (* We will need the otherwise branch. *)
                let otherwise_expr = f genv typ otherwise_mat in
                (* [branch_expr] cannot be empty, so its cardinal is one ! *)
                match Constant.Map.bindings branch_expr with
                | [(Constant.Bool true, true_expr)] ->
                    (* We only match on "True" here. *)
                    close
                      { expr= TIf (cond_expr, true_expr, otherwise_expr)
                      ; expr_typ= typ }
                | [(Constant.Bool false, false_expr)] ->
                    (* We only match on "False" here. *)
                    close
                      { expr= TIf (cond_expr, otherwise_expr, false_expr)
                      ; expr_typ= typ }
                | _ ->
                    (* All the other case cannot are impossible because:
                       - [branch_expr] cannot be empty because then we would have
                         a [None] returned by [build_submat].

                       - [branch_expr] cannot be of cardinal > 2 because the type
                         [Boolean] only have two values possible.

                       - [branch_expr] cannot be of cardinal 2 because then we
                         would have executed the other branch of the if. *)
                    assert false
            else
              (* This is a pattern matching on a type with uncountable value,
                 we cannot discard the otherwise branch. *)
              let otherwise_expr = f genv typ otherwise_mat in
              if is_int_t v_typ then
                let branch_expr =
                  Constant.Map.fold
                    (fun cst branch acc ->
                      match cst with
                      | Int i ->
                          IMap.add i branch acc
                      | _ ->
                          (* [branch_expr] is uniformly typed. *)
                          assert false )
                    branch_expr IMap.empty
                in
                close
                  { expr= TIntCase (v, v_typ, branch_expr, otherwise_expr)
                  ; expr_typ= typ }
              else if is_string_t v_typ then
                let branch_expr =
                  Constant.Map.fold
                    (fun cst branch acc ->
                      match cst with
                      | String s ->
                          SMap.add s branch acc
                      | _ ->
                          (* [branch_expr] is uniformly typed. *)
                          assert false )
                    branch_expr SMap.empty
                in
                close
                  { expr= TStringCase (v, v_typ, branch_expr, otherwise_expr)
                  ; expr_typ= typ }
              else
                (* We cannot have a pattern matching with constant that
                   are not String or Int at this point. *)
                assert false
        | Some (Either.Right constr_map) ->
            let branch_expr = Constructor.Map.map (f genv typ) constr_map in
            let symb, constr_set = constructors_of_symbol genv v_typ in
            let otherwise_ignored =
              (* [constr_set] is not empty ! So we discard the otherwise branch if
                 all constructors appear in the constructor to pattern matrix
                 mapping. *)
              Constructor.(Map.for_all (fun cst _ -> Map.mem cst constr_map))
                constr_set
            in
            if otherwise_ignored then
              close
                { expr= TConstructorCase (v, symb, branch_expr, None)
                ; expr_typ= typ }
            else
              let otherwise_expr = f genv typ otherwise_mat in
              close
                { expr=
                    TConstructorCase (v, symb, branch_expr, Some otherwise_expr)
                ; expr_typ= typ } )

(** [compile_case genv typ e pats actions] compiles the case statement over [e]
      with pattern [pats] and actions [actions] of type [typ] to an expression. *)
let compile_case genv typ e pats actions pos =
  let x =
    List.fold_left2
      (fun acc p act -> Monoid.(acc <> of_elm ([p], act)))
      Monoid.empty pats actions
  in
  try f genv typ {scrutineers= [e]; pat_rows= x}
  with NonExhaustive -> TypingError.not_exhaustive_case pos

(** [compile_function genv typ e pats actions] compiles the case statement over [e]
      with pattern [pats] and actions [actions] of type [typ] to an expression. *)
let compile_function genv typ scrutineers pat_rows fid decl_list =
  try f genv typ {scrutineers; pat_rows}
  with NonExhaustive -> TypingError.not_exhaustive_fun fid decl_list
