{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RankNTypes #-}

import Control.Lens
import Control.Monad.Fix
import Data.Align
import Data.AppendMap (AppendMap)
import qualified Data.AppendMap as AMap
import Data.Functor.Misc
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Semigroup
import Data.These

import Reflex
import Reflex.Patch.MapWithMove
import Test.Run

newtype MyQuery = MyQuery SelectedCount
  deriving (Show, Read, Eq, Ord, Monoid, Semigroup, Additive, Group)

instance Query MyQuery where
  type QueryResult MyQuery = ()
  crop _ _ = ()

instance (Ord k, Query a, Eq (QueryResult a)) => Query (Selector k a) where
  type QueryResult (Selector k a) = Selector k (QueryResult a)
  crop q r = undefined

newtype Selector k a = Selector { unSelector :: AppendMap k a }
  deriving (Show, Read, Eq, Ord, Functor)

instance (Ord k, Eq a, Monoid a) => Semigroup (Selector k a) where
  (Selector a) <> (Selector b) = Selector $ fmapMaybe id $ f a b
    where
      f = alignWith $ \case
        This x -> Just x
        That y -> Just y
        These x y ->
          let z = x `mappend` y
          in if z == mempty then Nothing else Just z

instance (Ord k, Eq a, Monoid a) => Monoid (Selector k a) where
  mempty = Selector AMap.empty
  mappend = (<>)

instance (Eq a, Ord k, Group a) => Group (Selector k a) where
  negateG = fmap negateG

instance (Eq a, Ord k, Group a) => Additive (Selector k a)

main :: IO ()
main = do
  [0, 1, 1, 0] <- fmap (map fst . concat) $
    runApp (testQueryT testRunWithReplace) () $ map (Just . That) $
      [ That (), This (), That () ]
  [0, 1, 1, 0] <- fmap (map fst . concat) $
    runApp (testQueryT testSequenceDMapWithAdjust) () $ map (Just . That) $
      [ That (), This (), That () ]
  [0, 1, 1, 0] <- fmap (map fst . concat) $
    runApp (testQueryT testSequenceDMapWithAdjustWithMove) () $ map (Just . That) $
      [ That (), This (), That () ]
  return ()

testQueryT :: (Reflex t, MonadFix m)
           => (Event t () -> Event t () -> QueryT t (Selector Int MyQuery) m ())
           -> AppIn t () (These () ())
           -> m (AppOut t Int Int)
testQueryT w (AppIn _ pulse) = do
  let replace = fmapMaybe (^? here) pulse
      increment = fmapMaybe (^? there) pulse
  (_, q) <- runQueryT (w replace increment) $ pure mempty
  let qDyn = head . AMap.keys . unSelector <$> incrementalToDynamic q
  return $ AppOut
    { _appOut_behavior = current qDyn
    , _appOut_event = updated qDyn
    }

testRunWithReplace :: ( Reflex t
                      , MonadAdjust t m
                      , MonadHold t m
                      , MonadFix m
                      , MonadQuery t (Selector Int MyQuery) m)
                   => Event t ()
                   -> Event t ()
                   -> m ()
testRunWithReplace replace increment = do
  let w = do
        n <- count increment
        queryDyn $ zipDynWith (\x y -> Selector (AMap.singleton (x :: Int) y)) n $ pure $ MyQuery $ SelectedCount 1
  _ <- runWithReplace w $ w <$ replace
  return ()

testSequenceDMapWithAdjust :: ( Reflex t
                              , MonadAdjust t m
                              , MonadHold t m
                              , MonadFix m
                              , MonadQuery t (Selector Int MyQuery) m)
                           => Event t ()
                           -> Event t ()
                           -> m ()
testSequenceDMapWithAdjust replace increment = do
  _ <- listHoldWithKey (Map.singleton () ()) (Map.singleton () (Just ()) <$ replace) $ \_ _ -> do
    n <- count increment
    queryDyn $ zipDynWith (\x y -> Selector (AMap.singleton (x :: Int) y)) n $ pure $ MyQuery $ SelectedCount 1
  return ()

testSequenceDMapWithAdjustWithMove :: ( Reflex t
                                      , MonadAdjust t m
                                      , MonadHold t m
                                      , MonadFix m
                                      , MonadQuery t (Selector Int MyQuery) m)
                                   => Event t ()
                                   -> Event t ()
                                   -> m ()
testSequenceDMapWithAdjustWithMove replace increment = do
  _ <- listHoldWithKeyWithMove (Map.singleton () ()) (Map.singleton () (Just ()) <$ replace) $ \_ _ -> do
    n <- count increment
    queryDyn $ zipDynWith (\x y -> Selector (AMap.singleton (x :: Int) y)) n $ pure $ MyQuery $ SelectedCount 1
  return ()

listHoldWithKey :: forall t m k v a. (Ord k, MonadHold t m, MonadAdjust t m) => Map k v -> Event t (Map k (Maybe v)) -> (k -> v -> m a) -> m (Dynamic t (Map k a))
listHoldWithKey m0 m' f = do
  let dm0 = mapWithFunctorToDMap $ Map.mapWithKey f m0
      dm' = fmap (PatchDMap . mapWithFunctorToDMap . Map.mapWithKey (\k v -> ComposeMaybe $ fmap (f k) v)) m'
  (a0, a') <- sequenceDMapWithAdjust dm0 dm'
  fmap dmapToMap . incrementalToDynamic <$> holdIncremental a0 a'


-- scam it out to test traverseDMapWithAdjustWithMove
listHoldWithKeyWithMove :: forall t m k v a. (Ord k, MonadHold t m, MonadAdjust t m) => Map k v -> Event t (Map k (Maybe v)) -> (k -> v -> m a) -> m (Dynamic t (Map k a))
listHoldWithKeyWithMove m0 m' f = do
  (n0, n') <- mapMapWithAdjustWithMove f m0 $ ffor m' $ PatchMapWithMove . Map.map (\v -> NodeInfo (maybe From_Delete From_Insert v) Nothing)
  incrementalToDynamic <$> holdIncremental n0 n'
-- -}
