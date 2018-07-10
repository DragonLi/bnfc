{-
    BNF Converter: C# Abstract Syntax Generator
    Copyright (C) 2006-2007  Author:  Johan Broberg

    Modified from CFtoSTLAbs

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

    Description   : This module generates the C# Abstract Syntax
                    tree classes. It uses the Visitor design
                    pattern.

    Author        : Johan Broberg (johan@pontemonti.com)

    License       : GPL (GNU General Public License)

    Created       : 22 November, 2006

    Modified      : 21 January, 2007 by Johan Broberg

   **************************************************************
-}

module BNFC.Backend.CSharp.CAbstoCSharpAbs (cabs2csharpabs) where

import BNFC.Backend.Common.OOAbstract
import BNFC.CF
import BNFC.Utils((+++))
import Data.List
import Data.Maybe
import BNFC.Backend.CSharp.CSharpUtils

--The result is one file (.cs)

cabs2csharpabs :: Namespace -> CAbs -> Bool -> String
cabs2csharpabs namespace cabs useWCF = unlinesInline [
  "//C# Abstract Syntax Interface generated by the BNF Converter.",
  -- imports
  "using System;",
  if useWCF then "using System.Runtime.Serialization;" else "",
  "using System.Collections.Generic;",
  "namespace " ++ namespace ++ ".Absyn",
  "{",
  "  #region Token Classes",
  prTokenBaseType useWCF,
  unlinesInlineMap (prToken namespace useWCF) (tokentypes cabs),
  "  #endregion",
  "  ",
  "  #region Abstract Syntax Classes",
  unlinesInlineMap (prAbs namespace useWCF) abstractclasses,
  "  ",
  unlinesInlineMap (prCon namespace useWCF) (flattenSignatures cabs),
  "  ",
  "  #region Lists",
  unlinesInlineMap (prList namespace) (listtypes cabs),
  "  #endregion",
  "  #endregion",
  "}"
 ]
  where
    -- an abstract class is a category which does not contain rules
      abstractclasses = [ (cat, map fst cabsrules) | (cat, cabsrules) <- signatures cabs, cat `notElem` map fst cabsrules ]

-- auxiliaries

prDataContract :: Bool -> [String] -> String
prDataContract False _   = ""
prDataContract True []   = "  [DataContract]"
prDataContract True funs = unlinesInline [
  prDataContract True [],
  unlinesInline $ map prDataContract' funs
  ]
  where
    prDataContract' :: String -> String
    prDataContract' fun = "  [KnownType(typeof(" ++ fun ++ "))]"

prDataMember :: Bool -> String
prDataMember False = ""
prDataMember True  = "    [DataMember]"

prTokenBaseType :: Bool -> String
prTokenBaseType useWCF =  unlinesInline [
  prDataContract useWCF [],
  "  public class TokenBaseType",
  "  {",
  prDataMember useWCF,
  "    private string str;",
  "    ",
  "    public TokenBaseType(string str)",
  "    {",
  "      this.str = str;",
  "    }",
  "    ",
  "    public override string ToString()",
  "    {",
  "      return this.str;",
  "    }",
  "  }",
  "  "
  ]

prToken :: Namespace -> Bool -> String -> String
prToken namespace useWCF name = unlinesInline [
  prDataContract useWCF [],
  "  public class " ++ name ++ " : " ++ identifier namespace "TokenBaseType",
  "  {",
  "    public " ++ name ++ "(string str) : base(str)",
  "    {",
  "    }",
  prAccept namespace name Nothing,
  prVisitor namespace [name],
  prEquals namespace name ["ToString()"],
  prHashCode namespace name ["ToString()"],
  "  }"
  ]

prAbs :: Namespace -> Bool -> (String, [String]) -> String
prAbs namespace useWCF (cat, funs) = unlinesInline [
  prDataContract useWCF funs,
  "  public abstract class " ++ cat,
  "  {",
  "    public abstract R Accept<R,A>(" ++ identifier namespace cat ++ ".Visitor<R,A> v, A arg);",
  prVisitor namespace funs,
  "  }"
  ]

prVisitor :: Namespace -> [String] -> String
prVisitor namespace funs = unlinesInline
  [ "    "
  , "    public interface Visitor<R,A>"
  , "    {"
  , unlinesInline (map prVisitFun funs)
  , "    }"
  ]
  where
    prVisitFun f = "      R Visit(" ++ identifier namespace f ++ " p, A arg);"

