import { describe, it, expect } from "vitest";
import { OscReceiver, WebAudioEngine } from "../src/index.js";
import type { OscConfig } from "../src/osc.js";

const defaultOscConfig: OscConfig = {
  port: 9000,
  host: "127.0.0.1",
  protocol: "udp",
};

describe("OSC-to-WebAudio Bridge", () => {
  it("should dispatch an OSC message to an engine voice", () => {
    const receiver = new OscReceiver(defaultOscConfig);
    const engine = new WebAudioEngine({ maxVoices: 4 });

    const voice = engine.allocateVoice({ frequency: 440, waveform: "sine" });
    expect(voice).not.toBeNull();

    // Wire OSC address to voice parameter update
    receiver.on("/synth/freq", (msg) => {
      if (voice && msg.args.length > 0 && typeof msg.args[0].value === "number") {
        voice.setParams({ frequency: msg.args[0].value });
      }
    });

    const parsed = receiver.parse("/synth/freq,880");
    expect(parsed).not.toBeNull();

    const dispatched = receiver.dispatch(parsed!);
    expect(dispatched).toBe(1);
    expect(voice!.getParams().frequency).toBe(880);
  });

  it("should respect max voice limit when bridging", () => {
    const engine = new WebAudioEngine({ maxVoices: 2 });
    const v1 = engine.allocateVoice();
    const v2 = engine.allocateVoice();
    const v3 = engine.allocateVoice();
    expect(v1).not.toBeNull();
    expect(v2).not.toBeNull();
    expect(v3).toBeNull();
    expect(engine.voiceCount).toBe(2);
  });
});