# mpfit
# Copyright Sebastian Schmidt
# Wrapper for the cMPFIT non-linear least squares fitting library (Levenberg-Marquardt)

## .. include:: ./docs/mpfit.rst

import strformat
import sequtils
import mpfit/mpfit_wrapper
export mpfit_wrapper
import macros

type
  FuncProto*[T] = proc (p: seq[T], x: T): T
  VarStruct[T] = ref object
    x: seq[T]
    y: seq[T]
    ey: seq[T]
    f: FuncProto[T]


proc `$`(v: VarStruct): string = $v[]

func error*(res: mp_result): seq[float] =
  ## given an `mp_result`, return the errors of the fit parameters
  let errs = cast[ptr UncheckedArray[cdouble]](res.xerror)
  result = newSeq[float](res.npar)
  for i in 0 .. result.high:
    result[i] = errs[i].float

func cov*(res: mp_result): seq[seq[float]] =
  ## given an `mp_result`, return the covariance matrix of the fit parameters
  ## as a nested seq of shape `[npar, npar]`
  let npar = res.npar.int
  let covar = cast[ptr UncheckedArray[cdouble]](res.covar)
  result = newSeqWith(npar, newSeq[float](npar))
  for i in 0 ..< npar:
    for j in 0 ..< npar:
      result[i][j] = covar[i * npar + j].float

func chiSq*(res: mp_result): float =
  ## given an `mp_result`, return the chi^2 of the fit
  result = res.bestnorm.float

func reducedChiSq*(res: mp_result): float =
  ## given an `mp_result`, return the reduced chi^2 of the fit, i.e.
  ##
  ## .. code-block:: sh
  ##    reducedChiSq = \chi^2 / d.o.f
  ##                 = \chi^2 / (# data points - # parameters)
  result = res.chisq / (res.nfunc - res.nfree).float

proc echoResult*(x: openArray[float], xact: openArray[float] = @[], res: mp_result) =
  ## A convenience proc to echo the fit parameters and their errors as well
  ## as the properties of the fit, e.g. chi^2 etc.
  ##
  ## The first argument `x` are the final resulting fit paramters (the first
  ## return value of `fit`, `xact` are the actual values (e.g.. your possibly
  ## known parameters you want to compare with in case the fit was only a
  ## cross check) and `res` is the `mp_result` object, the second return value of
  ## the `fit` proc.
  let errs = res.error
  let chisq_red = res.reducedChisq
  echo &"  CHI-SQUARE     = {res.chiSq}    ({res.nfunc - res.nfree} DOF)"
  echo &"  CHI_SQUARE/dof = {chisq_red}"
  echo &"        NPAR     = {res.npar}"
  echo &"       NFREE     = {res.nfree}"
  echo &"     NPEGGED     = {res.npegged}"
  echo &"     NITER       = {res.niter}"
  echo &"      NFEV       = {res.nfev}"
  if xact.len != 0:
    for i in 0 ..< res.npar:
      echo &"  P[{i}] = {x[i]} +/- {errs[i]}     (ACTUAL {xact[i]})"
  else:
    for i in 0 ..< res.npar:
      echo &"  P[{i}] = {x[i]} +/- {errs[i]}"

func funcImpl(m, n: cint,
             pPtr, dyPtr: ptr cdouble,
             dvecPtr: ptr ptr cdouble,
             vars: var pointer): cint {.cdecl.} =
  ## this function contains the actual code, which is called by the C MPFIT
  ## library. The `vars` argument contains the user data as well as the u
  ## user defined fit function. This function only exists to accomodate
  ## - taking into account errors on y (without the user having to do
  ##   this in the custom fitting function)
  ## - provide necessary arguments / types for CMPFIT
  ## It runs over the x, y data and calls the user custom function for
  ## each element, i.e. it wraps the user function
  var
    v = cast[VarStruct[float]](vars)
    p = cast[ptr UncheckedArray[cdouble]](pPtr)
    dy = cast[ptr UncheckedArray[cdouble]](dyPtr)
    x = v.x
    y = v.y
    ey = v.ey
    ff = v.f
    f: float
    # create a sequence for the parameters for the user defined proc
    pCall = newSeq[cdouble](n)

  for i in 0 ..< n:
    pCall[i] = p[i]
  for i in 0 ..< m:
    f = ff(pCall, x[i])
    dy[i] = (y[i] - f) / ey[i]

