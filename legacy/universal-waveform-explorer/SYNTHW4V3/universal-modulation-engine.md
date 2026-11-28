```


FUNCTION: Parameter modulation engine  
BEHAVIOR: Interpolates multiple wave inputs and clamps range

:: PSEUDO-CODE STRUCTURE ::

function modulate(parameter, lfo_shape, speed, affectors):
    value = base_value
    for affector in affectors:
        wave = affector.influence(lfo_shape, speed)
        value += wave
    value = clamp(value, -1.0, +1.0)
    return value

:: SAMPLE CALL ::

modulate(
  parameter = "emotion <> logic",
  lfo_shape = "sine",
  speed = 0.2Hz,
  affectors = [Jessica, Sunset, RNG_d8]
)
```