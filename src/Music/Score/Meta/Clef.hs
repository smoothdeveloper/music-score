
{-# LANGUAGE ConstraintKinds            #-}
{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE DeriveFoldable             #-}
{-# LANGUAGE DeriveFunctor              #-}
{-# LANGUAGE DeriveTraversable          #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE TypeFamilies               #-}

-------------------------------------------------------------------------------------
-- |
-- Copyright   : (c) Hans Hoglund 2012
--
-- License     : BSD-style
--
-- Maintainer  : hans@hanshoglund.se
-- Stability   : experimental
-- Portability : non-portable (TF,GNTD)
--
-------------------------------------------------------------------------------------

module Music.Score.Meta.Clef (
        -- * Clef type
        Clef(..),

        -- ** Adding clefs to scores
        clef,
        clefDuring,

        -- ** Extracting clefs
        withClef,
  ) where

import           Control.Arrow
import           Control.Lens (view)
import           Control.Monad.Plus
import           Data.Foldable             (Foldable)
import qualified Data.Foldable             as F
import qualified Data.List                 as List
import           Data.Map                  (Map)
import qualified Data.Map                  as Map
import           Data.Maybe
import           Data.Monoid.WithSemigroup
import           Data.Semigroup
import           Data.Set                  (Set)
import qualified Data.Set                  as Set
import           Data.String
import           Data.Traversable          (Traversable)
import qualified Data.Traversable          as T
import           Data.Typeable
import           Data.Void

import           Music.Pitch.Literal
import           Music.Score.Meta
import           Music.Score.Part
import           Music.Score.Pitch
import           Music.Score.Util
import           Music.Time
import           Music.Time.Reactive

data Clef = GClef | CClef | FClef
    deriving (Eq, Ord, Show, Typeable)

-- | Set clef of the given score.
clef :: (HasMeta a, {-HasPart' a,-} HasPosition a) => Clef -> a -> a
clef c x = clefDuring (_era x) c x

-- | Set clef of the given part of a score.
clefDuring :: (HasMeta a{-, HasPart' a-}) => Span -> Clef -> a -> a
clefDuring s c = addMetaNote $ view note (s, (Option $ Just $ Last c))

-- | Extract the clef in from the given score, using the given default clef.
withClef :: {-HasPart' a =>-} Clef -> (Clef -> Score a -> Score a) -> Score a -> Score a
withClef def f = withMeta (f . fromMaybe def . fmap getLast . getOption)

