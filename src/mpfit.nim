# mpfit
# Copyright Sebastian Schmidt
# Wrapper for the cMPFIT non-linear least squares fitting library (Levenberg-Marquardt)

import strformat
import sequtils
import mpfit/mpfit_wrapper
export mpfit_wrapper
import macros

type
  #varStruct[N: static[int]] = object
    # x: array[10, cdouble]
    # y: array[10, cdouble]
    # ey: array[10, cdouble]

  FuncProto[T] = proc (p: seq[T], x: T): T
  varStruct[T] = ref object
    x: seq[T]
    y: seq[T]
    ey: seq[T]
    f: FuncProto[T]
                       

proc `$`(v: varStruct): string = $v[]
            
proc echoResult*(x: openArray[float], xact: openArray[float] = @[], res: mp_result) =
  let errs = cast[ptr UncheckedArray[cdouble]](res.xerror)
  let chisq_red = res.bestnorm.float / (res.nfunc - res.nfree).float
  echo &"  CHI-SQUARE     = {res.bestnorm}    ({res.nfunc - res.nfree} DOF)"
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
    
func linfunc(m, n: cint, pPtr: ptr cdouble, dyPtr: ptr cdouble, dvecPtr: ptr ptr cdouble, vars: var pointer): cint {.cdecl.} =
  var
    v = cast[varStruct[float]](vars)
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
  
proc fit*[T](f: FuncProto[T], pS: openArray[T], x, y, ey: openArray[T]): (seq[T], mp_result) =
  ## The actual `fit` procedure, which needs to be called by the user.
  var
    vars = varStruct[float](x: @x, y: @y, ey: @ey, f: f)
    res: mp_result
    p = @pS
    m = x.len.cint
    n = pS.len.cint
    perror = newSeq[float](n)

  res.xerror = perror[0].addr
  var f = cast[mp_func](linfunc)
  
  let status = mpfit(f, m, n, p[0].addr, nil, nil, cast[pointer](addr(vars)), addr(res))
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