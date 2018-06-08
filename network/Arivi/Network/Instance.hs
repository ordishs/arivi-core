{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE ScopedTypeVariables   #-}

module Arivi.Network.Instance
(
    AriviNetworkInstance (..)
  , NetworkConfig (..)
  , NetworkHandle (..)
  , closeConnection
  , connectionMap
  , lookupCId
  , mkAriviNetworkInstance
  , openConnection
  , sendMessage
) where

import           Arivi.Crypto.Utils.PublicKey.Utils   (encryptMsg)
import           Arivi.Crypto.Utils.Random
import           Arivi.Env
import           Arivi.Logging
import           Arivi.Network.Connection             as Conn (Connection (..),
                                                               makeConnectionId)
import           Arivi.Network.ConnectionHandler
import           Arivi.Network.Fragmenter
import qualified Arivi.Network.FSM                    as FSM
import           Arivi.Network.Handshake
import           Arivi.Network.StreamClient
import           Arivi.Network.Types                  as ANT (AeadNonce,
                                                              ConnectionId,
                                                              Event (..),
                                                              Header (..),
                                                              NodeId,
                                                              OutboundFragment,
                                                              Parcel (..),
                                                              Payload (..),
                                                              PersonalityType,
                                                              SequenceNum,
                                                              TransportType (..))
import           Arivi.Network.Utils
import           Arivi.Utils.Exception
import           Codec.Serialise
import           Control.Concurrent                   (threadDelay)
import           Control.Concurrent.Async.Lifted.Safe
import           Control.Concurrent.Killable          (kill)
import           Control.Concurrent.STM
import           Control.Concurrent.STM.TChan         (TChan)
import           Control.Exception                    (SomeException, throw,
                                                       try)
import           Control.Monad
import           Control.Monad.Reader
import           Control.Monad.STM                    (atomically)
import           Crypto.PubKey.Ed25519                (SecretKey)
import qualified Data.ByteString                      as B
import           Data.ByteString.Lazy                 as L
import           Data.HashMap.Strict                  as HM
import           Data.Int                             (Int16, Int64)
import           Data.Maybe                           (fromMaybe)
import           Debug.Trace
import           Network.Socket

-- | Strcuture to hold the arivi configurations can also contain more
--   parameters but for now just contain 3
data NetworkConfig    = NetworkConfig {
                        hostip  :: String
                    ,   udpport :: String
                    ,   tcpPort :: String
                    -- , TODO   transportType :: TransportType and only one port
                    } deriving (Show)

-- | Strcuture which holds all the information about a running arivi Instance
--   and can be passed around to different functions to differentiate betweeen
--   different instances of arivi.
newtype NetworkHandle = NetworkHandle { ariviUDPSock :: (Socket,SockAddr) }
                    -- ,   ariviTCPSock :: (Socket,SockAddr)
                    -- ,   udpThread    :: MVar ThreadId
                    -- ,   tcpThread    :: MVar ThreadId
                    -- ,
                    -- registry     :: MVar MP.ServiceRegistry


doEncryptedHandshake :: Conn.Connection -> SecretKey -> IO Conn.Connection
doEncryptedHandshake connection sk = do
    (serialisedParcel, updatedConn) <- initiatorHandshake sk connection
    sendFrame (Conn.socket updatedConn) (createFrame serialisedParcel)
    hsRespParcel <- readHandshakeRespSock (Conn.socket updatedConn) sk
    return $ receiveHandshakeResponse updatedConn hsRespParcel

openConnection :: (HasAriviNetworkInstance m,
                   HasSecretKey m,
                   HasLogging m,
                   Forall (Pure m))
               => HostName
               -> PortNumber
               -> TransportType
               -> NodeId
               -> PersonalityType
               -> m (Either AriviException ANT.ConnectionId)
openConnection addr port tt rnid pType = do

  ariviInstance <- getAriviNetworkInstance
  let cId = makeConnectionId addr port tt
  let tv = connectionMap ariviInstance

  hm <- liftIO $ readTVarIO tv

  case HM.lookup cId hm of
    Just conn -> return $ Right cId
    Nothing   -> do
          sk <- getSecretKey
          socket <- liftIO $ createSocket addr (read (show port)) tt
          reassemblyChan <- liftIO (newTChanIO :: IO (TChan Parcel))
          p2pMsgTChan <- liftIO (newTChanIO :: IO (TChan ByteString))
          egressNonce <- liftIO (newTVarIO (2 :: SequenceNum))
          ingressNonce <- liftIO (newTVarIO (2 :: SequenceNum))
          aeadNonce <- liftIO (newTVarIO (2 :: AeadNonce))

          let connection = Connection {Conn.connectionId = cId,
                                       Conn.remoteNodeId = rnid,
                                       Conn.ipAddress = addr,
                                       Conn.port = port,
                                       Conn.transportType = tt,
                                       Conn.personalityType = pType,
                                       Conn.socket = socket,
                                       Conn.reassemblyTChan = reassemblyChan,
                                       Conn.p2pMessageTChan = p2pMsgTChan,
                                       Conn.egressSeqNum = egressNonce,
                                       Conn.ingressSeqNum = ingressNonce,
                                       Conn.aeadNonceCounter = aeadNonce}

          res <- liftIO $ try $ doEncryptedHandshake connection sk

          case res of
            Left e -> return $ Left e
            Right updatedConn ->
              do
                liftIO $ atomically $ modifyTVar tv (HM.insert cId updatedConn)
                async (readSock updatedConn HM.empty)
                return $ Right cId

sendMessage :: (HasAriviNetworkInstance m, HasLogging m)
            => ANT.ConnectionId
            -> ByteString
            -> m ()
sendMessage cId msg = do
  connectionOrFail <- lookupCId cId
  case connectionOrFail of
    Nothing -> throw AriviInvalidConnectionIdException
    Just conn -> do
      let sock = Conn.socket conn
      fragments <- liftIO $ processPayload (Payload msg) conn

      mapM_ (\frame -> liftIO (atomically frame >>= (try.sendFrame sock))
            >>= \case
                     Left (_::SomeException) -> closeConnection cId
                                             >> throw AriviSocketException
                     Right _ -> return ()
                     ) fragments


closeConnection :: (HasAriviNetworkInstance m)
                => ANT.ConnectionId
                -> m ()
closeConnection cId = do
  ariviInstance <- getAriviNetworkInstance
  let tv = connectionMap ariviInstance
  liftIO $ atomically $ modifyTVar tv (HM.delete cId)


lookupCId :: (HasAriviNetworkInstance m)
          => ANT.ConnectionId
          -> m (Maybe Connection)
lookupCId cId = do
  ariviInstance <- getAriviNetworkInstance
  let tv = connectionMap ariviInstance
  hmap <- liftIO $ readTVarIO tv
  return $ HM.lookup cId hmap

