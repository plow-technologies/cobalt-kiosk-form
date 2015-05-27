{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE OverloadedStrings         #-}

module Kiosk.Backend.Form.Parsers where

import           Kiosk.Backend.Form.Attribute
import           Kiosk.Backend.Form.Attribute.Indexable
import           Kiosk.Backend.Form.Attribute.Path
import           Kiosk.Backend.Form.Attribute.Width
import           Kiosk.Backend.Form.Element

import           Control.Applicative
import           Control.Applicative.Permutation
import           Control.Monad
import           Data.Attoparsec.Text
import           Data.Either

import           Data.List                              (sort)
import           Data.Monoid                            ((<>))
import           Data.Text                              (Text)
import qualified Data.Text                              as T

data Element = Element {
    element    :: T.Text
  , attributes :: [Attribute]
  , value      :: T.Text
} deriving (Show)

-- | separates each part of the above into a sum type for alternative parser
data TagParts = TagName Text |
                TagAttribute  Attribute |
                TagValue Text
  deriving (Show)

-- | the combinators below permutate to give any available combination in a tag
-- so < name a1='v1' a2='v2' a3='v3'> val </name>
-- parses the same as < name a3='v3' a2='v2' a1='v1'> val </name>
-- and so on... this is important because many xml libs don't respect attr order
-- A sumtype and list is used to create this parsing style then at the end the
-- the element record is constructed from the list
-- lastly, the element that is created is validated

elementFromTagParts :: [TagParts] -> Parser Element
elementFromTagParts = validate . foldr createTagParts emptyElement
  where
     emptyElement :: Element
     emptyElement = Element "" [] ""
     createTagParts :: TagParts -> Element -> Element
     createTagParts (TagName t) elem
       |T.null . element $ elem = elem {element=t}
       |otherwise = elem
     createTagParts (TagValue v) elem
       |T.null . value $ elem = elem {value=v}
       |otherwise = elem
     createTagParts (TagAttribute a) elem@(Element{attributes=attrLst}) =
                    elem{attributes=a:attrLst}
     validate :: Element -> Parser Element
     validate elem = (guard . T.null . element $ elem ) >> return elem <?>
                     "Error Element contains no name"

parseForm :: Parser Form
parseForm = do
  parseOpenTag "entry"
  parseOpenTag "form"
  company <- parseCompanyElement
  address <- parseAddressElement
  logo    <- parseLogoElement
  phone   <- parsePhoneElement
  constants <- many' $ try parseConstantElement
  rows      <- many' $ try parseRow
  parseCloseTag "form"
  parseCloseTag "entry"

  return $ Form company address logo phone constants rows

parseOpenTag :: T.Text -> Parser ()
parseOpenTag elemName = parseOpeningAngle  *>
                        parseElemName elemName *>
                        parseClosingAngle  *>
                        pure ()

parseOpenTagWithAttributes :: T.Text -> Parser Element
parseOpenTagWithAttributes elemName = do
  _ <- parseOpeningAngle
  _ <- parseElemName elemName
  attrList <- try $ many' parseAttributes
  _ <- parseClosingAngle
  return $ Element elemName attrList ""

parseCloseTag :: T.Text -> Parser ()
parseCloseTag elemName = parseOpeningAngle *>
                         (char '/' <?> "parseCloseTag did not find backslash '/'") *>
                         parseElemName elemName *>
                         parseClosingAngle *>
                         pure ()


-- parse path attribute
parseCompanyElement :: Parser Company
parseCompanyElement = do
  company <- parseElementWithoutAttributes "company"
  return $ Company (value company) []

parseAddressElement :: Parser Address
parseAddressElement = do
  address <- parseElementWithoutAttributes "address"
  return $ Address (value address) []

parseLogoElement :: Parser Logo
parseLogoElement = do
  logo <- parseElementWithRequiredAttributes "logo" ["path"]
  let logoAttribs = map (LogoPath . PathAttribute . val ) $ filter (\x -> name x == "path") (attributes logo)
  --let pathAttribs = filter (\x -> name x == "path") (attributes logo)
  --let logoAttribs = map (\x -> LogoPath . PathAttribute $ val x) pathAttribs
  return $ Logo (value logo) logoAttribs

parsePhoneElement :: Parser Phone
parsePhoneElement = do
  phone <- parseElementWithoutAttributes "phone"
  return $ Phone (value phone) []

parseConstantElement :: Parser Constant
parseConstantElement = do
  constant <- parseElementWithRequiredAttributes "constant" ["type","indexable"]
  return $ Constant (value constant) (map parseConstantAttributeType $ attributes constant)

parseConstantAttributeType :: Attribute -> ConstantAttributes
parseConstantAttributeType (Attribute "type"      v      ) = ConstantAttributeType v
parseConstantAttributeType (Attribute "indexable" "True" ) = ConstantAttributeIndexable $ IndexableAttribute True
parseConstantAttributeType (Attribute "indexable" "False") = ConstantAttributeIndexable $ IndexableAttribute False
parseConstantAttributeType (Attribute _           _      ) = ConstantAttributeType ""


{-
instance AttributeClass ConstantAttributes where
  toAttribute   (ConstantAttributeType t) = Attribute "type" t
  toAttribute   (ConstantAttributeIndexable i) = toAttribute i
  fromAttribute (Attribute "type" i) =  Right $ ConstantAttributeType $ i
  fromAttribute _ = Left "Not a valid button Attribute"

genericAttributeDecoder :: AttributeClass t => [Attribute] -> [t]
genericAttributeDecoder attrs = do
  let eAttrList = fromAttribute <$> attrs
  case rights eAttrList of
    [] -> []
    attrs' -> attrs'

parseInputType :: [InputAttribute] -> T.Text -> InputType
parseInputType (InputType (InputTypeAttributeText      ):_) elemVal = InputTypeText      . InputText   $ elemVal
parseInputType (InputType (InputTypeAttributeSignature ):_) elemVal = InputTypeSignature . Signature   $ elemVal
parseInputType (InputType (InputTypeAttributeInt       ):_) elemVal = InputTypeInt       . InputInt    $ (read (T.unpack elemVal) :: Int)
parseInputType (InputType (InputTypeAttributeDouble    ):_) elemVal = InputTypeDouble    . InputDouble $ (read (T.unpack elemVal) :: Double)
parseInputType [] _ = InputTypeText . InputText $ ""
parseInputType _  _ = InputTypeText . InputText $ ""

-- | Element with Content Parser

-- Button Parser
buttonParser :: Parser Button
buttonParser = buttonFromElement <$> parseElement "button"
    where
      buttonFromElement (Element _ attrs elemVal) = Button elemVal (genericAttributeDecoder attrs)


defaultConstant :: Constant
defaultConstant = Constant "Black Watch" [ ConstantAttributeType "'Company'", ConstantAttributeIndexable $ IndexableAttribute True ]

data Row = Row {
 _rowItem   :: [Item],
 _rowAttrib :: [RowAttributes]
} deriving (Show)
-}
parseRow :: Parser Row
parseRow = do
  parseOpenTag "row"

  -- all of these parses return Item
  items <- many $ try $ parseInput <|> parseSignature <|> parseButton <|> parseRadio <|> parseLabel

  parseCloseTag "row"

  return $ Row items []

parseInputOfType :: T.Text -> Parser Item
parseInputOfType inputType = do
  -- look for width or break
  _iElem <- parseOpenTagWithAttributes "item"

  labelElem <- parseElement "label"
  inputElem <- parseElement inputType

  -- look for width or break
  let itemLabel = Label (element labelElem) (genericAttributeDecoder $ attributes labelElem)
  let itemInput = Input (parseInputType (genericAttributeDecoder $ attributes inputElem) (value inputElem)) (genericAttributeDecoder $ attributes inputElem)

  parseCloseTag "item"
  return $ Item [ItemLabel itemLabel, ItemInput itemInput] [ItemWidth $ WidthAttribute (12::Int)]

parseInput :: Parser Item
parseInput = parseInputOfType "input"

parseSignature :: Parser Item
parseSignature = parseInputOfType "input"

parseButton :: Parser Item
parseButton = do
  _iElem <- parseOpenTagWithAttributes "item"

  buttonElement <- parseElement "button"
  let b = Button (value buttonElement) (genericAttributeDecoder $ attributes buttonElement)

  parseCloseTag "item"
  return $ Item [ItemButton b] [ItemWidth $ WidthAttribute (12::Int)] -- $ Item [ItemButton (Button (value buttonElement) (attributes buttonElement))] [ItemWidth $ WidthAttribute (12::Int)]

parseLabel :: Parser Item
parseLabel = do
  _iElem <- parseOpenTagWithAttributes "item"

  labelElem <- parseElement "label"

  let itemLabel = Label (element labelElem) (genericAttributeDecoder $ attributes labelElem)
  -- Label elemVal (genericAttributeDecoder attrs)

  return $ Item [ItemLabel itemLabel] [ItemWidth $ WidthAttribute (12::Int)]

-- used only by parseRadio
parseOptionQualifier :: Parser OptionQualifier
parseOptionQualifier = do
  _iElem <- parseOpenTagWithAttributes "option-qualifier"

  labelElem <- parseElement "label"
  inputElem <- parseElement "input"

  -- look for width or break
  let itemLabel = Label (element labelElem) (genericAttributeDecoder $ attributes labelElem)
  let itemInput = Input (parseInputType (genericAttributeDecoder $ attributes inputElem) (value inputElem)) (genericAttributeDecoder $ attributes inputElem)

  parseCloseTag "item"

  return $ OptionQualifier [QualifierLabel itemLabel, QualifierInput itemInput] []

parseRadio :: Parser Item
parseRadio = do
  _iElem <- parseOpenTagWithAttributes "item" <?> "parseRadio: did not find item."
  _ <- parseOpenTag "radio" <?> "parseRadio: did not find radio."
  labelElem <- parseElement "label"　<?> "parseRadio: did not find label."
  let itemLabel = Label (element labelElem) (genericAttributeDecoder $ attributes labelElem)

  optionElements <- many1 $ parseElement "option"
  --Option "Pit Water" []
  -- currently not using option attributes
  let ops = map (\x -> Option (value x ) []) optionElements

  opqs <- many' parseOptionQualifier

  _ <- parseCloseTag "radio" <?> "parseRadio: did not find radio close tag."
  _ <- parseCloseTag "item" <?> "parseRadio: did not find item close tag."

  return $ Item [ItemRadio $ Radio itemLabel ops opqs] [ItemWidth $ WidthAttribute (12::Int)]


textOrNullParser :: Parser T.Text
textOrNullParser = takeTill (== '<')

-- parseElement :: T.Text -> Parser Element
-- parseElement elemName = do
--   _ <- parseOpeningAngle
--   _ <- parseElemName elemName
--   attrList <- try . many' $ parseAttributes
--   _ <- parseClosingAngle
--   elemValue <- textOrNullParser
--   _ <- parseCloseTag elemName

--   return $ Element elemName attrList elemValue



parseElement elemName = angles parseInternal
  where
    parseInternal = do
       _ <- parseElemName elemName
       attrList <- (try . many' $ parseAttributes)
       elemValue <- textOrNullParser
       return $ Element elemName attrList elemValue



parseElementWithoutAttributes :: T.Text -> Parser Element
parseElementWithoutAttributes elemName = do
  _ <- parseOpeningAngle
  _ <- parseElemName elemName
  _ <- parseClosingAngle
  elemValue <- textOrNullParser
  _ <- parseCloseTag elemName
  return $ Element elemName [] elemValue

parseElementWithRequiredAttributes :: T.Text -> [T.Text] -> Parser Element
parseElementWithRequiredAttributes elemName requiredAttrs = do
  _ <- parseOpeningAngle
  _ <- parseElemName elemName
  attrList <- try $ many' parseAttributes
  _ <- parseClosingAngle
  elemValue <- textOrNullParser
  _ <- parseCloseTag elemName
  case sort requiredAttrs == sort (map name attrList) of
    True  -> return $ Element elemName attrList elemValue
    False -> fail   $ T.unpack  . T.concat $
      ["parseElementWithRequiredAttributes parsed the following attributes: "] ++ [(T.intercalate ", " (map name attrList))] ++
      [", but requires the following attributes: "] ++ [(T.intercalate ", " requiredAttrs)] ++ ["."]

parseAttributes :: Parser Attribute
parseAttributes = do
  _ <- many1 space
  nameFirstLetter <- letter
  nameRest <- manyTill letter (char '=')
  q <- char '\'' <|> char '"'
  attrVal <- takeTill (== q)
  _ <- char q
  return $ Attribute (T.pack $ nameFirstLetter:nameRest) attrVal

genericAttributeDecoder :: AttributeClass t => [Attribute] -> [t]
genericAttributeDecoder attrs = do
  let eAttrList = fromAttribute <$> attrs
  case rights eAttrList of
    [] -> []
    attrs' -> attrs'

parseInputType :: [InputAttribute] -> T.Text -> InputType
parseInputType (InputType InputTypeAttributeText      :_) elemVal = InputTypeText      . InputText   $ elemVal
parseInputType (InputType InputTypeAttributeSignature:_) elemVal = InputTypeSignature . Signature   $ elemVal
parseInputType (InputType InputTypeAttributeInt:_) elemVal = InputTypeInt       . InputInt    $ (read (T.unpack elemVal) :: Int)
parseInputType (InputType InputTypeAttributeDouble:_) elemVal = InputTypeDouble    . InputDouble $ (read (T.unpack elemVal) :: Double)
parseInputType [] _ = InputTypeText . InputText $ ""
parseInputType _  _ = InputTypeText . InputText $ ""

-- | Element with Content Parser

-- Button Parser
buttonParser :: Parser Button
buttonParser = buttonFromElement <$> parseElement "button"
    where
      buttonFromElement (Element _ attrs elemVal) = Button elemVal (genericAttributeDecoder attrs)

-- Label Parser
labelParser :: Parser Label
labelParser = labelFromElement <$> parseElement "label"
    where
      labelFromElement (Element _ attrs elemVal) = Label elemVal (genericAttributeDecoder attrs)

inputParser :: Parser Input
inputParser = inputFromElement <$> parseElement "input"
    where
      inputFromElement (Element _ attrs elemVal) = Input (parseInputType (genericAttributeDecoder attrs) elemVal) (genericAttributeDecoder attrs)




-- | parse primitives

parseClosingAngle :: Parser Char
parseClosingAngle = tokenChar '>'
                    <?> "Did not find closing angle '>'"


parseOpeningAngle :: Parser Char
parseOpeningAngle = tokenChar '<'
                    <?> "parseOpenTag did not find opening angle '<'"

parseElemName :: Text -> Parser Text
parseElemName elemName = (token $ string elemName)
                         <?> "parseElemName did not find '" <> T.unpack elemName <> "'"



-- > mainParser  = sum <$ whiteSpace <*> many (token digit) <* eof

angles :: Parser middle -> Parser middle
angles = between (tokenChar '<') (tokenString "/>")

between :: Parser leftBracket
        -> Parser rightBracket
        -> Parser middle -> Parser middle
between pi pf pMiddle = pi *> pMiddle <* pf



tokenChar :: Char -> Parser Char
tokenChar c = token (char c)

tokenString s = token (string s)
token :: Parser a -> Parser a
token a = a <* (someSpace <|> pure ())

-- someSpace :: m ()
someSpace :: Parser ()
someSpace = skipMany1 space
