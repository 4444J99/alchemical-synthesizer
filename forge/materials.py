"""Versioned artistic matter, shared with the browser through source-owned JSON."""
import hashlib
import json
import math
from pathlib import Path

DIRECTORY = Path(__file__).resolve().parent
LIBRARY_BYTES = (DIRECTORY / "materials.json").read_bytes()
CONTROL_BYTES = (DIRECTORY / "native-controls.json").read_bytes()
LIBRARY = json.loads(LIBRARY_BYTES)
CONTROLS = json.loads(CONTROL_BYTES)
MODEL_SHA256 = hashlib.sha256(LIBRARY_BYTES + b"\n" + CONTROL_BYTES).hexdigest()


def numeric(value, minimum, maximum, label):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not minimum <= value <= maximum:
        raise ValueError("Invalid material " + label)
    return value


def validate(state):
    if not isinstance(state, dict) or state.get("schema") != "brahma.material-state.v1" or type(state.get("modelVersion")) is not int or state["modelVersion"] != LIBRARY["version"]:
        raise ValueError("Unsupported material version")
    if not isinstance(state.get("phase"), str) or state["phase"] not in LIBRARY["phases"]:
        raise ValueError("Invalid material phase")
    amount = numeric(state.get("amount"), 0, 1, "amount")
    components = state.get("composition")
    if not isinstance(components, list) or not 1 <= len(components) <= 4:
        raise ValueError("Invalid material composition")
    composition, ids = [], set()
    for item in components:
        if not isinstance(item, dict) or not isinstance(item.get("id"), str) or item["id"] not in LIBRARY["materials"] or item["id"] in ids:
            raise ValueError("Invalid material composition")
        ids.add(item["id"])
        composition.append({"id": item["id"], "fraction": numeric(item.get("fraction"), 5e-324, 1, "fraction")})
    composition.sort(key=lambda item: item["id"])
    if abs(sum(item["fraction"] for item in composition) - 1) > 1e-6:
        raise ValueError("Material fractions must sum to one")
    return {"schema": "brahma.material-state.v1", "modelVersion": LIBRARY["version"], "phase": state["phase"], "amount": amount, "composition": composition}


def base_controls(module, values):
    if not isinstance(values, dict):
        raise ValueError("Invalid native controls")
    specs = CONTROLS.get(module, {})
    for key, value in values.items():
        if key not in specs:
            raise ValueError("Unsupported native control: " + key)
        _, minimum, maximum, step, _ = specs[key]
        numeric(value, minimum, maximum, "control range: " + key)
        if step == 1 and int(value) != value:
            raise ValueError("Native control must be an integer: " + key)
    return {key: values.get(key, spec[4]) for key, spec in specs.items()}


def resolve(module, values, state):
    if module not in LIBRARY["profiles"]:
        raise ValueError("Unsupported material mapping: " + module)
    material, params, properties = validate(state), base_controls(module, values), {}
    rounded = lambda value: math.floor(value * 1e6 + .5) / 1e6
    clamp = lambda value, low, high: max(low, min(high, value))
    for key, offset in LIBRARY["phases"][material["phase"]].items():
        mixed = sum(LIBRARY["materials"][item["id"]]["properties"][key] * item["fraction"] for item in material["composition"])
        properties[key] = rounded(clamp(mixed + offset, 0, 1))
    for control, (property_name, span) in LIBRARY["profiles"][module]["targets"].items():
        _, minimum, maximum, step, _ = CONTROLS[module][control]
        value = clamp(params[control] + (properties[property_name] - .5) * span * material["amount"], minimum, maximum)
        params[control] = math.floor(value + .5) if step == 1 else rounded(value)
    return {"material": material, "properties": properties, "params": params, "modelSha256": MODEL_SHA256}


def describe(module):
    profile = LIBRARY["profiles"].get(module)
    return {"supported": bool(profile), "claim": profile["claim"] if profile else "Material response is not mapped; original behavior acceptance remains unmeasured.",
            "targets": profile["targets"] if profile else {}, "modelSha256": MODEL_SHA256}
