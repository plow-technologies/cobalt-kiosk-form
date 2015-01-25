{- |
Module      :  Kiosk.Backend.Rendering
Description :  Render Form Types into XML
Copyright   :  (c) <Plow Technology 2014>
License     :  <MIT>
Maintainer  :  <lingpo.huang@plowtech.net>
Stability   :  unstable
Portability :  portable
<Render the Form Types into XML>
-}

{-# LANGUAGE OverloadedStrings #-}

module Kiosk.Backend.Form.Rendering where

import           Control.Applicative        ((<$>))
import           Data.ByteString            (ByteString)
import           Data.Monoid                ((<>))
import           Data.Text                  (Text, pack, unwords)
import           Data.Text.Encoding         (encodeUtf8)
import           Kiosk.Backend.Form.Element
import Kiosk.Backend.Form.Attribute
-- | Render Generator

-- Rendering a Attribute
renderAttribute :: Attribute -> Text
renderAttribute attr = name attr <>
                        "=" <>
                        val attr


-- Rendering a list of Attributes
renderAttrList :: (AttributeClass a) =>  [a] -> Text
renderAttrList attrs = Data.Text.unwords $ renderAttribute. toAttribute <$> attrs

-- Rendering Label Tag
renderLabel :: Label -> Text
renderLabel (Label txt attrs) = "<label " <> renderAttrList attrs
                                          <> ">"
                                          <> txt
                                          <> "</label>"

-- Rendering Input Tag
renderInput :: Input -> Text
renderInput (Input inputType attrs) = "<input " <> renderAttrList attrs
                                                <> ">"
                                                <> renderInputType inputType
                                                <> "</input>"


-- Rendering Different Input Type
renderInputType :: InputType -> Text
renderInputType (InputTypeText (InputText t)) = t
renderInputType (InputTypeSignature (Signature s)) = s
renderInputType (InputTypeInt (InputInt i)) = pack . show $ i
renderInputType (InputTypeDouble (InputDouble d)) = pack .show $ d

-- Rendering Button Tag
renderButton :: Button -> Text
renderButton (Button txt attrs) = "<button " <> renderAttrList attrs
                                             <> ">"
                                             <> txt
                                             <> "</button>"
-- Rendering Empty Block
renderEmptyBlock :: EmptyBlock -> Text
renderEmptyBlock _emptyBlock = pack . show $ (""::String)

-- Rendering TableTopHeader Tag
renderTableTopHeader :: TableTopHeader -> Text
renderTableTopHeader  (TableTopHeader txt) = "<tableTopHeader>"  <> txt
                                                                 <> "</tableTopHeader>"

-- Rendering TableLeftHeader Tag
renderTableLeftHeader :: TableLeftHeader -> Text
renderTableLeftHeader  (TableLeftHeader txt) =  "<tableLeftHeader>" <> txt
                                                                    <> "</tableLeftHeader>"

-- Rendering Company Tag
renderCompany :: Company -> Text
renderCompany (Company txt attrs) = "<company " <> renderAttrList attrs
                                                <> ">"
                                                <> txt
                                                <> "</company>"
-- Rendering Address Tag
renderAddress :: Address -> Text
renderAddress (Address txt attrs) = "<address " <> renderAttrList attrs
                                                <> ">"
                                                <> txt
                                                <> "</address>"

-- Rendering Constant Tag
  
renderConstant :: Constant -> Text 
renderConstant (Constant txt attrs)  = "<constant " <> renderAttrList attrs
                                                    <> ">"
                                                    <> txt
                                                    <> "</constant>"

-- Rendering a list of Constants
renderConstantList :: [Constant] -> Text
renderConstantList constants = Data.Text.unwords $ renderConstant <$> constants

-- Rendering ItemType
renderItemType :: ItemType -> Text
renderItemType it =
  case it of
       (ItemLabel l) -> renderLabel l
       (ItemInput i) -> renderInput i
       (ItemButton b) -> renderButton b
       (ItemEmptyBlock e) -> renderEmptyBlock e
       (ItemTableLeftHeader lh) -> renderTableLeftHeader lh
       (ItemTableTopHeader th) -> renderTableTopHeader th

-- Rendering a list of ItemTypes
renderItemTypeList :: [ItemType] -> Text
renderItemTypeList its = Data.Text.unwords $ renderItemType <$> its

-- Rendering Item tag
renderItem :: Item -> Text
renderItem (Item its attrs) = "<item " <> renderAttrList attrs
                                       <> ">"
                                       <> renderItemTypeList its
                                       <> "</item>"

-- Rendering a list of Items
renderItemList :: [Item] -> Text
renderItemList items = Data.Text.unwords $ renderItem <$> items

-- Rendering Row Tag
renderRow :: Row -> Text
renderRow (Row items attrs) = "<row " <> renderAttrList attrs
                                      <> ">"
                                      <> renderItemList items
                                      <> "</row>"

-- Rendering a list of Rows
renderRowList :: [Row] -> Text
renderRowList rows = Data.Text.unwords $ renderRow <$> rows

-- Rendering Onping Form
renderOnpingForm :: Form -> Text
renderOnpingForm (Form company address constants rows) = "<form>" <> renderCompany company
                                                                  <> renderAddress address              
                                                                  <> renderConstantList constants                                                          
                                                                  <> renderRowList rows                 
                                                                  <> "</form>"

-- Convert The XML Text into ByteString
renderByteString :: Text -> ByteString
renderByteString = encodeUtf8
