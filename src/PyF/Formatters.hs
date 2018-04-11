{-# LANGUAGE DataKinds, KindSignatures, GADTs, ViewPatterns, OverloadedStrings, StandaloneDeriving, LambdaCase #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE DeriveLift #-}
module PyF.Formatters where

import Data.Monoid ((<>))
import Data.List (intercalate)
import Data.Char (toUpper, chr)
import Data.Bifunctor (bimap)
import qualified Numeric
import Language.Haskell.TH.Syntax
-- ADT for API

data SignFmt = Plus | Minus | Space
  deriving (Show)

data Padding = PadLeft | PadRight | PadMiddle | PadSign
  deriving (Show)

data AltStatus = CanAlt | NoAlt
data UpperStatus = CanUpper | NoUpper
data FormatType = Fractional | Integral

data Format (k :: AltStatus) (k' :: UpperStatus) (k'' :: FormatType) where
  -- Integrals
  Decimal :: Format 'NoAlt 'NoUpper 'Integral
  Character :: Format 'NoAlt 'NoUpper 'Integral
  Binary :: Format 'CanAlt 'NoUpper 'Integral
  Hexa :: Format 'CanAlt 'CanUpper 'Integral
  Octal :: Format 'CanAlt 'NoUpper 'Integral

  -- Fractionals
  Fixed :: Format 'CanAlt 'CanUpper 'Fractional
  Exponent :: Format 'CanAlt 'CanUpper 'Fractional
  Generic :: Format 'CanAlt 'CanUpper 'Fractional
  Percent :: Format 'NoAlt 'NoUpper 'Fractional

  -- Meta formats
  Alternate :: Format 'CanAlt u f -> Format 'NoAlt u f
  -- Upper should come AFTER Alt, so this disallow any future alt
  Upper :: Format alt 'CanUpper f -> Format 'NoAlt 'NoUpper f

-- Internal Integral
-- Todo: remove the Show constraint ?
-- Needed for debug in Numeric function, this is painful
reprIntegral :: (Show i, Integral i) => Format t t' 'Integral -> i -> Repr
reprIntegral fmt i = IntegralRepr sign $ format fmt
  where
    format :: Format t t' 'Integral -> String
    format = \case
      Decimal -> Numeric.showInt iAbs ""
      Octal -> Numeric.showOct iAbs ""
      Binary -> Numeric.showIntAtBase 2 (\digit -> if digit == 0 then '0' else '1') iAbs ""
      Hexa -> Numeric.showHex iAbs ""
      Upper fmt' -> map toUpper $ format fmt'
      Character -> [chr (fromIntegral i)]
      Alternate fmt' -> format fmt'

    (sign, iAbs) = splitSign i

prefixIntegral :: Format t t' 'Integral -> String
prefixIntegral (Alternate Octal) = "0o"
prefixIntegral (Alternate Binary) = "0b"
prefixIntegral (Alternate Hexa) = "0x"
prefixIntegral (Upper f) = toUpper <$> prefixIntegral f
prefixIntegral _ = ""

splitSign :: (Num b, Ord b) => b -> (Sign, b)
splitSign v = (if v < 0 then Negative else Positive, abs v)

-- Internal Fractional
reprFractional :: (RealFloat f) => Format t t' 'Fractional -> Maybe Int -> f -> Repr
reprFractional fmt precision f
  | isInfinite f = Infinite sign (upperIt "inf")
  | isNaN f = NaN (upperIt "nan")
  | otherwise = FractionalRepr sign a b
  where
    upperIt s = case fmt of
      Upper _ -> toUpper <$> s
      _ -> s

    (sign, iAbs) = splitSign f
    (a, b) = format fmt

    format :: Format t t' 'Fractional -> (String, String)
    format = \case
      Fixed -> splitFractional (Numeric.showFFloatAlt precision iAbs "")
      Exponent -> splitFractional (Numeric.showEFloat precision iAbs "")
      Generic -> splitFractional (Numeric.showGFloatAlt precision iAbs "")
      Percent -> (<>"%") <$> splitFractional (Numeric.showFFloatAlt precision (iAbs * 100) "")
      Alternate fmt' -> format fmt'
      Upper fmt' -> bimap (map toUpper) (map toUpper) (format fmt')

    splitFractional :: String -> (String, String)
    splitFractional s = drop 1 <$> break (=='.') s

-- Cases Integral / Fractional

group :: Repr -> Maybe (Int, Char) -> Repr
group (IntegralRepr s str) (Just (size, c)) = IntegralRepr s (groupIntercalate c size str)
group (FractionalRepr s a b) (Just (size, c)) = FractionalRepr s (groupIntercalate c size a) b
group i _ = i

padAndSign :: String -> SignFmt -> Maybe (Int, Padding, Char) -> Repr -> String
padAndSign prefix sign padding repr = leftPadding <> prefixStr <> middlePadding <> content <> rightPadding
  where
    (signStr, content) = case repr of
      IntegralRepr s str -> (formatSign s sign, str)
      FractionalRepr s a b -> (formatSign s sign, a <> "." <> b)
      Infinite s str -> (formatSign s sign, str)
      NaN str -> ("", str)
    prefixStr = signStr <> prefix

    len = length prefixStr + length content
    (leftPadding, rightPadding, middlePadding) = case padding of
      Nothing -> ("", "", "")
      Just (pad, padMode, padC) -> let
        padNeeded = max 0 (pad - len)
        in case padMode of
             PadLeft -> (replicate padNeeded padC, "", "")
             PadRight -> ("", replicate padNeeded padC, "")
             PadMiddle -> (replicate (padNeeded `div` 2) padC, replicate (padNeeded - padNeeded `div` 2) padC, "")
             PadSign -> ("", "", replicate padNeeded padC)

-- Generic
data Repr
  = IntegralRepr Sign String
  | FractionalRepr Sign String String
  | Infinite Sign String
  | NaN String
  deriving (Show)

data Sign = Negative | Positive
  deriving (Show)

formatSign :: Sign -> SignFmt -> String
formatSign Positive Plus = "+"
formatSign Positive Minus = ""
formatSign Positive Space = " "
formatSign Negative _ = "-"

groupIntercalate :: Char -> Int -> String -> String
groupIntercalate c i s = intercalate [c] (reverse (pack (reverse s)))
  where
    pack "" = []
    pack l = reverse (take i l) : pack (drop i l)

-- Final formatters

formatIntegral :: (Show i, Integral i) => Format t t' 'Integral -> SignFmt -> Maybe (Int, Padding, Char) -> Maybe (Int, Char) -> i -> String
formatIntegral f sign padding grouping i = padAndSign (prefixIntegral f) sign padding (group (reprIntegral f i) grouping)

formatFractional :: (RealFloat f) => Format t t' 'Fractional -> SignFmt -> Maybe (Int, Padding, Char) -> Maybe (Int, Char) -> Maybe Int -> f -> String
formatFractional f sign padding grouping precision i = padAndSign "" sign padding (group (reprFractional f precision i) grouping)

formatString :: Maybe (Int, Padding, Char) -> Maybe Int -> String -> String
formatString Nothing Nothing s = s
formatString Nothing (Just i) s = take i s
formatString (Just (padSize, padMode, padC)) size s = padLeft <> str <> padRight
  where
    str = formatString Nothing size s

    paddingLength = max 0 (padSize - length str)
    (padLeft, padRight) = case padMode of
         PadLeft -> (replicate paddingLength padC, "")
         PadRight -> ("", replicate paddingLength padC)
         PadMiddle -> (replicate (paddingLength `div` 2) padC, replicate (paddingLength - paddingLength `div` 2) padC)
         PadSign -> error "Cannot pad with padSign a string"
-- TODO
{-
the .
-}

deriving instance Lift Padding
deriving instance Lift SignFmt
