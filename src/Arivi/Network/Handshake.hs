module Arivi.Network.Handshake
(
    initiatorHandshake,
    recipientHandshake,
    receiveHandshakeResponse
) where

import           Arivi.Crypto.Utils.PublicKey.Utils
import qualified Arivi.Network.Connection           as Conn
import           Arivi.Network.HandshakeUtils
import           Arivi.Network.Types                (ConnectionId,
                                                     HandshakeInitMasked (..),
                                                     HandshakeRespMasked (..),
                                                     NodeId, Opcode (..),
                                                     Parcel (..), Version (..))
import           Arivi.Network.Utils
import           Codec.Serialise
import qualified Crypto.PubKey.Ed25519              as Ed25519
import           Data.ByteArray
import           Data.ByteString.Char8              as B
import qualified Data.ByteString.Lazy               as L


-- | Takes the static secret key and connection object and returns a serialized KeyExParcel along with the updated connection object
initiatorHandshake :: Ed25519.SecretKey -> Conn.Connection -> IO (L.ByteString, Conn.Connection)
initiatorHandshake sk conn = do
        -- Generate an ephemeral keypair. Get a new connection with ephemeral keys populated
        newconn <- generateEphemeralKeys conn
        -- Get handshake init message and updated connection object with temp shared secret key
        let (hsInitMsg, updatedConn) = createHandshakeInitMsg sk newconn
        hsParcel <- generateInitParcel (lazyToStrict hsInitMsg) updatedConn
        return (serialise hsParcel, updatedConn)

-- | Takes receiver static secret key, connection object and the received msg and returns a Lazy Bytestring along with the updated connection object
recipientHandshake :: Ed25519.SecretKey -> Conn.Connection -> L.ByteString -> IO (L.ByteString, Conn.Connection)
recipientHandshake sk conn msg = do
    let (hsInitMsg, senderEphNodeId) = readHandshakeMsg sk conn msg
    --if verification returns false, do something
    print $ verifySignature sk senderEphNodeId hsInitMsg
    -- Generate an ephemeral keypair. Get a new connection with ephemeral keys populated
    newconn <- generateEphemeralKeys conn
    let eSKSign = Conn.ephemeralPrivKey newconn
    -- Get updated connection structure with final shared secret key for session
    let updatedConn = extractSecrets newconn senderEphNodeId eSKSign
    -- NOTE: Need to delete the ephemeral key pair from the connection object as it is not needed once shared secret key is derived
    let hsRespMsg = createHandshakeRespMsg updatedConn
    hsRespParcel <- generateRespParcel (lazyToStrict hsRespMsg) updatedConn
    return (serialise hsRespParcel, updatedConn)


-- | Initiator receives response from remote and returns updated connection object
receiveHandshakeResponse :: Conn.Connection -> L.ByteString -> Conn.Connection
receiveHandshakeResponse conn msg = updatedConn where
    (hsRespMsg, updatedConn) = readHandshakeResp conn msg
    -- Need to delete ephemeral keypair from updated conn object

