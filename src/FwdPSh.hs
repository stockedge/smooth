{-|
Lifting the module `Diffeo` into the category of
presheaves, adding higher-order functions. In particular,
we implement integration as a smooth higher-order function
of type `(R -> R) -> R`.
-}

{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleContexts #-}

module FwdPSh (
  module FwdPSh,
  module Types.Bijection,
  (:*) (..),
  R (..),
  Real,
  Additive,
  CPoint
) where

import Prelude hiding (Real, max, min)
import Control.Arrow
import Control.Category (Category)
import qualified Control.Category as C

import RealExpr (CMap (..), Additive (..), CPoint)
import qualified Rounded as R
import Interval (Interval, unitInterval)
import qualified Expr as E
import qualified RealExpr as RE
import Experimental.PSh
import FwdMode
import qualified MPFR as M
import MPFR (Real)
import Types.Bijection

type D = (:~>)

instance ConCat D where
  type Ok D a = Additive a
  id = dId
  (.) = (@.)

type CReal = R CMap Real
type DReal = R D Real

newtype K a g = K a

type Point a = () :~> a

instance Show a => Show (() :~> a) where
  show = show Prelude.. getValue

instance Show (DReal ()) where
  show (R x) = show x

infixr 2 :=>
data (:=>) a b (g :: *) = ArrD (forall d. Additive d => d :~> g -> a d -> b d)

infixl 8 #
(#) :: Additive g => (a :=> b) g -> a g -> b g
ArrD f # x = f dId x

instance RE.CNum a => Num (R CMap a g) where
  R x + R y = R (x + y)
  R x * R y = R (x * y)
  negate (R x) = R (negate x)
  R x - R y = R (x - y)
  abs (R x) = R (abs x)
  fromInteger = R Prelude.. fromInteger
  signum (R x) = R (signum x)

instance R.Rounded a => Num (g :~> Interval a) where
  (+) = dap2 add
  D x * D y = D (dMult x y)
  abs = dap1 (lift1 (abs C.id) (signum dId))
  -- not totally accurate for signum here, it should blow up at 0...
  signum = dap1 (lift1 (signum C.id) signum_deriv')
  fromInteger x = D $ fromInteger x :# dZero
  negate = dap1 negate'

instance R.Rounded a => Num (R D (Interval a) g) where
  R x + R y = R (x + y)
  R x * R y = R (x * y)
  negate (R x) = R (negate x)
  R x - R y = R (x - y)
  abs (R x) = R (abs x)
  fromInteger = R Prelude.. fromInteger
  signum (R x) = R (signum x)

instance R.Rounded a => Fractional (R CMap (Interval a) g) where
  recip (R x) = R (recip x)
  fromRational = R Prelude.. fromRational

instance R.Rounded a => Fractional (g :~> Interval a) where
  recip = dap1 recip'
  fromRational x = D $ fromRational x :# dZero

instance R.Rounded a => Fractional (R D (Interval a) g) where
  recip (R x) = R (recip x)
  fromRational = R Prelude.. fromRational

max :: R.Rounded a => g :~> Interval a -> g :~> Interval a -> g :~> Interval a
max = dap2 max'

min :: R.Rounded a => g :~> Interval a -> g :~> Interval a -> g :~> Interval a
min = dap2 min'

instance Floating (g :~> Real) where
  pi = D $ pi :# dZero
  log = dap1 log'
  exp = dap1 exp'
  sin = dap1 sin'
  cos = dap1 cos'
  -- tan      = lift1 tan $ recip . join (*) . cos
  -- asin     = lift1 asin $ \x -> recip (sqrt (1 - join (*) x))
  -- acos     = lift1 acos $ \x -> negate (recip (sqrt (1 - join (*) x)))
  -- atan     = lift1 atan $ \x -> recip (1 + join (*) x)
  -- sinh     = lift1 sinh cosh
  -- cosh     = lift1 cosh sinh
  -- tanh     = lift1 tanh $ recip . join (*) . cosh
  -- asinh    = lift1 asinh $ \x -> recip (sqrt (1 + join (*) x))
  -- acosh    = lift1 acosh $ \x -> recip (sqrt (join (*) x - 1))
  -- atanh    = lift1 atanh $ \x -> recip (1 - join (*) x)
  sqrt = dap1 sqrt'

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

-- Maybe this is working!!!
integral' :: R.Rounded a => ((g, Interval a) :~> Interval a) -> (g :~> Interval a)
integral' (D f) = D $ dlinearWkn (wknValueF integ f)
  where
  integ :: R.Rounded a => CMap ((g, Interval a), k1) (Interval a) -> CMap (g, k1) (Interval a)
  integ h = RE.integral1' (h <<< arr (\((g, k), a) -> ((g, a), k)))

integral :: R.Rounded a => ((g, Interval a) :~> Interval a -> (g, Interval a) :~> Interval a)
  -> g :~> (Interval a)
integral f = integral' (f sndD)

asReal :: R CMap Real g -> CMap g Real
asReal (R x) = x

derivative :: Additive g => Additive b => R.Rounded a =>
  ((g, Interval a) :~> Interval a -> (g, Interval a) :~> b)
  -> g :~> Interval a -> g :~> b
derivative f x = deriv (f sndD) @. pairD dId x

fwd_deriv' :: Additive g => Additive a => Additive b =>
  (g, a) :~> b -> g :~> a -> g :~> a -> g :~> b
fwd_deriv' f x dx = dap2 (fwdDer f) (pairD dId x) (pairD zeroD dx)

fwd_deriv :: Additive g => Additive a => Additive b =>
  ((g, a) :~> a -> (g, a) :~> b) -> g :~> a -> g :~> a -> g :~> b
fwd_deriv f = fwd_deriv' (f sndD)

fwd_deriv1 :: Additive g => Additive a => Additive b =>
  ((R D a :=> R D b) g) -> g :~> a -> g :~> a -> g :~> b
fwd_deriv1 (ArrD f) = fwd_deriv' (let R b = f fstD (R sndD) in b)

-- fwd_deriv1' :: Additive g => Additive a => Additive b =>

wkn :: Additive g => Additive a => g :~> a -> (g, x) :~> a
wkn f = f @. fstD

getDerivTower' :: R.Rounded a => (Interval a :~> Interval a -> Interval a :~> Interval a)
  -> CMap g (Interval a) -> [CMap g (Interval a)]
getDerivTower' f = getDerivTower (f dId)

example :: Int -> CPoint Real
example n = getDerivTower' (\c -> integral (\x -> sin (wkn c * x))) 3 !! n

example2 :: Point Real
example2 = fwd_deriv (\c -> integral (\x -> abs (x - wkn c))) 0.6 1

-- I think this is right!
example3 :: CPoint Real -> Int -> CPoint Real
example3 y n = getDerivTower' (\z -> fwd_deriv (\x -> x^2) z z) y !! n


absExample :: CPoint Real -> Int -> CPoint Real
absExample y n = getDerivTower' (\c -> integral (\x -> abs (x - wkn c))) y !! n

internalDiffExample :: Point Real
internalDiffExample = derivative (\c -> integral (\x -> abs (x - wkn c))) 0.6

reluIntegralExample :: CPoint Real -> Int -> CPoint Real
reluIntegralExample y n =
  getDerivTower' (\c -> integral (\x -> max 0 (x - wkn c))) y !! n

reluExample :: CPoint Real -> Int -> CPoint Real
reluExample x n = getDerivTower' (max 0) x !! n




-- Tangent spaces

data Tan f g where
   Tan :: Additive d => g :~> (d, d) -> f d -> Tan f g

class PShD f where
  dmap :: Additive d => Additive g => d :~> g -> f g -> f d

instance PShD (K a) where
  dmap _ (K x) = K x

instance Additive a => PShD (R (:~>) a) where
  dmap f (R x) = R (x @. f)

instance PShD (a :=> b) where
  dmap wk (ArrD f) = ArrD $ \wk' -> f (wk @. wk')

instance (PShD f) => PShD (Tan f) where
  dmap f (Tan gdd fd) = Tan (gdd @. f) fd

tangentValue :: Additive g => PShD f => Tan f g -> f g
tangentValue (Tan xdx f) = dmap (fstD @. xdx) f

tangentZero :: Additive g => f g -> Tan f g
tangentZero f = Tan (pairD dId zeroD) f

-- Both tangent bundles should be based on the same point
-- tangentAdd :: Additive g => Tan f g -> Tan f g -> Tan f g

tanR :: Tan DReal g :== (DReal :* DReal) g
tanR = Bijection from to where
  from (Tan gdd (R fd)) = R (fstD @. x) :* R (sndD @. x) where
    x = fwdWithValue fd @. gdd
  to (R x :* R dx) = Tan (pairD x dx) (R dId)

fwdGlobal :: (forall g. a g -> b g) -> Tan a g -> Tan b g
fwdGlobal f (Tan gdd fd) = Tan gdd (f fd)

scaleDerivRn :: VectorSpace v s => g :~> (v, v) -> g :~> s -> g :~> (v, v)
scaleDerivRn xdx c = pairD (fstD @. xdx) (scalarMultD c (sndD @. xdx))

exponentialMapRn :: VectorSpace v s => g :~> (v, v) -> g :~> s -> g :~> v
exponentialMapRn xdx c = addD (fstD @. xdx) (scalarMultD c (sndD @. xdx))

-- scaleDerivTan :: Tan f g -> g :~> Real -> Tan f g
-- scaleDerivTan (Tan xdx f) c = Tan (scaleDerivRn xdx c) f

fwd :: Additive g => PShD a => (a :=> b) g -> (Tan a :=> Tan b) g
fwd (ArrD f) = ArrD $ \ext (Tan xdx ax) -> let f1 = f fstD (dmap sndD ax) in
  Tan (pairD (pairD ext (fstD @. xdx)) (pairD zeroD (sndD @. xdx))) f1

tanProd :: PShD a => PShD b => Tan (a :* b) g :== (Tan a :* Tan b) g
tanProd = Bijection from to where
  from (Tan xdx (a :* b)) = Tan xdx a :* Tan xdx b
  to (Tan xdx a :* Tan ydy b) = Tan (pairD xy dxdy) (a' :* b') where
    xy = pairD (fstD @. xdx) (fstD @. ydy)
    dxdy = pairD (sndD @. xdx) (sndD @. ydy)
    a' = dmap fstD a
    b' = dmap sndD b

tanToR :: Additive g => PShD a =>
  Tan (a :=> DReal) g :== (a :=> (DReal :* DReal)) g
tanToR = Bijection from to where
  -- Haven't thought about this one too carefully,
  -- so I should make sure it's correct
  from (Tan xdx (ArrD f)) = ArrD $ \ext a ->
    let R z = f fstD (dmap sndD a) in
    let x = fwdWithValue z @. (pairD (pairD (fstD @. xdx @. ext) dId) (pairD (sndD @. xdx @. ext) zeroD)) in
    R (fstD @. x) :* R (sndD @. x)
  to :: Additive g => PShD a => (a :=> (DReal :* DReal)) g -> Tan (a :=> DReal) g
  to (ArrD f) = Tan (pairD (pairD dId 0) (pairD zeroD 1))
    (ArrD $ \ext a -> let g :* dg = f (fstD @. ext) a in
      g + (R (sndD @. ext)) * dg)

arrProdIso :: (a :=> b :* c) g :== ((a :=> b) :* (a :=> c)) g
arrProdIso = Bijection f g where
  f (ArrD f) = ArrD (\ext x -> let (a :* _) = f ext x in a)
            :* ArrD (\ext x -> let (_ :* b) = f ext x in b)
  g (ArrD ab :* ArrD ac) = ArrD $ \ext x -> ab ext x :* ac ext x

-- a test of using `fromFwd`. Appears to be working properly!
testSqrt :: Real :~> Real
testSqrt = fromFwd RE.csqrt $
  recip (2 * (testSqrt @. fstD)) * sndD


newton_cut' :: Additive g => R.Rounded a =>
  ((g, Interval a) :~> Interval a) -> (g :~> Interval a)
newton_cut' f = let fwdf = fwdWithValue f in
  -- value-level function, value-level derivative
  let ff' = getValue (dap2 fwdf dId (pairD zeroD 1)) in

  -- value context, derivative context
  let (g, dg) = (fstD, sndD) in

  -- the root of f is: (dap1 (newton_cut' f) g)
  -- f' x is the derivative of f composed with the vector x e.g. x = e0 then f' x = df/dx_0
  let f' x = sndD @. dap2 fwdf (pairD g (dap1 (newton_cut' f) g)) x in

  -- Pick out the right derivatives from the linear map f'
  -- and take the derivative using the implicit function theorem.
  fromFwd (E.newton_cut' ff')
    (- f' (pairD dg 0) / f' (pairD zeroD 1))


firstRoot' :: Additive g => R.Rounded a =>
  ((g, Interval a) :~> Interval a) -> (g :~> Interval a)
firstRoot' f = let fwdf = fwdWithValue f in
  let (g, dg) = (fstD, sndD) in
  let f' x = sndD @. dap2 fwdf (pairD g (dap1 (firstRoot' f) g)) x in
    fromFwd (E.firstRoot1 (getValue f E.> 0))
      (- f' (pairD dg 0) / f' (pairD zeroD 1))


