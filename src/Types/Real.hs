{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeFamilies #-}

module Types.Real (
  module Types.Real,
  R (..),
) where
import Prelude hiding (Real)
import FwdMode
import FwdPSh
import Rounded (Rounded)
import Interval (Interval)

type DReal = R D Real

tanR :: Tan DReal g :== (DReal :* DReal) g
tanR = Bijection from to where
  from (Tan gdd (R fd)) = R (fstD @. x) :* R (sndD @. x) where
    x = fwdWithValue fd @. gdd
  to (R x :* R dx) = Tan (pairD x dx) (R dId)

instance Tangential DReal where
  type Tangent DReal = (DReal :* DReal)
  tangent = tanR

instance Show (DReal ()) where
  show (R x) = show x

instance Rounded a => Num (R D (Interval a) g) where
  R x + R y = R (x + y)
  R x * R y = R (x * y)
  negate (R x) = R (negate x)
  R x - R y = R (x - y)
  abs (R x) = R (abs x)
  fromInteger = R Prelude.. fromInteger
  signum (R x) = R (signum x)

instance Rounded a => Fractional (R D (Interval a) g) where
  recip (R x) = R (recip x)
  fromRational = R Prelude.. fromRational

instance Floating (DReal g) where
  pi = R pi
  log (R x) = R (log x)
  exp (R x) = R (exp x)
  sin (R x) = R (sin x)
  cos (R x) = R (cos x)
  tan (R x) = R (tan x)
  asin (R x) = R (asin x)
  acos (R x) = R (cos x)
  atan (R x) = R (atan x)
  sinh (R x) = R (sinh x)
  cosh (R x) = R (cosh x)
  tanh (R x) = R (tanh x)
  asinh (R x) = R (asinh x)
  acosh (R x) = R (acosh x)
  atanh (R x) = R (atanh x)
  sqrt (R x) = R (sqrt x)

tanToR :: VectorSpace g => PShD a =>
  Tan (a :=> DReal) g :== (a :=> (DReal :* DReal)) g
tanToR = Bijection from to where
  -- Haven't thought about this one too carefully,
  -- so I should make sure it's correct
  from (Tan xdx (ArrD f)) = ArrD $ \ext a ->
    let R z = f fstD (dmap sndD a) in
    let x = fwdWithValue z @. (pairD (pairD (fstD @. xdx @. ext) dId) (pairD (sndD @. xdx @. ext) zeroD)) in
    R (fstD @. x) :* R (sndD @. x)
  to :: VectorSpace g => PShD a => (a :=> (DReal :* DReal)) g -> Tan (a :=> DReal) g
  to (ArrD f) = Tan (pairD (pairD dId 0) (pairD zeroD 1))
    (ArrD $ \ext a -> let g :* dg = f (fstD @. ext) a in
      g + (R (sndD @. ext)) * dg)

infixr 8 ^
(^) :: DReal g -> Int -> DReal g
R x ^ k = R (pow x k)

deriv :: Additive g => (DReal :=> DReal) g -> DReal g -> DReal g
deriv f (R x) = R $ fwd_deriv1 f x 1

min01 :: Additive g => (DReal :=> DReal) g -> DReal g
min01 (ArrD f) = R (FwdPSh.min01' (let R b = f fstD (R sndD) in b))

max01 :: Additive g => (DReal :=> DReal) g -> DReal g
max01 (ArrD f) = R (FwdPSh.max01' (let R b = f fstD (R sndD) in b))

max :: DReal g -> DReal g -> DReal g
max (R x) (R y) = R $ FwdPSh.max x y