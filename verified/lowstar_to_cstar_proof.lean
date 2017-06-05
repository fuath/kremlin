import lowstar_to_cstar
import lowstar_semantics
import cstar_semantics
import lowstar_to_cstar -- for transl_typ (FIXME?)
import transition

namespace lowstar_to_cstar_proof

open common
open semantics_common
open lowstar
open cstar
open lowstar_semantics
open cstar_semantics
open lowstar_to_cstar

universe variable u

-- C* to λow* back-translation

inductive back_exp {X : Type u} :
  (X → ident) → cstar.exp → lowstar.exp X → Prop
| int : ∀ names n,
  back_exp names (exp.int n) (exp.int n)
| unit : ∀ names,
  back_exp names exp.unit exp.unit
| loc : ∀ names l,
  back_exp names (exp.loc l) (exp.loc l)
| ptr_add : ∀ names e₁ e₂ le₁ le₂,
  back_exp names e₁ le₁ →
  back_exp names e₂ le₂ →
  back_exp names (exp.ptr_add e₁ e₂) (exp.subbuf le₁ le₂)
-- struct, field, field_addr
| var : ∀ names (x : X), -- ?
  back_exp names (exp.var (names x)) (exp.var x)

inductive back_stmt : ∀ {X : Type u},
  (X → ident) → list cstar.stmt → lowstar.exp X → Prop
| let_in : ∀ X (names : X → ident) b e ss τ (le1 : exp X) (le : exp (^X)),
  back_exp names e le1 →
  back_stmt (names_cons (binder.name b) names) ss le →
  transl_typ τ = binder.typ b → -- ehh
  back_stmt names
    ((stmt.decl b e) :: ss)
    (exp.let_in τ le1 le)
| let_newbuf : ∀ X (names : X → ident) x b n ss τ e le1 le,
  back_exp names e le1 →
  x = binder.name b →
  back_stmt (names_cons x names) ss le →
  transl_typ τ = binder.typ b → -- ehh
  back_stmt names
    ((stmt.decl_buf b n) :: (stmt.write_buf (exp.var x) n e) :: ss)
    (exp.let_newbuf n le1 τ le)
| let_app : ∀ X (names : X → ident) b x τ fn e ss le1 le,
  back_exp names e le1 →
  x = binder.name b →
  transl_typ τ = binder.typ b → -- ehh
  back_stmt (names_cons x names) ss le →
  back_stmt names
    ((stmt.call b fn e) :: ss)
    (exp.let_app τ fn le1 le)
| let_readbuf : ∀ X (names : X → ident) b x τ e1 e2 ss le1 le2 le,
  back_exp names e1 le1 →
  back_exp names e2 le2 →
  x = binder.name b →
  transl_typ τ = binder.typ b → -- ehh
  back_stmt (names_cons x names) ss le →
  back_stmt names
    ((stmt.read b (exp.ptr_add e1 e2)) :: ss)
    (exp.let_readbuf τ le1 le2 le)
| writebuf : ∀ X (names : X → ident) e1 e2 e3 ss le1 le2 le3 le,
  back_exp names e1 le1 →
  back_exp names e2 le2 →
  back_exp names e3 le3 →
  back_stmt names ss le →
  back_stmt names
    ((stmt.write (exp.ptr_add e1 e2) e3) :: ss)
    (exp.writebuf le1 le2 le3 le)
| withframe : ∀ X (names : X → ident) ss1 ss le1 le,
  back_stmt names ss1 le1 →
  back_stmt names ss le →
  back_stmt names
    ((stmt.block ss1) :: ss)
    (exp.ignore (exp.withframe le1) le)
| ignore : ∀ X (names : X → ident) e1 ss le1 le,
  back_exp names e1 le1 →
  back_stmt names ss le →
  back_stmt names
    ((stmt.ignore e1) :: ss)
    (exp.ignore le1 le)
| if_then_else : ∀ X (names : X → ident) e ss1 ss2 ss3 le le1 le2 le3,
  back_exp names e le →
  back_stmt names ss1 le1 →
  back_stmt names ss2 le2 →
  back_stmt names ss3 le3 →
  back_stmt names
    ((stmt.if_then_else e ss1 ss2) :: ss3)
    (exp.ignore (exp.if_then_else le le1 le2) le3)
