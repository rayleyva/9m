{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}

module Main where

import Prelude hiding (filter)
import Control.Exception (bracket)
import Control.Monad.Reader
import Data.Acid
import Data.Char
import Network.HTTP.Types
import System.Random
import Web.Scotty hiding (get, put)
import qualified Data.Map as Map
import Data.Text.Lazy hiding (find)

import DataLayer
import Templates

getIndexH :: ActionM ()
getIndexH = html indexTpl

getAboutH :: ActionM ()
getAboutH = html aboutTpl

postCreateH :: AcidState KeyValue -> ActionM ()
postCreateH db = do
    u <- (prefixHttp . filter (' '<)) `fmap` param "url"
    key <- liftIO $ do
      existing <- find db u
      case existing of
        Just v  -> return v
        Nothing -> do
          k <- randomKey 2
          insert db k u
          insert db u k
          return k
    redirect $ "/show/" `append` key
  where prefixHttp url
          | "http://" `isPrefixOf` url  = url
          | "https://" `isPrefixOf` url = url
          | otherwise = "http://" `append` url

randomKey :: Int -> IO Text
randomKey n = liftM pack $ replicateM n randomPrintChar
  where randomPrintChar = do
            c <- randomRIO ('A', '\128709')
            if isPrint c
              then return c
              else randomPrintChar

getRedirectH :: AcidState KeyValue -> ActionM ()
getRedirectH db = do
    key <- param "key"
    mbVal <- liftIO $ find db key
    case mbVal of
      Nothing    -> status status404
      Just value -> performRedirect value
  where performRedirect url = do
          setHeader "cache-control" "no-cache, no-store, max-age=0, must-revalidate"
          setHeader "pragma" "no-cache"
          setHeader "location" url
          status status301

getShowH :: AcidState KeyValue -> ActionM ()
getShowH db = do
    key <- param "key"
    mbVal <- liftIO $ find db key
    case mbVal of
      Nothing    -> status status404
      Just value -> html $ showTpl key value

nineM :: AcidState KeyValue -> ScottyM ()
nineM db = do
  addroute GET  "/"          getIndexH
  addroute GET  "/about"     getAboutH
  addroute GET  "/:key"      (getRedirectH db)
  addroute GET  "/show/:key" (getShowH db)
  addroute POST "/create"    (postCreateH db)

  -- static svg files
  addroute GET "/static/svg/:file" $ do
    setHeader "content-type" "image/svg+xml"
    param "file" >>= file . ("static/svg/" ++)

main :: IO ()
main = bracket
  (openLocalState (KeyValue Map.empty))
  closeAcidState
  (scotty 7000 . nineM)
