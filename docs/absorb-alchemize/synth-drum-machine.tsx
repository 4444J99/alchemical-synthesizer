import React, { useState, useRef, useEffect, useCallback, createContext, useContext } from 'react';

// === THEMES ===
const themes = {
  midnight: { name: 'Midnight', bg: 'bg-zinc-950', bgCard: 'bg-zinc-900', bgControl: 'bg-zinc-800', text: 'text-zinc-100', textMuted: 'text-zinc-400', textAccent: 'text-orange-400', accent: 'bg-orange-500', border: 'border-zinc-700', borderAccent: 'border-orange-500', colors: ['#f97316', '#06b6d4', '#a855f7', '#22c55e', '#f43f5e'], glow: false },
  vapor: { name: 'Vaporwave', bg: 'bg-gradient-to-br from-purple-950 via-fuchsia-950 to-cyan-950', bgCard: 'bg-purple-900/60', bgControl: 'bg-fuchsia-900/60', text: 'text-pink-100', textMuted: 'text-pink-300/60', textAccent: 'text-cyan-400', accent: 'bg-cyan-500', border: 'border-pink-500/30', borderAccent: 'border-cyan-400', colors: ['#22d3ee', '#f472b6', '#c084fc', '#a3e635', '#fb7185'], glow: true },
  terminal: { name: 'Terminal', bg: 'bg-black', bgCard: 'bg-green-950/30', bgControl: 'bg-green-950/50', text: 'text-green-400', textMuted: 'text-green-600', textAccent: 'text-green-300', accent: 'bg-green-500', border: 'border-green-900', borderAccent: 'border-green-500', colors: ['#22c55e', '#4ade80', '#86efac', '#a3e635', '#34d399'], glow: true },
  arctic: { name: 'Arctic', bg: 'bg-gradient-to-b from-slate-100 to-sky-100', bgCard: 'bg-white/90', bgControl: 'bg-sky-100', text: 'text-slate-800', textMuted: 'text-slate-500', textAccent: 'text-sky-600', accent: 'bg-sky-500', border: 'border-sky-200', borderAccent: 'border-sky-500', colors: ['#0ea5e9', '#6366f1', '#8b5cf6', '#14b8a6', '#06b6d4'], glow: false },
  neon: { name: 'Neon', bg: 'bg-black', bgCard: 'bg-zinc-950', bgControl: 'bg-zinc-900', text: 'text-white', textMuted: 'text-zinc-500', textAccent: 'text-lime-400', accent: 'bg-lime-500', border: 'border-zinc-800', borderAccent: 'border-lime-400', colors: ['#a3e635', '#f472b6', '#22d3ee', '#facc15', '#fb7185'], glow: true },
};
const ThemeContext = createContext(themes.midnight);

// === SYNTH & ENGINE FACTORIES ===
const synthTypes = { subtractive: 'Subtractive', fm: 'FM Synthesis', additive: 'Additive', noise: 'Noise', karplus: 'Karplus-Strong', wavefold: 'Wavefold' };
const modSources = ['lfo1', 'lfo2', 'lfo3', 'env', 'random', 'stepPos', 'velocity', 'xyPadX', 'xyPadY', 'synthA', 'synthB'];
const modDests = ['synthA.osc.freq', 'synthA.filter.cutoff', 'synthA.filter.res', 'synthA.ampEnv.d', 'synthB.osc.freq', 'synthB.filter.cutoff', 'blend.synthA', 'blend.synthB', 'blend.sampleA', 'blend.sampleB', 'master.pan', 'master.drive', 'fx.delayMix', 'fx.reverbMix', 'fx.bitcrush'];

const createSynth = (freq = 150) => ({
  enabled: true, type: 'subtractive', volume: 0.8,
  osc: { type: 'sine', freq, detune: 0 },
  fm: { ratio: 2, index: 1 },
  additive: { harmonics: [1, 0.5, 0.25, 0.125, 0.06, 0.03] },
  filter: { type: 'lowpass', cutoff: 2000, res: 1, envAmt: 0 },
  ampEnv: { a: 0.001, d: 0.2, s: 0, r: 0.1 },
  filterEnv: { a: 0.001, d: 0.1, s: 0.3, r: 0.1 },
  noise: { amount: 0 }, wavefold: { amount: 0 },
});

const createSample = () => ({
  enabled: false, buffer: null, name: '', volume: 0.8,
  start: 0, end: 1, pitch: 0, reverse: false,
  filter: { type: 'lowpass', cutoff: 8000, res: 0 },
});

const createEngine = () => ({
  synthA: createSynth(150), synthB: { ...createSynth(200), enabled: false },
  sampleA: createSample(), sampleB: createSample(),
  blend: { synthA: 1, synthB: 0, sampleA: 0, sampleB: 0 },
  xmod: { abAmt: 0, abTarget: 'freq', baAmt: 0, ring: 0 },
  master: { volume: 0.8, pan: 0, drive: 0 },
  fx: { reverbMix: 0, reverbDecay: 1.5, delayMix: 0, delayTime: 0.25, delayFB: 0.3, bitcrush: 0 },
  humanize: { velRand: 0, timeRand: 0, pitchRand: 0, probability: 1 },
});

const createTrack = (id, name) => ({
  id, name: name || `Track ${id}`, steps: 16, swing: 0,
  engine: createEngine(),
  lfos: [{ rate: 1, shape: 'sine', phase: 0 }, { rate: 2, shape: 'tri', phase: 0 }, { rate: 0.5, shape: 'sine', phase: 0 }],
  modMatrix: [], automation: {},
  pattern: Array(16).fill(null).map(() => ({ active: false, velocity: 0.8, pLocks: null })),
  muted: false, solo: false, muteGroup: null,
});

// === PRESETS ===
const enginePresets = {
  kick808: { ...createEngine(), synthA: { ...createSynth(55), osc: { type: 'sine', freq: 55, detune: 0 }, ampEnv: { a: 0.001, d: 0.5, s: 0.1, r: 0.3 }, filter: { type: 'lowpass', cutoff: 400, res: 2, envAmt: 0 } } },
  snare: { ...createEngine(), synthA: { ...createSynth(180), type: 'noise', osc: { type: 'triangle', freq: 180, detune: 0 }, noise: { amount: 0.7 }, ampEnv: { a: 0.001, d: 0.15, s: 0, r: 0.1 }, filter: { type: 'highpass', cutoff: 1000, res: 1, envAmt: 0 } } },
  clap: { ...createEngine(), synthA: { ...createSynth(100), type: 'noise', noise: { amount: 0.9 }, ampEnv: { a: 0.001, d: 0.2, s: 0, r: 0.15 }, filter: { type: 'bandpass', cutoff: 1500, res: 2, envAmt: 0 } } },
  hihatClosed: { ...createEngine(), synthA: { ...createSynth(800), type: 'noise', noise: { amount: 1 }, ampEnv: { a: 0.001, d: 0.04, s: 0, r: 0.02 }, filter: { type: 'highpass', cutoff: 7000, res: 3, envAmt: 0 } } },
  hihatOpen: { ...createEngine(), synthA: { ...createSynth(800), type: 'noise', noise: { amount: 1 }, ampEnv: { a: 0.001, d: 0.25, s: 0.1, r: 0.15 }, filter: { type: 'highpass', cutoff: 6000, res: 2, envAmt: 0 } } },
  tom: { ...createEngine(), synthA: { ...createSynth(100), osc: { type: 'sine', freq: 100, detune: 0 }, ampEnv: { a: 0.001, d: 0.3, s: 0, r: 0.2 }, filter: { type: 'lowpass', cutoff: 1500, res: 1, envAmt: 0.5 } } },
  rim: { ...createEngine(), synthA: { ...createSynth(400), osc: { type: 'square', freq: 400, detune: 0 }, ampEnv: { a: 0.001, d: 0.03, s: 0, r: 0.02 }, filter: { type: 'bandpass', cutoff: 2000, res: 8, envAmt: 0 } } },
  fmBell: { ...createEngine(), synthA: { ...createSynth(440), type: 'fm', fm: { ratio: 3.5, index: 5 }, ampEnv: { a: 0.001, d: 0.8, s: 0.2, r: 0.5 }, filter: { type: 'lowpass', cutoff: 6000, res: 0, envAmt: 0 } } },
  pluck: { ...createEngine(), synthA: { ...createSynth(220), type: 'karplus', ampEnv: { a: 0.001, d: 0.4, s: 0, r: 0.2 }, filter: { type: 'lowpass', cutoff: 3000, res: 1, envAmt: 0 } } },
};

