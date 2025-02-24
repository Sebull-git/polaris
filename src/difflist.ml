
type 'a t = 'a list -> 'a list

let empty = Fun.id

let of_list list = fun xs -> list @ xs

let to_list dl = dl []

let to_seq dl = List.to_seq (to_list dl)

let append_to_list dl list = dl list

let append dl1 dl2 = fun list -> dl1 (dl2 list)

let concat list = List.fold_left append empty list

let snoc dl x = append dl (of_list [x])

let cons x dl = append (of_list [x]) dl

let iter f dl = List.iter f (to_list dl)

let iteri f dl = List.iteri f (to_list dl)

let fold_left f z dl = List.fold_left f z (to_list dl)

let fold_right f dl z = List.fold_right f (to_list dl) z
