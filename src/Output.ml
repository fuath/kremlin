(** Decorate each file with a little bit of boilerplate, then print it *)

open Utils
open PPrint

let boilerplate = {|
#include <inttypes.h>
|}

let write_one (name, program) =
  let f = name ^ ".c" in
  with_open_out f (fun oc ->
    let doc =
      string boilerplate ^^ hardline ^^ hardline ^^
      separate_map (hardline ^^ hardline) PrintC.p_decl_or_function program
    in
    PPrint.ToChannel.pretty 0.95 80 oc doc
  )

let write files =
  List.iter write_one files