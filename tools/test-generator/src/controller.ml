open Core.Std
open Parser
open Model
open Utils
open Codegen
open Special_cases
open Template

type content = string

let find_nested_files (name: string) (base: string): (string * content) list =
  Sys.ls_dir base
    |> List.filter ~f:(fun slug -> Sys.is_directory_exn (base ^ "/" ^ slug))
    |> List.filter ~f:(fun slug -> Sys.file_exists_exn (base ^ "/" ^ slug ^ "/" ^ name))
    |> List.map ~f:(fun slug -> (slug, In_channel.read_all (base ^ "/" ^ slug ^ "/" ^ name)))

let find_template_files = find_nested_files "template.ml"

let find_canonical_data_files = find_nested_files "canonical-data.json"

let combine_files (template_files: (string * content) list) (canonical_data_files: (string * content) list): (string * content * content) list =
  List.filter_map template_files ~f:(fun (n,t) -> (List.Assoc.find canonical_data_files ~equal:String.equal n |> Option.map ~f:(fun c -> (n,t,c))))

let generate_code ~(slug: string) ~(template_file: content) ~(canonical_data_file: content): (content, content) Result.t =
  let template = find_template template_file in
  let open Result.Monad_infix in
  Result.of_option template ("cannot recognize file for " ^ slug ^ " as a template") >>= fun template ->
  parse_json_text canonical_data_file |> Result.map_error ~f:show_error >>= (function
      | Single cases ->
        Result.return (fill_in_template
          (edit_expected ~stringify:parameter_to_string ~slug)
          (edit_parameters ~slug)
          template.template
          slug
          cases |> fill_tests template);
      | Suite tests ->
        let x = List.map tests ~f:(fun {name;cases} ->
            (name, fill_in_template
               (edit_expected ~stringify:parameter_to_string ~slug)
               (edit_parameters ~slug)
               template.template
               name
               cases)
          ) in
        Result.return (fill_suite template x)
    )

let output_tests (files: (string * content * content) list) (output_folder: string): unit =
  let output_filepath name = output_folder ^ "/" ^ name ^ "/test.ml" in
  let output1 (slug,t,c) =
    match generate_code slug t c with
    | Ok code -> Out_channel.write_all (output_filepath slug) code
    | Error e -> print_endline ("Failed when generating " ^ slug ^ ", error: " ^ e) in
  List.iter files ~f:output1

let run ~(templates_folder: string) ~(canonical_data_folder: string) ~(output_folder: string) =
  let template_files = find_template_files templates_folder in
  let canonical_data_files = find_canonical_data_files canonical_data_folder in
  let combined = combine_files template_files canonical_data_files in
  output_tests combined output_folder