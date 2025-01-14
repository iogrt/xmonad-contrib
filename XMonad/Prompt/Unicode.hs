{- |
Module      :  XMonad.Prompt.Unicode
Description :  A prompt for inputting Unicode characters.
Copyright   :  (c) 2016 Joachim Breitner
                   2017 Nick Hu
License     :  BSD-style (see LICENSE)

Maintainer  :  <mail@joachim-breitner.de>
Stability   :  stable

A prompt for searching unicode characters by name and inserting them into
the clipboard.

The provided @unicodePrompt@ and @typeUnicodePrompt@ use @xsel@ and @xdotool@
respectively.
-}

module XMonad.Prompt.Unicode (
 -- * Usage
 -- $usage
 unicodePrompt,
 typeUnicodePrompt,
 mkUnicodePrompt
 ) where

import Codec.Binary.UTF8.String (decodeString)
import qualified Data.ByteString.Char8 as BS
import Numeric
import System.IO
import System.IO.Error
import Text.Printf

import XMonad
import XMonad.Prelude
import qualified XMonad.Util.ExtensibleState as XS
import XMonad.Util.Run
import XMonad.Prompt

data Unicode = Unicode
instance XPrompt Unicode where
  showXPrompt Unicode = "Unicode: "
  commandToComplete Unicode s = s
  nextCompletion Unicode = getNextCompletion

newtype UnicodeData = UnicodeData { getUnicodeData :: [(Char, String)] }
  deriving (Read, Show)

instance ExtensionClass UnicodeData where
  initialValue = UnicodeData []
  extensionType = StateExtension

{- $usage

You can use this module by importing it, along with
"XMonad.Prompt", into your ~\/.xmonad\/xmonad.hs file:

> import XMonad.Prompt
> import XMonad.Prompt.Unicode

and adding an appropriate keybinding, for example:

>  , ((modm .|. controlMask, xK_u), unicodePrompt "/path/to/unicode-data" def)

A path to a @UnicodeData.txt@ file or equivalent must be provided.  This file
should be available through your package manager; search for @unicode-data@.
If no package is found, one may opt to download this file directly from
[unicode.org](http://www.unicode.org/Public/UNIDATA/UnicodeData.txt).

More flexibility is given by the @mkUnicodePrompt@ function, which takes a
command and a list of arguments to pass as its first two arguments. See
@unicodePrompt@ for details.
-}

populateEntries :: String -> X Bool
populateEntries unicodeDataFilename = do
  entries <- fmap getUnicodeData (XS.get :: X UnicodeData)
  if null entries
    then do
      datE <- liftIO . tryIOError $ BS.readFile unicodeDataFilename
      case datE of
        Left e -> liftIO $ do
          hPutStrLn stderr $ "Could not read file \"" ++ unicodeDataFilename ++ "\""
          hPrint stderr e
          hPutStrLn stderr "Do you have unicode-data installed?"
          return False
        Right dat -> do
          XS.put . UnicodeData . sortOn (length . snd) $ parseUnicodeData dat
          return True
    else return True

parseUnicodeData :: BS.ByteString -> [(Char, String)]
parseUnicodeData = mapMaybe parseLine . BS.lines
  where parseLine l = do
          field1 : field2 : _ <- return $ BS.split ';' l
          [(c,"")] <- return . readHex $ BS.unpack field1
          desc <- return . decodeString $ BS.unpack field2
          return (chr c, desc)

type Predicate = String -> String -> Bool

searchUnicode :: [(Char, String)] -> Predicate -> String -> [(Char, String)]
searchUnicode entries p s = filter go entries
  where w = filter ((> 1) . length) . words $ map toUpper s
        go (_, d) = all (`p` d) w

mkUnicodePrompt :: String -> [String] -> String -> XPConfig -> X ()
mkUnicodePrompt prog args unicodeDataFilename xpCfg =
  whenX (populateEntries unicodeDataFilename) $ do
    entries <- fmap getUnicodeData (XS.get :: X UnicodeData)
    mkXPrompt
      Unicode
      (xpCfg {sorter = sorter xpCfg . map toUpper})
      (unicodeCompl entries $ searchPredicate xpCfg)
      paste
  where
    unicodeCompl :: [(Char, String)] -> Predicate -> String -> IO [String]
    unicodeCompl _ _ "" = return []
    unicodeCompl entries p s = do
      let m = searchUnicode entries p s
      return . map (\(c,d) -> printf "%s %s" [c] d) $ take 20 m
    paste [] = return ()
    paste (c:_) = liftIO $ do
      handle <- spawnPipe $ unwords $ prog : args
      hPutChar handle c
      hClose handle
      return ()

-- | Prompt the user for a Unicode character to be inserted into the paste buffer of the X server.
unicodePrompt :: String -> XPConfig -> X ()
unicodePrompt = mkUnicodePrompt "xsel" ["-i"]

-- | Prompt the user for a Unicode character to be typed by @xdotool@.
typeUnicodePrompt :: String -> XPConfig -> X ()
typeUnicodePrompt = mkUnicodePrompt "xdotool" ["type", "--clearmodifiers", "--file", "-"]