| exp : ∀ X (names : X → ident) e le,
  back_exp names e le →
  back_stmt names [stmt.return e] le
| unit : ∀ X (names : X → ident),
  back_stmt names [] exp.unit

inductive back_decl : cstar.decl → lowstar.decl → Prop
| function : ∀ ret_ty fn x b ss τ ρ e (le : exp (^pempty.{u})),
  x = binder.name b →
  transl_typ τ = binder.typ b → -- ehh
  transl_typ ρ = ret_ty →
  back_stmt (names_cons x names_empty) (ss ++ [stmt.ignore e]) le → -- ?
  back_decl
    (decl.function ret_ty fn b (ss ++ [stmt.return e])) -- ?
    (decl.function fn ρ le τ)

inductive back_ectx : ∀ {X : Type u} (names : X → ident),
  cstar_semantics.ectx → lowstar_semantics.ectx X → Prop
| ignore : ∀ X (names : X → ident) ss le,
  back_stmt names ss le →
  back_ectx names (ectx.ignore ss) (ectx.ignore ectx.here le)
| read : ∀ X (names : X → ident) ss le b x τ,
  x = binder.name b →
  transl_typ τ = binder.typ b → -- ehh
  back_stmt (names_cons x names) ss le →
  back_ectx names (ectx.read b ss) (ectx.let_in τ ectx.here le)

-- transition systems

def sys_cstar
  (p : cstar.program) (V : vars) (ss : list stmt) :
  transition.system label
:=
  transition.system.mk
    cstar_semantics.configuration
    (cstar_semantics.step p)
    ([], V, ss)
    (λC, let (stk, _, ss) := C in stk = [] ∧ ∃ e, ss = [stmt.return e])

def sys_lowstar
  {X : Type u} (lp : lowstar.program) (le : exp X) :
  transition.system label
:=
  transition.system.mk
    (lowstar_semantics.configuration X)
    (lowstar_semantics.step lp)
    (([] : lowstar_semantics.stack), le)
    (λC, let (stk, le) := C in stk = [] ∧ ∃ lv, le = exp_of_value lv)

-- rel

def close_vars
  {X : Type u} (names : X → ident) (V : vars) (e : exp X) :
  exp X
:=
  exp_bind e (λ (x : X),
    match V (names x) with
    | none := exp.var x
    | some v := v
    end)

lemma close_vars_subbuf :
  ∀ {X : Type u} (names : X → ident) V e1 e2,
  close_vars names V (exp.subbuf e1 e2) =
  exp.subbuf (close_vars names V e1) (close_vars names V e2)
:=
  by { intros, reflexivity }

lemma close_vars_if_then_else :
  ∀ {X : Type u} (names : X → ident) V e1 e2 e3,
  close_vars names V (exp.if_then_else e1 e2 e3) =
  exp.if_then_else (close_vars names V e1) (close_vars names V e2) (close_vars names V e3)
:=
  by { intros, reflexivity }

lemma close_vars_let_in :
  ∀ {X : Type u} (names : X → ident) V τ e1 e2,
  close_vars names V (exp.let_in τ e1 e2) =
  exp.let_in τ
    (close_vars names V e1)
    (exp_bind e2 (f_lift (λ (x : X), close_vars._match_1 x (V (names x)))))
:=
  by { intros, reflexivity }

lemma close_vars_ignore :
  ∀ {X : Type u} (names : X → ident) V e1 e2,
  close_vars names V (exp.ignore e1 e2) =
  exp.ignore (close_vars names V e1) (close_vars names V e2)
:=
  by { intros, reflexivity }

lemma close_vars_let_app :
  ∀ {X : Type u} (names : X → ident) V τ fn e1 e2,
  close_vars names V (exp.let_app τ fn e1 e2) =
  exp.let_app τ fn
    (close_vars names V e1)
    (exp_bind e2 (f_lift (λ (x : X), close_vars._match_1 x (V (names x)))))
:=
  by { intros, reflexivity }