prCon :: Namespace -> Bool -> (String,CSharpAbsRule) -> String
prCon namespace useWCF (c,(f,cs)) = unlinesInline [
  prDataContract useWCF [],
  "  public class " ++ f ++ ext,
  "  {",
  -- Instance variables
  unlines [prInstVar typ var | (typ,_,var,_) <- cs],
  prConstructor namespace (f,cs),
  unlinesInline [prProperty typ var prop | (typ,_,var,prop) <- cs],
  prEquals namespace f propnames,
  prHashCode namespace f propnames,
  -- print Accept method, override keyword needed for classes inheriting an abstract class
  prAccept namespace c (if isAlsoCategory f c then Nothing else Just " override"),
  -- if this label is also a category, we need to print the Visitor interface
  -- (if not, it was already printed in the abstract class)
  if isAlsoCategory f c then prVisitor namespace [c] else "",
  "  }"
  ]
  where
    -- This handles the case where a LBNF label is the same as the category.
    ext = if isAlsoCategory f c then "" else " : " ++ identifier namespace (identCat $ strToCat c)
    propnames = [prop | (_, _, _, prop) <- cs]
    prInstVar typ var = unlinesInline [
      "    private " ++ identifier namespace (typename typ) +++ var ++ ";"
      ]
    prProperty typ var prop = unlinesInline [
      "    ",
      prDataMember useWCF,
      "    public " ++ identifier namespace (typename typ) +++ prop,
      "    {",
      "      get",
      "      {",
      "        return this." ++ var ++ ";",
      "      }",
      "      set",
      "      {",
      "        this." ++ var ++ " = value;",
      "      }",
      "    }"
      ]

-- Creates the Equals() methods
prEquals :: Namespace -> Fun -> [String] -> String
prEquals namespace c vars = unlinesInline [
  "    ",
  "    public override bool Equals(Object obj)",
  "    {",
  "      if(this == obj)",
  "      {",
  "        return true;",
  "      }",
  "      if(obj is " ++ identifier namespace c ++ ")",
  "      {",
  "        return this.Equals((" ++ identifier namespace c ++ ")obj);",
  "      }",
  "      return base.Equals(obj);",
  "    }",
  "    ",
  "    public bool Equals(" ++ identifier namespace c ++ " obj)",
  "    {",
  "      if(this == obj)",
  "      {",
  "        return true;",
  "      }",
  "      return " ++ prEqualsVars vars ++ ";",
  "    }"
  ]
  where
    prEqualsVars [] = "true"
    prEqualsVars vs = intercalate " && " $ map equalVar vs
    equalVar v = "this." ++ v ++ ".Equals(obj." ++ v ++ ")"

-- Creates the GetHashCode() method.
prHashCode :: Namespace -> Fun -> [String] -> String
prHashCode _ _ vars = unlinesInline [
  "    ",
  "    public override int GetHashCode()",
  "    {",
  "      return " ++ prHashVars vars ++ ";",
  "    }"
  ]
  where
    aPrime = 37
    prHashVars [] = show aPrime
    prHashVars (v:vs) =
        foldl (\ r v -> show aPrime ++ "*" ++ "(" ++ r ++ ")+" ++ hashVar v) (hashVar v) vs
    hashVar var = "this." ++ var ++ ".GetHashCode()"

prList :: Namespace -> (String,Bool) -> String
prList namespace (c,_) = unlinesInline [
  "  public class " ++ c ++ " : List<" ++ identifier namespace (typename bas) ++ ">",
  "  {",
  "  }"
  ]
  where
    bas = drop 4 c -- drop List

-- The standard Accept method for the Visitor pattern
prAccept :: Namespace -> String -> Maybe String -> String
prAccept namespace cat maybeOverride = unlinesInline [
  "    ",
  "    public" ++ fromMaybe "" maybeOverride ++ " R Accept<R,A>(" ++ identifier namespace cat ++ ".Visitor<R,A> visitor, A arg)",
  "    {",
  "      return visitor.Visit(this, arg);",
  "    }"
  ]

-- The constructor assigns the parameters to the corresponding instance variables.
prConstructor :: Namespace -> CSharpAbsRule -> String
prConstructor namespace (f,cs) = unlinesInline [
  "    public " ++ f ++ "(" ++ conargs ++ ")",
  "    {",
  unlinesInline ["      " ++ c ++ " = " ++ p ++ ";" | (c,p) <- zip cvs pvs],
  "    }"
  ]
 where
   cvs = [c | (_,_,c,_) <- cs]
   pvs = ["p" ++ show i | ((_,_,_,_),i) <- zip cs [1..]]
   conargs = intercalate ", "
     [identifier namespace (typename x) +++ v | ((x,_,_,_),v) <- zip cs pvs]