// === UI COMPONENTS ===
const Knob = ({ value, onChange, min = 0, max = 1, label, size = 'md', color, bipolar }) => {
  const theme = useContext(ThemeContext);
  const ref = useRef(null);
  const [dragging, setDragging] = useState(false);
  const startY = useRef(0), startVal = useRef(0);

  const sizes = { sm: 'w-10 h-10', md: 'w-12 h-12', lg: 'w-16 h-16' };
  const handleStart = (e) => { e.preventDefault(); startY.current = (e.touches?.[0] || e).clientY; startVal.current = value; setDragging(true); };

  useEffect(() => {
    if (!dragging) return;
    const move = (e) => { const y = (e.touches?.[0] || e).clientY; onChange(Math.max(min, Math.min(max, startVal.current + (startY.current - y) / 100 * (max - min)))); };
    const end = () => setDragging(false);
    window.addEventListener('mousemove', move); window.addEventListener('mouseup', end);
    window.addEventListener('touchmove', move, { passive: false }); window.addEventListener('touchend', end);
    return () => { window.removeEventListener('mousemove', move); window.removeEventListener('mouseup', end); window.removeEventListener('touchmove', move); window.removeEventListener('touchend', end); };
  }, [dragging, min, max, onChange]);

  const ratio = (value - min) / (max - min);
  const angle = bipolar ? (ratio - 0.5) * 270 : -135 + ratio * 270;
  const c = color || theme.colors[0];

  return (
    <div className="flex flex-col items-center gap-1 select-none">
      {label && <span className={`${theme.textMuted} text-xs truncate max-w-14 text-center`}>{label}</span>}
      <div ref={ref} className={`${sizes[size]} rounded-full ${theme.bgControl} relative cursor-pointer touch-none ${dragging ? 'ring-2' : ''}`}
        style={{ boxShadow: 'inset 0 2px 4px rgba(0,0,0,0.3)' }} onMouseDown={handleStart} onTouchStart={handleStart}>
        <div className="absolute inset-1 rounded-full" style={{ background: `conic-gradient(from -135deg, ${c} ${ratio * 270}deg, transparent ${ratio * 270}deg)`, opacity: 0.4 }} />
        <div className={`absolute inset-2 rounded-full ${theme.bgControl}`} />
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="w-0.5 h-1/3 rounded-full origin-bottom" style={{ background: c, transform: `rotate(${angle}deg) translateY(-50%)`, boxShadow: theme.glow ? `0 0 6px ${c}` : 'none' }} />
        </div>
      </div>
      <span className={`${theme.textMuted} text-xs font-mono`}>{value?.toFixed?.(2) ?? value}</span>
    </div>
  );
};

const Slider = ({ value, onChange, min = 0, max = 1, label, vertical, color }) => {
  const theme = useContext(ThemeContext);
  const ref = useRef(null);
  const [dragging, setDragging] = useState(false);

  const handleStart = (e) => { e.preventDefault(); setDragging(true); handleMove(e); };
  const handleMove = useCallback((e) => {
    if (!ref.current) return;
    const rect = ref.current.getBoundingClientRect();
    const t = e.touches?.[0] || e;
    const ratio = vertical ? 1 - Math.max(0, Math.min(1, (t.clientY - rect.top) / rect.height)) : Math.max(0, Math.min(1, (t.clientX - rect.left) / rect.width));
    onChange(min + ratio * (max - min));
  }, [min, max, onChange, vertical]);

  useEffect(() => {
    if (!dragging) return;
    const move = (e) => handleMove(e);
    const end = () => setDragging(false);
    window.addEventListener('mousemove', move); window.addEventListener('mouseup', end);
    window.addEventListener('touchmove', move, { passive: false }); window.addEventListener('touchend', end);
    return () => { window.removeEventListener('mousemove', move); window.removeEventListener('mouseup', end); window.removeEventListener('touchmove', move); window.removeEventListener('touchend', end); };
  }, [dragging, handleMove]);

  const ratio = (value - min) / (max - min);
  const c = color || theme.colors[0];

  return (
    <div className={`flex ${vertical ? 'flex-col items-center' : 'flex-col'} gap-1 select-none`}>
      {label && <span className={`${theme.textMuted} text-xs`}>{label}</span>}
      <div ref={ref} className={`${vertical ? 'w-3 h-20' : 'w-full h-3'} ${theme.bgControl} rounded-full relative cursor-pointer touch-none`}
        onMouseDown={handleStart} onTouchStart={handleStart}>
        <div className="absolute rounded-full" style={{ background: c, ...(vertical ? { bottom: 0, left: 0, right: 0, height: `${ratio * 100}%` } : { top: 0, bottom: 0, left: 0, width: `${ratio * 100}%` }) }} />
        <div className={`absolute w-4 h-4 rounded-full bg-white shadow border-2 transform -translate-x-1/2 -translate-y-1/2 ${dragging ? 'scale-110' : ''}`}
          style={{ borderColor: c, ...(vertical ? { left: '50%', bottom: `${ratio * 100}%`, transform: 'translate(-50%, 50%)' } : { top: '50%', left: `${ratio * 100}%`, transform: 'translate(-50%, -50%)' }) }} />
      </div>
    </div>
  );
};

const StepBtn = ({ active, playing, hasPLock, velocity, onToggle, onLongPress, onVelChange }) => {
  const theme = useContext(ThemeContext);
  const [pressing, setPressing] = useState(false);
  const timer = useRef(null), startY = useRef(0), startVel = useRef(0);

  const handleStart = (e) => {
    e.preventDefault();
    const t = e.touches?.[0] || e;
    startY.current = t.clientY; startVel.current = velocity; setPressing(true);
    timer.current = setTimeout(() => { onLongPress?.(); setPressing(false); }, 400);
  };

  useEffect(() => {
    if (!pressing) return;
    const move = (e) => { const t = e.touches?.[0] || e; const d = (startY.current - t.clientY) / 60; if (Math.abs(d) > 0.05 && active) { clearTimeout(timer.current); onVelChange?.(Math.max(0.1, Math.min(1, startVel.current + d))); } };
    const end = () => { clearTimeout(timer.current); if (pressing) onToggle?.(); setPressing(false); };
    window.addEventListener('mousemove', move); window.addEventListener('mouseup', end);
    window.addEventListener('touchmove', move, { passive: false }); window.addEventListener('touchend', end);
    return () => { window.removeEventListener('mousemove', move); window.removeEventListener('mouseup', end); window.removeEventListener('touchmove', move); window.removeEventListener('touchend', end); clearTimeout(timer.current); };
  });

  const bg = active ? (hasPLock ? theme.colors[2] : theme.colors[0]) : undefined;
  return (
    <div className={`w-9 h-12 rounded-lg flex flex-col justify-end overflow-hidden transition-all touch-none select-none cursor-pointer ${!active ? theme.bgControl : ''} ${playing ? 'ring-2 ring-white scale-105' : ''} ${pressing ? 'scale-95' : ''}`}
      style={{ background: bg, boxShadow: active && theme.glow ? `0 0 10px ${bg}` : 'inset 0 1px 2px rgba(0,0,0,0.2)' }}
      onMouseDown={handleStart} onTouchStart={handleStart}>
      {active && <div className="w-full bg-white/30" style={{ height: `${velocity * 100}%` }} />}
    </div>
  );
};

const Select = ({ value, onChange, options, label }) => {
  const theme = useContext(ThemeContext);
  return (
    <div className="flex flex-col gap-1">
      {label && <span className={`${theme.textMuted} text-xs`}>{label}</span>}
      <select value={value} onChange={e => onChange(e.target.value)} className={`${theme.bgControl} ${theme.text} rounded-lg px-2 py-1.5 text-sm outline-none`}>
        {options.map(o => <option key={o.value ?? o} value={o.value ?? o}>{o.label ?? o}</option>)}
      </select>
    </div>
  );
};

const EnvDisplay = ({ a, d, s, r, color }) => {
  const theme = useContext(ThemeContext);
  const total = a + d + r + 0.2;
  const pts = [[0, 100], [a / total * 100, 0], [(a + d) / total * 100, (1 - s) * 100], [(a + d + 0.2) / total * 100, (1 - s) * 100], [100, 100]].map(p => p.join(',')).join(' ');
  return (
    <svg viewBox="0 0 100 100" className="w-full h-12">
      <polygon points={`0,100 ${pts}`} fill={color || theme.colors[0]} opacity="0.2" />
      <polyline points={pts} fill="none" stroke={color || theme.colors[0]} strokeWidth="2" />
    </svg>
  );
};

