
module Network.Arivi.Instance
(
AriviConfig (..),
getAriviInstance ,
runAriviInstance ,
AriviHandle (..),
) where

import           Network.Socket
import           Network.Arivi.Types
import           Network.Arivi.Datagram
import           Network.Arivi.Stream
import           Control.Concurrent                         (forkIO,ThreadId,newEmptyMVar,putMVar,
                                                            takeMVar,MVar)
import qualified Data.Map.Strict                    as Map
import qualified Network.Arivi.Multiplexer          as MP
import           Control.Concurrent.Async
import           Control.Monad


-- | Strcuture to hold the arivi configurations can also contain more parameters but for now
--   just contain 3
data AriviConfig    = AriviConfig {
                        hostip  :: String
                    ,   udpport :: String
                    ,   tcpPort :: String
                    } deriving (Show)

-- | Strcuture which holds all the information about a running arivi Instance and can be passed
--   around to different functions to differentiate betweeen different instances of
--   arivi.
data AriviHandle    = AriviHandle {
                        ariviUDPSock    :: (Socket,SockAddr)
                    ,   ariviTCPSock    :: (Socket,SockAddr)
                    ,   udpThread       :: MVar ThreadId
                    ,   tcpThread       :: MVar ThreadId
                    ,   registry        :: MP.Registry
            }

getAriviInstance :: AriviConfig -> IO AriviHandle
getAriviInstance ac = do
    addrinfos <- getAddrInfo Nothing (Just (hostip ac)) (Just (udpport ac))
    let udpServeraddr = head addrinfos
        tcpServeraddr = head $ tail addrinfos

    udpSock <- socket (addrFamily udpServeraddr) Datagram defaultProtocol
    tcpSock <- socket (addrFamily tcpServeraddr) Datagram defaultProtocol

    let ariviUdpSock = (udpSock,addrAddress udpServeraddr)
        arivitcpSock = (tcpSock,addrAddress tcpServeraddr)
        registry     = MP.Registry Map.empty
    udpt <- newEmptyMVar
    tcpt <- newEmptyMVar
    return (AriviHandle ariviUdpSock arivitcpSock udpt tcpt registry)

-- | Starts an arivi instance from ariviHandle which contains all the information required to run
--   an arivi instance.
runAriviInstance :: AriviHandle
                 -> IO ()

runAriviInstance ah = do
    tid1 <- async $ uncurry runUDPServerForever (ariviUDPSock ah) (registry ah)
    tid2 <- async $ uncurry runTCPServerForever (ariviTCPSock ah) (registry ah)

    let threadIDUDP = asyncThreadId tid1
        threadIDTCP = asyncThreadId tid2
    putMVar (udpThread ah) threadIDUDP
    putMVar (udpThread ah) threadIDTCP

    wait tid1
    wait tid2

-- | Register callback functions for subprotocols which will be fired when arivi recieves a
--   message meant for a particular subprotocl essentially passing the control to subprotocol
--   with the message.
register :: AriviHandle
            -> Int               -- Subprotocol Code
            -> (PayLoad -> IO()) -- Subprotocol Message Handler
            -> SubProtocol
            -> Transport
            -> EncryptionType
            -> Encoding
            -> ContextID

register ah key value protocol transport encryptionType encoding = undefined

-- | assigns a unique session for each connection & subprotocol between two nodes which is
--   identified by a sessionID
createSession :: PortNumber
              -> HostAddress
              -> ContextID
              -> SessionId

createSession recPort recHost contextID = undefined

sendMessage :: SessionId -> PayLoad -> IO ()
sendMessage ssid message = undefined

closeSession :: SessionId -> IO ()
closeSession ssid = undefined

resetSession :: SessionId -> IO ()
resetSession ssid = undefined