"""Contract test for the testament sonic bridge receiver (issue #127).

The engine half lives in organvm-engine (osc_bridge.py build_osc_messages,
OE main 1e4bec99): it transmits five OSC addresses over UDP to 127.0.0.1:57120.
This test pins the alchemical-synthesizer side of that contract in
brahma/sc/16_engine_responders.scd — every address the engine sends must have
a listener, the voice SynthDef must take the contract's arguments, and the
waveform map must cover every waveform the engine can send. It also checks
the responder file's delimiters balance, since no sclang runs in CI to catch
a syntax slip (see brahma/sc/tests/testament_receiver.scd for the live test,
runnable with SuperCollider via tools/test-supercollider.py).
"""

import re
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
RESPONDERS = ROOT / "brahma/sc/16_engine_responders.scd"
LOADER = ROOT / "brahma/sc/loader.scd"

# address -> argument names, from OE osc_bridge.py build_osc_messages.
EXPECTED = {
    "/testament/master": ["amp"],
    "/testament/bpm": ["bpm"],
    "/testament/env": ["attack", "decay", "sustain", "release"],
    "/testament/filter": ["cutoff", "resonance"],
    "/testament/voice/*": ["freq", "amp", "waveform", "detune", "pan"],
}

VOICE_DEF_ARGS = {
    "freq", "amp", "wave", "detune", "pan",
    "attack", "decay", "sustain", "release",
    "cutoff", "resonance", "master", "gate", "out",
}

ENGINE_WAVEFORMS = {"sine", "saw", "square", "tri"}


def _strip_sc(src):
    """Drop comments, strings, symbols and char literals, keeping code."""
    out = []
    i, n = 0, len(src)
    while i < n:
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j == -1 else j
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            if j == -1:
                raise AssertionError("unterminated block comment")
            i = j + 2
        elif src[i] == '"':
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == '"':
                    break
                j += 1
            if j >= n:
                raise AssertionError("unterminated string")
            i = j + 1
        elif src[i] == "'":
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == "'":
                    break
                j += 1
            if j >= n:
                raise AssertionError("unterminated symbol literal")
            i = j + 1
        elif src[i] == "$":
            i += 2  # char literal: $ + one character
        elif src[i] == "\\":
            j = i + 1
            if j < n and not (src[j].isalnum() or src[j] == "_"):
                i = j + 1
            else:
                while j < n and (src[j].isalnum() or src[j] == "_"):
                    j += 1
                i = j
        else:
            out.append(src[i])
            i += 1
    return "".join(out)


class TestamentReceiverContract(unittest.TestCase):
    def setUp(self):
        self.src = RESPONDERS.read_text()

    def test_every_engine_address_has_a_listener(self):
        for address in EXPECTED:
            pattern = re.compile(
                r"OSCdef\(\\\w+,\s*\{.*?\},\s*\"" + re.escape(address) + r'"\)',
                re.S,
            )
            self.assertRegex(
                self.src, pattern,
                f"no OSCdef listens on {address} — the engine sends it, nothing would hear it",
            )

    def test_voice_synthdef_takes_the_contract_arguments(self):
        match = re.search(
            r"SynthDef\(\\testament_voice,\s*\{\s*\|([^|]+)\|", self.src
        )
        self.assertIsNotNone(match, "SynthDef(\\testament_voice) not found")
        found = {part.split("=")[0].strip() for part in match.group(1).split(",")}
        self.assertEqual(
            VOICE_DEF_ARGS, found,
            f"voice def args {sorted(found)} != contract {sorted(VOICE_DEF_ARGS)}",
        )

    def test_waveform_map_covers_every_engine_waveform(self):
        start = self.src.index("~testamentWaveIndex")
        end = self.src.index("~testamentVoiceTrigger", start)
        region = self.src[start:end]
        for waveform in ENGINE_WAVEFORMS:
            self.assertIn(f'"{waveform}"', region, f"waveform {waveform} not mapped")

    def test_voice_index_comes_from_the_address_not_the_args(self):
        # The engine sends no index argument; the OSCdef must parse it from
        # the address, or every voice would land on index 0.
        region = self.src[self.src.index("OSCdef(\\testament_voice"):]
        self.assertIn("msg[0]", region)
        self.assertIn("split($/)", region)

    def test_loader_loads_the_responders_file(self):
        self.assertIn("16_engine_responders.scd", LOADER.read_text())

    def test_responder_file_delimiters_balance(self):
        code = _strip_sc(self.src)
        pairs = {"(": ")", "{": "}", "[": "]"}
        stack = []
        for pos, ch in enumerate(code):
            if ch in pairs:
                stack.append((ch, pos))
            elif ch in pairs.values():
                self.assertTrue(stack, f"unmatched {ch} at offset {pos}")
                opener, _ = stack.pop()
                self.assertEqual(
                    pairs[opener], ch,
                    f"mismatched {opener} closed by {ch} at offset {pos}",
                )
        self.assertEqual(stack, [], f"unclosed delimiters: {stack[-3:]}")


if __name__ == "__main__":
    unittest.main()
