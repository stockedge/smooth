module Types.KShape where

import Prelude hiding (Real, (&&), (||), not, max, min, Ord (..), product, map)
import FwdMode ((:~>), fstD, sndD, getDerivTower, (@.))
import FwdPSh
import Types.SmoothBool
import Types.OShape (OShape)
import qualified Types.OShape as O

type KShape a = (a :=> SBool) :=> SBool

point :: Additive g => PShD a => a g -> KShape a g
point x = ArrD $ \wk f -> f # dmap wk x

compactUnion :: Additive g => KShape a g -> (a :=> KShape b) g -> KShape b g
compactUnion i f = ArrD $ \wk p ->
  dmap wk i # (ArrD $ \wk' x -> (dmap (wk @. wk') f # x) # dmap wk' p)

empty :: KShape a g
empty = ArrD $ \_ p -> true

union :: Additive g => KShape a g -> KShape a g -> KShape a g
union k k' = ArrD $ \wk p -> dmap wk k # p && dmap wk k' # p

intersect :: Additive g => KShape a g -> OShape a g -> KShape a g
intersect k o = ArrD $ \wk p ->
  dmap wk k # (ArrD $ \wk' x -> not (dmap (wk @. wk') o # x) || dmap wk' p # x)

difference :: Additive g => KShape a g -> OShape a g -> KShape a g
difference k o = intersect k (O.complement o)

map :: Additive g => (a :=> b) g -> KShape a g -> KShape b g
map f k = ArrD $ \wk p -> dmap wk k # ArrD (\wk' x -> dmap wk' p # (dmap (wk @. wk') f # x))

forall :: Additive g => KShape a g -> (a :=> SBool) g -> SBool g
forall k p = k # p

exists :: Additive g =>  KShape a g -> (a :=> SBool) g -> SBool g
exists k p = not (k # ArrD (\wk x -> not (dmap wk p # x)))

isEmpty :: Additive g => KShape a g -> SBool g
isEmpty k = k # ArrD (\_ _ -> false)

infimum :: Additive g => KShape DReal g -> DReal g
infimum k = dedekind_cut $ ArrD (\wk q -> forall (dmap wk k) (ArrD (\wk' x -> dmap wk' q < x)))

supremum :: Additive g => KShape DReal g -> DReal g
supremum k = dedekind_cut $ ArrD (\wk q -> exists (dmap wk k) (ArrD (\wk' x -> dmap wk' q < x)))

inf :: Additive g => KShape a g -> (a :=> DReal) g -> DReal g
inf k f = infimum (map f k)

sup :: Additive g => KShape a g -> (a :=> DReal) g -> DReal g
sup k f = supremum (map f k)

hausdorffDist :: Additive g => PShD a =>
  (a :* a :=> DReal) g -> KShape a g -> KShape a g -> DReal g
hausdorffDist d k k' =
  mx (sup k  (ArrD (\wk x  -> inf (dmap wk k') (ArrD (\wk' x' -> dmap (wk @. wk') d # (dmap wk' x :* x'))))))
     (sup k' (ArrD (\wk x' -> inf (dmap wk k ) (ArrD (\wk' x  -> dmap (wk @. wk') d # (x :* dmap wk' x'))))))
  where
  mx (R x) (R y) = R (max x y)

separationDist :: Additive g => PShD a =>
  (a :* a :=> DReal) g -> KShape a g -> KShape a g -> DReal g
separationDist d k k' =
  inf k' (ArrD (\wk x' -> inf (dmap wk k ) (ArrD (\wk' x  -> dmap (wk @. wk') d # (x :* dmap wk' x')))))

unit_interval :: Additive g => KShape DReal g
unit_interval = ArrD $ \_ -> forall01