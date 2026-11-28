/**
 * audio-synthesis-bridge: OSC-to-WebAudio bridge for real-time synthesis.
 *
 * Part of ORGAN II (Poiesis) — the generative art and performance layer.
 */

export { OscReceiver, OscMessage } from "./osc.js";
export { WebAudioEngine, SynthVoice } from "./webaudio.js";
export type { OscConfig } from "./osc.js";
export type { EngineConfig, VoiceParams } from "./webaudio.js";