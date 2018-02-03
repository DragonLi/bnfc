{-
    BNF Converter: Latex Generator
    Copyright (C) 2004  Author:  Markus Forberg, Aarne Ranta

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
module BNFC.Backend.Latex where

import Data.List
import Data.Monoid
import System.FilePath ((<.>),replaceExtension)
import Text.Printf

import AbsBNF (Reg (..))
import BNFC.Options hiding (Backend)
import BNFC.Backend.Base
import BNFC.Backend.Common.Makefile as Makefile
import BNFC.CF
import BNFC.Utils
import BNFC.PrettyPrint hiding ((<.>), empty)

-- | Entry point: create .tex file and a Makefile to compile it.
makeLatex :: SharedOptions -> CF -> Backend
makeLatex opts cf = do
    let texfile = name <.> "tex"
    mkfile texfile (cfToLatex name cf)
    Makefile.mkMakefile opts (makefile texfile)
  where name = lang opts

-- | Create a makefile for the given tex file
--
-- >>> makefile "myFile.tex"
-- all: myFile.pdf
-- <BLANKLINE>
-- myFile.pdf: myFile.tex
-- 	pdflatex myFile.tex
-- <BLANKLINE>
-- clean:
-- 	-rm myFile.pdf myFile.aux myFile.log
-- <BLANKLINE>
-- cleanall: clean
-- 	-rm Makefile myFile.tex
-- <BLANKLINE>
makefile :: String -> Doc
makefile texfile = vcat
    [ Makefile.mkRule "all" [pdffile]
        []
    , Makefile.mkRule pdffile [texfile]
        [ printf "pdflatex %s" texfile ]
    , Makefile.mkRule "clean" []
        [ unwords [ "-rm", pdffile, auxfile, logfile ]]
    , Makefile.mkRule "cleanall" ["clean"]
        [ "-rm Makefile " ++ texfile ]
    ]
  where pdffile = replaceExtension texfile "pdf"
        auxfile = replaceExtension texfile "aux"
        logfile = replaceExtension texfile "log"

-- | Create content of .tex file.
cfToLatex :: String -> CF -> String
cfToLatex name cf = unlines
  -- Overall structure of created LaTeX document:
  [ "\\batchmode"
  , beginDocument name
  , macros
  , introduction
  , prtTerminals name cf
  , prtBNF name cf
  , endDocument
  ]

introduction :: String
introduction = unlines
  [ "This document was automatically generated by the {\\em BNF-Converter}."
  , "It was generated together with the lexer, the parser, and the"
  , "abstract syntax module, which guarantees that the document"
  , "matches with the implementation of the language"
  , "(provided no hand-hacking has taken place)."
  ]

prtTerminals :: String -> CF -> String
prtTerminals name cf = unlines $
  [ "\\section*{The lexical structure of " ++ name ++ "}"
  , ""
  ] ++ identSection cf ++
  [ "\\subsection*{Literals}"
  , prtLiterals name cf
  ] ++ map prtOwnToken (tokenPragmas cf) ++
  [ "\\subsection*{Reserved words and symbols}"
  , prtReserved name cf
  , prtSymb name cf
  , "\\subsection*{Comments}"
  , prtComments $ comments cf
  ]

identSection :: CF -> [String]
identSection cf
  | hasIdent cf = [ "\\subsection*{Identifiers}" ] ++ prtIdentifiers
  | otherwise   = []

prtIdentifiers :: [String]
prtIdentifiers =
  [ "Identifiers \\nonterminal{Ident} are unquoted strings beginning with a letter,"
  , "followed by any combination of letters, digits, and the characters {\\tt \\_ '},"
  , "reserved words excluded."
  ]

prtLiterals :: String -> CF -> String
prtLiterals _ cf =
  unlines $ map stringLit $
    filter (`notElem` [Cat "Ident"]) $
      literals cf

stringLit :: Cat -> String
stringLit cat = unlines $ case cat of
  Cat "Char" -> ["Character literals \\nonterminal{Char}\\ have the form",
                 "\\terminal{'}$c$\\terminal{'}, where $c$ is any single character.",
                 ""
                ]
  Cat "String" -> ["String literals \\nonterminal{String}\\ have the form",
                 "\\terminal{\"}$x$\\terminal{\"}, where $x$ is any sequence of any characters",
                 "except \\terminal{\"}\\ unless preceded by \\verb6\\6.",
                 ""]
  Cat "Integer" -> ["Integer literals \\nonterminal{Int}\\ are nonempty sequences of digits.",
                 ""]
  Cat "Double" -> ["Double-precision float literals \\nonterminal{Double}\\ have the structure",
                   "indicated by the regular expression" +++
                      "$\\nonterminal{digit}+ \\mbox{{\\it `.'}} \\nonterminal{digit}+ (\\mbox{{\\it `e'}} \\mbox{{\\it `-'}}? \\nonterminal{digit}+)?$ i.e.\\",
                   "two sequences of digits separated by a decimal point, optionally",
                   "followed by an unsigned or negative exponent.",
                   ""]
  _ -> []

prtOwnToken (name,reg) = unlines
  [ show name +++ "literals are recognized by the regular expression",
   "\\(" ++
   latexRegExp reg ++
   "\\)"
  ]

prtComments :: ([(String,String)],[String]) -> String
prtComments (xs,ys) =
    (if null ys
        then "There are no single-line comments in the grammar. \\\\"
        else "Single-line comments begin with " ++ sing ++". \\\\")
    ++
    (if null xs
        then "There are no multiple-line comments in the grammar."
        else "Multiple-line comments are  enclosed with " ++ mult ++".")
 where
 sing = intercalate ", " $ map (symbol.prt) ys
 mult = intercalate ", " $
         map (\(x,y) -> symbol (prt x)
                       ++ " and " ++
                      symbol (prt y)) xs

prtSymb :: String -> CF -> String
prtSymb name cf = case cfgSymbols cf of
                   [] -> "\nThere are no symbols in " ++ name ++ ".\\\\\n"
                   xs -> "The symbols used in " ++ name ++ " are the following: \\\\\n"
                         ++
                         tabular 3 (three $ map (symbol.prt) xs)

prtReserved :: String -> CF -> String
prtReserved name cf = case reservedWords cf of
                       [] -> stringRes name ++
                             "\nThere are no reserved words in " ++ name ++ ".\\\\\n"
                       xs -> stringRes name ++
                             tabular 3 (three $ map (reserved.prt) xs)

stringRes :: String -> String
stringRes name = concat
                 ["The set of reserved words is the set of terminals ",
                  "appearing in the grammar. Those reserved words ",
                  "that consist of non-letter characters are called symbols, and ",
                  "they are treated in a different way from those that ",
                  "are similar to identifiers. The lexer ",
                  "follows rules familiar from languages ",
                  "like Haskell, C, and Java, including longest match ",
                  "and spacing conventions.",
                  "\n\n",
                  "The reserved words used in " ++ name ++ " are the following: \\\\\n"]

-- | Group a list into blocks of 3 elements.
three :: Monoid a => [a] -> [[a]]
three []         = []
three [x]        = [[x,mempty,mempty]]
three [x,y]      = [[x,y,mempty]]
three (x:y:z:xs) = [x,y,z] : three xs

prtBNF :: String -> CF -> String
prtBNF name cf = unlines
  [ "\\section*{The syntactic structure of " ++ name ++ "}"
  , ""
  , "Non-terminals are enclosed between $\\langle$ and $\\rangle$. "
  , "The symbols " ++ arrow ++ " (production), " ++ delimiter ++ " (union) "
  , "and " ++ empty ++ " (empty rule) belong to the BNF notation. "
  , "All other symbols are terminals.\\\\"
  , prtRules (ruleGroups cf)
  ]

prtRules :: [(Cat,[Rule])] -> String
prtRules          [] = []
prtRules ((c,[]):xs)
    = tabular 3 [[nonterminal c,arrow,[]]] ++ prtRules xs
prtRules ((c, r : rs) : xs)
    = tabular 3 ([nonterminal c,arrow,prtSymbols $ rhsRule r] :
                 [[[],delimiter,prtSymbols (rhsRule y)] | y <-  rs]) ++
      prtRules xs

prtSymbols :: [Either Cat String] -> String
prtSymbols [] = empty
prtSymbols xs = foldr ((+++) . p) [] xs
 where p (Left  r) = nonterminal r --- (prt r)
       p (Right r) = terminal    (prt r)


prt :: String -> String
prt = concatMap escape
  where escape '\\'                               = "$\\backslash$"
        escape '~'                                = "\\~{}"
        escape '^'                                = "{\\textasciicircum}"
        escape c | c `elem` ("$&%#_{}" :: String) = ['\\', c]
        escape c | c `elem` ("+=|<>-" :: String)  = "{$"  ++ [c] ++ "$}"
        escape c                                  = [c]

macros :: String
macros = unlines
  [ "\\newcommand{\\emptyP}{\\mbox{$\\epsilon$}}"
  , "\\newcommand{\\terminal}[1]{\\mbox{{\\texttt {#1}}}}"
  , "\\newcommand{\\nonterminal}[1]{\\mbox{$\\langle \\mbox{{\\sl #1 }} \\! \\rangle$}}"
  , "\\newcommand{\\arrow}{\\mbox{::=}}"
  , "\\newcommand{\\delimit}{\\mbox{$|$}}"
  , "\\newcommand{\\reserved}[1]{\\mbox{{\\texttt {#1}}}}"
  , "\\newcommand{\\literal}[1]{\\mbox{{\\texttt {#1}}}}"
  , "\\newcommand{\\symb}[1]{\\mbox{{\\texttt {#1}}}}"
  ]

reserved :: String -> String
reserved s = "{\\reserved{" ++ s ++ "}}"

literal :: String -> String
literal s = "{\\literal{" ++ s ++ "}}"

empty :: String
empty = "{\\emptyP}"

symbol :: String -> String
symbol s = "{\\symb{" ++ s ++ "}}"

tabular :: Int -> [[String]] -> String
tabular n xs = "\n\\begin{tabular}{" ++ concat (replicate n "l") ++ "}\n" ++
               concatMap (\(a:as) -> foldr (+++) "\\\\\n" (a: map ('&':) as)) xs ++
               "\\end{tabular}\\\\\n"

terminal :: String -> String
terminal s = "{\\terminal{" ++ s ++ "}}"

nonterminal :: Cat -> String
nonterminal s = "{\\nonterminal{" ++ mkId (identCat s) ++ "}}" where
 mkId = map mk
 mk c = case c of
   '_' -> '-' ---
   _ -> c


arrow :: String
arrow = " {\\arrow} "

delimiter :: String
delimiter = " {\\delimit} "

beginDocument :: String -> String
beginDocument name = unlines
 [ "%This Latex file is machine-generated by the BNF-converter"
 , ""
 , "\\documentclass[a4paper,11pt]{article}"
 -- "\\usepackage{isolatin1}"
 , "\\setlength{\\parindent}{0mm}"
 , "\\setlength{\\parskip}{1mm}"
 , ""
 , "\\title{The Language " ++ name ++ "}"
 , "\\author{BNF-converter}"
 , ""
 , "\\begin{document}"
 , "\\maketitle"
 , ""
 ]

endDocument :: String
endDocument = unlines
  [ ""
  , "\\end{document}"
  ]

latexRegExp :: Reg -> String
latexRegExp = rex 0
  where
  rex :: Int -> Reg -> String
  rex i = \case
    RSeq r0 r   -> ifPar i 2 $ rex 2 r0 +++ rex 2 r
    RAlt r0 r   -> ifPar i 1 $ rex 1 r0 +++ "\\mid" +++ rex 1 r
    RMinus r0 r -> ifPar i 1 $ rex 2 r0 +++ "-" +++ rex 2 r
    RStar r     -> rex 3 r ++ "*"
    RPlus r     -> rex 3 r ++ "+"
    ROpt r      -> rex 3 r ++ "?"
    REps        -> "\\epsilon"
    RChar c     -> "\\mbox{`" ++ prt [c] ++ "'}"
    RAlts s     -> "[" ++ "\\mbox{``" ++ prt s ++ "''}" ++ "]"
    RSeqs s     -> "\\{" ++ "\\mbox{``" ++ prt s ++ "''}" ++ "\\}"
    RDigit      -> "{\\nonterminal{digit}}"
    RLetter     -> "{\\nonterminal{letter}}"
    RUpper      -> "{\\nonterminal{upper}}"
    RLower      -> "{\\nonterminal{lower}}"
    RAny        -> "{\\nonterminal{anychar}}"
  ifPar i j s = if i > j then "(" ++ s ++ ")" else s
