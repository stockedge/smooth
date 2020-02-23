{-# LANGUAGE TypeFamilies, FlexibleInstances #-}
module Types.Integral where

import Prelude hiding (Real, (&&), (||), not, max, min, Ord (..), product, map, Integral, (^))
import FwdMode ((:~>), fstD, sndD, getDerivTower, (@.), getValue, VectorSpace)
import qualified Control.Category as C
import FwdPSh
import Types.Discrete (Box (..))
import Types.SmoothBool ((^))

type Integral a = (a :=> DReal) :=> DReal

instance PShD a => Tangential (a :=> DReal) where
  type Tangent (a :=> DReal) = (a :=> DReal) :* (a :=> DReal)
  -- tangent :: VectorSpace g => Tan (Integral a) g :== (Integral a :* Integral a) g
  tangent = arrProdIso C.. tanToR

dirac :: Additive g => PShD a => a g -> Integral a g
dirac x = ArrD $ \wk f -> f # dmap wk x

diracInternal :: Additive g => PShD a => (a :=> Integral a) g
diracInternal = ArrD $ \_ -> dirac

bind :: Additive g => Integral a g -> (a :=> Integral b) g -> Integral b g
bind i f = ArrD $ \wk p ->
  dmap wk i # (ArrD $ \wk' x -> (dmap (wk @. wk') f # x) # dmap wk' p)

zero :: Integral a g
zero = ArrD $ \_ p -> 0

sum :: Additive g => Integral a g -> Integral a g -> Integral a g
sum k k' = ArrD $ \wk p -> dmap wk k # p + dmap wk k' # p

scale :: Additive g => DReal g -> Integral a g -> Integral a g
scale c k = ArrD $ \wk p -> dmap wk c * dmap wk k # p

map :: Additive g => (a :=> b) g -> Integral a g -> Integral b g
map f k = ArrD $ \wk p -> dmap wk k # ArrD (\wk' x -> dmap wk' p # (dmap (wk @. wk') f # x))

factor :: Additive g => DReal g -> Integral (K ()) g
factor x = ArrD $ \wk f -> (f # K ()) * dmap wk x

normalize :: Additive g => Integral a g -> Integral a g
normalize i = ArrD $ \wk f -> let i' = dmap wk i in i' # f / i' # (ArrD (\_ _ -> 1))

bernoulli :: Additive g => DReal g -> Integral (K Bool) g
bernoulli p = ArrD $ \wk f -> let p' = dmap wk p in
  p' * (f # K True) + (1 - p') * (f # K False)

uniform :: Integral DReal g
uniform = ArrD $ \wk (ArrD f) -> R (integral' (let R y = f fstD (R sndD) in y))

-- total mass 1
uniformAB :: Additive g => DReal g -> DReal g -> Integral DReal g
uniformAB a b = map (ArrD (\wk x -> dmap wk a + x * (dmap wk (b - a)))) uniform

-- total mass (b - a)
lebesgueAB :: Additive g => DReal g -> DReal g -> Integral DReal g
lebesgueAB a b = scale (b - a) (uniformAB a b)

bernoulliObs :: Additive g => DReal g -> Bool -> Integral (K ()) g
bernoulliObs p b = factor (if b then p else (1 - p))

simpleBetaBernoulli :: Additive g => Integral DReal g
simpleBetaBernoulli = normalize $
  bind uniform $ ArrD (\_ p ->
  bind (bernoulliObs p True) $ ArrD (\wk' _ ->
  dirac (dmap wk' p)))

simpleBetaBernoulliExpectation :: Point Real
simpleBetaBernoulliExpectation = unR $
  simpleBetaBernoulli # ArrD (\_ x -> x)


fwdDelta ::  VectorSpace g => PShD a => Tan a g -> Tan (Integral a) g
fwdDelta = fwd diracInternal

fwdDeltaExample :: VectorSpace g => DReal g -> Integral DReal g
fwdDeltaExample x = dmu where
  (mu :* dmu) = from tangent (fwdDelta (to tanR (x :* 1)))

-- "Pretend" that we can't compute derivatives of our sampling primitive
sampleuniformAB :: Box DReal g -> Box DReal g -> Box (Integral DReal) g
sampleuniformAB (Box a) (Box b) = Box (uniformAB a b)

mean :: (Integral DReal :=> DReal) g
mean = ArrD $ \_ mu -> mu # (ArrD (\_ x -> x))

variance :: (Integral DReal :=> DReal) g
variance = ArrD $ \_ mu -> mu # (ArrD (\wk x -> (x - mean # dmap wk mu) ^ 2))

change :: Integral DReal g
change = ArrD $ \_ f -> uniform # (ArrD (\wk x -> (x - 1/2) * dmap wk f # x))

derMeanChange :: DReal ()
derMeanChange = let (y :* dy) = derivT mean (uniform :* change) in dy

derVarianceChange :: DReal ()
derVarianceChange = let (y :* dy) = derivT variance (uniform :* change) in dy