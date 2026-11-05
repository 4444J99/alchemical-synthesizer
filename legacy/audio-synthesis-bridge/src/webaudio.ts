/**
 * WebAudio engine module for synthesis voice management.
 *
 * Provides a synthesis engine that manages multiple voices,
 * each with configurable oscillator parameters.
 */

/** Parameters for a single synthesis voice. */
export interface VoiceParams {
  frequency: number;
  amplitude: number;
  waveform: "sine" | "square" | "sawtooth" | "triangle";
  detune: number;
}

/** Configuration for the WebAudio engine. */
export interface EngineConfig {
  sampleRate: number;
  maxVoices: number;
  masterGain: number;
}

/** A single synthesis voice with parameter state. */
export class SynthVoice {
  readonly id: string;
  private params: VoiceParams;
  private active = false;

  constructor(id: string, params: Partial<VoiceParams> = {}) {
    this.id = id;
    this.params = {
      frequency: params.frequency ?? 440,
      amplitude: params.amplitude ?? 0.5,
      waveform: params.waveform ?? "sine",
      detune: params.detune ?? 0,
    };
  }

  /** Start this voice (begin producing sound). */
  noteOn(): void {
    this.active = true;
  }

  /** Stop this voice. */
  noteOff(): void {
    this.active = false;
  }

  /** Update voice parameters. */
  setParams(updates: Partial<VoiceParams>): void {
    this.params = { ...this.params, ...updates };
  }

  /** Get current voice parameters. */
  getParams(): VoiceParams {
    return { ...this.params };
  }

  /** Whether this voice is currently producing sound. */
  get isActive(): boolean {
    return this.active;
  }
}

/** Multi-voice synthesis engine with polyphonic voice allocation. */
export class WebAudioEngine {
  private config: EngineConfig;
  private voices: Map<string, SynthVoice> = new Map();
  private nextVoiceId = 1;

  constructor(config: Partial<EngineConfig> = {}) {
    this.config = {
      sampleRate: config.sampleRate ?? 44100,
      maxVoices: config.maxVoices ?? 16,
      masterGain: config.masterGain ?? 0.8,
    };
  }

  /**
   * Allocate a new synthesis voice.
   * @param params - Initial voice parameters.
   * @returns The allocated SynthVoice, or null if max voices reached.
   */
  allocateVoice(params: Partial<VoiceParams> = {}): SynthVoice | null {
    if (this.voices.size >= this.config.maxVoices) {
      return null;
    }
    const id = `voice-${String(this.nextVoiceId++).padStart(4, "0")}`;
    const voice = new SynthVoice(id, params);
    this.voices.set(id, voice);
    return voice;
  }

  /**
   * Release a voice by ID, removing it from the engine.
   * @param voiceId - The voice to release.
   */
  releaseVoice(voiceId: string): boolean {
    const voice = this.voices.get(voiceId);
    if (!voice) return false;
    voice.noteOff();
    this.voices.delete(voiceId);
    return true;
  }

  /** Get a voice by its ID. */
  getVoice(voiceId: string): SynthVoice | undefined {
    return this.voices.get(voiceId);
  }

  /** Number of currently allocated voices. */
  get voiceCount(): number {
    return this.voices.size;
  }

  /** Number of active (sounding) voices. */
  get activeVoiceCount(): number {
    return [...this.voices.values()].filter((v) => v.isActive).length;
  }

  /** Current engine configuration. */
  get currentConfig(): EngineConfig {
    return { ...this.config };
  }
}
