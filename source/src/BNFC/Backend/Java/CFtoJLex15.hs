{-# LANGUAGE NoImplicitPrelude #-}

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

import Prelude'

import BNFC.CF
import BNFC.Backend.Common.NamedVariables
import BNFC.Backend.Java.RegToJLex
import BNFC.Options (JavaLexerParser(..), RecordPositions(..))
import BNFC.Utils (cstring)
import Text.PrettyPrint

--The environment must be returned for the parser to use.
cf2jlex :: JavaLexerParser -> RecordPositions -> String -> CF -> (Doc, SymEnv)
cf2jlex jflex rp packageBase cf = (vcat
 [
  prelude jflex rp packageBase,
  cMacros,
  lexSymbols jflex env,
  restOfJLex jflex rp cf
 ], env)
  where
   env = makeSymEnv (cfgSymbols cf ++ reservedWords cf) (0 :: Int)
   makeSymEnv [] _ = []
   makeSymEnv (s:symbs) n = (s, "_SYMB_" ++ show n) : makeSymEnv symbs (n+1)

-- | File prelude
prelude :: JavaLexerParser -> RecordPositions -> String -> Doc
prelude jflex rp packageBase = vcat
    [ "// This JLex file was machine-generated by the BNF converter"
    , "package" <+> text packageBase <> ";"
    , ""
    , "import java_cup.runtime.*;"
    , "%%"
    , "%cup"
    , "%unicode"
    , (if rp == RecordPositions
      then vcat
        [ "%line"
        , (if jflex == JFlexCup then "%column" else "")
        , "%char" ]
      else "")
    , "%public"
    , "%{"
    , nest 2 $ vcat
        [ "String pstring = new String();"
        , "final int unknown = -1;"
        , "ComplexSymbolFactory.Location left = new ComplexSymbolFactory.Location(unknown, unknown);"
        , "ComplexSymbolFactory cf = new ComplexSymbolFactory();"
        , "public SymbolFactory getSymbolFactory() { return cf; }"
        , positionDeclarations
        , "public int line_num() { return (yyline+1); }"
        , "public ComplexSymbolFactory.Location left_loc() {"
        , if rp == RecordPositions
            then "  return new ComplexSymbolFactory.Location(yyline+1, yycolumn+1, yychar);"
            else "  return left;"
        , "}"
        , "public ComplexSymbolFactory.Location right_loc() {"
        , "  ComplexSymbolFactory.Location left = left_loc();"
        , (if rp == RecordPositions
            then "return new ComplexSymbolFactory.Location(left.getLine(), left.getColumn()+yylength(), left.getOffset()+yylength());"
            else "return left;")
        , "}"
        , "public String buff()" <+> braces
            (if jflex == JFlexCup
            then "return new String(zzBuffer,zzCurrentPos,10).trim();"
            else "return new String(yy_buffer,yy_buffer_index,10).trim();")
        ]
    , "%}"
    , if jflex /= JFlexCup then vcat ["%eofval{"
      , "  return cf.newSymbol(\"EOF\", sym.EOF, left_loc(), left_loc());"
      , "%eofval}"]
        else ""
    ]
  where
    positionDeclarations =
      -- JFlex always defines yyline, yychar, yycolumn, even if unused.
      if jflex == JFlexCup then ""
        else if rp == RecordPositions then "int yycolumn = unknown - 1;"
          else vcat
            -- subtract one so that one based numbering still ends up with unknown.
            [ "int yyline = unknown - 1;"
            , "int yycolumn = unknown - 1;"
            , "int yychar = unknown;" ]

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
-- >>> lexSymbols JLexCup [("foo","bar")]
-- <YYINITIAL>foo { return cf.newSymbol("", sym.bar, left_loc(), right_loc()); }
-- >>> lexSymbols JLexCup [("\\","bar")]
-- <YYINITIAL>\\ { return cf.newSymbol("", sym.bar, left_loc(), right_loc()); }
-- >>> lexSymbols JLexCup [("/","bar")]
-- <YYINITIAL>/ { return cf.newSymbol("", sym.bar, left_loc(), right_loc()); }
-- >>> lexSymbols JFlexCup [("/","bar")]
-- <YYINITIAL>\/ { return cf.newSymbol("", sym.bar, left_loc(), right_loc()); }
-- >>> lexSymbols JFlexCup [("~","bar")]
-- <YYINITIAL>\~ { return cf.newSymbol("", sym.bar, left_loc(), right_loc()); }
lexSymbols :: JavaLexerParser -> SymEnv -> Doc
lexSymbols jflex ss = vcat $  map transSym ss
  where
    transSym (s,r) =
      "<YYINITIAL>" <> text (escapeChars s) <> " { return cf.newSymbol(\"\", sym."
      <> text r <> ", left_loc(), right_loc()); }"
    --Helper function that escapes characters in strings
    escapeChars :: String -> String
    escapeChars = concatMap (escapeChar jflex)

restOfJLex :: JavaLexerParser -> RecordPositions -> CF -> Doc
restOfJLex jflex rp cf = vcat
    [ lexComments (comments cf)
    , ""
    , userDefTokens
    , ifC catString strStates
    , ifC catChar chStates
    , ifC catDouble
        "<YYINITIAL>{DIGIT}+\".\"{DIGIT}+(\"e\"(\\-)?{DIGIT}+)? { return cf.newSymbol(\"\", sym._DOUBLE_, left_loc(), right_loc(), new Double(yytext())); }"
    , ifC catInteger
        "<YYINITIAL>{DIGIT}+ { return cf.newSymbol(\"\", sym._INTEGER_, left_loc(), right_loc(), new Integer(yytext())); }"
    , ifC catIdent
        "<YYINITIAL>{LETTER}{IDENT}* { return cf.newSymbol(\"\", sym._IDENT_, left_loc(), right_loc(), yytext().intern()); }"
    , "<YYINITIAL>[ \\t\\r\\n\\f] { /* ignore white space. */ }"
    , if jflex == JFlexCup
        then "<<EOF>> { return cf.newSymbol(\"EOF\", sym.EOF, left_loc(), left_loc()); }"
        else ""
    , if rp == RecordPositions
        then ". { throw new Error(\"Illegal Character <\"+yytext()+\"> at \"+(yyline+1)" <>
          (if jflex == JFlexCup then "+\":\"+(yycolumn+1)+\"(\"+yychar+\")\"" else "") <> "); }"
        else ". { throw new Error(\"Illegal Character <\"+yytext()+\">\"); }"
    ]
  where
    ifC cat s = if isUsedCat cf cat then s else ""
    userDefTokens = vcat
        [ "<YYINITIAL>" <> text (printRegJLex exp)
            <+> "{ return cf.newSymbol(\"\", sym." <> text (show name)
            <> ", left_loc(), right_loc(), yytext().intern()); }"
        | (name, exp) <- tokenPragmas cf ]
    strStates = vcat --These handle escaped characters in Strings.
        [ "<YYINITIAL>\"\\\"\" { left = left_loc(); yybegin(STRING); }"
        , "<STRING>\\\\ { yybegin(ESCAPED); }"
        , "<STRING>\\\" { String foo = pstring; pstring = new String(); yybegin(YYINITIAL); return cf.newSymbol(\"\", sym._STRING_, left, right_loc(), foo.intern()); }"
        , "<STRING>.  { pstring += yytext(); }"
        , "<STRING>\\r\\n|\\r|\\n { throw new Error(\"Unterminated string on line \" + left.getLine() " <>
          (if jflex == JFlexCup then "+ \" begining at column \" + left.getColumn()" else "") <> "); }"
        , if jflex == JFlexCup 
          then "<STRING><<EOF>> { throw new Error(\"Unterminated string at EOF, beginning at \" + left.getLine() + \":\" + left.getColumn()); }"
          else ""
        , "<ESCAPED>n { pstring +=  \"\\n\"; yybegin(STRING); }"
        , "<ESCAPED>\\\" { pstring += \"\\\"\"; yybegin(STRING); }"
        , "<ESCAPED>\\\\ { pstring += \"\\\\\"; yybegin(STRING); }"
        , "<ESCAPED>t  { pstring += \"\\t\"; yybegin(STRING); }"
        , "<ESCAPED>.  { pstring += yytext(); yybegin(STRING); }"
        , "<ESCAPED>\\r\\n|\\r|\\n { throw new Error(\"Unterminated string on line \" + left.getLine() " <>
          (if jflex == JFlexCup then "+ \" beginning at column \" + left.getColumn()" else "") <> "); }"
        , if jflex == JFlexCup
          then "<ESCAPED><<EOF>> { throw new Error(\"Unterminated string at EOF, beginning at \" + left.getLine() + \":\" + left.getColumn()); }"
          else ""
        ]
    chStates = vcat --These handle escaped characters in Chars.
        [ "<YYINITIAL>\"'\" { left = left_loc(); yybegin(CHAR); }"
        , "<CHAR>\\\\ { yybegin(CHARESC); }"
        , "<CHAR>[^'] { yybegin(CHAREND); return cf.newSymbol(\"\", sym._CHAR_, left, right_loc(), new Character(yytext().charAt(0))); }"
        , "<CHAR>\\r\\n|\\r|\\n { throw new Error(\"Unterminated character literal on line \" + left.getLine() " <>
          (if jflex == JFlexCup then "+ \" beginning at column \" + left.getColumn()" else "") <> "); }"
        , if jflex == JFlexCup
          then "<CHAR><<EOF>> { throw new Error(\"Unterminated character literal at EOF, beginning at \" + left.getLine() + \":\" + left.getColumn()); }"
          else ""
        , "<CHARESC>n { yybegin(CHAREND); return cf.newSymbol(\"\", sym._CHAR_, left, right_loc(), new Character('\\n')); }"
        , "<CHARESC>t { yybegin(CHAREND); return cf.newSymbol(\"\", sym._CHAR_, left, right_loc(), new Character('\\t')); }"
        , "<CHARESC>. { yybegin(CHAREND); return cf.newSymbol(\"\", sym._CHAR_, left, right_loc(), new Character(yytext().charAt(0))); }"
        , "<CHARESC>\\r\\n|\\r|\\n { throw new Error(\"Unterminated character literal on line \" + left.getLine() " <>
          (if jflex == JFlexCup then "+ \" beginning at column \" + left.getColumn()" else "") <> "); }"
        , if jflex == JFlexCup
          then "<CHARESC><<EOF>> { throw new Error(\"Unterminated character literal at EOF, beginning at \" + left.getLine() + \":\" + left.getColumn()); }"
          else ""
        , "<CHAREND>\"'\" {yybegin(YYINITIAL);}"
        , "<CHAREND>\\r\\n|\\r|\\n { throw new Error(\"Unterminated character literal on line \" + left.getLine() " <>
          (if jflex == JFlexCup then "+ \" beginning at column \" + left.getColumn()" else "") <> "); }"
        , if jflex == JFlexCup
          then "<CHAREND><<EOF>> { throw new Error(\"Unterminated character literal at EOF, beginning at \" + left.getLine() + \":\" + left.getColumn()); }"
          else ""
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
