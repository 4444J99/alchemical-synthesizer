import { describe, it, expect } from "vitest";
import { OscReceiver } from "../src/osc.js";
import type { OscMessage } from "../src/osc.js";

describe("OscReceiver", () => {
  it("should parse a valid OSC message string", () => {
    const receiver = new OscReceiver({ port: 9000, host: "127.0.0.1", protocol: "udp" });
    const msg = receiver.parse("/synth/freq,440.0,0.8");
    expect(msg).not.toBeNull();
    expect(msg!.address).toBe("/synth/freq");
    expect(msg!.args).toHaveLength(2);
    expect(msg!.args[0].value).toBe(440.0);
  });

  it("should return null for invalid messages", () => {
    const receiver = new OscReceiver({ port: 9000, host: "127.0.0.1", protocol: "udp" });
    const msg = receiver.parse("not-an-osc-message");
    expect(msg).toBeNull();
  });

  it("should dispatch messages to registered handlers", () => {
    const receiver = new OscReceiver({ port: 9000, host: "127.0.0.1", protocol: "udp" });
    const received: OscMessage[] = [];
    receiver.on("/test", (msg) => received.push(msg));
    const msg = receiver.parse("/test,1.0")!;
    const count = receiver.dispatch(msg);
    expect(count).toBe(1);
    expect(received).toHaveLength(1);
  });

  it("should manage start/stop lifecycle", () => {
    const receiver = new OscReceiver({ port: 9000, host: "127.0.0.1", protocol: "udp" });
    expect(receiver.isRunning).toBe(false);
    receiver.start();
    expect(receiver.isRunning).toBe(true);
    receiver.stop();
    expect(receiver.isRunning).toBe(false);
  });
});