lemma close_vars_let_newbuf :
  ∀ {X : Type u} (names : X → ident) V τ n e1 e2,
  close_vars names V (exp.let_newbuf n e1 τ e2) =
  exp.let_newbuf n
    (close_vars names V e1) τ
    (exp_bind e2 (f_lift (λ (x : X), close_vars._match_1 x (V (names x)))))
:=
  by { intros, reflexivity }

lemma close_vars_let_readbuf :
  ∀ {X : Type u} (names : X → ident) V τ e1 e2 e3,
  close_vars names V (exp.let_readbuf τ e1 e2 e3) =
  exp.let_readbuf τ
    (close_vars names V e1)
    (close_vars names V e2)
    (exp_bind e3 (f_lift (λ (x : X), close_vars._match_1 x (V (names x)))))
:=
  by { intros, reflexivity }

lemma close_vars_writebuf :
  ∀ {X : Type u} (names : X → ident) V e1 e2 e3 e4,
  close_vars names V (exp.writebuf e1 e2 e3 e4) =
  exp.writebuf
    (close_vars names V e1)
    (close_vars names V e2)
    (close_vars names V e3)
    (close_vars names V e4)
:=
  by { intros, reflexivity }

lemma close_vars_pop :
  ∀ {X : Type u} (names : X → ident) V e,
  close_vars names V (exp.pop e) =
  exp.pop (close_vars names V e)
:=
  by { intros, reflexivity }

def ectx_close_vars
  {X : Type u} (names : X → ident) (V : vars) (c : ectx X) :
  ectx X
:=
  ectx_bind c (λ (x : X),
    match V (names x) with
    | none := exp.var x
    | some v := v
    end)

def mem : cstar_semantics.stack → lowstar_semantics.stack :=
  sorry
  -- TODO


inductive unravel_frame {X : Type u} (names : X → ident) :
  exp X → cstar_semantics.frame → exp X → Prop
| no_mem : ∀ V E lE le,
  back_ectx names E lE →
  unravel_frame
    le (none, V, E)
    (close_vars names V (apply_ectx lE le))
| mem : ∀ M V E lE le,
  back_ectx names E lE →
  unravel_frame
    le (some M, V, E)
    (close_vars names V (apply_ectx lE (exp.pop le)))

inductive unravel {X : Type u} (names : X → ident) :
  cstar_semantics.stack → exp X → exp X → Prop
| nil : ∀ le,
  unravel [] le le
| cons : ∀ le le' le'' F FS,
  unravel_frame names le F le' →
  unravel FS le' le'' →
  unravel (F :: FS) le le''

--TODO: move
inductive back_cfg {X : Type u} (names : X → ident) (p : cstar.program) :
  cstar_semantics.configuration → lowstar_semantics.configuration X → Prop
