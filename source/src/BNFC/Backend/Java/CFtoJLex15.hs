{-
    BNF Converter: Java JLex generator
    Copyright (C) 2004  Author:  Michael Pellauer

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
-}

{-
   **************************************************************
    BNF Converter Module

    Description   : This module generates the JLex input file. This
                    file is quite different than Alex or Flex.

    Author        : Michael Pellauer (pellauer@cs.chalmers.se),
                    Bjorn Bringert (bringert@cs.chalmers.se)

    License       : GPL (GNU General Public License)

    Created       : 25 April, 2003

    Modified      : 4 Nov, 2004


   **************************************************************
-}

module BNFC.Backend.Java.CFtoJLex15 ( cf2jlex ) where

import BNFC.CF
import BNFC.Backend.Java.RegToJLex
import BNFC.Utils (cstring)
import BNFC.Backend.Common.NamedVariables
import Text.PrettyPrint

--The environment must be returned for the parser to use.
cf2jlex :: Bool -> String -> CF -> (Doc, SymEnv)
cf2jlex jflex packageBase cf = (vcat
 [
  prelude jflex packageBase,
  cMacros,
  lexSymbols jflex env,
  restOfJLex cf
 ], env)
  where
   env = makeSymEnv (cfgSymbols cf ++ reservedWords cf) (0 :: Int)
   makeSymEnv [] _ = []
   makeSymEnv (s:symbs) n = (s, "_SYMB_" ++ show n) : makeSymEnv symbs (n+1)

-- | File prelude
prelude :: Bool -> String -> Doc
prelude jflex packageBase = vcat
    [ "// This JLex file was machine-generated by the BNF converter"
    , "package" <+> text packageBase <> ";"
    , ""
    , "import java_cup.runtime.*;"
    , "%%"
    , "%cup"
    , "%unicode"
    , "%line"
    , "%public"
    , "%{"
    , nest 2 $ vcat
        [ "String pstring = new String();"
        , "public int line_num() { return (yyline+1); }"
        , "public String buff()" <+> braces
            (if jflex
            then "return new String(zzBuffer,zzCurrentPos,10).trim();"
            else "return new String(yy_buffer,yy_buffer_index,10).trim();")
        ]
    , "%}"
    ]

--For now all categories are included.
--Optimally only the ones that are used should be generated.
cMacros :: Doc
cMacros = vcat [
  "LETTER = ({CAPITAL}|{SMALL})",
  "CAPITAL = [A-Z\\xC0-\\xD6\\xD8-\\xDE]",
  "SMALL = [a-z\\xDF-\\xF6\\xF8-\\xFF]",
  "DIGIT = [0-9]",
  "IDENT = ({LETTER}|{DIGIT}|['_])",
  "%state COMMENT",
  "%state CHAR",
  "%state CHARESC",
  "%state CHAREND",
  "%state STRING",
  "%state ESCAPED",
  "%%"
  ]

-- |
-- >>> lexSymbols False [("foo","bar")]
-- <YYINITIAL>foo { return new Symbol(sym.bar); }
-- >>> lexSymbols False [("\\","bar")]
-- <YYINITIAL>\\ { return new Symbol(sym.bar); }
-- >>> lexSymbols False [("/","bar")]
-- <YYINITIAL>/ { return new Symbol(sym.bar); }
-- >>> lexSymbols True [("/","bar")]
-- <YYINITIAL>\/ { return new Symbol(sym.bar); }
-- >>> lexSymbols True [("~","bar")]
-- <YYINITIAL>\~ { return new Symbol(sym.bar); }
lexSymbols :: Bool -> SymEnv -> Doc
lexSymbols jflex ss = vcat $  map transSym ss
  where
    transSym (s,r) =
      "<YYINITIAL>" <> text (escapeChars s) <> " { return new Symbol(sym."
      <> text r <> "); }"
    --Helper function that escapes characters in strings
    escapeChars :: String -> String
    escapeChars = concatMap (escapeChar jflex)

