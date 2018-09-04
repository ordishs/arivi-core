module Arivi.P2P.Connection (
      getConnectionHandle
) where

import           Arivi.P2P.Exception
import           Arivi.P2P.MessageHandler.HandlerTypes
import           Arivi.P2P.MessageHandler.Utils
import           Arivi.P2P.P2PEnv
import           Arivi.P2P.Handler

import qualified Control.Concurrent.Async.Lifted       as LA (async)
import           Control.Concurrent.STM
import           Control.Concurrent.STM.TMVar          (putTMVar, takeTMVar)
import           Control.Monad.IO.Class                (liftIO)
import           Data.HashMap.Strict                   as HM
import           Control.Lens

-- | Obtains the connectionLock on entry and then checks if connection has been made. If yes, then simply returns the connectionHandle; else it tries to openConnection
-- | Returns the connectionHandle or an exception
createConnection ::
       (HasP2PEnv env m r msg)
    => TVar PeerDetails
    -> TVar NodeIdPeerMap
    -> TransportType
    -> m (Either AriviP2PException ConnectionHandle)
createConnection peerDetailsTVar _ transportType = do
    peerDetails <- liftIO $ atomically $ readTVar peerDetailsTVar
    lock <- liftIO $ atomically $ takeTMVar (peerDetails ^. connectionLock)
    connHandleEither <-
        case checkConnection peerDetails transportType of
            Connected connHandle -> return $ Right connHandle
            NotConnected -> networkToP2PException <$> openConnectionToPeer (peerDetails ^. networkConfig) transportType
    liftIO $ atomically $ putTMVar (peerDetails ^. connectionLock) lock
    case connHandleEither of
        Right c -> do
            liftIO $ atomically $ updatePeer transportType (Connected c) peerDetailsTVar
            _ <- LA.async $ readIncomingMessage c peerDetailsTVar
            return (Right c)
        Left e -> return (Left e)

-- | Gets the connection handle for the particular message type. If not present, it will create and return else will throw an exception
getConnectionHandle ::
       (HasP2PEnv env m r msg)
    => NodeId
    -> TVar NodeIdPeerMap
    -> TransportType
    -> m (Either AriviP2PException ConnectionHandle)
getConnectionHandle peerNodeId nodeToPeerTVar transportType = do
    nodeIdPeerMap <- liftIO $ atomically $ readTVar nodeToPeerTVar
    -- should find an entry in the hashmap
    -- exception if it is not found
    case HM.lookup peerNodeId nodeIdPeerMap of
        Just peerDetailsTVar -> do
            peerDetails <- liftIO $ atomically $ readTVar peerDetailsTVar
            case getHandlerByMessageType peerDetails transportType of
                Connected connHandle -> return (Right connHandle)
                NotConnected -> createConnection peerDetailsTVar nodeToPeerTVar transportType
        Nothing -> return (Left PeerNotFound)