const XYPad = ({ x, y, onX, onY }) => {
  const theme = useContext(ThemeContext);
  const ref = useRef(null);
  const [dragging, setDragging] = useState(false);

  const handleStart = (e) => { e.preventDefault(); setDragging(true); handleMove(e); };
  const handleMove = useCallback((e) => {
    if (!ref.current) return;
    const rect = ref.current.getBoundingClientRect();
    const t = e.touches?.[0] || e;
    onX(Math.max(0, Math.min(1, (t.clientX - rect.left) / rect.width)));
    onY(1 - Math.max(0, Math.min(1, (t.clientY - rect.top) / rect.height)));
  }, [onX, onY]);

  useEffect(() => {
    if (!dragging) return;
    const move = (e) => handleMove(e);
    const end = () => setDragging(false);
    window.addEventListener('mousemove', move); window.addEventListener('mouseup', end);
    window.addEventListener('touchmove', move, { passive: false }); window.addEventListener('touchend', end);
    return () => { window.removeEventListener('mousemove', move); window.removeEventListener('mouseup', end); window.removeEventListener('touchmove', move); window.removeEventListener('touchend', end); };
  }, [dragging, handleMove]);

  return (
    <div ref={ref} className={`relative aspect-square ${theme.bgControl} rounded-xl cursor-crosshair touch-none overflow-hidden`}
      onMouseDown={handleStart} onTouchStart={handleStart}>
      <svg className="absolute inset-0 w-full h-full opacity-20" viewBox="0 0 100 100">
        {[25, 50, 75].map(p => <g key={p}><line x1={p} y1="0" x2={p} y2="100" stroke="currentColor" /><line x1="0" y1={p} x2="100" y2={p} stroke="currentColor" /></g>)}
      </svg>
      <div className="absolute w-0.5 opacity-50" style={{ left: `${x * 100}%`, top: 0, bottom: 0, background: theme.colors[0] }} />
      <div className="absolute h-0.5 opacity-50" style={{ top: `${(1 - y) * 100}%`, left: 0, right: 0, background: theme.colors[1] }} />
      <div className={`absolute w-6 h-6 rounded-full border-2 -translate-x-1/2 -translate-y-1/2 ${dragging ? 'scale-125' : ''}`}
        style={{ left: `${x * 100}%`, top: `${(1 - y) * 100}%`, borderColor: theme.colors[0], background: `${theme.colors[0]}44`, boxShadow: theme.glow ? `0 0 15px ${theme.colors[0]}` : 'none' }} />
    </div>
  );
};

