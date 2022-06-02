
exception TODO
exception Panic of string

type ('a, 'b) either =
  | Left of 'a
  | Right of 'b

let rec take_exact count list = match count, list with
| 0, _ -> Some []
| n, (x::xs) -> Option.map (fun y -> x::y) (take_exact (n - 1) xs)
| _, [] -> None

let split_at_exact ix list =
  let rec go ix found rest = match ix, found, rest with
  | 0, xs, ys -> Some (List.rev xs, ys)
  | n, xs, (y::ys) -> go (n - 1) (y::xs) ys
  | n, xs, [] -> None
  in
  go ix [] list

type void

let absurd (_ : void) = raise (Panic "absurd: impossible argument")
