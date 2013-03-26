                              
{-# LANGUAGE
    TypeFamilies,
    DeriveFunctor,
    DeriveFoldable,
    FlexibleInstances,
    GeneralizedNewtypeDeriving #-} 

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
-- Provides a musical score represenation.
--
-------------------------------------------------------------------------------------


module Music.Score.Voice (
        HasVoice(..),
        VoiceT(..),
        voices,
        mapVoices,
        getVoices,
        setVoices,
        modifyVoices,
  ) where

import Control.Monad (ap, mfilter, join, liftM, MonadPlus(..))
import Data.Foldable
import Data.Traversable
import qualified Data.List as List
import Data.VectorSpace
import Data.AffineSpace
import Data.Ratio

import Music.Score.Part
import Music.Score.Score
import Music.Score.Duration
import Music.Score.Time
import Music.Score.Ties

-- See commment in Tie module
instance Tiable a => Tiable (VoiceT a) where
    toTied (VoiceT (v,a)) = (VoiceT (v,b), VoiceT (v,c)) where (b,c) = toTied a


class HasVoice a where
    -- | 
    -- Associated voice type. Should implement 'Eq' and 'Show' to be usable.
    -- 
    type Voice a :: *

    -- |
    -- Get the voice of the given note.
    -- 
    getVoice :: a -> Voice a

    -- |
    -- Set the voice of the given note.
    -- 
    setVoice :: Voice a -> a -> a

    -- |
    -- Modify the voice of the given note.
    -- 
    modifyVoice :: (Voice a -> Voice a) -> a -> a
   
    setVoice n = modifyVoice (const n)
    modifyVoice f x = x

newtype VoiceT a = VoiceT { getVoiceT :: (String, a) }

instance HasVoice ()                            where   { type Voice ()         = String ; getVoice _ = "" }
instance HasVoice Double                        where   { type Voice Double     = String ; getVoice _ = "" }
instance HasVoice Float                         where   { type Voice Float      = String ; getVoice _ = "" }
instance HasVoice Int                           where   { type Voice Int        = String ; getVoice _ = "" }
instance HasVoice Integer                       where   { type Voice Integer    = String ; getVoice _ = "" }
instance Integral a => HasVoice (Ratio a)       where   { type Voice (Ratio a)  = String ; getVoice _ = "" }

instance HasVoice (String, a) where   
    type Voice (String, a) = String
    getVoice (v,_) = v
    modifyVoice f (v,x) = (f v, x)
instance HasVoice a => HasVoice (Bool, a, Bool) where   
    type Voice (Bool, a, Bool) = Voice a
    getVoice (_,x,_) = getVoice x

instance HasVoice (VoiceT a) where   
    type Voice (VoiceT a)        = String
    getVoice (VoiceT (v,_))      = v
    modifyVoice f (VoiceT (v,x)) = VoiceT (f v, x)
instance HasVoice a => HasVoice (TieT a) where   
    type Voice (TieT a) = Voice a
    getVoice (TieT (_,x,_)) = getVoice x




-- | 
-- Extract parts from the given score. Returns a list of single-part score. A dual of @pcat@.
--
-- > Score a -> [Score a]
--
voices :: (HasVoice a, Eq v, v ~ Voice a, MonadPlus s, Foldable s) => s a -> [s a]
voices sc = fmap (flip extract $ sc) (getVoices sc) 
    where                    
        extract v = mfilter ((== v) . getVoice)

-- |
-- Map over the voices in a given score.
--
-- > ([Score a] -> [Score a]) -> Score a -> Score a
--
mapVoices :: (HasVoice a, Eq v, v ~ Voice a, MonadPlus s, Foldable s) => ([s a] -> [s b]) -> s a -> s b
mapVoices f = msum . f . voices

-- |
-- Get all voices in the given score. Returns a list of voices.
--
-- > Score a -> [Voice]
--
getVoices :: (HasVoice a, Eq v, v ~ Voice a, Foldable s) => s a -> [Voice a]
getVoices = List.nub . fmap getVoice . toList

-- |
-- Set all voices in the given score.
--
-- > Voice -> Score a -> Score a
--
setVoices :: (HasVoice a, Functor s) => Voice a -> s a -> s a
setVoices n = fmap (setVoice n)

-- |
-- Modify all voices in the given score.
--
-- > (Voice -> Voice) -> Score a -> Score a
--
modifyVoices :: (HasVoice a, Functor s) => (Voice a -> Voice a) -> s a -> s a
modifyVoices n = fmap (modifyVoice n)


