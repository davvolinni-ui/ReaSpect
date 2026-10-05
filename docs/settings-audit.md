# ReaSpect settings interaction audit

Reviewed 2026-10-05: Track, Event/audio/MIDI, Channel, FX parameters, routing, headers/colors/icons, panel layout, and theme preferences. This is a code and regression-test audit; it does not establish that every setting has been manually exercised in a live user project.

## Changes

- Numeric drag speed now follows the control's units. Integer controls advance in valid whole steps; take/send pan uses 1 percentage point per pixel; take gain uses 0.05 dB; audio/MIDI rate uses 0.005; event position/length/end and source offset use 10 ms. Track offset uses 0.1 ms or 1 sample. Fade dragging remains 5 ms per pixel, with 50 ms wheel steps.
- Single-sided numeric limits are passed as valid native drag ranges. Values are clamped again after quantization, and identical numeric commits skip writes.
- Wheel bursts and ongoing gestures finish on inspected selection changes. Drag undo blocks close in their captured project, including after a project-tab change.
- Fixed-lane count changes by wheel refresh the timeline, matching the typed/drag path.
- Record Arm resets to disarmed on plain right-click; Monitor resets to Off. Shift-right-click retains REAPER recording options.
- Theme editor colors reset individually to the current light/dark preset on right-click. Accent-linked routing colors remain synchronized.

## Default/reset inventory

| Control | Right-click behavior |
| --- | --- |
| Track/event color | Remove custom color and use native default/inheritance |
| Track icon | Remove assigned icon |
| Track automation / Channel automation | Trim/Read |
| Track/event timebase | Project/track default |
| Playback offset | Zero; offset-enabled switch resets to enabled |
| Recording input | None |
| MIDI input channel | All channels |
| Record mode | Input |
| Monitoring / Channel Monitor | Off |
| Auto-arm | Off |
| Channel Record Arm | Disarmed; auto-arm has its own separate setting |
| Pan mode / law | Project default |
| Track channels | Two |
| Parent/master send | Enabled |
| Take gain / Channel fader / send/receive level | 0 dB / unity |
| Take pan / Channel pan | Center |
| Stereo width | 100% |
| Dual pan | Left control fully left; right control fully right |
| Audio/MIDI transpose / fine-tune buttons | Zero |
| Audio/MIDI rate | 1.0 |
| Preserve pitch | Enabled |
| Fade in/out | Zero manual fade; automatic crossfades retained |
| Fade shapes | Linear |
| Pitch algorithm / algorithm mode | Project default / mode zero |
| Snap offset / source offset | Zero |
| Source channel mode | Normal |
| Event Loop / Lock / Mute | Loop enabled / unlocked / unmuted |
| Channel Mute / Solo / polarity | Unmuted / unsoloed / normal polarity |
| Routing details pan / mode / Mute / Mono / polarity | Center / post-fader / unmuted / stereo / normal |
| FX parameter | Plug-in default when a finite native default is available |
| FX/Sends divider | Automatic sizing |
| Theme color | Current light/dark preset for that color role |

Numeric values retain wheel adjustment and exact typing (double-click or Ctrl-click for drag fields). Drag uses Alt for fine movement and Shift for faster movement; wheel uses Shift for fine steps and Ctrl for coarse steps. Mixed values retain direct typing and relative wheel changes. Bounds, integer quantization, take polarity, automatic crossfades, incompatible pan modes, and project/selection targeting are preserved.

## Deliberate exceptions

No universal reset is assigned to event position/length/end, active take, folder role, item placement, or fixed-lane count. These change media placement, identity, or structure. Names and Notes are not erased by right-click. Freeze/render/normalize/reverse/grouping/source-property commands remain actions. FX names/slots, routing labels, and panel toolbar buttons retain their contextual menus or established cycling behavior; their individual value controls expose resets. FX parameters without a valid plug-in default remain unchanged on right-click.

## Validation

The offline suite covers wheel/reset/enum behavior, mixed selections, numeric drag sensitivity/bounds/undo, wheel burst/context/project boundaries, light/dark theme defaults, Notes drafts, recording-input defaults, native menus, pan/fader/slot contracts, panel layout, FX parameter defaults, and frame lifecycle. The isolated REAPER verifier checks native wheel undo/redo and inspector rendering at 230 and 350 pixels across audio, MIDI, mixed, multi-take, empty, and recording contexts.
