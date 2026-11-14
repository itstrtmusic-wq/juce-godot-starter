# Saving and loading DSP network patches

The patch API stores **topology and base parameter settings** as a plain Godot Dictionary or UTF-8 JSON file. It does not store live audio-device configuration, delay/reverb contents, oscillator phase, envelope position, or the currently modulated effective values.

```gdscript
# Export while stopped or running; no processor state is changed.
var patch: Dictionary = network.export_patch()
var ok := network.save_patch("user://my_effect.json")
# Overwrite is opt-in: network.save_patch(path, true).

# Loading is structural: stop the device first.
audio.stop_audio()
if not network.load_patch_file("user://my_effect.json"):
    push_error(network.get_last_error())
# Or use: network.load_patch(patch).
# Prepare for offline processing, or start_audio() to prepare for the actual device.
```

Loading is transactional: every node, parameter, audio edge and modulation edge is checked in a temporary native graph before replacement. Wrong field types, unknown fields, unsupported versions/types/parameters, duplicate IDs/routes, invalid ranges, excess graph limits and mixed audio/modulation cycles reject the entire load. The original network and its prepared processor state stay intact after rejection. A successful load resets DSP state and requires preparation before offline processing.

## Schema version 1

```json
{
  "schema_version": 1,
  "nodes": [
    {"id": "filter", "type": "low_pass", "parameters": {"frequency": 2200, "q": 0.7071}},
    {"id": "slow", "type": "lfo", "parameters": {"rate_hz": 0.75}}
  ],
  "connections": [
    {"source": "input", "destination": "filter", "gain": 1},
    {"source": "filter", "destination": "output", "gain": 1}
  ],
  "modulations": [
    {"source": "slow", "destination": "filter", "parameter": "frequency", "depth": 1600, "offset": 0, "channel": 0}
  ]
}
```

- `schema_version`, `nodes` and `connections` are required. `modulations` is optional and defaults to an empty array.
- `input` and `output` exist implicitly; do not include them in `nodes`.
- Node `parameters` may be omitted or partial; missing parameters retain node defaults. Export includes all current base settings, including bypass.
- Connection `gain` defaults to 1. Modulation `depth`, `offset` and `channel` default to 1, 0 and 0.
- Parameter values must be finite numbers, not strings or booleans. Integral schema/channel values accept Godot integers and integral JSON numbers; fractional channels are rejected.
- Source-channel availability is checked when preparing for a particular mono/stereo configuration. A structurally valid stereo-channel patch may fail preparation on a mono device.
- Keep your UI layout, preset title and other application metadata outside this strict DSP schema.

`save_patch()` accepts `res://`, `user://` and filesystem paths and writes through a temporary file. Existing targets require `overwrite=true`; directories are not valid targets. File loading is capped at 1 MiB. Error details are available through `get_last_error()`. An effect-specific schema version is separate from the API release version (currently 0.3).

For a complete executable save/load/render example, see [preset_render.gd](../demo/examples/preset_render.gd).