restOfJLex :: CF -> Doc
restOfJLex cf = vcat
    [ lexComments (comments cf)
    , ""
    , userDefTokens
    , ifC catString strStates
    , ifC catChar chStates
    , ifC catDouble
        "<YYINITIAL>{DIGIT}+\".\"{DIGIT}+(\"e\"(\\-)?{DIGIT}+)? { return new Symbol(sym._DOUBLE_, new Double(yytext())); }"
    , ifC catInteger
        "<YYINITIAL>{DIGIT}+ { return new Symbol(sym._INTEGER_, new Integer(yytext())); }"
    , ifC catIdent
        "<YYINITIAL>{LETTER}{IDENT}* { return new Symbol(sym._IDENT_, yytext().intern()); }"
    , "<YYINITIAL>[ \\t\\r\\n\\f] { /* ignore white space. */ }"
    ]
  where
    ifC cat s = if isUsedCat cf cat then s else ""
    userDefTokens = vcat
        [ "<YYINITIAL>" <> text (printRegJLex exp)
            <+> "{ return new Symbol(sym." <> text (show name)
            <> ", yytext().intern()); }"
        | (name, exp) <- tokenPragmas cf ]
    strStates = vcat --These handle escaped characters in Strings.
        [ "<YYINITIAL>\"\\\"\" { yybegin(STRING); }"
        , "<STRING>\\\\ { yybegin(ESCAPED); }"
        , "<STRING>\\\" { String foo = pstring; pstring = new String(); yybegin(YYINITIAL); return new Symbol(sym._STRING_, foo.intern()); }"
        , "<STRING>.  { pstring += yytext(); }"
        , "<ESCAPED>n { pstring +=  \"\\n\"; yybegin(STRING); }"
        , "<ESCAPED>\\\" { pstring += \"\\\"\"; yybegin(STRING); }"
        , "<ESCAPED>\\\\ { pstring += \"\\\\\"; yybegin(STRING); }"
        , "<ESCAPED>t  { pstring += \"\\t\"; yybegin(STRING); }"
        , "<ESCAPED>.  { pstring += yytext(); yybegin(STRING); }"
        ]
    chStates = vcat --These handle escaped characters in Chars.
        [ "<YYINITIAL>\"'\" { yybegin(CHAR); }"
        , "<CHAR>\\\\ { yybegin(CHARESC); }"
        , "<CHAR>[^'] { yybegin(CHAREND); return new Symbol(sym._CHAR_, new Character(yytext().charAt(0))); }"
        , "<CHARESC>n { yybegin(CHAREND); return new Symbol(sym._CHAR_, new Character('\\n')); }"
        , "<CHARESC>t { yybegin(CHAREND); return new Symbol(sym._CHAR_, new Character('\\t')); }"
        , "<CHARESC>. { yybegin(CHAREND); return new Symbol(sym._CHAR_, new Character(yytext().charAt(0))); }"
        , "<CHAREND>\"'\" {yybegin(YYINITIAL);}"
        ]

lexComments :: ([(String, String)], [String]) -> Doc
lexComments (m,s) =
    vcat (map lexSingleComment s ++ map lexMultiComment m)

-- | Create lexer rule for single-line comments.
--
-- >>> lexSingleComment "--"
-- <YYINITIAL>"--"[^\n]*\n { /* skip */ }
--
-- >>> lexSingleComment "\""
-- <YYINITIAL>"\""[^\n]*\n { /* skip */ }
lexSingleComment :: String -> Doc
lexSingleComment c =
  "<YYINITIAL>" <> cstring c <>  "[^\\n]*\\n { /* skip */ }"

-- | Create lexer rule for multi-lines comments.
--
-- There might be a possible bug here if a language includes 2 multi-line
-- comments. They could possibly start a comment with one character and end it
-- with another. However this seems rare.
--
-- >>> lexMultiComment ("{-", "-}")
-- <YYINITIAL>"{-" { yybegin(COMMENT); }
-- <COMMENT>"-}" { yybegin(YYINITIAL); }
-- <COMMENT>. { /* skip */ }
-- <COMMENT>[\n] { /* skip */ }
--
-- >>> lexMultiComment ("\"'", "'\"")
-- <YYINITIAL>"\"'" { yybegin(COMMENT); }
-- <COMMENT>"'\"" { yybegin(YYINITIAL); }
-- <COMMENT>. { /* skip */ }
-- <COMMENT>[\n] { /* skip */ }
lexMultiComment :: (String, String) -> Doc
lexMultiComment (b,e) = vcat
    [ "<YYINITIAL>" <> cstring b <+> "{ yybegin(COMMENT); }"
    , "<COMMENT>" <> cstring e <+> "{ yybegin(YYINITIAL); }"
    , "<COMMENT>. { /* skip */ }"
    , "<COMMENT>[\\n] { /* skip */ }"
    ]
