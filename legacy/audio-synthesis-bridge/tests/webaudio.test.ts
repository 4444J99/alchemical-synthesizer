import { describe, it, expect } from "vitest";
import { WebAudioEngine, SynthVoice } from "../src/webaudio.js";

describe("WebAudioEngine", () => {
  it("should allocate a voice with default params", () => {
    const engine = new WebAudioEngine();
    const voice = engine.allocateVoice();
    expect(voice).not.toBeNull();
    expect(voice!.getParams().frequency).toBe(440);
  });

  it("should respect max voice limit", () => {
    const engine = new WebAudioEngine({ maxVoices: 2 });
    engine.allocateVoice();
    engine.allocateVoice();
    const third = engine.allocateVoice();
    expect(third).toBeNull();
    expect(engine.voiceCount).toBe(2);
  });

  it("should assign deterministic voice ids and retain custom voice params", () => {
    const engine = new WebAudioEngine({ maxVoices: 3 });

    const first = engine.allocateVoice({
      frequency: 220,
      amplitude: 0.25,
      waveform: "triangle",
      detune: -12,
    })!;
    const second = engine.allocateVoice({ waveform: "square" })!;

    expect(first.id).toBe("voice-0001");
    expect(second.id).toBe("voice-0002");
    expect(engine.getVoice(first.id)).toBe(first);
    expect(first.getParams()).toEqual({
      frequency: 220,
      amplitude: 0.25,
      waveform: "triangle",
      detune: -12,
    });
    expect(second.getParams()).toEqual({
      frequency: 440,
      amplitude: 0.5,
      waveform: "square",
      detune: 0,
    });
  });

  it("should release voices", () => {
    const engine = new WebAudioEngine();
    const voice = engine.allocateVoice()!;
    expect(engine.releaseVoice(voice.id)).toBe(true);
    expect(engine.voiceCount).toBe(0);
  });

  it("should return false when releasing an unknown voice", () => {
    const engine = new WebAudioEngine();
    const voice = engine.allocateVoice()!;

    voice.noteOn();

    expect(engine.releaseVoice("missing-voice")).toBe(false);
    expect(engine.voiceCount).toBe(1);
    expect(voice.isActive).toBe(true);
  });

  it("should stop and remove released voices", () => {
    const engine = new WebAudioEngine();
    const voice = engine.allocateVoice()!;

    voice.noteOn();

    expect(engine.releaseVoice(voice.id)).toBe(true);
    expect(voice.isActive).toBe(false);
    expect(engine.getVoice(voice.id)).toBeUndefined();
  });

  it("should track active voice count", () => {
    const engine = new WebAudioEngine();
    const v1 = engine.allocateVoice()!;
    const v2 = engine.allocateVoice()!;
    v1.noteOn();
    expect(engine.activeVoiceCount).toBe(1);
    v2.noteOn();
    expect(engine.activeVoiceCount).toBe(2);
    v1.noteOff();
    expect(engine.activeVoiceCount).toBe(1);
  });

  it("should expose a defensive copy of engine configuration", () => {
    const engine = new WebAudioEngine({
      sampleRate: 48000,
      maxVoices: 2,
      masterGain: 0.6,
    });

    const config = engine.currentConfig;
    config.maxVoices = 99;
    config.masterGain = 1;

    expect(engine.currentConfig).toEqual({
      sampleRate: 48000,
      maxVoices: 2,
      masterGain: 0.6,
    });

    engine.allocateVoice();
    engine.allocateVoice();

    expect(engine.allocateVoice()).toBeNull();
  });
});

describe("SynthVoice", () => {
  it("should update params without losing unchanged values", () => {
    const voice = new SynthVoice("v1", { frequency: 880 });
    voice.setParams({ amplitude: 0.3 });
    const params = voice.getParams();
    expect(params.frequency).toBe(880);
    expect(params.amplitude).toBe(0.3);
  });

  it("should preserve explicit zero-valued params", () => {
    const voice = new SynthVoice("zero", {
      frequency: 0,
      amplitude: 0,
      detune: 0,
    });

    expect(voice.getParams()).toEqual({
      frequency: 0,
      amplitude: 0,
      waveform: "sine",
      detune: 0,
    });
  });

  it("should expose defensive copies of voice params", () => {
    const voice = new SynthVoice("copy", {
      amplitude: 0.75,
      waveform: "sawtooth",
      detune: 7,
    });

    const params = voice.getParams();
    params.frequency = 110;
    params.waveform = "square";

    expect(voice.getParams()).toEqual({
      frequency: 440,
      amplitude: 0.75,
      waveform: "sawtooth",
      detune: 7,
    });
  });

  it("should toggle active state with note lifecycle calls", () => {
    const voice = new SynthVoice("lifecycle");

    expect(voice.isActive).toBe(false);

    voice.noteOn();
    expect(voice.isActive).toBe(true);

    voice.noteOff();
    expect(voice.isActive).toBe(false);
  });
});
