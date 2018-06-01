module Arivi.Utils.Exception (
    AriviException(..)
) where

import           Codec.Serialise   (DeserialiseFailure)
import           Control.Exception
import           Crypto.Error      (CryptoError (..))

data AriviException =       AriviDeserialiseException DeserialiseFailure
                            | AriviCryptoException CryptoError
                            | AriviSignatureVerificationFailedException
                            | AriviSocketException deriving(Show)

instance Exception AriviException