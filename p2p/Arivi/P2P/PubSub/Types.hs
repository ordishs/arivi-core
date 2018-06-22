module Arivi.P2P.PubSub.Types
    (
    ) where

import           Arivi.P2P.MessageHandler.HandlerTypes

import           Control.Concurrent.STM.TQueue
import           Control.Concurrent.STM.TVar

import           Data.Digest.Murmur32
import           Data.HashMap.Strict                   as HM
import           Data.Time.Clock

type TopicId = String

type ServiceId = String

type TopicMessage = ByteString

type ResponseCode = Int

data MessageTypePubSub
    = Subscribe { topicId :: TopicId
                , timer   :: NominalDiffTime }
    | Notify { topicId      :: TopicId
             , topicMessage :: TopicMessage }
    | Publish { topicId      :: TopicId
              , topicMessage :: TopicMessage }
    | Response { responseCode :: ResponseCode
               , timer        :: NominalDiffTime }

data NodeTimer = NodeTimer
    { nodeId :: NodeId
    , timer  :: NominalDiffTime
    }

instance Ord NodeTimer where
    x <= y = timer x <= timer y
    x > y = timer x > timer y
    x < y = timer x < timer y
    x >= y = timer x >= timer y

instance Eq NodeTimer where
    x == y = nodeId x == nodeId y

type TopicMap
     = HM.Hashmap TopicId ( ServiceId
                          , TVar [NodeTimer]
                          , TVar [NodeTimer]
                          , TQueue TopicMessage -- need to use sorted list on nodeTimer
                           )

type MessageHashMap = HM.HashMap Hash32 TVar (Bool, [NodeId])
