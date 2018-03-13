{-# LANGUAGE OverloadedStrings #-}

module Main where
import           Control.Concurrent (forkIO, newChan, newEmptyMVar, putMVar,
                                     readChan, takeMVar, threadDelay, writeChan)
import           Data.List          (find, length, tail)
import           Data.Maybe         (fromMaybe)
import           Node
import           System.Environment
import           System.IO 
import qualified Data.Configurator  as C
import qualified Data.List.Split    as S (splitOn)
import           Data.Text          hiding (find)

import qualified Network.Socket.Internal   as M 
import           Network.Socket            hiding (recv)
import           Utils 
import qualified Types as T 
import           Random 
import           KeyHandling 
import qualified Data.ByteString           as B 
import qualified Data.ByteString.Char8     as BC 

import Data.ByteArray
import Control.Concurrent.STM.TChan
import Control.Monad.STM 
import Control.Monad 


-- Custom data type to collect data from configutation file 
data Config = Config
  { localIpAddress :: String
  , localPortNo    :: String
  , bootStrapPeers :: [String]
  , k              :: Int 
  } deriving (Eq, Show)

readConfig :: FilePath -> IO Config
readConfig cfgFile = do
  cfg          <- C.load [C.Required cfgFile]
  localIpAddress    <- C.require cfg "node.localIpAddress"
  localPortNo       <- C.require cfg "node.localPortNo"
  bootStrapPeers    <- C.require cfg "node.bootStrapPeers"
  k                 <- C.require cfg "node.k"
  return $ Config localIpAddress localPortNo bootStrapPeers k 

--extractTupleFromConfig [] = ("0.0.0":"0")
extractTupleFromConfig :: String -> (String,String)
extractTupleFromConfig [] = ("","")
extractTupleFromConfig x = (peer_Ip,peer_Port)
  where
    peerInfo = S.splitOn ":" x
    peer_Ip = (peerInfo !! 0)
    peer_Port = (peerInfo !! 1)

main :: IO ()
main = do
  hSetBuffering stdout NoBuffering

  -- Assing the node a NodeID which is alos the public id of the node 

  seed <- getRandomByteString 32 
  let sk     = getSecretKey seed
      pk     = getPublicKey sk 
      pk2    = convert pk :: BC.ByteString
      nodeId = pk :: T.NodeId

  print ("NodeId : " ++ BC.unpack (toHex(pk)))

  args <- getArgs
  let cfgFilePath =
        fromMaybe (error "Usage: ./kademlia-exe --config /file/path") $
        find (/= "--config") args

  -- reads configuration file
  cfg <- readConfig cfgFilePath

  let workerCount = 5
  inboundChan  <- atomically $ newTChan
  outboundChan <- atomically $ newTChan
  peerChan     <- atomically $ newTChan
  kbChan       <- atomically $ newTChan 
  -- kbDChan     <- atomically $ dupTChan kbChan 
  servChan     <- atomically $ newTChan 
  
  mapM_ (messageHandler nodeId sk servChan inboundChan outboundChan peerChan kbChan (k cfg)) [1..workerCount]
  mapM_ (networkClient outboundChan ) [1..workerCount]
  mapM_ (addToKbChan kbChan peerChan) [1..workerCount]
 
  let peerList = bootStrapPeers cfg
      defaultPeerList = (Prelude.map convertToSockAddr peerList)
  
  case (Data.List.length defaultPeerList) of
    -- case in which the default peerList is empty i.e the node will run
    -- as a bootstrap node. 
    (0)       -> do 
                     done <- newEmptyMVar 
                     forkIO $ runUDPServerForever (localIpAddress cfg) (localPortNo cfg) inboundChan servChan >> putMVar done ()
                     takeMVar done 
    -- case in which the default peerList is present and thus the peer would 
    -- load the default peerList 
    otherwise -> do 
                     done <- newEmptyMVar
                     forkIO $ runUDPServerForever (localIpAddress cfg) (localPortNo cfg) inboundChan servChan >> putMVar done ()
                     forkIO $ loadDefaultPeers nodeId sk (defaultPeerList) outboundChan peerChan servChan >> putMVar done ()
                     takeMVar done
                     takeMVar done 

