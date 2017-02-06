(** CFlat, without structures and with computed stack frames. *)

(** The point of this IR is to:
  * - compute the size of the stack frames;
  * - remove structs and enums, favoring instead n-ary parameters and variables,
  *   along with constant numbers for enums.
  * We keep the size of machine operations, so that we know which sequence of
  * instructions to emit (e.g. for small int types, we want to add a
  * truncation); we also keep the signedness to pick the right operator.
  *)
open Common

module K = Constant

module Sizes = struct

  (** There are only two sizes for values in Wasm. A Low* 64-bit integer maps to
   * I64; everything else maps to I32. *)
  type size =
    | I32
    | I64
    [@@deriving show]

  (* We may want, however, to adopt a more optimal representation for arrays, and
   * store bytes within arrays. Therefore, there is a different notion of how
   * arrays are indexed. *)
  and array_size =
    | A8
    | A16
    | A32
    | A64

  let size_of_width (w: K.width) =
    let open K in
    match w with
    | UInt64 | Int64 | UInt | Int ->
        I64
    | _ ->
        I32

  let array_size_of_width (w: K.width) =
    let open K in
    match w with
    | UInt64 | Int64 | UInt | Int ->
        A64
    | UInt32 | Int32 ->
        A32
    | UInt16 | Int16 ->
        A16
    | UInt8 | Int8 ->
        A8
    | Bool ->
        invalid_arg "array_size_of_width"

end

open Sizes

type program =
  decl list

and decl =
  | Global of ident * size * expr * bool
  | Function of function_t
  | External of ident * size list (* args *) * size list (* ret *)

and function_t = {
  name: ident;
  args: size list;
  ret: size list;
  locals: locals;
  body: stmt list;
  public: bool;
}

(* This is NOT De Bruijn *)
and locals =
  size list

and stmt =
  | Abort
  | Return of expr option
  | Ignore of expr
  | IfThenElse of expr * block * block
  | While of expr * block
  | Assign of var * expr
  | Copy of expr * expr * size * expr
    (** Destination, source, element size, number of elements *)
  | Switch of expr * (expr * block) list
  | BufWrite of expr * expr * expr * array_size
  | BufBlit of expr * expr * expr * expr * expr * array_size
  | BufFill of expr * expr * expr * array_size
  | PushFrame
  | PopFrame
  [@@ deriving show]

and expr =
  | CallOp of op * expr list
  | CallFunc of ident * expr list
  | Var of var
  | Qualified of ident
  | Constant of K.width * string
  | BufCreate of lifetime * expr * expr * array_size
  | BufCreateL of lifetime * expr list * array_size
  | BufRead of expr * expr * array_size
  | BufSub of expr * expr * array_size
  | Comma of expr * expr
  | StringLiteral of string
  | Cast of expr * K.width * K.width
      (** from; to *)
  | Any

and block =
  stmt list

and var =
  int (** NOT De Bruijn *)

and op = K.width * K.op

and ident =
  string