proc fit*[T](userFunc: FuncProto[T],
             pS: openArray[T],
             x, y, ey: openArray[T],
             bounds: seq[tuple[l, u: float]] = @[]): (seq[T], mp_result) =
  ## The actual `fit` procedure, which needs to be called by the user.
  ## `userFunc` is the function to be fitted to the data `x`, `y` and `ey`,
  ## where `ey` is the error on `y`.
  ##
  ## It's possible to set bounds on the fit parameters, by handing a
  ## seq (one element per parameter) of lower `l` and upper `u` bound values.
  # convert bounds to mp_par objects
  var
    # create a VarStruct to hold the user data and custom function
    vars = VarStruct[float](x: @x, y: @y, ey: @ey, f: userFunc)
    res: mp_result
    p = @pS
    m = x.len.cint
    n = pS.len.cint
    perror = newSeq[float](n)
    # variables for the bounds seq
    mbounds: seq[mp_par]
    mboundsPtr: ptr mp_par = nil
  if bounds.len > 0:
    doAssert bounds.len == 0 or bounds.len == pS.len, "Bounds must either be " &
      "empty or one bound tuple for each parameter!"
    for tup in bounds:
      let (l, u) = tup
      let b = mp_par(fixed: 0,
                     limited: [1.cint, 1],
                     limits: [l.cdouble, u.cdouble])
      mbounds.add b
    # in case bounds is non empty, use the address of that seq. Else we keep it
    # as nil
    #doAssert bounds.len == n, "There needs to be one `mp_par` object for each parameter!"
    mboundsPtr = mbounds[0].addr

  res.xerror = perror[0].addr
  # cast the `funcImpl` function, which wraps the user function to the needed type
  # for the C lib
  var f = cast[mp_func](funcImpl)

  let status = mpfit(f, m, n, p[0].addr, mboundsPtr, nil, cast[pointer](addr(vars)), addr(res))
  echo &"*** testlinfit status = {status}"
  result = (p, res)


# the following define a few tests, taken from the tests of the C library
func ffunc[T](p: seq[T], x: T): T =
  result = p[0] + p[1] * x

func fsquare[T](p: seq[T], x: T): T =
  result =  p[0] + p[1] * x + p[2] * x * x

proc testlinfit() =
  let
    x = @[-1.7237128E+00,1.8712276E+00,-9.6608055E-01,
         -2.8394297E-01,1.3416969E+00,1.3757038E+00,
         -1.3703436E+00,4.2581975E-02,-1.4970151E-01,
          8.2065094E-01]
    y = @[1.9000429E-01,6.5807428E+00,1.4582725E+00,
         2.7270851E+00,5.5969253E+00,5.6249280E+00,
         0.787615,3.2599759E+00,2.9771762E+00,
         4.5936475E+00]
    ey = @[0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 0.07]
    p = @[1.0, 1.0]
    pactual = [3.20, 1.78]
  echo x

  #let status = mpfit(f, 10.cint, 2.cint, p[0].addr, nil, nil, cast[pointer](addr(vars)), addr(res))

  let (pRes, res) = fit[float](ffunc, p, x, y, ey)

  echoResult(pRes, pactual, res)

proc testquadfit() =
  let
    x = @[-1.7237128E+00,1.8712276E+00,-9.6608055E-01,
           -2.8394297E-01,1.3416969E+00,1.3757038E+00,
           -1.3703436E+00,4.2581975E-02,-1.4970151E-01,
           8.2065094E-01]
    y = @[2.3095947E+01,2.6449392E+01,1.0204468E+01,
           5.40507,1.5787588E+01,1.6520903E+01,
           1.5971818E+01,4.7668524E+00,4.9337711E+00,
           8.7348375E+00]
    ey = newSeqWith[float](10, 0.2)
    p = @[1.0, 1.0, 1.0]
    pactual = @[4.7, 0.0, 6.2]
  let (pRes, res) = fit[float](fsquare, p, x, y, ey)
  echoResult(pRes, pactual, res)


proc testquadfix() =
  discard

proc testgaussfit() =
  discard

proc testgaussfix() =
  discard

proc main() =

  testlinfit()
  testquadfit()
  testquadfix()
  testgaussfit()
  testgaussfix()

when isMainModule:
  main()
