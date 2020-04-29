(* This file is part of the Catala compiler, a specification language for tax and social benefits
   computation rules. Copyright (C) 2020 Inria, contributor: Denis Merigoux
   <denis.merigoux@inria.fr>

   Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except
   in compliance with the License. You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software distributed under the License
   is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
   or implied. See the License for the specific language governing permissions and limitations under
   the License. *)

(** This modules weaves the source code and the legislative text together into a document that law
    professionals can understand. *)

module A = Ast
module P = Printf
module R = Re.Pcre
module C = Cli

let pre_html (s : string) = s

let wrap_html (code : string) (source_files : string list) (custom_pygments : string option)
    (language : Cli.language_option) (output_html_file : string) : string =
  let pygments = match custom_pygments with Some p -> p | None -> "pygmentize" in
  let css_file = Filename.remove_extension output_html_file ^ ".css" in
  let pygments_args = [| "-f"; "html"; "-S"; "colorful" |] in
  let cmd =
    Printf.sprintf "%s %s > %s" pygments (String.concat " " (Array.to_list pygments_args)) css_file
  in
  let return_code = Sys.command cmd in
  if return_code <> 0 then
    Errors.weaving_error
      (Printf.sprintf "pygmentize command \"%s\" returned with error code %d" cmd return_code);
  Printf.sprintf
    "<head>\n\
     <link rel='stylesheet' type='text/css' href='%s'>\n\
     <head>\n\
     <h1>%s<br />\n\
     <small>%s Catala version %s</small>\n\
     </h1>\n\
     <p>\n\
     %s\n\
     </p>\n\
     <ul>\n\
     %s\n\
     </ul>\n\
     <hrule />\n\
     %s"
    css_file
    ( match language with
    | C.Fr -> "Implémentation de texte législatif"
    | C.En -> "Legislative text implementation" )
    (match language with C.Fr -> "Document généré par" | C.En -> "Document generated by")
    ( match Build_info.V1.version () with
    | None -> "n/a"
    | Some v -> Build_info.V1.Version.to_string v )
    ( match language with
    | C.Fr -> "Fichiers sources tissés dans ce document"
    | C.En -> "Source files weaved in this document" )
    (String.concat "\n"
       (List.map
          (fun filename ->
            let mtime = (Unix.stat filename).Unix.st_mtime in
            let ltime = Unix.localtime mtime in
            let ftime =
              Printf.sprintf "%d-%02d-%02d, %d:%02d" ltime.Unix.tm_mday ltime.Unix.tm_mon
                (1900 + ltime.Unix.tm_year) ltime.Unix.tm_hour ltime.Unix.tm_min
            in
            Printf.sprintf "<li><tt>%s</tt>, %s %s</li>"
              (pre_html (Filename.basename filename))
              ( match language with
              | C.Fr -> "dernière modification le"
              | C.En -> "last modification" )
              ftime)
          source_files))
    code

let pygmentize_code (c : string Pos.marked) (language : C.language_option)
    (custom_pygments : string option) : string =
  C.debug_print (Printf.sprintf "Pygmenting the code chunk %s" (Pos.to_string (Pos.get_position c)));
  let temp_file_in = Filename.temp_file "catala_html_pygments" "in" in
  let temp_file_out = Filename.temp_file "catala_html_pygments" "out" in
  let oc = open_out temp_file_in in
  Printf.fprintf oc "%s" (Pos.unmark c);
  close_out oc;
  let pygments = match custom_pygments with Some p -> p | None -> "pygmentize" in
  let pygments_lexer = match language with C.Fr -> "catala_fr" | C.En -> "catala_en" in
  let pygments_args =
    [|
      "-l";
      pygments_lexer;
      "-f";
      "html";
      "-O";
      "style=colorful,linenos=table,linenostart="
      ^ string_of_int (Pos.get_start_line (Pos.get_position c));
      "-o";
      temp_file_out;
      temp_file_in;
    |]
  in
  let cmd = Printf.sprintf "%s %s" pygments (String.concat " " (Array.to_list pygments_args)) in
  let return_code = Sys.command cmd in
  if return_code <> 0 then
    Errors.weaving_error
      (Printf.sprintf "pygmentize command \"%s\" returned with error code %d" cmd return_code);
  let oc = open_in temp_file_out in
  let output = really_input_string oc (in_channel_length oc) in
  close_in oc;
  output

let program_item_to_html (i : A.program_item) (custom_pygments : string option)
    (language : C.language_option) : string =
  match i with
  | A.LawHeading (title, precedence) ->
      let h_number = precedence + 2 in
      P.sprintf "<h%d>%s</h%d>" h_number (pre_html title) h_number
  | A.LawText t -> pre_html t
  | A.LawArticle a -> P.sprintf "<div>%s</div>" (pre_html (Pos.unmark a.law_article_name))
  | A.CodeBlock (_, c) ->
      P.sprintf "<div>\n<div><tt>%s</tt></div>\n%s\n</div>"
        (Pos.get_file (Pos.get_position c))
        (pygmentize_code (Pos.same_pos_as ("/*" ^ Pos.unmark c ^ "*/") c) language custom_pygments)
  | A.MetadataBlock (_, c) ->
      P.sprintf "<div>\n<div><tt>%s</tt></div>\n%s\n</div>"
        (Pos.get_file (Pos.get_position c))
        (pygmentize_code (Pos.same_pos_as ("/*" ^ Pos.unmark c ^ "*/") c) language custom_pygments)
  | A.LawInclude (_file, _page) -> ""

let ast_to_html (program : A.program) (custom_pygments : string option)
    (language : C.language_option) : string =
  String.concat "\n\n"
    (List.map (fun i -> program_item_to_html i custom_pygments language) program.program_items)
