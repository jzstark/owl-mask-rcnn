open Owl
open Owl_types
open Neural 
open Neural.S
open Neural.S.Graph

(* Implementation of ResNet101.
 * The code is heavily inspired by
 * https://github.com/keras-team/keras-applications/blob/master/keras_applications/resnet50.py *)

let id_block input kernel_size filters stage block input_layer =
  let suffix = string_of_int stage ^ block ^ "_branch" in
  let conv_name = "res" ^ suffix in
  let bn_name = "bn" ^ suffix in
  let f1, f2, f3 = filters in
  let x =
    input_layer
    |> conv2d [|1; 1; input; f1|] [|1; 1|] ~padding:VALID ~name:(conv_name^"2a")
    |> normalisation ~axis:3 ~name:(bn_name^"2a") (* 3 should be the axis since [|1;224;224;3|] *)
    |> activation Activation.Relu
                  
    |> conv2d [|kernel_size; kernel_size; f1; f2|] [|1; 1|] ~padding:SAME ~name:(conv_name^"2b")
    |> normalisation ~axis:3 ~name:(bn_name^"2b")
    |> activation Activation.Relu
                  
    |> conv2d [|1; 1; f2; f3|] [|1; 1|] ~padding:VALID ~name:(conv_name^"2c")
    |> normalisation ~axis:3 ~name:(bn_name^"2c") in

  add [|x; input_layer|]
  |> activation Activation.Relu

let conv_block input kernel_size filters strides stage block input_layer =
  let suffix = string_of_int stage ^ block ^ "_branch" in
  let conv_name = "res" ^ suffix in
  let bn_name = "bn" ^ suffix in
  let f1, f2, f3 = filters in
  let x =
    input_layer
    |> conv2d [|1; 1; input; f1|] strides ~padding:VALID ~name:(conv_name^"2a")
    |> normalisation ~axis:3 ~name:(bn_name^"2a")
    |> activation Activation.Relu
                  
    |> conv2d [|kernel_size; kernel_size; f1; f2|] [|1; 1|] ~padding:SAME ~name:(conv_name^"2b")
    |> normalisation ~axis:3 ~name:(bn_name^"2b")
    |> activation Activation.Relu
                  
    |> conv2d [|1; 1; f2; f3|] [|1; 1|] ~padding:VALID ~name:(conv_name^"2c")
    |> normalisation ~axis:3 ~name:(bn_name^"2c") in
  
  let shortcut =
    input_layer
    |> conv2d [|1; 1; input; f3|] strides ~name:(conv_name^"1")
    |> normalisation ~axis:3 ~name:(bn_name^"1") in

  add [|x; shortcut|]
  |> activation Activation.Relu

let resnet101 img_size nb_classes =
  (* +6 is a quick hack instead of zero_padding2d [|3; 3|] *)
  let c1 = 
    input [|img_size + 6; img_size + 6; 3|]
    (* should be |> zero_padding2d [|3; 3|] ~name:"conv1_pad" *)
    |> conv2d [|7; 7; 3; 64|] [|2; 2|] ~padding:VALID ~name:"conv1"
    |> normalisation ~axis:3 ~name:"bn_conv1"
    |> activation Activation.Relu
    |> max_pool2d [|3; 3|] [|2; 2|] in
  let c2 =
    conv_block 64 3 (64, 64, 256) [|1; 1|] 2 "a" c1
    |> id_block 256 3 (64, 64, 256) 2 "b"
    |> id_block 256 3 (64, 64, 256) 2 "c" in

  let c3 =
    conv_block 256 3 (128, 128, 512) [|2; 2|] 3 "a" c2
    |> id_block 512 3 (128, 128, 512) 3 "b"
    |> id_block 512 3 (128, 128, 512) 3 "c"
    |> id_block 512 3 (128, 128, 512) 3 "d" in
                
  let x =
    conv_block 512 3 (256, 256, 1024) [|2; 2|] 4 "a" c3 in
  let y = ref x in
  for i = 0 to 21 do  (* code('b') is 98 *)
    y := id_block 1024 3 (256, 256, 1024) 4 (Char.escaped (Char.chr (98 + i))) !y
  done;
  let c4 = !y in
  
  let c5 =
    conv_block 1024 3 (512, 512, 2048) [|2; 2|] 5 "a" c4
    |> id_block 2048 3 (512, 512, 2048) 5 "b"
    |> id_block 2048 3 (512, 512, 2048) 5 "c" in

  [|c1; c2; c3; c4; c5|]