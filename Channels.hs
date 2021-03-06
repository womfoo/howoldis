module Channels (DiffChannel (..), channels, age, jobset) where

import Control.Monad (liftM)
import Data.List (isPrefixOf)
import Network.HTTP (simpleHTTP, getRequest, getResponseBody)
import Data.Text (pack, unpack, strip)
import Text.HTML.TagSoup (sections, (~==), (~/=), innerText, parseTags)
import Data.Time.Clock (UTCTime, NominalDiffTime, getCurrentTime, diffUTCTime)
import Data.Time.Format (parseTimeM, defaultTimeLocale)
import Data.Time.LocalTime (localTimeToUTC, hoursToTimeZone)


data Channel = Channel { name :: String
                       , time :: Either String UTCTime
                       } deriving (Show)

data DiffChannel = DiffChannel { dname :: String
                               , dtime :: String
                               } deriving (Show)

openURL :: String -> IO String
openURL url = getResponseBody =<< simpleHTTP (getRequest url)

channelsPage :: IO String
channelsPage = openURL "http://nixos.org/channels/"

parseTime :: String -> Either String UTCTime
parseTime = liftM (localTimeToUTC tz) . parseTimeM True defaultTimeLocale format . strip'
  where format = "%F %R"
        tz = hoursToTimeZone 1 -- CET
        strip' = unpack . strip . pack

-- |The list of the current NixOS channels
channels :: IO [DiffChannel]
channels = do
  chans <- liftM findGoodChannels channelsPage
  mapM makeDiffChannel chans
    where findGoodChannels = filter isRealdDir . findChannels . parseTags
          isRealdDir channel = not $ "Parent" `isPrefixOf` name channel
          findChannels = map makeChannel . filter isNotHeader . sections (~== "<tr>")
          isNotHeader = (~/= "<th>") . head . drop 1
          makeDiffChannel c = do
            diff <- age c
            return $ DiffChannel (name c) diff
          makeChannel x = Channel name time
            where name = init . takeTextOf "<a>" $ x
                  time = parseTime . takeTextOf "<td align=right>" $ x
                  takeTextOf t = innerText . take 2 . dropWhile (~/= t)

age :: Channel -> IO String
age channel = do current <- getCurrentTime
                 let diff = diffUTCTime current <$> time channel
                 return (either id humanTimeDiff diff)

humanTimeDiff :: NominalDiffTime -> String
humanTimeDiff d
  | days > 1 = doShow days "days"
  | hours > 1 = doShow hours "hours"
  | minutes > 1 = doShow minutes "minutes"
  | otherwise = doShow d "seconds"
  where minutes = d / 60
        hours = minutes / 60
        days = hours / 24
        doShow x unit = (show $ truncate x) ++ " " ++ unit


jobset :: DiffChannel -> Maybe String
jobset channel = j (dname channel)
  where j "nixos-unstable" = Just "nixos/trunk-combined/tested"
        j "nixos-unstable-small" = Just "nixos/unstable-small/tested"
        j "nixpkgs-unstable" = Just "nixpkgs/trunk/unstable"
        j c | "nixos-" `isPrefixOf` c = Just $ "nixos/release-" ++ (drop 6 c) ++ "/tested"
        j _ = Nothing