// === PATCHBAY ===
const PatchBay = ({ track, onUpdateLFO, onAddMod, onRemoveMod, onUpdateMod }) => {
  const theme = useContext(ThemeContext);
  const containerRef = useRef(null);
  const srcRefs = useRef({}), destRefs = useRef({});
  const [cables, setCables] = useState([]);
  const [patching, setPatching] = useState(null);
  const [mousePos, setMousePos] = useState({ x: 0, y: 0 });

  const updateCables = useCallback(() => {
    if (!containerRef.current) return;
    const rect = containerRef.current.getBoundingClientRect();
    setCables(track.modMatrix.map((m, i) => {
      const s = srcRefs.current[m.source], d = destRefs.current[m.dest];
      if (!s || !d) return null;
      const sr = s.getBoundingClientRect(), dr = d.getBoundingClientRect();
      return { from: { x: sr.right - rect.left, y: sr.top + sr.height / 2 - rect.top }, to: { x: dr.left - rect.left, y: dr.top + dr.height / 2 - rect.top }, color: theme.colors[i % theme.colors.length], amt: m.amount };
    }).filter(Boolean));
  }, [track.modMatrix, theme.colors]);

  useEffect(() => { updateCables(); window.addEventListener('resize', updateCables); return () => window.removeEventListener('resize', updateCables); }, [updateCables]);
  useEffect(() => { setTimeout(updateCables, 50); }, [track.modMatrix, updateCables]);

  const startPatch = (src) => setPatching(src);
  const endPatch = (dest) => { if (patching) { onAddMod(patching, dest, 0.5); setPatching(null); } };

  return (
    <div ref={containerRef} className="relative" onMouseMove={e => { if (!containerRef.current || !patching) return; const r = containerRef.current.getBoundingClientRect(); setMousePos({ x: e.clientX - r.left, y: e.clientY - r.top }); }}>
      <svg className="absolute inset-0 w-full h-full pointer-events-none" style={{ zIndex: 5 }}>
        {cables.map((c, i) => (
          <g key={i}>
            <path d={`M ${c.from.x} ${c.from.y} C ${c.from.x + 40} ${c.from.y + 30}, ${c.to.x - 40} ${c.to.y + 30}, ${c.to.x} ${c.to.y}`}
              fill="none" stroke={c.color} strokeWidth={2 + Math.abs(c.amt) * 2} strokeLinecap="round" opacity="0.7"
              style={{ filter: theme.glow ? `drop-shadow(0 0 4px ${c.color})` : 'none' }} />
            <circle cx={c.from.x} cy={c.from.y} r="4" fill={c.color} />
            <circle cx={c.to.x} cy={c.to.y} r="4" fill={c.color} />
          </g>
        ))}
        {patching && srcRefs.current[patching] && (
          <path d={`M ${srcRefs.current[patching].getBoundingClientRect().right - containerRef.current.getBoundingClientRect().left} ${srcRefs.current[patching].getBoundingClientRect().top + srcRefs.current[patching].getBoundingClientRect().height / 2 - containerRef.current.getBoundingClientRect().top} Q ${mousePos.x} ${mousePos.y + 30}, ${mousePos.x} ${mousePos.y}`}
            fill="none" stroke={theme.colors[0]} strokeWidth="2" strokeDasharray="6 3" opacity="0.6" />
        )}
      </svg>

      {/* LFOs */}
      <div className="grid grid-cols-3 gap-3 mb-4 relative z-10">
        {[0, 1, 2].map(i => (
          <div key={i} className={`${theme.bgControl} rounded-xl p-3`}>
            <div className="flex items-center justify-between mb-2">
              <span className={`${theme.textAccent} text-sm font-medium`}>LFO {i + 1}</span>
              <div ref={el => srcRefs.current[`lfo${i + 1}`] = el} onClick={() => startPatch(`lfo${i + 1}`)}
                className={`w-4 h-4 rounded-full ${theme.accent} cursor-pointer hover:scale-110 ${patching ? 'animate-pulse' : ''}`} />
            </div>
            <Slider value={track.lfos[i].rate} onChange={v => onUpdateLFO(i, 'rate', v)} min={0.1} max={20} label="Rate" />
            <Select value={track.lfos[i].shape} onChange={v => onUpdateLFO(i, 'shape', v)} options={['sine', 'square', 'saw', 'tri', 'rand']} label="Shape" />
          </div>
        ))}
      </div>

      {/* Sources */}
      <div className="mb-3 relative z-10">
        <span className={`${theme.textMuted} text-xs mb-2 block`}>SOURCES</span>
        <div className="flex gap-2 flex-wrap">
          {['env', 'random', 'stepPos', 'velocity', 'xyPadX', 'xyPadY'].map((s, i) => (
            <div key={s} ref={el => srcRefs.current[s] = el} onClick={() => startPatch(s)}
              className={`px-3 py-2 ${theme.bgControl} rounded-lg cursor-pointer hover:scale-105 flex items-center gap-2 ${patching ? 'animate-pulse' : ''}`}>
              <div className="w-2 h-2 rounded-full" style={{ background: theme.colors[(i + 3) % 5] }} />
              <span className={`${theme.text} text-xs`}>{s}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Destinations */}
      <div className="mb-4 relative z-10">
        <span className={`${theme.textMuted} text-xs mb-2 block`}>DESTINATIONS {patching && `(connect ${patching})`}</span>
        <div className="flex gap-2 flex-wrap">
          {modDests.map((d, i) => (
            <div key={d} ref={el => destRefs.current[d] = el} onClick={() => patching && endPatch(d)}
              className={`px-2 py-1.5 ${patching ? theme.accent : theme.bgControl} rounded-lg cursor-pointer hover:scale-105 flex items-center gap-1`}>
              <div className="w-2 h-2 rounded-full border" style={{ borderColor: theme.colors[i % 5] }} />
              <span className={`${theme.text} text-xs`}>{d.split('.').pop()}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Active Patches */}
      <div className="space-y-2 relative z-10">
        <span className={`${theme.textMuted} text-xs`}>PATCHES ({track.modMatrix.length})</span>
        {track.modMatrix.map((m, i) => (
          <div key={i} className={`flex items-center gap-2 ${theme.bgControl} rounded-lg p-2`}>
            <div className="w-2 h-2 rounded-full" style={{ background: theme.colors[i % 5] }} />
            <span className={`${theme.text} text-xs`}>{m.source}</span>
            <span className={theme.textMuted}>→</span>
            <span className={`${theme.text} text-xs`}>{m.dest.split('.').pop()}</span>
            <input type="range" min="-1" max="1" step="0.01" value={m.amount} onChange={e => onUpdateMod(i, +e.target.value)} className="flex-1 h-1" />
            <span className={`${theme.textMuted} text-xs w-8`}>{m.amount.toFixed(2)}</span>
            <button onClick={() => onRemoveMod(i)} className={`w-6 h-6 ${theme.bgCard} rounded text-red-400`}>×</button>
          </div>
        ))}
        {patching && <button onClick={() => setPatching(null)} className={`w-full py-2 ${theme.bgControl} rounded-lg ${theme.text} text-sm`}>Cancel</button>}
      </div>
    </div>
  );
};

// === MAIN ===
export default function DrumMachine() {
  const [themeName, setThemeName] = useState('midnight');
  const theme = themes[themeName];

  const [tracks, setTracks] = useState([
    { ...createTrack(1, 'Kick'), engine: { ...enginePresets.kick808 } },
    { ...createTrack(2, 'Snare'), engine: { ...enginePresets.snare } },
    { ...createTrack(3, 'HiHat'), engine: { ...enginePresets.hihatClosed } },
  ]);
  const [selectedTrack, setSelectedTrack] = useState(0);
  const [selectedStep, setSelectedStep] = useState(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentStep, setCurrentStep] = useState(0);
  const [tempo, setTempo] = useState(120);
  const [masterVol, setMasterVol] = useState(0.8);
  const [view, setView] = useState('sequencer');
  const [engineTab, setEngineTab] = useState('synthA');
  const [scenes, setScenes] = useState([{ patterns: {} }]);
  const [currentScene, setCurrentScene] = useState(0);
  const [muteGroups, setMuteGroups] = useState({ A: false, B: false, C: false, D: false });
  const [xyPad, setXYPad] = useState({ x: 0.5, y: 0.5 });
  const [clipboard, setClipboard] = useState(null);
  const [isRecording, setIsRecording] = useState(false);
  const [midiRec, setMidiRec] = useState([]);
  const [recStart, setRecStart] = useState(null);
  const [isRecSample, setIsRecSample] = useState(null);
  const [lfoPhase, setLfoPhase] = useState(0);
  const [autoParam, setAutoParam] = useState('synthA.filter.cutoff');
  const [savedPresets, setSavedPresets] = useState({});

  const audioCtxRef = useRef(null);
  const intervalRef = useRef(null);
  const lfoRef = useRef(null);
  const mediaRecRef = useRef(null);
  const chunksRef = useRef([]);
  const nextId = useRef(4);

  const getCtx = () => { if (!audioCtxRef.current) audioCtxRef.current = new (window.AudioContext || window.webkitAudioContext)(); return audioCtxRef.current; };

  // === LFO ===
  const getLfoVal = useCallback((lfo, phase) => {
    const p = ((phase * lfo.rate) + lfo.phase) % 1;
    switch (lfo.shape) { case 'sine': return Math.sin(p * Math.PI * 2); case 'square': return p < 0.5 ? 1 : -1; case 'saw': return 2 * p - 1; case 'tri': return 1 - 4 * Math.abs(p - 0.5); default: return Math.random() * 2 - 1; }
  }, []);

  const applyMod = useCallback((track, params, stepIdx, vel) => {
    const mod = { ...params };
    track.modMatrix.forEach(m => {
      let v = 0;
      switch (m.source) {
        case 'lfo1': v = getLfoVal(track.lfos[0], lfoPhase); break;
        case 'lfo2': v = getLfoVal(track.lfos[1], lfoPhase); break;
        case 'lfo3': v = getLfoVal(track.lfos[2], lfoPhase); break;
        case 'env': v = 1 - stepIdx / track.steps; break;
        case 'random': v = Math.random() * 2 - 1; break;
        case 'stepPos': v = (stepIdx / track.steps) * 2 - 1; break;
        case 'velocity': v = vel * 2 - 1; break;
        case 'xyPadX': v = xyPad.x * 2 - 1; break;
        case 'xyPadY': v = xyPad.y * 2 - 1; break;
      }
      const keys = m.dest.split('.');
      let obj = mod;
      for (let i = 0; i < keys.length - 1; i++) { if (!obj[keys[i]]) return; obj = obj[keys[i]]; }
      const k = keys[keys.length - 1];
      if (typeof obj[k] === 'number') obj[k] = Math.max(0, obj[k] + v * m.amount * 1000);
    });
    return mod;
  }, [getLfoVal, lfoPhase, xyPad]);

  useEffect(() => { if (isPlaying) { lfoRef.current = setInterval(() => setLfoPhase(p => (p + 0.01) % 1), 16); } return () => clearInterval(lfoRef.current); }, [isPlaying]);

  // === SYNTH ===
  const synth = useCallback((voice, ctx, now, vel) => {
    if (!voice.enabled) return null;
    const out = ctx.createGain(); out.gain.value = voice.volume * vel;
    const flt = ctx.createBiquadFilter(); flt.type = voice.filter.type; flt.frequency.value = voice.filter.cutoff; flt.Q.value = voice.filter.res;
    const env = ctx.createGain();
    env.gain.setValueAtTime(0, now);
    env.gain.linearRampToValueAtTime(1, now + voice.ampEnv.a);
    env.gain.linearRampToValueAtTime(voice.ampEnv.s, now + voice.ampEnv.a + voice.ampEnv.d);
    env.gain.linearRampToValueAtTime(0, now + voice.ampEnv.a + voice.ampEnv.d + voice.ampEnv.r);

    let src;
    if (voice.type === 'subtractive' || voice.type === 'wavefold') {
      const osc = ctx.createOscillator(); osc.type = voice.osc.type; osc.frequency.value = voice.osc.freq; osc.detune.value = voice.osc.detune;
      osc.frequency.exponentialRampToValueAtTime(Math.max(20, voice.osc.freq * 0.1), now + voice.ampEnv.d);
      if (voice.type === 'wavefold' && voice.wavefold.amount > 0) {
        const ws = ctx.createWaveShaper(); const curve = new Float32Array(256); const amt = 1 + voice.wavefold.amount * 10;
        for (let i = 0; i < 256; i++) curve[i] = Math.sin(((i / 128) - 1) * amt * Math.PI);
        ws.curve = curve; osc.connect(ws); src = ws;
      } else { src = osc; }
      osc.start(now); osc.stop(now + 2);
    } else if (voice.type === 'fm') {
      const car = ctx.createOscillator(), mod = ctx.createOscillator(), modG = ctx.createGain();
      car.frequency.value = voice.osc.freq; mod.frequency.value = voice.osc.freq * voice.fm.ratio; modG.gain.value = voice.osc.freq * voice.fm.index;
      mod.connect(modG); modG.connect(car.frequency); mod.start(now); mod.stop(now + 2); car.start(now); car.stop(now + 2); src = car;
    } else if (voice.type === 'additive') {
      const merger = ctx.createGain();
      voice.additive.harmonics.forEach((amp, i) => { if (amp > 0) { const o = ctx.createOscillator(), g = ctx.createGain(); o.frequency.value = voice.osc.freq * (i + 1); g.gain.value = amp; o.connect(g); g.connect(merger); o.start(now); o.stop(now + 2); } });
      src = merger;
    } else if (voice.type === 'noise') {
      const buf = ctx.createBuffer(1, ctx.sampleRate * 0.5, ctx.sampleRate), d = buf.getChannelData(0);
      for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
      const ns = ctx.createBufferSource(); ns.buffer = buf;
      const osc = ctx.createOscillator(); osc.frequency.value = voice.osc.freq;
      const mix = ctx.createGain(), nG = ctx.createGain(), oG = ctx.createGain();
      nG.gain.value = voice.noise.amount; oG.gain.value = 1 - voice.noise.amount;
      ns.connect(nG); nG.connect(mix); osc.connect(oG); oG.connect(mix);
      ns.start(now); osc.start(now); ns.stop(now + 2); osc.stop(now + 2); src = mix;
    } else if (voice.type === 'karplus') {
      const len = Math.round(ctx.sampleRate / voice.osc.freq), buf = ctx.createBuffer(1, len, ctx.sampleRate), d = buf.getChannelData(0);
      for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
      const ns = ctx.createBufferSource(); ns.buffer = buf; ns.loop = true;
      const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = voice.osc.freq * 4;
      ns.connect(lp); ns.start(now); ns.stop(now + 2); src = lp;
    }
    if (src) { try { src.connect(flt); } catch { } }
    flt.connect(env); env.connect(out);
    return out;
  }, []);

  const playSample = useCallback((slot, ctx, now, vel) => {
    if (!slot.enabled || !slot.buffer) return null;
    const src = ctx.createBufferSource(); src.buffer = slot.buffer; src.playbackRate.value = Math.pow(2, slot.pitch / 12);
    const g = ctx.createGain(); g.gain.value = slot.volume * vel;
    const flt = ctx.createBiquadFilter(); flt.type = slot.filter.type; flt.frequency.value = slot.filter.cutoff; flt.Q.value = slot.filter.res;
    src.connect(flt); flt.connect(g);
    const dur = slot.buffer.duration; src.start(now, dur * slot.start, dur * (slot.end - slot.start));
    return g;
  }, []);

  const playTrack = useCallback((track, vel, stepIdx = 0) => {
    const ctx = getCtx(), now = ctx.currentTime;
    let eng = JSON.parse(JSON.stringify(track.engine));
    eng = applyMod(track, eng, stepIdx, vel);

    // Humanize
    const h = eng.humanize;
    if (Math.random() > h.probability) return;
    vel = Math.max(0.1, Math.min(1, vel + (Math.random() - 0.5) * h.velRand * 2));
    const timeOff = (Math.random() - 0.5) * h.timeRand * 0.05;

    const master = ctx.createGain(), pan = ctx.createStereoPanner();
    master.gain.value = eng.master.volume * masterVol * vel; pan.pan.value = eng.master.pan;

    const srcs = [];
    if (eng.blend.synthA > 0) { const s = synth(eng.synthA, ctx, now + timeOff, eng.blend.synthA); if (s) srcs.push(s); }
    if (eng.blend.synthB > 0) { const s = synth(eng.synthB, ctx, now + timeOff, eng.blend.synthB); if (s) srcs.push(s); }
    if (eng.blend.sampleA > 0) { const s = playSample(eng.sampleA, ctx, now + timeOff, eng.blend.sampleA); if (s) srcs.push(s); }
    if (eng.blend.sampleB > 0) { const s = playSample(eng.sampleB, ctx, now + timeOff, eng.blend.sampleB); if (s) srcs.push(s); }

    // FX
    let fxChain = pan;
    if (eng.fx.bitcrush > 0) {
      const ws = ctx.createWaveShaper(), curve = new Float32Array(256), step = Math.pow(0.5, 8 - eng.fx.bitcrush * 7);
      for (let i = 0; i < 256; i++) curve[i] = Math.round(((i / 128) - 1) / step) * step;
      ws.curve = curve; pan.connect(ws); fxChain = ws;
    }
    if (eng.fx.delayMix > 0) {
      const d = ctx.createDelay(2), dg = ctx.createGain(), fb = ctx.createGain();
      d.delayTime.value = eng.fx.delayTime; dg.gain.value = eng.fx.delayMix; fb.gain.value = eng.fx.delayFB;
      fxChain.connect(d); d.connect(dg); d.connect(fb); fb.connect(d); dg.connect(ctx.destination);
    }
    if (eng.fx.reverbMix > 0) {
      const len = ctx.sampleRate * eng.fx.reverbDecay, imp = ctx.createBuffer(2, len, ctx.sampleRate);
      for (let c = 0; c < 2; c++) { const ch = imp.getChannelData(c); for (let i = 0; i < len; i++) ch[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, 2); }
      const conv = ctx.createConvolver(), rg = ctx.createGain(); conv.buffer = imp; rg.gain.value = eng.fx.reverbMix;
      fxChain.connect(conv); conv.connect(rg); rg.connect(ctx.destination);
    }
    if (eng.master.drive > 0) {
      const ws = ctx.createWaveShaper(), k = eng.master.drive * 50, curve = new Float32Array(256);
      for (let i = 0; i < 256; i++) { const x = (i / 128) - 1; curve[i] = ((3 + k) * x * 20) / (Math.PI + k * Math.abs(x * 20)); }
      ws.curve = curve; srcs.forEach(s => s.connect(ws)); ws.connect(pan);
    } else { srcs.forEach(s => s.connect(pan)); }

    fxChain.connect(master); master.connect(ctx.destination);
  }, [synth, playSample, masterVol, applyMod]);

  const playStep = useCallback((track, si) => {
    const step = track.pattern[si]; if (!step.active || track.muted) return;
    if (tracks.some(t => t.solo) && !track.solo) return;
    if (track.muteGroup && muteGroups[track.muteGroup]) return;

    // Apply p-locks & automation
    let t = { ...track, engine: JSON.parse(JSON.stringify(track.engine)) };
    if (step.pLocks) Object.entries(step.pLocks).forEach(([k, v]) => { const keys = k.split('.'); let o = t.engine; for (let i = 0; i < keys.length - 1; i++) o = o[keys[i]]; o[keys[keys.length - 1]] = v; });
    Object.entries(track.automation).forEach(([k, vals]) => { if (vals?.[si] !== undefined) { const keys = k.split('.'); let o = t.engine; for (let i = 0; i < keys.length - 1; i++) o = o[keys[i]]; o[keys[keys.length - 1]] = vals[si]; } });

    playTrack(t, step.velocity, si);

    if (isRecording && recStart) setMidiRec(p => [...p, { ts: Date.now() - recStart, trackId: track.id, step: si, vel: step.velocity }]);
  }, [playTrack, tracks, muteGroups, isRecording, recStart]);

  // Sequencer
  useEffect(() => {
    if (!isPlaying) return;
    const int = (60 / tempo / 4) * 1000;
    let last = performance.now(), acc = 0;
    const tick = () => {
      const now = performance.now(); acc += now - last; last = now;
      if (acc >= int) {
        acc -= int;
        setCurrentStep(p => {
          const next = (p + 1) % Math.max(...tracks.map(t => t.steps));
          tracks.forEach(t => {
            const s = next % t.steps, sw = s % 2 === 1 ? t.swing * int * 0.5 : 0;
            if (sw > 0) setTimeout(() => playStep(t, s), sw); else playStep(t, s);
          });
          return next;
        });
      }
      intervalRef.current = requestAnimationFrame(tick);
    };
    intervalRef.current = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(intervalRef.current);
  }, [isPlaying, tempo, tracks, playStep]);

  // Sample Recording
  const startRecSample = async (slot) => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const rec = new MediaRecorder(stream); mediaRecRef.current = rec; chunksRef.current = [];
      rec.ondataavailable = e => { if (e.data.size > 0) chunksRef.current.push(e.data); };
      rec.onstop = async () => {
        const blob = new Blob(chunksRef.current, { type: 'audio/webm' }), ab = await blob.arrayBuffer();
        const buf = await getCtx().decodeAudioData(ab);
        updateEngine(`${slot}.enabled`, true); updateEngine(`${slot}.buffer`, buf); updateEngine(`${slot}.name`, `Rec ${new Date().toLocaleTimeString()}`);
        stream.getTracks().forEach(t => t.stop());
      };
      rec.start(); setIsRecSample(slot);
    } catch (e) { console.error(e); }
  };
  const stopRecSample = () => { mediaRecRef.current?.stop(); setIsRecSample(null); };

  // MIDI Export
  const exportMidi = () => {
    if (!midiRec.length) return;
    const header = [0x4D, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 0, 0, 1, 0, 0x60], trkHdr = [0x4D, 0x54, 0x72, 0x6B];
    const evts = []; let lastT = 0;
    const varLen = v => { if (v < 128) return [v]; const b = []; b.unshift(v & 0x7F); v >>= 7; while (v > 0) { b.unshift((v & 0x7F) | 0x80); v >>= 7; } return b; };
    midiRec.forEach(e => { const d = Math.round((e.ts - lastT) * 0.096); lastT = e.ts; evts.push(...varLen(d), 0x90, 60, Math.round(e.vel * 127), 0, 0x80, 60, 0); });
    evts.push(0, 0xFF, 0x2F, 0);
    const len = evts.length, lenB = [(len >> 24) & 0xFF, (len >> 16) & 0xFF, (len >> 8) & 0xFF, len & 0xFF];
    const data = new Uint8Array([...header, ...trkHdr, ...lenB, ...evts]);
    const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([data], { type: 'audio/midi' })); a.download = `session-${Date.now()}.mid`; a.click();
  };

  // State Helpers
  const updateTrack = (k, v) => setTracks(p => p.map((t, i) => i === selectedTrack ? { ...t, [k]: v } : t));
  const updateEngine = (path, v) => setTracks(p => p.map((t, i) => {
    if (i !== selectedTrack || typeof path !== 'string') return t;
    const keys = path.split('.');
    if (keys.some(k => !k || ['__proto__', 'constructor', 'prototype'].includes(k))) return t;
    const e = JSON.parse(JSON.stringify(t.engine));
    let o = e;
    for (let j = 0; j < keys.length; j++) {
      if (!o || typeof o !== 'object' || !Object.prototype.hasOwnProperty.call(o, keys[j])) return t;
      if (j === keys.length - 1) o[keys[j]] = v;
      else o = o[keys[j]];
    }
    return { ...t, engine: e };
  }));
  const updateLFO = (i, k, v) => setTracks(p => p.map((t, j) => { if (j !== selectedTrack) return t; const lfos = [...t.lfos]; lfos[i] = { ...lfos[i], [k]: v }; return { ...t, lfos }; }));
  const addMod = (src, dest, amt) => setTracks(p => p.map((t, i) => i !== selectedTrack || t.modMatrix.find(m => m.source === src && m.dest === dest) ? t : { ...t, modMatrix: [...t.modMatrix, { source: src, dest, amount: amt }] }));
  const removeMod = (idx) => setTracks(p => p.map((t, i) => i !== selectedTrack ? t : { ...t, modMatrix: t.modMatrix.filter((_, j) => j !== idx) }));
  const updateMod = (idx, amt) => setTracks(p => p.map((t, i) => { if (i !== selectedTrack) return t; const mm = [...t.modMatrix]; mm[idx] = { ...mm[idx], amount: amt }; return { ...t, modMatrix: mm }; }));
  const toggleStep = (ti, si) => setTracks(p => p.map((t, i) => { if (i !== ti) return t; const pat = [...t.pattern]; pat[si] = { ...pat[si], active: !pat[si].active }; return { ...t, pattern: pat }; }));
  const setStepVel = (ti, si, v) => setTracks(p => p.map((t, i) => { if (i !== ti) return t; const pat = [...t.pattern]; pat[si] = { ...pat[si], velocity: v }; return { ...t, pattern: pat }; }));
  const setPLock = (k, v) => { if (selectedStep === null) return; setTracks(p => p.map((t, i) => { if (i !== selectedTrack) return t; const pat = [...t.pattern]; pat[selectedStep] = { ...pat[selectedStep], pLocks: { ...(pat[selectedStep].pLocks || {}), [k]: v } }; return { ...t, pattern: pat }; })); };
  const setAuto = (si, v) => setTracks(p => p.map((t, i) => { if (i !== selectedTrack) return t; const auto = { ...t.automation }; if (!auto[autoParam]) auto[autoParam] = Array(t.steps).fill(undefined); auto[autoParam][si] = v; return { ...t, automation: auto }; }));
  const addTrack = () => setTracks(p => [...p, createTrack(nextId.current++)]);
  const removeTrack = i => { if (tracks.length <= 1) return; setTracks(p => p.filter((_, j) => j !== i)); if (selectedTrack >= tracks.length - 1) setSelectedTrack(Math.max(0, tracks.length - 2)); };
  const copyPattern = () => setClipboard({ pattern: JSON.parse(JSON.stringify(tracks[selectedTrack].pattern)), auto: JSON.parse(JSON.stringify(tracks[selectedTrack].automation)) });
  const pastePattern = () => { if (clipboard) setTracks(p => p.map((t, i) => i === selectedTrack ? { ...t, pattern: JSON.parse(JSON.stringify(clipboard.pattern)), automation: JSON.parse(JSON.stringify(clipboard.auto)) } : t)); };
  const saveScene = i => setScenes(p => { const u = [...p]; u[i] = { patterns: tracks.reduce((a, t) => ({ ...a, [t.id]: JSON.parse(JSON.stringify(t.pattern)) }), {}) }; return u; });
  const loadScene = i => { const s = scenes[i]; if (s?.patterns && Object.keys(s.patterns).length) { setTracks(p => p.map(t => ({ ...t, pattern: s.patterns[t.id] || t.pattern }))); setCurrentScene(i); } };
  const loadPreset = name => { if (enginePresets[name]) setTracks(p => p.map((t, i) => i === selectedTrack ? { ...t, engine: JSON.parse(JSON.stringify(enginePresets[name])) } : t)); };
  const savePreset = name => { if (name) setSavedPresets(p => ({ ...p, [name]: JSON.parse(JSON.stringify(tracks[selectedTrack].engine)) })); };
  const loadSavedPreset = name => { if (savedPresets[name]) setTracks(p => p.map((t, i) => i === selectedTrack ? { ...t, engine: JSON.parse(JSON.stringify(savedPresets[name])) } : t)); };

  const saveSession = async () => { try { await window.storage.set('drum-v6', JSON.stringify({ tracks: tracks.map(t => ({ ...t, engine: { ...t.engine, sampleA: { ...t.engine.sampleA, buffer: null }, sampleB: { ...t.engine.sampleB, buffer: null } } })), scenes, tempo, muteGroups, savedPresets })); alert('Saved!'); } catch (e) { } };
  const loadSession = async () => { try { const r = await window.storage.get('drum-v6'); if (r?.value) { const d = JSON.parse(r.value); setTracks(d.tracks); setScenes(d.scenes || [{ patterns: {} }]); setTempo(d.tempo); setMuteGroups(d.muteGroups || { A: false, B: false, C: false, D: false }); setSavedPresets(d.savedPresets || {}); } } catch (e) { } };

  const track = tracks[selectedTrack];
  const eng = track?.engine;
  const voice = eng?.[engineTab];

  return (
    <ThemeContext.Provider value={theme}>
      <div className={`min-h-screen ${theme.bg} ${theme.text} p-2 md:p-4 font-sans text-sm select-none`} onContextMenu={e => e.preventDefault()}>
        {/* Header */}
        <header className={`flex items-center justify-between mb-3 pb-2 ${theme.border} border-b`}>
          <h1 className={`text-lg font-bold ${theme.textAccent}`}>SYNTH DRUM v6</h1>
          <div className="flex gap-2">
            <select value={themeName} onChange={e => setThemeName(e.target.value)} className={`${theme.bgControl} ${theme.text} rounded-lg px-2 py-1 text-xs`}>
              {Object.entries(themes).map(([k, v]) => <option key={k} value={k}>{v.name}</option>)}
            </select>
            <button onClick={saveSession} className={`${theme.bgControl} px-3 py-1 rounded-lg text-xs`}>Save</button>
            <button onClick={loadSession} className={`${theme.bgControl} px-3 py-1 rounded-lg text-xs`}>Load</button>
          </div>
        </header>

        {/* Transport */}
        <div className={`flex items-center gap-3 mb-3 p-3 ${theme.bgCard} rounded-xl`}>
          <button onClick={() => setIsPlaying(!isPlaying)} className={`w-12 h-12 rounded-xl flex items-center justify-center text-2xl ${isPlaying ? theme.accent : theme.bgControl}`} style={{ boxShadow: isPlaying && theme.glow ? `0 0 20px ${theme.colors[0]}` : 'none' }}>{isPlaying ? '⏸' : '▶'}</button>
          <button onClick={() => { setIsPlaying(false); setCurrentStep(0); }} className={`w-12 h-12 rounded-xl ${theme.bgControl} text-2xl`}>⏹</button>
          <button onClick={() => { if (isRecording) { setIsRecording(false); setRecStart(null); } else { setMidiRec([]); setRecStart(Date.now()); setIsRecording(true); } }} className={`w-12 h-12 rounded-xl text-2xl ${isRecording ? 'bg-red-500 animate-pulse' : theme.bgControl}`}>⏺</button>
          <div className="flex-1"><span className={`${theme.textMuted} text-xs`}>BPM</span><Slider value={tempo} onChange={setTempo} min={40} max={240} /></div>
          <div className="w-20"><span className={`${theme.textMuted} text-xs`}>MASTER</span><Slider value={masterVol} onChange={setMasterVol} /></div>
          {midiRec.length > 0 && <button onClick={exportMidi} className="px-3 py-2 bg-purple-600 rounded-lg text-xs">MIDI ({midiRec.length})</button>}
        </div>

        {/* Scenes & Groups */}
        <div className="flex gap-2 mb-3 flex-wrap items-center">
          <span className={`${theme.textMuted} text-xs`}>SCENES</span>
          {scenes.map((_, i) => (<div key={i} className="flex"><button onClick={() => loadScene(i)} className={`px-3 py-1.5 rounded-l-lg ${currentScene === i ? theme.accent : theme.bgControl}`}>{i + 1}</button><button onClick={() => saveScene(i)} className={`px-2 py-1.5 rounded-r-lg ${theme.bgCard} text-xs`}>S</button></div>))}
          <button onClick={() => setScenes(p => [...p, { patterns: {} }])} className={`${theme.bgControl} px-2 py-1.5 rounded-lg`}>+</button>
          <span className={`${theme.textMuted} text-xs ml-2`}>GROUPS</span>
          {['A', 'B', 'C', 'D'].map(g => (<button key={g} onClick={() => setMuteGroups(p => ({ ...p, [g]: !p[g] }))} className={`px-3 py-1.5 rounded-lg ${muteGroups[g] ? 'bg-red-600' : theme.bgControl}`}>{g}</button>))}
        </div>

        {/* View Tabs */}
        <div className="flex gap-2 mb-3 overflow-x-auto pb-1">
          {['sequencer', 'engine', 'patchbay', 'mixer', 'automation', 'perform'].map(v => (
            <button key={v} onClick={() => setView(v)} className={`px-4 py-2 rounded-xl text-xs font-medium whitespace-nowrap ${view === v ? theme.accent + ' text-white' : theme.bgControl}`}>{v.toUpperCase()}</button>
          ))}
        </div>

        {/* SEQUENCER */}
        {view === 'sequencer' && (
          <div className="space-y-2">
            <div className="flex items-center gap-2 mb-2">
              <span className={theme.textMuted}>TRACKS</span>
              <button onClick={addTrack} className={`${theme.bgControl} px-2 py-1 rounded-lg text-xs`}>+</button>
              <button onClick={copyPattern} className={`${theme.bgControl} px-2 py-1 rounded-lg text-xs`}>CPY</button>
              <button onClick={pastePattern} className={`${clipboard ? 'bg-blue-600' : theme.bgControl + ' opacity-50'} px-2 py-1 rounded-lg text-xs`}>PST</button>
            </div>
            {tracks.map((t, ti) => (
              <div key={t.id} onClick={() => setSelectedTrack(ti)} className={`p-3 rounded-xl ${ti === selectedTrack ? theme.bgCard + ' ' + theme.borderAccent + ' border' : theme.bgCard + '/50 border border-transparent'} ${t.muted ? 'opacity-40' : ''}`}>
                <div className="flex items-center gap-2 mb-2">
                  <input value={t.name} onChange={e => setTracks(p => p.map((tr, i) => i === ti ? { ...tr, name: e.target.value } : tr))} className={`bg-transparent ${theme.textAccent} font-bold w-20 outline-none`} onClick={e => e.stopPropagation()} />
                  <button onClick={e => { e.stopPropagation(); setTracks(p => p.map((tr, i) => i === ti ? { ...tr, muted: !tr.muted } : tr)); }} className={`px-2 py-1 rounded-lg text-xs ${t.muted ? 'bg-red-500' : theme.bgControl}`}>M</button>
                  <button onClick={e => { e.stopPropagation(); setTracks(p => p.map((tr, i) => i === ti ? { ...tr, solo: !tr.solo } : tr)); }} className={`px-2 py-1 rounded-lg text-xs ${t.solo ? 'bg-yellow-500 text-black' : theme.bgControl}`}>S</button>
                  {t.modMatrix.length > 0 && <span className="px-2 py-0.5 bg-purple-600 rounded text-xs">⚡{t.modMatrix.length}</span>}
                  <span className={`${theme.textMuted} text-xs ml-auto`}>SW</span>
                  <input type="range" min="0" max="1" step="0.05" value={t.swing} onChange={e => setTracks(p => p.map((tr, i) => i === ti ? { ...tr, swing: +e.target.value } : tr))} className="w-16" onClick={e => e.stopPropagation()} />
                  <button onClick={e => { e.stopPropagation(); removeTrack(ti); }} className={`${theme.textMuted} hover:text-red-500`}>×</button>
                </div>
                <div className="flex gap-1 flex-wrap">
                  {t.pattern.map((step, si) => (
                    <div key={si} className={si % 4 === 0 && si > 0 ? 'ml-1.5' : ''}>
                      <StepBtn active={step.active} playing={currentStep % t.steps === si && isPlaying} hasPLock={!!step.pLocks} velocity={step.velocity} onToggle={() => toggleStep(ti, si)} onLongPress={() => { setSelectedTrack(ti); setSelectedStep(si); setView('engine'); }} onVelChange={v => setStepVel(ti, si, v)} />
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        )}

        {/* ENGINE */}
        {view === 'engine' && track && (
          <div className="space-y-3">
            {/* Presets */}
            <div className={`${theme.bgCard} rounded-xl p-3`}>
              <span className={`${theme.textMuted} text-xs mb-2 block`}>PRESETS</span>
              <div className="flex gap-2 flex-wrap">
                {Object.keys(enginePresets).map(p => (<button key={p} onClick={() => loadPreset(p)} className={`${theme.bgControl} px-3 py-1.5 rounded-lg text-xs`}>{p}</button>))}
              </div>
              <div className="flex gap-2 mt-2">
                {Object.keys(savedPresets).map(p => (<button key={p} onClick={() => loadSavedPreset(p)} className="bg-purple-700 px-3 py-1.5 rounded-lg text-xs">{p}</button>))}
                <button onClick={() => { const n = prompt('Preset name:'); if (n) savePreset(n); }} className={`${theme.bgControl} px-3 py-1.5 rounded-lg text-xs`}>+ Save</button>
              </div>
            </div>

            {/* Source Tabs */}
            <div className={`${theme.bgCard} rounded-xl p-3`}>
              <div className="grid grid-cols-4 gap-2 mb-3">
                {['synthA', 'synthB', 'sampleA', 'sampleB'].map((s, i) => (<button key={s} onClick={() => setEngineTab(s)} className={`p-2 rounded-lg text-xs ${engineTab === s ? theme.accent : theme.bgControl}`}>{s.includes('synth') ? `Synth ${s.slice(-1)}` : `Sample ${s.slice(-1)}`}</button>))}
              </div>
              <div className="grid grid-cols-4 gap-3 mb-3">
                {['synthA', 'synthB', 'sampleA', 'sampleB'].map((s, i) => (<div key={s} className="text-center"><Slider value={eng.blend[s]} onChange={v => updateEngine(`blend.${s}`, v)} vertical color={theme.colors[i % 5]} /><span className={`${theme.textMuted} text-xs`}>{s.slice(0, 2).toUpperCase()}{s.slice(-1)}</span></div>))}
              </div>
            </div>

            {/* Synth Params */}
            {engineTab.includes('synth') && voice && (
              <div className={`${theme.bgCard} rounded-xl p-3 space-y-3`}>
                <div className="flex items-center gap-2">
                  <button onClick={() => updateEngine(`${engineTab}.enabled`, !voice.enabled)} className={`px-3 py-1.5 rounded-lg text-xs ${voice.enabled ? theme.accent : theme.bgControl}`}>{voice.enabled ? 'ON' : 'OFF'}</button>
                  <Select value={voice.type} onChange={v => updateEngine(`${engineTab}.type`, v)} options={Object.entries(synthTypes).map(([k, v]) => ({ value: k, label: v }))} label="Type" />
                </div>
                <div className="grid grid-cols-4 md:grid-cols-6 gap-3">
                  {voice.type !== 'noise' && <Select value={voice.osc.type} onChange={v => updateEngine(`${engineTab}.osc.type`, v)} options={['sine', 'square', 'sawtooth', 'triangle']} label="Wave" />}
                  <Knob label="Freq" value={voice.osc.freq} onChange={v => updateEngine(`${engineTab}.osc.freq`, v)} min={20} max={2000} />
                  <Knob label="Detune" value={voice.osc.detune} onChange={v => updateEngine(`${engineTab}.osc.detune`, v)} min={-100} max={100} />
                  {voice.type === 'fm' && <><Knob label="FM Ratio" value={voice.fm.ratio} onChange={v => updateEngine(`${engineTab}.fm.ratio`, v)} min={0.5} max={8} /><Knob label="FM Index" value={voice.fm.index} onChange={v => updateEngine(`${engineTab}.fm.index`, v)} min={0} max={10} /></>}
                  {voice.type === 'noise' && <Knob label="Noise" value={voice.noise.amount} onChange={v => updateEngine(`${engineTab}.noise.amount`, v)} />}
                  {voice.type === 'wavefold' && <Knob label="Fold" value={voice.wavefold.amount} onChange={v => updateEngine(`${engineTab}.wavefold.amount`, v)} />}
                </div>
                <div className="grid grid-cols-4 md:grid-cols-5 gap-3">
                  <Select value={voice.filter.type} onChange={v => updateEngine(`${engineTab}.filter.type`, v)} options={['lowpass', 'highpass', 'bandpass', 'notch']} label="Filter" />
                  <Knob label="Cutoff" value={voice.filter.cutoff} onChange={v => updateEngine(`${engineTab}.filter.cutoff`, v)} min={20} max={20000} color={theme.colors[1]} />
                  <Knob label="Res" value={voice.filter.res} onChange={v => updateEngine(`${engineTab}.filter.res`, v)} min={0} max={25} color={theme.colors[1]} />
                  <Knob label="Env Amt" value={voice.filter.envAmt} onChange={v => updateEngine(`${engineTab}.filter.envAmt`, v)} min={-1} max={1} bipolar color={theme.colors[1]} />
                </div>
                <EnvDisplay a={voice.ampEnv.a} d={voice.ampEnv.d} s={voice.ampEnv.s} r={voice.ampEnv.r} color={theme.colors[2]} />
                <div className="grid grid-cols-4 gap-3">
                  <Knob label="Atk" value={voice.ampEnv.a} onChange={v => updateEngine(`${engineTab}.ampEnv.a`, v)} min={0.001} max={1} color={theme.colors[2]} />
                  <Knob label="Dec" value={voice.ampEnv.d} onChange={v => updateEngine(`${engineTab}.ampEnv.d`, v)} min={0.001} max={2} color={theme.colors[2]} />
                  <Knob label="Sus" value={voice.ampEnv.s} onChange={v => updateEngine(`${engineTab}.ampEnv.s`, v)} color={theme.colors[2]} />
                  <Knob label="Rel" value={voice.ampEnv.r} onChange={v => updateEngine(`${engineTab}.ampEnv.r`, v)} min={0.001} max={2} color={theme.colors[2]} />
                </div>
              </div>
            )}

            {/* Sample Params */}
            {engineTab.includes('sample') && (
              <div className={`${theme.bgCard} rounded-xl p-3 space-y-3`}>
                <button onClick={() => isRecSample === engineTab ? stopRecSample() : startRecSample(engineTab)} className={`w-full py-3 rounded-xl ${isRecSample === engineTab ? 'bg-red-500 animate-pulse' : theme.bgControl}`}>{isRecSample === engineTab ? '⏹ Stop' : '🎤 Record'}</button>
                {eng[engineTab].name && <div className={`${theme.bgControl} rounded-lg p-2`}><span className={theme.textMuted}>Loaded: </span>{eng[engineTab].name}</div>}
                <div className="grid grid-cols-4 gap-3">
                  <Knob label="Start" value={eng[engineTab].start} onChange={v => updateEngine(`${engineTab}.start`, v)} max={0.99} />
                  <Knob label="End" value={eng[engineTab].end} onChange={v => updateEngine(`${engineTab}.end`, v)} min={0.01} />
                  <Knob label="Pitch" value={eng[engineTab].pitch} onChange={v => updateEngine(`${engineTab}.pitch`, v)} min={-24} max={24} bipolar />
                  <Knob label="Vol" value={eng[engineTab].volume} onChange={v => updateEngine(`${engineTab}.volume`, v)} />
                </div>
              </div>
            )}

            {/* FX & Master */}
            <div className={`${theme.bgCard} rounded-xl p-3`}>
              <span className={`${theme.textMuted} text-xs mb-2 block`}>FX & MASTER</span>
              <div className="grid grid-cols-4 md:grid-cols-6 gap-3">
                <Knob label="Reverb" value={eng.fx.reverbMix} onChange={v => updateEngine('fx.reverbMix', v)} color={theme.colors[3]} />
                <Knob label="Delay" value={eng.fx.delayMix} onChange={v => updateEngine('fx.delayMix', v)} color={theme.colors[3]} />
                <Knob label="Dly Time" value={eng.fx.delayTime} onChange={v => updateEngine('fx.delayTime', v)} min={0.05} max={1} color={theme.colors[3]} />
                <Knob label="Crush" value={eng.fx.bitcrush} onChange={v => updateEngine('fx.bitcrush', v)} color={theme.colors[4]} />
                <Knob label="Drive" value={eng.master.drive} onChange={v => updateEngine('master.drive', v)} />
                <Knob label="Pan" value={eng.master.pan} onChange={v => updateEngine('master.pan', v)} min={-1} max={1} bipolar />
              </div>
            </div>

            {/* Humanize */}
            <div className={`${theme.bgCard} rounded-xl p-3`}>
              <span className={`${theme.textMuted} text-xs mb-2 block`}>HUMANIZE</span>
              <div className="grid grid-cols-4 gap-3">
                <Knob label="Vel Rand" value={eng.humanize.velRand} onChange={v => updateEngine('humanize.velRand', v)} max={0.5} />
                <Knob label="Time Rand" value={eng.humanize.timeRand} onChange={v => updateEngine('humanize.timeRand', v)} />
                <Knob label="Pitch Rand" value={eng.humanize.pitchRand} onChange={v => updateEngine('humanize.pitchRand', v)} />
                <Knob label="Probability" value={eng.humanize.probability} onChange={v => updateEngine('humanize.probability', v)} />
              </div>
            </div>

            {/* P-Lock */}
            {selectedStep !== null && (
              <div className={`${theme.bgCard} rounded-xl p-3`}>
                <span className={`${theme.textAccent} text-sm mb-2 block`}>P-LOCK STEP {selectedStep + 1}</span>
                <div className="grid grid-cols-4 gap-3">
                  <Knob label="Freq" value={track.pattern[selectedStep].pLocks?.['synthA.osc.freq'] ?? eng.synthA.osc.freq} onChange={v => setPLock('synthA.osc.freq', v)} min={20} max={2000} color={theme.colors[2]} />
                  <Knob label="Cutoff" value={track.pattern[selectedStep].pLocks?.['synthA.filter.cutoff'] ?? eng.synthA.filter.cutoff} onChange={v => setPLock('synthA.filter.cutoff', v)} min={20} max={20000} color={theme.colors[2]} />
                  <Knob label="Decay" value={track.pattern[selectedStep].pLocks?.['synthA.ampEnv.d'] ?? eng.synthA.ampEnv.d} onChange={v => setPLock('synthA.ampEnv.d', v)} max={2} color={theme.colors[2]} />
                  <button onClick={() => setTracks(p => p.map((t, i) => { if (i !== selectedTrack) return t; const pat = [...t.pattern]; pat[selectedStep] = { ...pat[selectedStep], pLocks: null }; return { ...t, pattern: pat }; }))} className={`${theme.bgControl} rounded-lg text-xs`}>Clear</button>
                </div>
              </div>
            )}
          </div>
        )}

        {/* PATCHBAY */}
        {view === 'patchbay' && track && (
          <div className={`${theme.bgCard} rounded-xl p-4`}>
            <h3 className={`${theme.textAccent} font-medium mb-3`}>MODULATION PATCHBAY — {track.name}</h3>
            <PatchBay track={track} onUpdateLFO={updateLFO} onAddMod={addMod} onRemoveMod={removeMod} onUpdateMod={updateMod} />
          </div>
        )}

        {/* MIXER */}
        {view === 'mixer' && (
          <div className={`${theme.bgCard} rounded-xl p-4`}>
            <div className="flex gap-4 overflow-x-auto pb-2">
              {tracks.map((t, i) => (
                <div key={t.id} className={`flex flex-col items-center ${theme.bgControl} rounded-xl p-3 min-w-24`}>
                  <span className={`text-xs ${theme.textMuted} mb-3`}>{t.name}</span>
                  <Slider value={t.engine.master.volume} onChange={v => setTracks(p => p.map((tr, j) => j === i ? { ...tr, engine: { ...tr.engine, master: { ...tr.engine.master, volume: v } } } : tr))} vertical />
                  <div className="mt-3 w-full"><Slider value={t.engine.master.pan} onChange={v => setTracks(p => p.map((tr, j) => j === i ? { ...tr, engine: { ...tr.engine, master: { ...tr.engine.master, pan: v } } } : tr))} min={-1} max={1} /></div>
                  <div className="flex gap-2 mt-3">
                    <button onClick={() => setTracks(p => p.map((tr, j) => j === i ? { ...tr, muted: !tr.muted } : tr))} className={`px-2 py-1 rounded text-xs ${t.muted ? 'bg-red-500' : theme.bgCard}`}>M</button>
                    <button onClick={() => setTracks(p => p.map((tr, j) => j === i ? { ...tr, solo: !tr.solo } : tr))} className={`px-2 py-1 rounded text-xs ${t.solo ? 'bg-yellow-500 text-black' : theme.bgCard}`}>S</button>
                  </div>
                </div>
              ))}
              <div className={`flex flex-col items-center ${theme.bgControl} rounded-xl p-3 min-w-24`}>
                <span className={`text-xs ${theme.textAccent} mb-3`}>MASTER</span>
                <Slider value={masterVol} onChange={setMasterVol} vertical color={theme.colors[0]} />
              </div>
            </div>
          </div>
        )}

        {/* AUTOMATION */}
        {view === 'automation' && track && (
          <div className={`${theme.bgCard} rounded-xl p-4`}>
            <div className="flex items-center gap-2 mb-3">
              <Select value={autoParam} onChange={setAutoParam} options={modDests.map(d => ({ value: d, label: d.split('.').slice(-2).join('.') }))} label="Parameter" />
              <button onClick={() => setTracks(p => p.map((t, i) => i === selectedTrack ? { ...t, automation: { ...t.automation, [autoParam]: undefined } } : t))} className={`${theme.bgControl} px-3 py-1.5 rounded-lg text-xs`}>Clear</button>
            </div>
            <div className="flex gap-px items-end h-24 bg-black/20 rounded-lg p-2">
              {Array(track.steps).fill(0).map((_, si) => {
                const val = track.automation[autoParam]?.[si];
                const pct = val !== undefined ? (val / 20000) * 100 : 0;
                return (
                  <div key={si} className="flex-1 h-full flex flex-col justify-end cursor-pointer"
                    onClick={() => setAuto(si, val !== undefined ? undefined : 1000)}
                    onMouseDown={e => { if (val === undefined) return; const rect = e.currentTarget.getBoundingClientRect(); const move = me => { const y = 1 - Math.max(0, Math.min(1, (me.clientY - rect.top) / rect.height)); setAuto(si, y * 20000); }; const up = () => { window.removeEventListener('mousemove', move); window.removeEventListener('mouseup', up); }; window.addEventListener('mousemove', move); window.addEventListener('mouseup', up); }}>
                    <div className={`w-full rounded-sm ${val !== undefined ? 'bg-cyan-500' : theme.bgControl}`} style={{ height: val !== undefined ? `${pct}%` : '2px' }} />
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* PERFORM */}
        {view === 'perform' && (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className={`${theme.bgCard} rounded-xl p-4`}>
              <h3 className={`${theme.textAccent} font-medium mb-3`}>XY PAD</h3>
              <XYPad x={xyPad.x} y={xyPad.y} onX={x => setXYPad(p => ({ ...p, x }))} onY={y => setXYPad(p => ({ ...p, y }))} />
              <div className="flex justify-between mt-2 text-xs"><span className={theme.textMuted}>X: {xyPad.x.toFixed(2)}</span><span className={theme.textMuted}>Y: {xyPad.y.toFixed(2)}</span></div>
            </div>
            <div className={`${theme.bgCard} rounded-xl p-4`}>
              <h3 className={`${theme.textAccent} font-medium mb-3`}>DRUM PADS</h3>
              <div className="grid grid-cols-4 gap-2">
                {tracks.slice(0, 8).map(t => (
                  <button key={t.id} onMouseDown={() => playTrack(t, 1, 0)} onTouchStart={e => { e.preventDefault(); playTrack(t, 1, 0); }}
                    className={`aspect-square rounded-xl ${theme.bgControl} flex items-center justify-center text-sm font-medium active:scale-95`}
                    style={{ boxShadow: theme.glow ? `inset 0 0 15px ${theme.colors[0]}33` : 'none' }}>{t.name}</button>
                ))}
              </div>
            </div>
          </div>
        )}

        <footer className={`${theme.textMuted} text-xs text-center mt-4`}>Tap to toggle • Drag for velocity • Long-press for P-Lock</footer>
      </div>
    </ThemeContext.Provider>
  );
}