newton_cut :: R.Rounded a => Additive g => ((g, Interval a) :~> Interval a -> (g, Interval a) :~> Interval a)
    -> g :~> (Interval a)
newton_cut f = newton_cut' (f sndD)

-- Need to fix this to account for the special cases where
-- the argmax might be 0 or 1.
argmax01' :: Additive g => R.Rounded a =>
  ((g, Interval a) :~> Interval a) -> (g :~> Interval a)
argmax01' f = let fwd2f = fwdSecondDer f in
  let (g, dg) = (fstD, sndD) in
  let f'' x = dap2 fwd2f (pairD g (dap1 (argmax01' f) g)) (pairD (pairD zeroD 1) x) in
  fromFwd (E.argmax_unit_interval' (getValue f))
  (- f'' (pairD dg 0) / f'' (pairD zeroD 1))

argmax01 :: R.Rounded a => Additive g => ((g, Interval a) :~> Interval a -> (g, Interval a) :~> Interval a)
    -> g :~> (Interval a)
argmax01 f = argmax01' (f sndD)

-- We could just say that max01 = f . argmax01 f, but
-- this would be slower for the evaluation map
max01' :: Additive g => R.Rounded a =>
  ((g, Interval a) :~> Interval a) -> (g :~> Interval a)
max01' f = let D (unoptimized :# derivs) = f @. pairD dId (argmax01' f) in
   D ((E.max_unit_interval' (getValue f) <<< arr (\(g, ()) -> g)) :# derivs)

max01 :: R.Rounded a => Additive g => ((g, Interval a) :~> Interval a -> (g, Interval a) :~> Interval a)
    -> g :~> (Interval a)
max01 f = max01' (f sndD)

argmin01' :: Additive g => R.Rounded a =>
  ((g, Interval a) :~> Interval a) -> (g :~> Interval a)
argmin01' f = let fwd2f = fwdSecondDer f in
  let (g, dg) = (fstD, sndD) in
  let f'' x = dap2 fwd2f (pairD g (dap1 (argmin01' f) g)) (pairD (pairD zeroD 1) x) in
  fromFwd (E.argmin_unit_interval' (getValue f))
  (- f'' (pairD dg 0) / f'' (pairD zeroD 1))

argmin01 :: R.Rounded a => Additive g => ((g, Interval a) :~> Interval a -> (g, Interval a) :~> Interval a)
    -> g :~> (Interval a)
argmin01 f = argmin01' (f sndD)

-- We could just say that max01 = f . argmax01 f, but
-- this would be slower for the evaluation map
min01' :: Additive g => R.Rounded a =>
  ((g, Interval a) :~> Interval a) -> (g :~> Interval a)
min01' f = let D (unoptimized :# derivs) = f @. pairD dId (argmax01' f) in
   D ((E.min_unit_interval' (getValue f) <<< arr (\(g, ()) -> g)) :# derivs)

min01 :: R.Rounded a => Additive g => ((g, Interval a) :~> Interval a -> (g, Interval a) :~> Interval a)
    -> g :~> (Interval a)
min01 f = min01' (f sndD)

firstRoot :: R.Rounded a => Additive g => ((g, Interval a) :~> Interval a -> (g, Interval a) :~> Interval a)
    -> g :~> (Interval a)
firstRoot f = firstRoot' (f sndD)

testNewtonSqrt :: CPoint Real -> [CPoint Real]
testNewtonSqrt z = getDerivTower'
  (\c -> newton_cut (\x -> max (-x) (wkn c - x * x))) z

-- Should test that this is giving correct answers!
-- Hmm, seems to be giving nonzero 4th derivative, even though it shouldn't?
testArgMax :: CPoint Real -> [CPoint Real]
testArgMax z = getDerivTower'
  (\c -> argmax01 (\x -> 0.5 - (x - wkn c)^2 + 0.3 * (wkn c^3) * x)) z

testArgMax2 :: CPoint Real -> [CPoint Real]
testArgMax2 z = getDerivTower'
  (\c -> argmax01 (\x -> -x)) z

testFirstRootForArgmax :: CPoint Real -> [CPoint Real]
testFirstRootForArgmax z = getDerivTower'
  (\c -> firstRoot (\x -> - (2 * (x - wkn c) + 0.3 * (wkn c ^ 3)))) z

testFirstRootSqrt :: CPoint Real -> [CPoint Real]
testFirstRootSqrt z = getDerivTower' (\c -> firstRoot (\x -> max (-x) (wkn c - x * x))) z

testMax :: CPoint Real -> [CPoint Real]
testMax z = getDerivTower'
  (\c -> max01 (\x -> wkn c / 4 - (x - wkn c)^2 )) z

testMaxArgmax :: CPoint Real -> [CPoint Real]
testMaxArgmax z = getDerivTower'
  (\c -> argmax01 (\x -> wkn c / 4 - (x - wkn c)^2 )) z