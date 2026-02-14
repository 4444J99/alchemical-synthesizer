/*
  Phase 4: The Absorption-Fusion Loop
  Module: Relinquished (The Parasite)
  Spec: v1.0 Strict
*/

(
// STAGE-01 INPUT_ASSIMILATION (IA)
SynthDef(elinquished_ia, {
  |inBusA=0, inBusB=1, outBus=0,
   iaSelect=0,               // 0=A, 1=B
   iaGain=1.0,               // 0..4
   iaPadDb=0.0,              // 0, -10, -20
   iaHpHz=20.0,              // 10..200
   iaLimit=1,                // 0/1
   // clip bus out
   iaClipBus=0
  |

  var a, b, sel, pad, gain, hp, limited, clip;
  a = In.ar(inBusA, 1);
  b = In.ar(inBusB, 1);

  // strict selection, no mixing
  sel = Select.ar(iaSelect.clip(0,1), [a, b]);

  pad = sel * (10 ** (iaPadDb / 20));
  gain = pad * iaGain.clip(0, 4);
  hp = HPF.ar(gain, iaHpHz.clip(10, 200));

  limited = Select.ar(iaLimit.clip(0,1), [
    hp,
    Limiter.ar(LeakDC.ar(hp), 0.98, 0.01)
  ]);

  // clip detect
  clip = (Amplitude.kr(hp, 0.01, 0.05) > 0.98).lag(0.02);
  Out.kr(iaClipBus, clip);

  Out.ar(outBus, limited);
}).add;


// STAGE-03 BINDING_CORE (BC)
SynthDef(elinquished_bc, {
  |inBus=0, outBus=0,
   equipState=0,             // 0/1
   equipTrig=0,              // trigger
   evictTrig=0,              // trigger
   bcFreeze=0.0,             // 0..1
   bcLenMs=120.0,            // 5..500
   bcReadPos=0.35,           // 0..1
   bcJitterMs=0.0,           // 0..50
   bcXfadeMs=5.0,            // 0..50
   bcValidBus=0
  |

  var in, lenS, bufFrames, buf, writeOn, prime, valid, jitterS;
  var readPosS, readBaseS, ph, rdA, rdB, xfadeT, out;

  in = In.ar(inBus, 1);

  bufFrames = (0.5 * SampleRate.ir).asInteger.max(2);
  buf = LocalBuf(bufFrames, 1);

  lenS = (bcLenMs.clip(5,500) / 1000);
  writeOn = (equipState > 0) * (1 - bcFreeze.clip(0,1));

  prime = Trig1.kr(equipTrig, lenS);
  valid = (Sweep.kr(equipTrig, 1) > lenS).lag(0.0);
  valid = valid * (1 - Trig1.kr(evictTrig, 0.05));
  Out.kr(bcValidBus, valid);

  ph = Phasor.ar(writeOn, 1, 0, bufFrames);
  BufWr.ar(in, buf, ph, loop: 1);

  jitterS = (TExpRand.kr(0.0, bcJitterMs.clip(0,50) / 1000 + 1e-6, equipTrig) - 1e-6);
  readPosS = (bcReadPos.clip(0,1) * lenS) + jitterS;
  readBaseS = (ph - (readPosS * SampleRate.ir)).wrap(0, bufFrames);

  xfadeT = Lag.kr(evictTrig + equipTrig, bcXfadeMs.clip(0,50) / 1000).clip(0,1);
  rdA = BufRd.ar(1, buf, readBaseS, loop: 1, interpolation: 4);
  rdB = BufRd.ar(1, buf, (readBaseS + (bcXfadeMs.clip(0,50) / 1000 * SampleRate.ir)).wrap(0, bufFrames), loop: 1, interpolation: 4);

  out = XFade2.ar(rdA, rdB, (xfadeT * 2 - 1)); 
  Out.ar(outBus, out * valid); 
}).add;


// STAGE-04 ANALYSIS_EXTRACTION (AE)
SynthDef(elinquished_ae, {
  |inBus=0,
   aeRateHz=50.0,            
   aeSmoothMs=40.0,          
   aeEnvSens=1.0,            
   aeTransThrDbfs=(-18.0),   
   cvEnvBus=0, cvToneBus=1, cvNoiseBus=2, gateTransBus=3
  |

  var in, env, envSm, thrLin, dEnv, isTrans;
  var chain, centroid, flat, tone01, noise01;

  in = In.ar(inBus, 1);

  env = Amplitude.kr(in, 0.01, 0.05) * aeEnvSens.clip(0.25, 4);
  envSm = Lag.kr(env, (aeSmoothMs.clip(0,500) / 1000));

  thrLin = (10 ** (aeTransThrDbfs.clip(-40,-6) / 20));
  dEnv = HPZ1.kr(envSm).abs;
  isTrans = (dEnv > thrLin).lag(0.02);
  Out.kr(gateTransBus, isTrans);

  chain = FFT(LocalBuf(1024), in);
  centroid = SpecCentroid.kr(chain);      
  flat = SpecFlatness.kr(chain);          

  tone01 = (centroid.explin(50, 8000, 0, 1)).clip(0,1);
  noise01 = flat.clip(0,1);

  Out.kr(cvEnvBus, envSm.clip(0,1));      
  Out.kr(cvToneBus, tone01);
  Out.kr(cvNoiseBus, noise01);
}).add;


// STAGE-05 TRANSMUTATION_ENGINE (TE)
SynthDef(elinquished_te, {
  |inBus=0, outBus=0,
   cvEnvBus=0, cvToneBus=1, cvNoiseBus=2, gateTransBus=3,
   teDrive=0.35, teColor=0.50, teChaos=0.15, teMix=1.0,
   teOp1=1.0, teOp2=0.65, teOp3=0.35, teOp4=0.15, teOp5=0.10, teOp6=0.25,
   teSatBus=0
  |

  var in, env, tone, noise;
  var x, y, cutoff, rq, carrier, grains, comb, sat;

  in = In.ar(inBus, 1);
  env = In.kr(cvEnvBus, 1);
  tone = In.kr(cvToneBus, 1);
  noise = In.kr(cvNoiseBus, 1);

  // OP1 VCA
  x = in * ((1 - teOp1.clip(0,1)) + (teOp1.clip(0,1) * (env * (0.5 + teDrive.clip(0,2))))).clip(0,2);

  // OP2 FILTER 
  cutoff = tone.linexp(0,1, 50, 8000);
  rq = (0.6 + (noise * teChaos.clip(0,1) * 3.0)).clip(0.2, 4.0);
  y = SelectX.ar(teColor.clip(0,1) * 2, [
    RLPF.ar(x, cutoff, (1/rq).clip(0.05, 0.99)),   
    BPF.ar(x, cutoff, (1/rq).clip(0.05, 0.99)),    
    HPF.ar(x, cutoff)                               
  ]);
  x = XFade2.ar(x, y, teOp2.clip(0,1) * 2 - 1);

  // OP3 WAVESHAPE
  y = tanh(x * (1 + 10 * teDrive.clip(0,2) * teOp3.clip(0,1)));
  x = XFade2.ar(x, y, teOp3.clip(0,1) * 2 - 1);

  // OP4 RINGMOD
  carrier = SinOsc.ar(20 + (tone * 2000));
  y = x * carrier;
  x = XFade2.ar(x, y, teOp4.clip(0,1) * 2 - 1);

  // Output Mix
  y = XFade2.ar(in, x, teMix.clip(0,1) * 2 - 1);

  sat = (Amplitude.kr(y, 0.01, 0.05) > 0.95).lag(0.02);
  Out.kr(teSatBus, sat);

  Out.ar(outBus, LeakDC.ar(y));
}).add;


// STAGE-06 PROTECTION_REFLECTION (PR)
SynthDef(elinquished_pr, {
  |inBus=0, outBus=0, reflectBus=0,
   iaClipBus=0, teSatBus=1,
   cvToneBus=2, cvNoiseBus=3,
   prMode=0,                 // 0=SACRIFICE,1=INVERT,2=RING,3=MUTE
   prThrDbfs=(-12.0),        
   prResponseMs=10.0,        
   prReflectMix=0.30,        
   prFbGain=0.10,            
   fbInBus=(-1),             
   prFaultBus=0,
   prSacrificeTrigBus=1
  |

  var in, fb, fbGain, sum, thrLin, iaClip, teSat, overload, respS, overGate;
  var tone, inv, ring, reflect, out, fault, trig;

  in = In.ar(inBus, 1);
  fb = (fbInBus < 0).if(0, In.ar(fbInBus, 1));
  fbGain = prFbGain.clip(0, 0.5);
  sum = in + (fb * fbGain);

  iaClip = In.kr(iaClipBus, 1);
  teSat  = In.kr(teSatBus, 1);
  thrLin = (10 ** (prThrDbfs.clip(-24,-3) / 20));

  overload = (Amplitude.kr(sum, 0.01, 0.05) > thrLin) + (iaClip > 0) + (teSat > 0);
  respS = prResponseMs.clip(1,100) / 1000;
  overGate = (Lag.kr(overload, respS) > 0).lag(0.0);

  tone = In.kr(cvToneBus, 1);

  inv = -sum * prReflectMix.clip(0,1);
  ring = (sum * SinOsc.ar(200 + tone * 800)) * prReflectMix.clip(0,1);
  reflect = Select.ar(prMode.clip(0,3), [0, inv, ring, 0]);

  fault = Latch.kr((prMode.clip(0,3) == 3) * overGate, 1); 
  Out.kr(prFaultBus, fault);

  trig = (prMode.clip(0,3) == 0) * overGate;
  Out.kr(prSacrificeTrigBus, trig);

  out = Select.ar(prMode.clip(0,3), [
    (sum * (1 - trig)).lag(0.01),
    Limiter.ar(sum, 0.98, 0.02),
    Limiter.ar(sum, 0.98, 0.02),
    Select.ar(fault, [Limiter.ar(sum, 0.98, 0.02), 0])
  ]);

  Out.ar(reflectBus, reflect);
  Out.ar(outBus, out);
}).add;

// STAGE-07 RELEASE_ROUTER (RR)
SynthDef(elinquished_rr, {
  |iaBus=0, prBus=1, outBus=0,
   rrBypass=0,               
   rrLevelDb=0.0             
  |
  var ia, pr, level, out;
  ia = In.ar(iaBus, 1);
  pr = In.ar(prBus, 1);
  level = (10 ** (rrLevelDb.clip(-99, 6) / 20));
  out = Select.ar(rrBypass.clip(0,1), [pr, ia]) * level;
  Out.ar(outBus, out);
}).add;

"--- BRAHMA: Relinquished SynthDefs Loaded ---".postln;
)