| mk : ∀ S V ss ss' le le',
  eval_head_exp p V ss ss' →
  back_stmt names ss' le →
  unravel names S (close_vars names V le) le' →
  back_cfg (S, V, ss) (mem S, le')

def rel {X : Type u}
  (p : cstar.program) (lp : lowstar.program)
  (names : X → ident)
  (lC : lowstar_semantics.configuration X)
  (C : cstar_semantics.configuration) :
  Prop
:=
  let (H, le) := lC in
  ∃ (n : nat) (le' : exp X),
  back_cfg names p C (H, le') ∧
  (transition.iter (lowstar_semantics.step lp) n) (H, le) (H, le') [] --?

-- auxiliary lemmas

lemma back_stmt_value {X : Type u} (le : exp X) (v : value) : ∀ names,
  back_stmt names [stmt.return v] le →
  le = v
:=
begin
  intros _ H,
  cases v; cases H,
  { cases a_1, refl },
  { cases a, refl },
  { cases a_1, refl }
end

lemma close_vars_value (v : value) : ∀ {X : Type u} (names : X → ident) V,
  close_vars names V v = v
:=
begin
  introv, cases v; simp [close_vars];
  unfold coe lift_t has_lift_t.lift coe_t has_coe_t.coe coe_b has_coe.coe; -- ??
  simp [lowstar.exp_of_value]; simp [exp_bind]
end

lemma close_vars_ectx : ∀ {X : Type u} V names (c : ectx X) (e : lowstar.exp X),
  close_vars names V (apply_ectx c e) =
  apply_ectx (ectx_close_vars names V c) (close_vars names V e)
:=
begin
  intros X V names c, induction c; intros; simp [lowstar_semantics.apply_ectx],
  { simp [ectx_close_vars, lowstar_semantics.apply_ectx, ectx_bind] },
  { rw [close_vars_subbuf, ih_1], reflexivity },
  { rw [close_vars_subbuf, ih_1, close_vars_value], reflexivity },
  { rw [close_vars_if_then_else, ih_1], reflexivity },
  { rw [close_vars_let_in, ih_1], reflexivity },
  { rw [close_vars_ignore, ih_1], reflexivity },
  { rw [close_vars_let_app, ih_1], reflexivity },
  { rw [close_vars_let_newbuf, ih_1], reflexivity },
  { rw [close_vars_let_readbuf, ih_1], reflexivity },
  { rw [close_vars_let_readbuf, ih_1, close_vars_value], reflexivity },
  { rw [close_vars_writebuf, ih_1], reflexivity },
  { rw [close_vars_writebuf, ih_1, close_vars_value], reflexivity },
  { simp [close_vars_writebuf, ih_1, close_vars_value], reflexivity },
  { simp [close_vars_pop, ih_1], reflexivity }
end

-- lemma close_vars_astep : ∀ {X : Type u} V names lp H (a a': exp X) l,
--   astep lp (H, a) (H, a') l →
--   astep lp (H, close_vars names V a) (H, close_vars names V a') l
-- :=
--   sorry

-- end


lemma steps_with_ctx_lemma {X : Type u} (ctx : ectx X) : ∀ decls stack stack' (e1 e1' e e' : exp X) ls,
  e = apply_ectx ctx e1 →
  e' = apply_ectx ctx e1' →
  transition.star (lowstar_semantics.step decls) (stack, e1) (stack', e1') ls →
  transition.star (lowstar_semantics.step decls) (stack, e) (stack', e') ls
:=
begin
  introv E1 E2 H, rw [E1, E2], apply step_steps, assumption
end

lemma steps_with_ctx_close_vars_lemma {X : Type u} (ctx : ectx X) :
  ∀ names V decls stack stack' (e1 e1' e e' : exp X) ls,
  e = apply_ectx ctx e1 →
  e' = apply_ectx ctx e1' →
  transition.star (lowstar_semantics.step decls) (stack, close_vars names V e1) (stack', close_vars names V e1') ls →
  transition.star (lowstar_semantics.step decls) (stack, close_vars names V e) (stack', close_vars names V e') ls
:=
begin
  introv E1 E2 H, rw [E1, E2], simp [close_vars_ectx], apply step_steps, assumption
end

lemma step_here_close_vars_lemma {X : Type u} : ∀ names V decls stack stack' (e e' : exp X) ls,
  astep decls (stack, close_vars names V e) (stack', close_vars names V e') ls →
  step decls (stack, close_vars names V e) (stack', close_vars names V e') ls
:=
begin
  introv H,
  rw [show e = apply_ectx ectx.here e, { refl }],
  rw [show e' = apply_ectx ectx.here e', { refl }],
  simp [close_vars_ectx], constructor, assumption
end

end lowstar_to_cstar_proof

-- open a github issue
namespace tactic.interactive
open lean lean.parser
open interactive interactive.types tactic

open lowstar_to_cstar_proof

meta def steps_with_ctx (ctx : parse texpr) : tactic unit :=
do
  τ ← target,
  match τ with
  | `(transition.star _ (_, close_vars _ _ _) _ _) := do
    l ← i_to_expr ``(lowstar_to_cstar_proof.steps_with_ctx_close_vars_lemma %%ctx),
    tactic.apply l; [try reflexivity, try reflexivity, tactic.skip]
  | `(transition.star _ _ _ _) := do
    l ← i_to_expr ``(lowstar_to_cstar_proof.steps_with_ctx_lemma %%ctx),
    tactic.apply l; [try reflexivity, try reflexivity, tactic.skip]
  | _ := failed
  end
end tactic.interactive

namespace lowstar_to_cstar_proof

-- XXX
open common
open semantics_common
open lowstar
open cstar
open lowstar_semantics
open cstar_semantics
open lowstar_to_cstar

lemma init : ∀ X seen seen' seen'' (names : X → ident) p lp le ss V,
  transl_program seen lp = some (seen', p) →
  transl_to_stmt seen' names le = some (seen'', ss) →
  rel p lp names ([], close_vars names V le) ([], V, ss) :=
begin
  intros X,
  assert Hsteps :
    ∀ le seen seen' (names : X → ident) p lp V ss ss' le',
    transl_to_stmt seen names le = some (seen', ss) →
    eval_head_exp p V ss ss' →
    back_stmt names ss' le' →
    (transition.star (lowstar_semantics.step lp))
      ([], close_vars names V le)
      ([], close_vars names V le')
      [],
  { intro le, induction le,
    { introv Hle Hss Hle',
      simp [transl_to_stmt, transl_to_exp] at Hle,
      opt_inv Hle,
      cases Hss, -- with h' ?
      cases a_1, cases Hle', cases a_2,
      constructor },
    { introv Hle Hss Hle',
      simp [transl_to_stmt, transl_to_exp] at Hle, opt_inv Hle,
      cases Hss, cases a, cases Hle', cases a_1, constructor },
    { introv Hle Hss Hle',
      simp [transl_to_stmt, transl_to_exp] at Hle, opt_inv Hle,
      cases Hss, cases a_1, cases Hle', cases a_2, constructor },
    { introv Hle Hss Hle',
      simp [transl_to_stmt, transl_to_exp] at Hle, opt_inv Hle,
      cases Hss, cases a_1,
      rw [show close_vars names V (exp.var a) = v,
          by { simp [close_vars, exp_bind], rw [a_2], simp [close_vars._match_1] } ],
      rw [back_stmt_value le' v], rw [close_vars_value], constructor, --XX
      assumption, assumption
    },
    { introv Hle Hss Hle',
      simp [transl_to_stmt, transl_to_exp] at Hle,
      opt_inv Hle with x1 H1 x2 H2,
      cases Hss, cases a_2, cases Hle', cases a_5,
      apply transition.star_trans,
      { steps_with_ctx (ectx.subbuf_1 ectx.here a_1), apply ih_1,
        { apply transl_to_stmt_exp, assumption },
        { constructor, assumption },
        { constructor, constructor }
      },
      apply transition.star_trans,
      { steps_with_ctx (ectx.subbuf_2 _ ectx.here),

        -- simp [lowstar_semantics.apply_ectx],
        repeat { admit } },

    --   apply (transition.star_trans ([], close_vars names V (exp.subbuf (value.loc (b, n, [])) a_1))),
    --   show [] = [] ++ [], { reflexivity },
    --   { steps_with_ctx (ectx.subbuf_1 ectx.here a_1),

    --     simp [show ∀ a, exp.subbuf a a_1 = apply_ectx (ectx.subbuf_1 ectx.here a_1) a, { intro, reflexivity }],
    --     simp [close_vars_ectx],
    --     apply step_steps, apply ih_1,
    --     { apply transl_to_stmt_exp, assumption },
    --     { constructor, assumption },
    --     { constructor, constructor }
    --   },
    --   apply (transition.star_trans ([], close_vars names V (exp.subbuf (value.loc (b, n, [])) (value.int n')))),
    --   show [] = [] ++ [], { refl },
    --   { simp [show ∀ (v : value) (a: exp X_1), exp.subbuf ↑v a = apply_ectx (ectx.subbuf_2 v ectx.here) a, { intros, refl }],
    --     simp [close_vars_ectx],
    --     apply step_steps, apply ih_2,
    --     { apply transl_to_stmt_exp, assumption },
    --     { constructor, assumption },
    --     { constructor, constructor }
    --   },
    --   apply (steps_with_ctx_close_vars_lemma ectx.here), refl, refl,
    --   apply transition.star_one, apply step_here_close_vars_lemma, constructor
    -- },

     repeat { admit }
  },
  repeat { admit }
},
admit
end

end lowstar_to_cstar_proof