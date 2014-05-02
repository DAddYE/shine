--[=[
Copyright (C) 2013-2014 Richard Hundt and contributors.
See Copyright Notice in shine
]=]

local lpeg = require('lpeg')
local util = require('shine.lang.util')
local defs = require('shine.lang.tree')
local re   = require('shine.lang.re')
lpeg.setmaxstack(1024)

local patt = [=[
   chunk  <- (%2 => topline) {|
      <shebang>? s (<stmt> (<sep> s <stmt>)* <sep>?)? s (!. / %1 => error)
   |} -> chunk

   shebang  <- '#!' (!<nl> .)*

   lcomment <- "--" (!<nl> .)* <nl>

   bclose   <- ']' =eq ']' / (<nl> / .) <bclose>
   bcomment <- ('--[' {:eq: (!'[' .)* :} '[' <bclose>)

   cclose   <- ':' =mk ':' / (<nl> / .) <cclose>
   ccomment <- ('--:' {:mk: (!(':'/'(').)* :} ('(' (!')'.)* ')')? ':' <cclose>)

   comment  <- <bcomment> / <ccomment> / <lcomment>

   idsafe   <- !(%alnum / "_" / "!" / "?" / "$")
   nl       <- %nl -> incline
   s        <- (<comment> / <nl> / !%nl %s)*
   S        <- (<comment> / <nl> / !%nl %s)+
   ws       <- <nl> / %s
   hs       <- (!%nl %s)*
   HS       <- (!%nl %s)+
   word     <- (%alpha / "_" / "$" / "!" / "?") (%alnum / "_" / "$" / "!" / "?")*

   reserved <- (
      "var" / "func" / "nil" / "true" / "false" / "return"
      / "break" / "goto" / "not" / "for" / "in" / "if" / "else"
   ) <idsafe>

   keyword  <- (
      <reserved> / "class" / "module" / "next" / "throw" / "super"
      / "import" / "export" / "try" / "catch" / "finally" / "is" / "as"
      / "include" / "grammar" / "switch" / "case" / "macro"
   ) <idsafe>

   sep <- <bcomment>? (<nl> / ";" / <lcomment>) / <ws> <sep>?

   escape <- {~ ('\' (
      'x' %xdigit %xdigit / 'u' %xdigit %xdigit %xdigit %xdigit
      / %digit (%digit %digit?)? / .
   )) -> escape ~}

   astring <- (
      "'''" {~ (<nl> / ("\\" -> "\") / ("\'" -> "'") / {!"'''" .})* ~} "'''"
   ) / (
      "'" {~ (<nl> / ("\\" -> "\") / ("\'" -> "'") / {!"'" .})* ~} "'"
   )

   qstring <- {|
      ('"""' (
         <raw_expr> / {~ (<escape> / <nl> / !(<raw_expr> / '"""') .)+ ~}
      )* '"""')
      /
      ('"' (
         <raw_expr> / {~ (<escape> / <nl> / !(<raw_expr> / '"') .)+ ~}
      )* '"')
   |} -> rawString

   raw_expr <- (
      "%{" s <expr> s "}"
   ) -> rawExpr

   string <- <astring>

   octal <- { "0o" [0-7]+ }

   heximal <- { "0x" %xdigit+ }

   decexp <- ("e"/"E") "-"? %digit+

   double <- (
      %digit+ ("." !"." %digit+ <decexp>? / <decexp>)
   ) -> double

   integer <- ((
      <heximal> / <octal> / { %digit+ }
   ) {'LL' / 'ULL'}?) -> integer

   number <- <double> / <integer>

   boolean <- (
      {"true"/"false"} <idsafe>
   ) -> boolean

   literal <- ( <number> / <string> / <boolean> ) -> literal

   in  <- "in" <idsafe>
   end <- "}"  <idsafe>

   export_stmt <- (
      "export" <idsafe> s {| <ident_list> |}
   ) -> exportStmt

   import_stmt <- (
      "import" <idsafe> s (<import_from> / <import_path>)
   )

   import_path <- {| <import_path_expr> |} -> importPath

   import_path_expr <- (
      <ident> "." <import_path_expr>
      / {:names: {| "{" s <import_name> (s "," s <import_name>)* s "}" |} :}
      / {:names: {| {| <ident> |} |} :}
   )

   import_from <- (
      {| <import_name> (s "," s <import_name>)* |} s
      "from" <idsafe> s <expr>
   ) -> importFrom

   import_name <- {|
      <ident> (hs "=" hs <ident>)?
   |}

   stmt <- (('' -> curline) (
      <import_stmt>
      / <export_stmt>
      / <if_stmt>
      / <for_stmt>
      / <for_in_stmt>
      / <do_stmt>
      / <decl_stmt>
      / <macro_decl>
      / <return_stmt>
      / <try_stmt>
      / <throw_stmt>
      / <break_stmt>
      / <next_stmt>
      / <switch_stmt>
      / <label_stmt>
      / <goto_stmt>
      / <expr_stmt>
   )) -> stmt

   stmt_list <- {|
      (<stmt> (<sep> s <stmt>)* <sep>?)?
   |}

   label_stmt <- (
      <ident> ':' !':'
   ) -> labelStmt

   goto_stmt <- (
      'goto' <idsafe> hs <ident>
   ) -> gotoStmt

   break_stmt <- (
      "break" <idsafe>
   ) -> breakStmt

   next_stmt <- (
      "next" <idsafe>
   ) -> nextStmt

   return_stmt <- (
      "return" <idsafe> {| (hs <expr_list>)? |}
   ) -> returnStmt

   throw_stmt <- (
      "throw" <idsafe> hs <expr>
   ) -> throwStmt

   try_stmt <- (
      "try" <idsafe> s <block_stmt>
      {| <catch_clause>* |} (s "finally" <idsafe> s <block_stmt>)?
   ) -> tryStmt

   catch_clause <- (
      s "catch" <idsafe> hs
      <ident> (hs "if" <idsafe> s <expr>)? s <block_stmt> s
   ) -> catchClause

   decl_stmt <- (
      {| (<decorator> (s <decorator>)* s)? |} (
           <local_coro>
         / <local_func>
         / <local_decl>
         / <coro_decl>
         / <func_decl>
         / <class_decl>
         / <module_decl>
         / <grammar_decl>
      )
   ) -> declStmt

   decorator <- (
      "@" <term>
   ) -> decorator

   guarded_ident <- (
      <ident> hs ":" <idsafe> s <expr>
   ) -> guardedIdent

   local_decl <- (
      "var" <idsafe> %1 s {| <bind_left> (s "," s <bind_left>)* |}
      (s ({"="} s {| <expr_list> |} / {"in"} <idsafe> s <expr>))?
   ) -> localDecl

   local_func <- (
      "var" <idsafe> s
      "func" <idsafe> s <ident> s <func_head> s <func_body>
   ) -> localFuncDecl

   local_coro <- (
      "var" <idsafe> s
      "func*" <idsafe> s <ident> s <func_head> s <func_body>
   ) -> localCoroDecl

   macro_decl <- (
      "macro" <idsafe> s <ident> s (
         {"="} s <ident> /
         "(" s {| <expr_list> |} s ")" s "{" s
         <stmt_list> s
         ("}" / %1 => error)
      )
   ) -> macroDecl

   bind_left <- (
        <array_patt>
      / <table_patt>
      / <guarded_ident>
      / <term>
   )

   array_patt <- (
      "[" s {| <bind_left> (s "," s <bind_left>)* |} s ("]" / %1 => error)
   ) -> arrayPatt

   table_sep <- (
      hs (","/";"/<nl>)
   )

   table_patt <- (
      "{" s {|
         <table_patt_pair> (<table_sep> s <table_patt_pair>)*
         <table_sep>?
      |} s ("}" / %1 => error)
   ) -> tablePatt

   table_patt_pair <- {|
      ( {:name: <name> :} / {:expr: "[" s <expr> s "]" :} ) s
      "=" s {:value: <bind_left> :}
      / {:value: <bind_left> :}
   |}

   ident_list <- (
      <ident> (s "," s <ident>)*
   )

   expr_list <- (
      <expr> (s "," s <expr>)*
   )

   qname <- (
      (<ident> (s {"."} s <qname> / s {"::"} s <qname>)) / <ident>
   )

   func_decl <- (
      "func" <idsafe> s {| <qname> |} s <func_head> s <func_body>
   ) -> funcDecl

   func_head <- (
      "(" s {| <param_list>? |} s ")"
   )

   func_expr <- (
      "func" <idsafe> s <func_head> s <func_body>
      / (<func_head> / {| |}) s "=>" (s
         "{" s "=" s {| <expr_list> |} s ("}" / %1 => error)
         / <block_stmt>
      )
   ) -> funcExpr

   func_body <- <block_stmt>

   coro_expr <- (
      "func*" s <func_head> s <func_body>
      / "*" <func_head> s "=>" s (hs <expr> / <block_stmt> / %1 => error)
   ) -> coroExpr

   coro_decl <- (
      "func*" s {| <qname> |} s <func_head> s <func_body>
   ) -> coroDecl

   coro_prop <- (
      ({"get"/"set"} <idsafe> HS &<ident> / '' -> "init") "*" <ident> s
      <func_head> s <func_body>
   ) -> coroProp

   include_stmt <- (
      "include" <idsafe> s {| <expr_list> |}
   ) -> includeStmt

   module_decl <- (
      ({"var"} <idsafe> s / '' -> "package")
      "module" <idsafe> s <ident> s
      <class_body>
   ) -> moduleDecl

   class_decl <- (
      ({"var"} <idsafe> s / '' -> "package")
      "class" <idsafe> s <ident> (s <class_heritage>)? s
      <class_body>
   ) -> classDecl

   class_body <- {|
      "{" s (<class_body_stmt> (<sep> s <class_body_stmt>)* <sep>?)? s ("}" / %1 => error)
   |} -> classBody

   class_body_stmt <- (('' -> curline) (
      <class_member> / <include_stmt> / !<return_stmt> <stmt>
   )) -> stmt

   class_member <- (
      {| (<decorator> (s <decorator>)* s)? |} (
         <coro_prop> / <prop_defn>
      )
   ) -> classMember

   class_heritage <- (
      "extends" <idsafe> s <ident> / {| |}
   )

   prop_defn <- (
      ({"get"/"set"} <idsafe> HS &<ident> / '' -> "init") <ident> s
      <func_head> s <func_body>
   ) -> propDefn

   param <- {|
      {:name: <ident> :}
      (s ":" s {:guard: <expr> :})?
      (s "=" s {:default: <expr> :})?
   |}
   param_list <- (
        <param> s "," s <param_list>
      / <param> s "," s <param_rest>
      / <param>
      / <param_rest>
   )

   param_rest <- {| "..." {:name: <ident>? :} {:rest: '' -> 'true' :} |}

   block_stmt <- ("{" s
      {| (<stmt> (<sep> s <stmt>)* <sep>?)? |}
   s ("}" / %1 => error)
   ) -> blockStmt

   if_stmt <- (
      "if" <idsafe> s "(" s <expr> s (")" / %1 => error) s <block_stmt> s (
         "else" <idsafe> s (<if_stmt> / <block_stmt>)
      )
   ) -> ifStmt

   switch_stmt <- (
      "switch" <idsafe> s "(" s <expr> s ")" s "{" s
         ({| <switch_case>+ |} / %1 => error)
         (s "else" <idsafe> s <block_stmt>)? s
      ("}" / %1 => error)
   ) -> switchStmt

   switch_case <- (
      s "case" <idsafe> s "(" s (
           <array_patt>
         / <table_patt>
         / <expr>
      )
      {| (s "if" <idsafe> s <expr>)? |}
      s ")"
      s <block_stmt>
   ) -> switchCase

   for_stmt <- (
      "for" <idsafe> s "(" s <ident> s "=" s <expr> s "," s <expr>
      (s "," s <expr> / ('' -> '1') -> literalNumber) s ")" s
      <loop_body>
   ) -> forStmt

   for_in_stmt <- (
      "for" <idsafe> s "(" {| <ident_list> |} s <in> s <expr> s ")" s
      <loop_body>
   ) -> forInStmt

   loop_body <- "{" s <block_stmt> s ("}" / %1 => error)

   do_stmt <- <loop_body> -> doStmt

   ident <- (
      !<keyword> { <word> }
   ) -> identifier

   name <- (
      !<reserved> { <word> }
   ) -> identifier

   primary <- (('' -> curline) (
        <coro_expr>
      / <func_expr>
      / <nil_expr>
      / <super_expr>
      / <comp_expr>
      / <table_expr>
      / <array_expr>
      / <regex_expr>
      / <ident>
      / <literal>
      / <qstring>
      / "(" s <expr> s ")"
   ))

   term <- (
      <primary> {| (
         s {'.' / '::'} s <name>
         / { "[" } s <expr> s ("]" / %1 => error)
         / { "(" } s {| <expr_list>? |} s (")" / %1 => error)
      )* (
         {~ (hs &['"[{] / HS) -> "(" ~}
         {| <spread_expr> / !<binop> <expr_list> |}
      )? |}
   ) -> term

   expr <- (('' -> curline) (<in_expr> / <infix_expr> / <spread_expr>)) -> expr

   spread_expr <- (
      "..." <term>?
   ) -> spreadExpr

   in_expr <- (
      {| <ident_list> |} s "in" <idsafe> s <expr>
   ) -> inExpr

   nil_expr <- (
      "nil" <idsafe>
   ) -> nilExpr

   super_expr <- (
      "super" <idsafe>
   ) -> superExpr

   expr_stmt <- (
      ('' -> curline) <update_expr>
   ) -> exprStmt

   binop <- {
      "+" / "-" / "~" / "/" / "**" / "*" / "%" / "^" / "|" / "&"
      / ">>>" / ">>" / ">=" / ">" / "<<" / "<=" / "<" / ".."
      / "!=" / "==" / ":" [-~/*%^|&><!?=]
      / ("is" / "||" / "&&" / "as") <idsafe>
   }

   infix_expr  <- (
      {| <prefix_expr> (s <binop> s <prefix_expr>)* |}
   ) -> infixExpr

   prefix_expr <- (
      ({ "#" / "-" !'-' / "~" / "!" / "not" <idsafe> } s)? <term>
   ) -> prefixExpr

   assop <- {
      "+=" / "-=" / "~=" / "**=" / "*=" / "/=" / "%=" / "&&="
      / "|=" / "||=" / "&=" / "^=" / "<<=" / ">>>=" / ">>="
   }

   update_expr <- (
      <bind_left> {|
         (s {:oper: <assop> :} s {:expr: <expr> :})
         / ((s "," s <bind_left>)* s {:oper: {'=' !'>' / 'in' <idsafe>} :}
             s {:list: {| <expr_list> |} :})
      |}?
   ) -> updateExpr

   array_expr <- (
      "[" s {| <array_elements>? |} s ("]" / %1 => error)
   ) -> arrayExpr

   array_elements <- <expr> (s "," s <expr>)* (s ",")?

   table_expr <- (
      "{" s {| <table_entries>? |} s ("}" / %1 => error)
   ) -> tableExpr

   table_entries <- (
      <table_entry> (<table_sep> s <table_entry>)* <table_sep>?
   )

   table_entry <- {|
      ( {:name: <name> :} / {:expr: "[" s <expr> s "]" :} ) s
      "=" !'>' s {:value: <expr> :}
      / {:value: <expr> :}
   |} -> tableEntry

   comp_expr <- (
      "[" s <expr> {| (s <comp_block>)+ |} s ("]" / %1 => error)
   ) -> compExpr

   comp_block <- (
      "for" <idsafe> s {| <ident_list> |} s <in> s <expr>
      (s "if" <idsafe> s <expr>)? s
   ) -> compBlock

   regex_expr <- (
      "/" s (<patt_grammar> / <patt_expr>) s ("/" / %s => error)
   ) -> regexExpr

   grammar_decl <- (
      ({"var"} <idsafe> s / '' -> "package")
      "grammar" <idsafe> HS <ident> s "{" (s <grammar_body>)? s
      ("}" / %1 => error)
   ) -> grammarDecl

   grammar_body <- {|
      (<grammar_body_stmt> (<sep> s <grammar_body_stmt>)* <sep>?)?
   |}

   grammar_body_stmt <- (
      <patt_rule> / <class_body_stmt>
   )

   patt_expr <- (('' -> curline) <patt_alt>) -> pattExpr

   patt_grammar <- {|
      <patt_rule> (s <patt_rule>)*
   |} -> pattGrammar

   patt_rule <- (
      <patt_name> hs '<-' s <patt_expr>
   ) -> pattRule

   patt_sep <- '|' !'}'
   patt_alt <- {|
      <patt_seq> (s <patt_sep> s <patt_seq>)*
   |} -> pattAlt

   patt_seq <- {|
      (<patt_prefix> (s <patt_prefix>)*)?
   |} -> pattSeq

   patt_any <- '.' -> pattAny

   patt_prefix <- (
      <patt_assert> / <patt_suffix>
   )

   patt_assert  <- (
      {'&' / '!' } s <patt_prefix>
   ) -> pattAssert

   patt_suffix <- (
      <patt_primary> {| (s <patt_tail>)* |}
   ) -> pattSuffix

   patt_tail <- (
      <patt_opt> / <patt_rep> / <patt_prod>
   )

   patt_prod <- (
        {'~>'} s <term>
      / {'->'} s <term>
      / {'+>'} s <term>
   ) -> pattProd

   patt_opt <- (
      !'+>' { [+*?] }
   ) -> pattOpt

   patt_rep <- (
      '^' { [+-]? <patt_num> }
   ) -> pattRep

   patt_capt <- (
        <patt_capt_subst>
      / <patt_capt_const>
      / <patt_capt_group>
      / <patt_capt_table>
      / <patt_capt_basic>
      / <patt_capt_back>
      / <patt_capt_bref>
   )

   patt_capt_subst <- (
      '{~' s <patt_expr> s '~}'
   ) -> pattCaptSubst

   patt_capt_group <- (
      '{:' (<patt_name> ':')? s <patt_expr> s ':}'
   ) -> pattCaptGroup

   patt_capt_table <- (
      '{|' s <patt_expr> s '|}'
   ) -> pattCaptTable

   patt_capt_basic <- (
      '{' s <patt_expr> s '}'
   ) -> pattCaptBasic

   patt_capt_const <- (
      '{`' s <expr> s '`}'
   ) -> pattCaptConst

   patt_capt_back <- (
      '{=' s <patt_name> s '=}'
   ) -> pattCaptBack

   patt_capt_bref <- (
      '=' <patt_name>
   ) -> pattCaptBackRef

   patt_primary  <- (
      '(' s <patt_expr> s ')'
      / <patt_term>
      / <patt_class>
      / <patt_predef>
      / <patt_capt>
      / <patt_arg>
      / <patt_any>
      / <patt_ref>
      / '<{' s <expr> s '}>'
   )

   patt_ref <- (
      '<' <patt_name> '>'
   ) -> pattRef

   patt_arg <- (
      '%' { <patt_num> }
   ) -> pattArg

   patt_class <- (
      '[' {'^' / ''} {| <patt_item> (!']' <patt_item>)* |} ']'
   ) -> pattClass

   patt_item <- (
      <patt_predef> / <patt_range> / ({~ <escape> / . ~} -> pattTerm)
   )

   patt_term  <- (
      '"' ({~ (<escape> / <nl> / !'"' .)+ ~})* '"'
      / "'" ({~ (<nl> / !"'" .)+ ~})* "'"
   ) -> pattTerm

   patt_range   <- ({~ <escape> / . ~} '-' {~ <escape> / !"]" . ~}) -> pattRange
   patt_name    <- { [A-Za-z_][A-Za-z0-9_]* } -> pattName
   patt_num     <- [0-9]+

   patt_predef  <- '%' <patt_name> -> pattPredef

]=]

local grammar = re.compile(patt, defs)
local function parse(src, name, line, ...)
   return grammar:match(src, nil, name, line or 1, ...)
end

return {
   parse = parse
}
