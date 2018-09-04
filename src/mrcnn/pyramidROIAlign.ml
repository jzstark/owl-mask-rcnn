open Owl
module AD = Neural.S.Algodiff
module N = Dense.Ndarray.S

module C = Configuration

(* *** ROIAlign Layer *** *)

let pyramid_roi_align pool_shape = fun inputs ->
  let inputs = Array.map AD.unpack_arr inputs in
  (* [batch, N, [y1, x1, y2, x2]] *)
  let boxes = inputs.(0) in
  let image_meta = inputs.(1) in
  let feature_maps = Array.sub inputs 2 4 in

  let y1, x1, y2, x2 =
    let tmp = N.split ~axis:2 [|4|] boxes in (* check that *)
    tmp.(0), tmp.(1), tmp.(2), tmp.(3) in
  let h = N.(y2 - y1)
  and w = N.(x2 - x1) in
  let image_shape = (Image.parse_image_meta image_meta).image_shape in
  (* Shape of the first image of batch, they must all have the same size. *)
  let image_area = N.get image_shape [|0;0|] *. N.get image_shape [|0;1|] in
  let roi_level =
    let tmp = N.(log2 (sqrt (h * w) /$ (224. /. image_area))) in
    let five = N.of_array [|5.|] [|1|]
    and two = N.of_array [|2.|] [|1|] in
    let roi_level = N.(min2 five (max2 two (tmp +$ 4.))) in
    N.squeeze ~axis:[|2|] roi_level in

  let zero = N.zeros [|1|] in
  let pooled = Array.make 4 zero in
  let box_to_level = Array.make 4 [||] in
  for level = 2 to 5 do
    let i = level - 2 in
    let ix = N.filteri_nd (fun _ x -> (int_of_float (x +. 1e-5)) = level)
               roi_level in
    (* Would set_slice be more efficient? *)
    let level_boxes = N.init_nd [|Array.length ix; 4|]
                        (fun t -> N.get boxes [|0; ix.(t.(0)).(1); t.(1)|]) in
    box_to_level.(i) <- ix;
    
    (* *** Stop gradient computation here if training the network *** *)

    pooled.(i) <- Image.crop_and_resize feature_maps.(i) level_boxes pool_shape;
  done;

  let pooled = N.concatenate ~axis:0 pooled in
  let box_to_level = N.concatenate ~axis:0 box_to_level in
  (* TODO *)
  AD.pack_arr (N.expand pooled 5)
