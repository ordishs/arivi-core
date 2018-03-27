module Network.Arivi.Types 
(
Payload     (..),
Frame       (..),
Socket,
SockAddr 
) where 

import           Network.Socket     
import qualified Data.ByteString.Char8              as C 
import qualified Data.Map.Strict                    as Map 
import           Data.UUID                                  (UUID)
import           Data.Int                                   (Int16,Int64)   

-- | Structure to hold the Payload which arivi will send and receive (PENDING)

type ConnectionId   = Int64  
type PayloadLength  = Int16    
type FragmentNumber = Integer 
type MessageId      = UUID 
type SubProtocol    = Int 

data Frame   = Frame {
                    version       :: Version 
                ,   payLoadMarker :: PayloadMarker 
                ,   opcode        :: Opcode 
                ,   publicFlags   :: PublicFlags     
                ,   payload       :: Payload 
                ,   connectionId  :: ConnectionId   
                ,   payloadLength :: PayloadLength 
                ,   transport     :: Transport
                ,   encoding      :: Encoding 
            } deriving (Show)

data Version
    = V0 
    | V1 
    deriving (Eq, Ord, Show)

data PayloadMarker = PayloadMarker {
                    subProtocol    :: SubProtocol 
                ,   fragmentNumber :: FragmentNumber
                ,   messageId      :: MessageId
            } deriving (Show)

data Opcode       = ERROR 
                    | HANDSHAKE_REQUEST 
                    | HANDSHAKE_REPONSE 
                    | OPTIONS 
                    | RESET 
                    | CLOSE 
                    | PING  
                    | PONG 
                    deriving (Show)

data PublicFlags  = PublicFlags {
                    finalFragment :: Bool 
                ,   textOrBinary  :: Bool 
                ,   initiator     :: Bool 
                ,   ecncryption   :: EncryptionType 
            } deriving (Show)

data EncryptionType = NONE 
                      | AES_CTR
                      | CHA_CHA_POLY 
                      deriving (Show)
                      
data Payload = Payload C.ByteString 
               deriving (Show)

data Transport = UDP 
                 | TCP 
                 deriving (Show)
                 
data Encoding = UTF_8
                | ASCII 
                | CBOR 
                | JSON 
                | PROTO_BUFF 
                deriving (Show)
               

                    