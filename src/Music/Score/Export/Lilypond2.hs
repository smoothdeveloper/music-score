

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE StandaloneDeriving #-}

module Music.Score.Export.Lilypond2 (
    HasBackend(..),
    HasBackendScore(..),
    HasBackendNote(..),
    export,
    HasMidiProgram,
    Midi,
    toMidi,
    Ly,
    toLilypondString,
    toLilypond,
  ) where

import Music.Pitch.Literal
import Music.Dynamics.Literal
import Music.Score hiding (
  toLilypond,
  toLilypondString,
  toMidi,
  HasMidiProgram(..),
  HasMidiPart(..),
  writeLilypond,
  writeLilypond',
  LilypondOptions,
  Inline,
  showLilypond,
  openLilypond,
  openLilypond',
  )

import Control.Arrow ((***))
import qualified Codec.Midi                as Midi
import qualified Music.Lilypond as Lilypond
import qualified Text.Pretty                  as Pretty
import           Music.Score.Export.Common hiding (MVoice)
import           System.Process
import Data.Default
import Data.Ratio
import Data.Maybe
import Data.Foldable (Foldable)
import qualified Data.Foldable
import Data.Traversable (Traversable, sequenceA)
import Music.Time.Internal.Transform (whilstLD) -- TODO move
import Music.Time.Util (composed, unRatio)
import Data.Colour.Names as Color
-- import           Music.Score.Convert (scoreToVoice, reactiveToVoice')

{-
  Assume that Music is a type function that returns the underlying music
  representation for a given backend.

  Then, for each backend B we need to provide a function
    s a -> Music B
  where s is some score-like type constructor, and a is some note-like type.
  From a we need to fetch each aspect:
    pitch
    dynamic
    articulation
    part
  and convert it to the relevant representation of that aspect in B.
  For example with lilypond we need to convert to LilypondPitch, LilypondDynamic etc.
  Then we need to take s and convert it into some kind of fold for the musical types
  (usually a set of parallel, seequential compositions). Apply the folds, and we're done.
  
  
  
  
  

  chord
  behavior
  tie
  slide

  tremolo
  harmonic
  text
  clef
-}

-- TODO remove this somehow
type HasOrdPart a = (HasPart' a, Ord (Part a))
-- type HasOrdPart a = (a ~ a)



-- |
-- This class defines types and functions for exporting music. It provides the
-- primitive types and methods used to implement 'export'.
--
-- The backend type @b@ is just a type level tag to identify a specific backend.
-- It is typically defined as an empty data declaration.
--
-- The actual conversion is handled by the subclasses 'HasBackendScore' and
-- 'HasBackendNote', which converts the time structure, and the contained music
-- respectively. Thus structure and content are handled separately. 
--
-- It is often necessary to alter the events based on their surrounding context: for
-- examples the beginning and end of spanners and beams depend on surrounding notes. 
-- The 'BackendContext' type allow 'HasBackendScore' instances to provide context for 
-- 'HasBackendNote' instances.
--
-- @
-- data Foo
-- 
-- instance HasBackend Foo where
--   type BackendScore Foo     = []
--   type BackendContext Foo   = Identity
--   type BackendNote Foo      = [(Sum Int, Int)]
--   type BackendMusic Foo     = [(Sum Int, Int)]
--   finalizeExport _ = concat
-- 
-- instance HasBackendScore Foo [a] a where
--   exportScore _ = fmap Identity
-- 
-- instance HasBackendNote Foo a => HasBackendNote Foo [a] where
--   exportNote b ps = mconcat $ map (exportNote b) $ sequenceA ps
-- 
-- instance HasBackendNote Foo Int where
--   exportNote _ (Identity p) = [(mempty ,p)]
-- 
-- instance HasBackendNote Foo a => HasBackendNote Foo (DynamicT (Sum Int) a) where
--   exportNote b (Identity (DynamicT (d,ps))) = set (mapped._1) d $ exportNote b (Identity ps)
-- -- @
--
--
class Functor (BackendScore b) => HasBackend b where
  -- | External music representation
  type BackendMusic b :: *

  -- | Notes, chords and rests, with output handled by 'HasBackendNote' 
  type BackendNote b :: *

  -- | Score, voice and time structure, with output handled by 'HasBackendScore' 
  type BackendScore b :: * -> *

  -- | This type may be used to pass context from 'exportScore' to 'exportNote'.
  --   If the note export is not context-sensitive, 'Identity' can be used.
  type BackendContext b :: * -> *

  finalizeExport :: b -> BackendScore b (BackendNote b) -> BackendMusic b
  
class (HasBackend b) => HasBackendScore b s where
  type ScoreEvent b s :: *
  exportScore :: b -> s -> BackendScore b (BackendContext b (ScoreEvent b s))
  -- default exportScore :: (BackendContext b ~ Identity) => b -> s a -> BackendScore b (BackendContext b a)
  -- exportScore b = fmap Identity

class (HasBackend b) => HasBackendNote b a where
  exportNote  :: b -> BackendContext b a   -> BackendNote b
  exportChord :: b -> BackendContext b [a] -> BackendNote b
  exportChord = error "Not implemented: exportChord"

  -- exportNote' :: (BackendContext b ~ Identity) => b -> a -> BackendNote b
  -- exportNote' b x = exportNote b (Identity x)

export :: (HasBackendScore b s, HasBackendNote b (ScoreEvent b s)) => b -> s -> BackendMusic b
export b = finalizeExport b . export'
  where
    export' = fmap (exportNote b) . exportScore b



data Foo

instance HasBackend Foo where
  type BackendScore Foo     = []
  type BackendContext Foo   = Identity
  type BackendNote Foo      = [(Sum Int, Int)]
  type BackendMusic Foo     = [(Sum Int, Int)]
  finalizeExport _ = concat

instance HasBackendScore Foo [a] where
  type ScoreEvent Foo [a] = a
  exportScore _ = fmap Identity

instance HasBackendNote Foo a => HasBackendNote Foo [a] where
  exportNote b ps = mconcat $ map (exportNote b) $ sequenceA ps

instance HasBackendNote Foo Int where
  exportNote _ (Identity p) = [(mempty ,p)]

instance HasBackendNote Foo a => HasBackendNote Foo (DynamicT (Sum Int) a) where
  exportNote b (Identity (DynamicT (d,ps))) = set (mapped._1) d $ exportNote b (Identity ps)






-- | Class of part types with an associated MIDI program number.
class HasMidiProgram a where
    getMidiChannel :: a -> Midi.Channel
    getMidiProgram :: a -> Midi.Preset
    getMidiChannel _ = 0

instance HasMidiProgram () where
    getMidiProgram _ = 0
instance HasMidiProgram Double where
    getMidiProgram = fromIntegral . floor
instance HasMidiProgram Float where
    getMidiProgram = fromIntegral . floor
instance HasMidiProgram Int where
    getMidiProgram = id
instance HasMidiProgram Integer where
    getMidiProgram = fromIntegral
instance (Integral a, HasMidiProgram a) => HasMidiProgram (Ratio a) where
    getMidiProgram = fromIntegral . floor


-- | A token to represent the Midi backend.
data Midi

-- | We do not need to pass any context to the note export.
type MidiContext = Identity

-- | Every note may give rise to a number of messages. We represent this as a score of messages.
type MidiEvent = Score Midi.Message

type MidiInstr = (Midi.Channel, Midi.Preset)

-- | A Midi file consist of a number of tracks. 
--   Channel and preset info is passed on from exportScore to finalizeExport using this type.
data MidiScore a = MidiScore [(MidiInstr, Score a)] 
  deriving Functor

instance HasBackend Midi where
  type BackendContext Midi    = MidiContext
  type BackendScore   Midi    = MidiScore
  type BackendNote    Midi    = MidiEvent
  type BackendMusic   Midi    = Midi.Midi

  finalizeExport _ (MidiScore trs) = let 
    controlTrack  = [(0, Midi.TempoChange 1000000), (endDelta, Midi.TrackEnd)]
    mainTracks    = fmap (uncurry translMidiTrack . fmap join) trs
    in  
    Midi.Midi fileType (Midi.TicksPerBeat divisions) (controlTrack : mainTracks) 
    
    where
      translMidiTrack :: MidiInstr -> Score (Midi.Message) -> [(Int, Midi.Message)]
      translMidiTrack (ch, p) x = id
        $ addTrackEnd 
        $ setProgramChannel ch p 
        $ scoreToMidiTrack 
        $ x

      -- Each track needs TrackEnd
      -- We place it a long time after last event just in case (necessary?)
      addTrackEnd :: [(Int, Midi.Message)] -> [(Int, Midi.Message)]
      addTrackEnd = (<> [(endDelta, Midi.TrackEnd)])

      setProgramChannel :: Midi.Channel -> Midi.Preset -> Midi.Track Midi.Ticks -> Midi.Track Midi.Ticks
      setProgramChannel ch prg = ([(0, Midi.ProgramChange ch prg)] <>) . fmap (fmap $ setC ch)

      scoreToMidiTrack :: Score Midi.Message -> Midi.Track Midi.Ticks
      scoreToMidiTrack = fmap (\(t,_,x) -> (round ((t .-. 0) ^* divisions), x)) . toRelative . (^. events)

      -- Hardcoded values for Midi export
      -- We always generate MultiTrack (type 1) files with division 1024
      fileType    = Midi.MultiTrack
      divisions   = 1024
      endDelta    = 10000


type instance Part (Voice a) = Part a
type instance SetPart g (Voice a) = Voice (SetPart g a)

-- TODO move
instance (HasParts a b) => HasParts (Voice a) (Voice b) where
  parts = 
    _Wrapped
    . traverse 
    . _Wrapped      -- this needed?
    . whilstLD parts

instance (HasPart' a, HasMidiProgram (Part a)) => HasBackendScore Midi (Voice a) where
  type ScoreEvent Midi (Voice a) = a
  exportScore _ xs = MidiScore [((getMidiChannel (xs^?!parts), getMidiProgram (xs^?!parts)), fmap Identity $ voiceToScore xs)]
    where
      voiceToScore :: Voice a -> Score a
      voiceToScore = error "TODO"

instance (HasPart' a, Ord (Part a), HasMidiProgram (Part a)) => HasBackendScore Midi (Score a) where
  type ScoreEvent Midi (Score a) = a
  exportScore _ xs = MidiScore (map (\(p,sc) -> ((getMidiChannel p, getMidiProgram p), fmap Identity sc)) $ extractParts' xs)

instance HasBackendNote Midi a => HasBackendNote Midi [a] where
  exportNote b ps = mconcat $ map (exportNote b) $ sequenceA ps

instance HasBackendNote Midi Int where
  exportNote _ (Identity pv) = mkMidiNote pv

instance HasBackendNote Midi a => HasBackendNote Midi (DynamicT (Sum Int) a) where
  exportNote b (Identity (DynamicT (Sum v, x))) = fmap (setV v) $ exportNote b (Identity x)

instance HasBackendNote Midi a => HasBackendNote Midi (ArticulationT b a) where
  exportNote b (Identity (ArticulationT (_, x))) = fmap id $ exportNote b (Identity x)

instance HasBackendNote Midi a => HasBackendNote Midi (PartT n a) where
  -- Part structure is handled by HasMidiBackendScore instances, so this is just an identity
  -- TODO use Comonad.extract
  exportNote b = exportNote b . fmap (snd . getPartT)

instance HasBackendNote Midi a => HasBackendNote Midi (TremoloT a) where
  -- TODO use Comonad.extract
  exportNote b = exportNote b . fmap (snd . getTremoloT)

instance HasBackendNote Midi a => HasBackendNote Midi (TextT a) where
  -- TODO use Comonad.extract
  exportNote b = exportNote b . fmap (snd . getTextT)

instance HasBackendNote Midi a => HasBackendNote Midi (HarmonicT a) where
  -- TODO use Comonad.extract
  exportNote b = exportNote b . fmap (snd . getHarmonicT)

instance HasBackendNote Midi a => HasBackendNote Midi (SlideT a) where
  -- TODO use Comonad.extract
  exportNote b = exportNote b . fmap (snd . getSlideT)

instance HasBackendNote Midi a => HasBackendNote Midi (TieT a) where
  -- TODO use Comonad.extract
  exportNote b = exportNote b . fmap (snd . getTieT)

mkMidiNote :: Int -> Score Midi.Message
mkMidiNote p = mempty
    |> pure (Midi.NoteOn 0 (fromIntegral $ p + 60) 64) 
    |> pure (Midi.NoteOff 0 (fromIntegral $ p + 60) 64)

setV :: Midi.Velocity -> Midi.Message -> Midi.Message
setV v = go
  where
    go (Midi.NoteOff c k _)       = Midi.NoteOff c k v
    go (Midi.NoteOn c k _)        = Midi.NoteOn c k v
    go (Midi.KeyPressure c k _)   = Midi.KeyPressure c k v
    go (Midi.ControlChange c n v) = Midi.ControlChange c n v
    go (Midi.ProgramChange c p)   = Midi.ProgramChange c p
    go (Midi.ChannelPressure c p) = Midi.ChannelPressure c p
    go (Midi.PitchWheel c w)      = Midi.PitchWheel c w
    go (Midi.ChannelPrefix c)     = Midi.ChannelPrefix c

setC :: Midi.Channel -> Midi.Message -> Midi.Message
setC c = go
  where
    go (Midi.NoteOff _ k v)       = Midi.NoteOff c k v
    go (Midi.NoteOn _ k v)        = Midi.NoteOn c k v
    go (Midi.KeyPressure _ k v)   = Midi.KeyPressure c k v
    go (Midi.ControlChange _ n v) = Midi.ControlChange c n v
    go (Midi.ProgramChange _ p)   = Midi.ProgramChange c p
    go (Midi.ChannelPressure _ p) = Midi.ChannelPressure c p
    go (Midi.PitchWheel _ w)      = Midi.PitchWheel c w
    go (Midi.ChannelPrefix _)     = Midi.ChannelPrefix c

toMidi :: (HasBackendNote Midi (ScoreEvent Midi s), HasBackendScore Midi s) => s -> Midi.Midi
toMidi = export (undefined::Midi)










-- | A token to represent the Lilypond backend.
data Ly

-- | Hierachical representation of a Lilypond score.
{-
  TODO rewrite so that:
    - Each bar may include voices/layers (a la Sibelius)
    - Each part may generate more than one staff (for piano etc)
-}

-- | A score is a parallel composition of staves.
data LyScore a = LyScore { getLyScore :: [LyStaff a] } deriving (Functor, Eq, Show)

-- | A staff is a sequential composition of bars.
data LyStaff a = LyStaff { getLyStaff :: [LyBar a]   } deriving (Functor, Eq, Show)

-- | A bar is a sequential composition of chords/notes/rests.
data LyBar   a = LyBar   { getLyBar   :: Rhythm a    } deriving (Functor, Eq, Show)

-- | Context passed to the note export.
--   Includes duration and note/rest distinction.
data LyContext a = LyContext Duration (Maybe a) deriving (Functor, Foldable, Traversable, Eq, Show)
instance Monoid Lilypond.Music where
  mempty = pcatLy []
  mappend x y = pcatLy [x,y]

type LyMusic = Lilypond.Music

instance HasBackend Ly where
  type BackendScore Ly   = LyScore
  type BackendContext Ly = LyContext
  type BackendNote Ly    = LyMusic
  type BackendMusic Ly   = LyMusic
  -- TODO staff names etc
  -- TODO clefs
  finalizeExport _ = id
    pcatLy
    -- [LyMusic]
    . fmap (addStaff . {-addPartName "Foo" . -}addClef () . scatLy . map scatRhythm)
    . fmap (fmap getLyBar)
    -- [[Bar]] 
    . fmap (getLyStaff)
    -- [Staff]
    . getLyScore

-- TODO simplify
instance (
  HasPart' a, Ord (Part a), 
  Semigroup a,
  Transformable a, 
  Tiable (SetDynamic DynamicNotation a), 
  Dynamic (SetDynamic DynamicNotation a) ~ DynamicNotation, 
  HasDynamics a (SetDynamic DynamicNotation a),
  Dynamic a ~ Ctxt (OptAvg r), Real r
  ) 
  => HasBackendScore Ly (Score a) where
  type ScoreEvent Ly (Score a) = SetDynamic DynamicNotation a
  exportScore b x = LyScore 
    . map (uncurry exportPart) 
    . extractParts' 
    . simultaneous -- Needed?
    $ x
    where

-- | Export a score as a single staff. Overlapping notes will cause an error.
exportPart :: (Real d, HasDynamics (Score a) (Score b), Dynamic a ~ Ctxt d, Dynamic b ~ DynamicNotation, Tiable b) 
  => Part a -> Score a -> LyStaff (LyContext b)
exportPart p = id
  -- LyStaff (LyContext b)
  . exportStaff
  -- Voice b
  . view singleMVoice
  -- Score b
  . over dynamics dynamicDisplay

exportStaff :: Tiable a => MVoice a -> LyStaff (LyContext a)
exportStaff = LyStaff . map exportBar . splitTies (repeat 1){-TODO get proper bar length-}
  where                      
    exportBar :: Tiable a => MVoice a -> LyBar (LyContext a)
    exportBar = LyBar . toRhythm
    
    -- TODO rename
    splitTies :: Tiable a => [Duration] -> MVoice a -> [MVoice a]
    splitTies ds = map (view $ from unsafeEventsV) . voiceToBars' ds



-- -- |
-- -- Convert a voice score to a list of bars.
-- --
-- voiceToLilypond :: () => [Maybe TimeSignature] -> [Duration] -> Voice (Maybe a) -> [Lilypond]
-- voiceToLilypond barTimeSigs barDurations = zipWith setBarTimeSig barTimeSigs . fmap barToLilypond . voiceToBars' barDurations
-- --
-- -- This is where notation of a single voice takes place
-- --      * voiceToBars is generic for most notations outputs: it handles bar splitting and ties
-- --      * barToLilypond is specific: it handles quantization and notation
-- --
--     where
--         -- TODO compounds
--         setBarTimeSig Nothing x = x
--         setBarTimeSig (Just (getTimeSignature -> (m:_, n))) x = scatLy [Lilypond.Time m n, x]


-- TODO remove
rhythmList :: Iso' (Rhythm a) [a]
rhythmList = undefined

-- XXX What about chords, rests and durations?
scatRhythm :: Rhythm Lilypond -> Lilypond
-- scatRhythm = scatLy . view rhythmList
scatRhythm = rhythmToLilypond . fmap Just

toRhythm :: Tiable a => MVoice a -> Rhythm (LyContext a)
-- toRhythm = view (from rhythmList) . map (uncurry LyContext) . view unsafeEventsV
toRhythm = fmap (LyContext 1) . rewrite . (\(Right x) -> x) . quantize . view unsafeEventsV

rhythmToLilypond :: (a ~ LyMusic) => Rhythm (Maybe a) -> Lilypond
rhythmToLilypond (Beat d x)            = noteRestToLilypond d x
rhythmToLilypond (Dotted n (Beat d x)) = noteRestToLilypond (dotMod n * d) x
rhythmToLilypond (Group rs)            = scatLy $ map rhythmToLilypond rs
rhythmToLilypond (Tuplet m r)          = Lilypond.Times (realToFrac m) (rhythmToLilypond r)
    where (a,b) = fromIntegral *** fromIntegral $ unRatio $ realToFrac m

noteRestToLilypond :: (a ~ LyMusic) => Duration -> Maybe a -> Lilypond
noteRestToLilypond d Nothing  = Lilypond.rest^*(realToFrac d*4)
noteRestToLilypond d (Just p) = Lilypond.removeSingleChords $ toLy d p  
  where
    toLy :: Duration -> LyMusic -> LyMusic
    toLy = error "FIXME"








    
-- Get notes, assume no rests, assume duration 1, put each note in single bar

addStaff :: LyMusic -> LyMusic
addStaff = Lilypond.New "Staff" Nothing

-- TODO
addClef :: () -> LyMusic -> LyMusic
addClef () x = Lilypond.Sequential [Lilypond.Clef Lilypond.Alto, x]

addPartName :: String -> [LyMusic] -> [LyMusic]
addPartName partName xs = longName : shortName : xs
  where
    longName  = Lilypond.Set "Staff.instrumentName" (Lilypond.toValue $ partName)
    shortName = Lilypond.Set "Staff.shortInstrumentName" (Lilypond.toValue $ partName)



  
-- foo = undefined
-- foo :: Score (DynamicT (Ctxt Double) ())
-- foo' = over dynamics dynamicDisplay foo

-- TODO move
deriving instance Num a => Num (Sum a)
deriving instance Real a => Real (Sum a)

instance HasBackendNote Ly a => HasBackendNote Ly [a] where
  exportNote b = exportChord b

instance HasBackendNote Ly Integer where
  -- TODO rest
  exportNote _ (LyContext d (Just x))    = (^*realToFrac (d*4)) . Lilypond.note  . spellLy $ x
  exportChord _ (LyContext d (Just xs))  = (^*realToFrac (d*4)) . Lilypond.chord . fmap spellLy $ xs

instance HasBackendNote Ly Int where 
  exportNote b = exportNote b . fmap toInteger
  exportChord b = exportChord b . fmap (fmap (toInteger))

instance HasBackendNote Ly Float where 
  exportNote b = exportNote b . fmap (toInteger . round)
  exportChord b = exportChord b . fmap (fmap (toInteger . round))

instance HasBackendNote Ly Double where 
  exportNote b = exportNote b . fmap (toInteger . round)
  exportChord b = exportChord b . fmap (fmap (toInteger . round))

instance Integral a => HasBackendNote Ly (Ratio a) where 
  exportNote b = exportNote b . fmap (toInteger . round)

instance HasBackendNote Ly a => HasBackendNote Ly (Behavior a) where
  exportNote b = exportNote b . fmap (! 0)

instance HasBackendNote Ly a => HasBackendNote Ly (Sum a) where
  exportNote b = exportNote b . fmap getSum

instance HasBackendNote Ly a => HasBackendNote Ly (Product a) where
  exportNote b = exportNote b . fmap getProduct

instance HasBackendNote Ly a => HasBackendNote Ly (PartT n a) where
  -- Part structure is handled by HasMidiBackendScore instances, so this is just an identity
  -- TODO use Comonad.extract
  exportNote b = exportNote b . fmap (snd . getPartT)

instance HasBackendNote Ly a => HasBackendNote Ly (DynamicT DynamicNotation a) where
  -- TODO Nothing
  exportNote b (LyContext d (Just (DynamicT (n, x)))) = notate n $ exportNote b $ LyContext d (Just x) -- TODO many
    where
      notate dynNot x = notateDD dynNot x

notateDD :: DynamicNotation -> Lilypond -> Lilypond
notateDD (DynamicNotation (cds, showLevel)) = (rcomposed $ fmap notateCrescDim $ cds) . notateLevel
  where
    -- Use rcomposed as dynamicDisplay returns "mark" order, not application order
    rcomposed = composed . reverse         
    notateCrescDim x = case x of
      NoCrescDim -> id
      BeginCresc -> Lilypond.beginCresc
      EndCresc   -> Lilypond.endCresc
      BeginDim   -> Lilypond.beginDim
      EndDim     -> Lilypond.endDim
    
    -- TODO these literals are not so nice...
    notateLevel = case showLevel of
       Nothing -> id
       Just lvl -> Lilypond.addDynamics (fromDynamics (DynamicsL (Just (fixLevel . realToFrac $ lvl), Nothing)))

instance HasBackendNote Ly a => HasBackendNote Ly (ColorT a) where
  exportNote b (LyContext d (Just (ColorT (col, x)))) = notate col $ exportNote b $ LyContext d (Just x) -- TODO many
    where
      notate (Option Nothing)             = id
      notate (Option (Just (Last color))) = \x -> Lilypond.Sequential [
      -- TODO this syntax will probably change in future Lilypond versions!
        Lilypond.Override "NoteHead#' color" (Lilypond.toLiteralValue $ "#" ++ colorName color),
        x,
        Lilypond.Revert "NoteHead#' color"
        ]

      -- TODO handle any color
      colorName c
        | c == Color.black = "black"
        | c == Color.red   = "red"
        | c == Color.blue  = "blue"
        | otherwise        = error "Unkown color"



instance HasBackendNote Ly a => HasBackendNote Ly (ArticulationT n a) where
  exportNote b = exportNote b . fmap (snd . getArticulationT)
  
instance HasBackendNote Ly a => HasBackendNote Ly (TremoloT a) where
  exportNote b (LyContext d (Just (TremoloT (n, x)))) = exportNote b $ LyContext d (Just x) -- TODO many
    -- where
    -- getL d (TremoloT (Max 0, x)) = exportNote b (LyContext d [x])
    -- getL d (TremoloT (Max n, x)) = notate $ getLilypond newDur x
    --     where
    --         scale   = 2^n
    --         newDur  = (d `min` (1/4)) / scale
    --         repeats = d / newDur
    --         notate = Lilypond.Tremolo (round repeats)

instance HasBackendNote Ly a => HasBackendNote Ly (TextT a) where
  exportNote b (LyContext d (Just (TextT (n, x)))) = notate n (exportNote b $ LyContext d (Just x)) -- TODO many
    where
      notate ts = foldr (.) id (fmap Lilypond.addText ts)

instance HasBackendNote Ly a => HasBackendNote Ly (HarmonicT a) where
  exportNote b = exportNote b . fmap (snd . getHarmonicT)

instance HasBackendNote Ly a => HasBackendNote Ly (SlideT a) where
  exportNote b = exportNote b . fmap (snd . getSlideT)

instance HasBackendNote Ly a => HasBackendNote Ly (TieT a) where
  -- TODO Nothing
  exportNote b (LyContext d (Just (TieT ((Any ta, Any tb), x)))) = notate (exportNote b $ LyContext d (Just x)) -- TODO many
        where
            notate | ta && tb                      = id . Lilypond.beginTie
                   | tb                            = Lilypond.beginTie
                   | ta                            = id
                   | otherwise                     = Lilypond.beginTie

-- type Lilypond = Lilypond.Music
toLilypondString :: (HasBackendNote Ly (ScoreEvent Ly s), HasBackendScore Ly s) => s -> String
toLilypondString = show . Pretty.pretty . toLilypond

toLilypond :: (HasBackendNote Ly (ScoreEvent Ly s), HasBackendScore Ly s) => s -> Lilypond.Music
toLilypond x = export (undefined::Ly) x

aScore :: Score a -> Score a
aScore = id    





-- TODO tests
-- main = putStrLn $ show $ view notes $ simultaneous 
main = do
  showLilypond $ music
  openLilypond $ music
music = (addDynCon.simultaneous)
  --  $ over pitches' (+ 2)
  --  $ text "Hello"
  $ times 2 (scat [
    setColor Color.blue $ level _f $ c<>d,
    cs,
    setColor Color.red $ level _f ds,
    level ff fs,
    level _f a_,
    level pp gs_,
    d,
    e
    ::Score MyNote])^*(2.75)

type MyNote = (PartT Int (TieT (ColorT (ArticulationT () (DynamicT (OptAvg Double) [Double])))))
open :: Score MyNote -> IO ()
open = openLilypond . addDynCon . simultaneous

newtype OptAvg a = OptAvg 
  -- (Option (Average a))
  (Sum a)
  deriving (Semigroup, Monoid, Real, Ord, Num, Eq, Transformable, IsDynamics)
deriving instance AdditiveGroup a => AdditiveGroup (OptAvg a)
instance VectorSpace a => VectorSpace (OptAvg a) where
  type Scalar (OptAvg a) = Scalar a
  s *^ OptAvg v = OptAvg (s *^ v)
instance AffineSpace a => AffineSpace (OptAvg a) where
  type Diff (OptAvg a) = OptAvg (Diff a)
  OptAvg p .-. OptAvg q = OptAvg (p .-. q)
  OptAvg p .+^ OptAvg v = OptAvg (p .+^ v)








deriving instance AdditiveGroup a => AdditiveGroup (Sum a)
instance VectorSpace a => VectorSpace (Sum a) where
  type Scalar (Sum a) = Scalar a
  s *^ Sum v = Sum (s *^ v)
instance AffineSpace a => AffineSpace (Sum a) where
  type Diff (Sum a) = Sum (Diff a)
  Sum p .-. Sum q = Sum (p .-. q)
  Sum p .+^ Sum v = Sum (p .+^ v)
  
instance IsDynamics a => IsDynamics (Sum a) where
  fromDynamics = Sum . fromDynamics
instance HasPitches a b => HasPitches (Sum a) (Sum b) where
  pitches = _Wrapped . pitches
instance IsPitch a => IsPitch (Sum a) where
  fromPitch = Sum . fromPitch
type instance Pitch (Sum a) = Pitch a
type instance SetPitch b (Sum a) = Sum (SetPitch b a)




-- Or use type (NonEmpty a -> a)
average :: Fractional a => [a] -> Maybe a
average = fmap getAverage . getOption . Data.Foldable.foldMap (Option . Just . avg)

newtype Average a = Average (Sum Integer, Sum a)
  deriving (Semigroup, Eq, Ord)

avg :: a -> Average a
avg x = Average (1, Sum x)

getAverage :: Fractional a => Average a -> a
getAverage (Average (Sum n, Sum x)) = x / fromInteger n

instance (Show a, Fractional a) => Show (Average a) where
  show n = "Average {getAverage = " ++ show (getAverage n) ++ "}"







pcatLy :: [Lilypond] -> Lilypond
pcatLy = pcatLy' False

pcatLy' :: Bool -> [Lilypond] -> Lilypond
pcatLy' p = foldr Lilypond.simultaneous e
    where
        e = Lilypond.Simultaneous p []

scatLy :: [Lilypond] -> Lilypond
scatLy = foldr Lilypond.sequential e
    where
        e = Lilypond.Sequential []

spellLy :: Integer -> Lilypond.Note
spellLy a = Lilypond.NotePitch (spellLy' a) Nothing

spellLy' :: Integer -> Lilypond.Pitch
spellLy' p = Lilypond.Pitch (
    toEnum $ fromIntegral pc,
    fromIntegral alt,
    fromIntegral oct
    )
    where (pc,alt,oct) = spellPitch (p + 72)







-- TODO generalize level
newtype DynamicNotation = DynamicNotation { getDynamicNotation :: ([CrescDim], Maybe Double) }

type instance Dynamic DynamicNotation = DynamicNotation

instance Wrapped DynamicNotation where
  type Unwrapped DynamicNotation = ([CrescDim], Maybe Double)
  _Wrapped' = iso getDynamicNotation DynamicNotation

instance Transformable DynamicNotation where
  transform _ = id
instance Tiable DynamicNotation where
  toTied (DynamicNotation (beginEnd, marks)) = (DynamicNotation (beginEnd, marks), DynamicNotation (mempty, Nothing))
  -- TODO important!

fixLevel :: Double -> Double
fixLevel x = (fromIntegral $ round (x - 0.5)) + 0.5

data CrescDim = NoCrescDim | BeginCresc | EndCresc | BeginDim | EndDim

instance Monoid CrescDim where
  mempty = NoCrescDim
  mappend a _ = a

-- TODO use any
-- type ShowDyn = Bool

mapCtxt :: (a -> b) -> Ctxt a -> Ctxt b
mapCtxt f (a,b,c) = (fmap f a, f b, fmap f c)

extractCtxt :: Ctxt a -> a
extractCtxt (_,x,_) = x

-- Given a dynamic value and its context, decide:
--   
--   1) Whether we should begin or end a crescendo or diminuendo
--   2) Whether we should display the current dynamic value
--   
dynamicDisplay :: (Ord a, Real a) => Ctxt a -> DynamicNotation
dynamicDisplay x = DynamicNotation $ over _2 (\t -> if t then Just (realToFrac $ extractCtxt x) else Nothing) $ case x of
  (Nothing, y, Nothing) -> ([], True)
  (Nothing, y, Just z ) -> case (y `compare` z) of
    LT      -> ([BeginCresc], True)
    EQ      -> ([],           True)
    GT      -> ([BeginDim],   True)
  (Just x,  y, Just z ) -> case (x `compare` y, y `compare` z) of
    (LT,LT) -> ([NoCrescDim], False)
    (LT,EQ) -> ([EndCresc],   True)
    (EQ,LT) -> ([BeginCresc], False{-True-})
  
    (GT,GT) -> ([NoCrescDim], False)
    (GT,EQ) -> ([EndDim],     True)
    (EQ,GT) -> ([BeginDim],   False{-True-})
  
    (EQ,EQ) -> ([],                   False)
    (LT,GT) -> ([EndCresc, BeginDim], True)
    (GT,LT) -> ([EndDim, BeginCresc], True)
  
  
  (Just x,  y, Nothing) -> case (x `compare` y) of
    LT      -> ([EndCresc],   True)
    EQ      -> ([],           False)
    GT      -> ([EndDim],     True)   
                                      
                                      






-- |
-- Convert a score to a Lilypond representaiton and print it on the standard output.
--
-- showLilypond :: (HasLilypond2 a, HasPart2 a, Semigroup a) => Score a -> IO ()
showLilypond = putStrLn . toLilypondString

-- |
-- Convert a score to a Lilypond representation and write to a file.
--
-- writeLilypond :: (HasLilypond2 a, HasPart2 a, Semigroup a) => FilePath -> Score a -> IO ()
writeLilypond = writeLilypond' def

data LilypondOptions
    = LyInlineFormat
    | LyScoreFormat
instance Default LilypondOptions where
    def = LyInlineFormat

-- |
-- Convert a score to a Lilypond representation and write to a file.
--
-- writeLilypond' :: (HasLilypond2 a, HasPart2 a, Semigroup a) => LilypondOptions -> FilePath -> Score a -> IO ()
writeLilypond' options path sc = writeFile path $ (lyFilePrefix ++) $ toLilypondString sc
    where
        title    = fromMaybe "" $ flip getTitleAt 0                  $ metaAtStart sc
        composer = fromMaybe "" $ flip getAttribution "composer"     $ metaAtStart sc

        lyFilePrefix = case options of
            LyInlineFormat -> lyInlinePrefix
            LyScoreFormat  -> lyScorePrefix

        lyInlinePrefix = mempty                                        ++
            "%%% Generated by music-score %%%\n"                       ++
            "\\include \"lilypond-book-preamble.ly\"\n"                ++
            "\\paper {\n"                                              ++
            "  #(define dump-extents #t)\n"                            ++
            "\n"                                                       ++
            "  indent = 0\\mm\n"                                       ++
            "  line-width = 210\\mm - 2.0 * 0.4\\in\n"                 ++
            "  ragged-right = ##t\n"                                   ++
            "  force-assignment = #\"\"\n"                             ++
            "  line-width = #(- line-width (* mm  3.000000))\n"        ++
            "}\n"                                                      ++
            "\\header {\n"                                             ++
            "  title = \"" ++ title ++ "\"\n"                          ++
            "  composer = \"" ++ composer ++ "\"\n"                    ++
            "}\n"                                                      ++
            "\\layout {\n"                                             ++
            "}"                                                        ++
            "\n\n"

        lyScorePrefix = mempty                                         ++
            "\\paper {"                                                ++
            "  indent = 0\\mm"                                         ++
            "  line-width = 210\\mm - 2.0 * 0.4\\in"                   ++
            "}"                                                        ++
            "\\header {\n"                                             ++
            "  title = \"" ++ title ++ "\"\n"                          ++
            "  composer = \"" ++ composer ++ "\"\n"                    ++
            "}\n"                                                      ++
            "\\layout {"                                               ++
            "}" ++
            "\n\n"


-- |
-- Typeset a score using Lilypond and open it.
--
-- /Note/ This is simple wrapper around 'writeLilypond' that may not work well on all platforms.
--
-- openLilypond :: (HasLilypond2 a, HasPart2 a, Semigroup a) => Score a -> IO ()
openLilypond = openLilypond' def

-- openLilypond' :: (HasLilypond2 a, HasPart2 a, Semigroup a) => LilypondOptions -> Score a -> IO ()
openLilypond' options sc = do
    writeLilypond' options "test.ly" sc
    runLilypond
    cleanLilypond
    openLilypond''

runLilypond    = void $ runCommand "lilypond -f pdf test.ly 2>/dev/null" >>= waitForProcess
cleanLilypond  = void $ runCommand "rm -f test-*.tex test-*.texi test-*.count test-*.eps test-*.pdf test.eps"
openLilypond'' = void $ runCommand $ openCommand ++ " test.pdf"
