# ReaSpect

ReaSpect is a narrow ReaImGui inspector for REAPER. Run `ReaSpect.lua` from the Action List, then dock or resize the window beside the arrange view.

Testing release by **Davvo**. Requires REAPER 6.8+ and the ReaImGui extension.

## Install through ReaPack

1. Install ReaPack and ReaImGui if needed.
2. Choose **Extensions > ReaPack > Import repositories** and import:
   `https://raw.githubusercontent.com/davvolinni-ui/ReaSpect/main/index.xml`
3. Synchronize packages, browse for **ReaSpect - context-sensitive inspector**, and install it. If the testing version is hidden, enable pre-release versions in ReaPack or select the version explicitly.
4. Run **ReaSpect.lua** from REAPER's Action List.

ReaPack installs the entry point and all supporting modules together. Restart ReaSpect after updating. If migrating from a ZIP installation, stop the old instance and remove its Action List entry before running the ReaPack copy.

Contact and support: [ReaSpect forum thread](https://forum.cockos.com/showthread.php?t=311132).
ReaSpect is distributed under its [End User License Agreement](EULA.md). Public access to this repository does not grant an open-source license.

## Features and behavior

The implementation is split into a small API/state layer, reusable widgets, and independent Track, Item/Event, and Channel panels. Selection and project state are refreshed through REAPER's selection APIs and project state change counter; FX, sends, and receives are rebuilt only when their section is opened or the project changes.

Implemented native controls include:

- Optional Notes section in the Track panel provides multiline notes for the focused track, saved with the track in the project. Text wraps to the panel width. On older ReaImGui versions, click the wrapped notes to edit and click outside to return to the reading view; versions exposing native editor wrapping also wrap while typing. Collapse it to hide the notes without deleting text; the open/closed preference is remembered. Notes edit only the focused track during multi-selection.
- Track name/color, automation, correctly mapped timebase, playback offset in milliseconds or samples, and a compact routing summary. Recording opens contextually and includes mono/stereo/MIDI input, MIDI channel, record mode, monitoring, auto-arm, and Input FX access. Advanced holds pan mode/law, channel count, parent/master send, and folder/placement settings.
- Freeze defaults to stereo; the options menu offers mono, multichannel and unfreeze. Frozen tracks show Unfreeze and their freeze-pass count when supported. These explicit actions use REAPER's native render/restore workflow and retain the track selection.
- Optional FX parameters section displays assigned track-control parameters, with wheel adjustment, plugin-default reset when available, and show/hide envelope buttons. Add last touched exposes a parameter from the focused track; existing envelope points, arm and bypass settings are preserved.
- Track tools keeps less frequent actions together: render mono/stereo/multichannel stems (and mute originals), open track envelopes, choose/remove native track icons, and open grouping setup or the grouping matrix. Assigned track icons appear in the fixed Track header; otherwise it shows the media-type glyph.
- Click the Track header icon to open a searchable thumbnail browser of REAPER's track icon library. Choose a thumbnail for that focused track, use None to remove it, or Browse files... for a custom image. Right-click the header icon to remove it. The fallback glyph and tooltip describe the track's audio/MIDI/mixed contents; Event icons describe the active event/take or mixed selection, with a separate empty-event glyph.
- Matching Track/Event headers with media icons, event identity, active-take rename, and a color picker. The event inspector leads with paired Position/Length controls and compact Loop/Lock/Mute switches.
- Audio take gain/pan, decimal semitone transpose, one-cent fine-tuning, rate, preserve pitch, dynamically enumerated pitch algorithms, manual fades and all seven native fade shapes. Normalize opens REAPER's peak/RMS/LUFS dialog; Reverse uses its native take-reverse action. Event FX opens the active take chain, with an event chooser for multi-selection.
- Contextual active-take switching and Take / Source details: source offset, correctly mapped audio channels, source file/format/length, and native source/item properties. MIDI selections have take transpose/rate, note/CC counts, and direct access to the MIDI editor.
- Channel strip with track-colour identity, input/output buttons, mode-aware pan controls, mute/solo/arm/monitor, meter, fader, automation, polarity, routing, and a ReaperTips-style right-side insert/routing stack. Stereo pan shows width; dual pan shows independent left/right knobs; balance modes show one pan knob. Group edits skip tracks with incompatible pan controls.

Property edits use native REAPER APIs and descriptive undo blocks. Native dialogs/actions run on the following deferred callback, before any ImGui drawing, and validate the captured project/item/take context. This also covers native recording/routing menus, FX windows, rename dialogs and plugin loading. UI state is stored with REAPER ExtState (`panel_*`, `height_*`, and `section_*` keys).

The inspector draws on every REAPER defer cycle: ReaImGui requires its context to be used each cycle. Skipping callbacks to cap FPS can expire the context and cause an invalid-context error at the next theme color push.

Notes keeps a local draft while typing and saves it as one track-only undo point when editing ends, the inspected context changes, or the inspector closes. Click outside Notes before saving the project. Ordinary Track and Channel value edits avoid rebuilding the track layout; channel count, folder role and free-item positioning changes still refresh that layout.

Wheel adjustments apply immediately and share one undo point per scroll burst, published after a 250 ms pause. Switching controls, editing another property, changing projects, or closing the inspector completes the pending burst. This reduces repeated native menu redraws during scrolling.

Numeric fields support dragging left/right, with Alt for finer movement and Shift for faster movement. Double-click or Ctrl-click a field to type an exact value. A drag creates one undo point on release. Mixed-value fields retain direct typing and relative wheel adjustment.

Track, Event, and Channel share one focused track. Selecting a new event focuses its owning track; selecting a different track shows only that track's selected events, or an empty Event panel. REAPER's cross-track arrange selection is preserved, but Event edits affect only the focused track. Track multi-selection remains available for group track edits.

Multi-selection shows differing values as `—`; enter a value to set it across the inspected selection. Position moves the selection as a group and preserves its spacing. Plain wheel edits numeric controls, knobs, faders, option selectors, and switches; Shift gives finer numeric steps and Ctrl gives larger steps. Integer controls retain valid whole steps. Wheel edits preserve differences between mixed numeric values. Hovered controls consume the wheel, including at their limits; unused panel space and list labels scroll normally. Right-click resets values with meaningful defaults (gain/pan/transpose/offset/fades to zero, rate to 1, width to 100%, and so on). Position, length, active take, folder structure, and other controls without a safe generic default are not reset. The mixer input button opens source choices for mono, stereo, valid multichannel, and MIDI device/channel; right-click resets input to None. Right-click Arm or Monitor resets to disarmed or Off; Shift-right-click opens native recording options. Manual fade edits preserve automatic crossfades, and gain edits preserve take polarity.

Detailed MIDI note editing remains in REAPER's MIDI editor. Audio source channel mode is not presented as MIDI channel remapping. Fixed-lane controls require REAPER 7; freeze status requires REAPER 7.43. Native actions and pitch algorithms are offered only when the installed host exposes them. Fade curves use the native menu order (Linear, then Curves 2–7).

The default three-panel proportions are Track 33%, Item 42%, and Channel 25%; previously saved custom splitter positions are preserved. The Channel toolbar button cycles through mixer + FX/Sends, FX/Sends only, and hidden, remembering the choice across restarts. Right-click cycles backwards. FX/Sends-only mode uses the full panel width and remains available in narrow docks. The Channel panel uses the same 102-unit selected-track strip width at every height. A short panel reduces its visible state buttons to Mute and Solo; at greater height it reveals input, routing, monitoring, automation, phase, and arm without widening the strip. Its meter/fader bay stretches to the bottom footer, while FX and Sends remain alongside it for the full panel height. Track and Event identity headers stay fixed while their property bodies scroll independently.

The FX label opens the selected track's chain; right-clicking it or clicking a blank insert slot opens ReaSpect's installed-FX picker. Each insert has a bypass marker and a context menu for add/replace, serial/parallel mode, bypass, offline, rename and delete. Clicking an FX toggles its floating window; Ctrl-click opens the chain at that FX. Internal drag/reorder is supported; native FX Browser drag-and-drop is not implemented. The adjacent header light bypasses the entire chain while retaining each insert's bypass state.

Right-click the FX header and enable **Respect REAPER slot positions** to preserve the track's FX/send gaps. This preference is saved; the default remains compact. Empty FX slots accept internal drops and picker insertion. Hardware-output slots are reserved in the send display, with their controls in REAPER's routing window. Hosts without the slot APIs retain consecutive rows.

The Channel fader follows REAPER's live volume-fader minimum and maximum preferences; its existing curved travel is retained. The meter follows the track's native peak, RMS or LUFS mode and uses REAPER's measurements. Armed tracks display peaks: stereo for loudness modes, or multichannel when selected. Multichannel peaks are summarized as odd/even channel maxima in the existing two bars. Hover for the mode and units; clicking clears the relevant native holds. Meter colors remain controlled by ReaSpect's theme. FX that report gain reduction enable a separate yellow meter between the level meter and fader. It fills downward on a 0–24 dB scale and shows the strongest reported enabled FX reduction, including supported FX inside containers; unsupported or bypassed FX are excluded.

FX and routing stay in one rack with independently scrolling lists and fixed narrow scrollbar gutters. The FX header shares the rows' height and bypass-column width. The divider initially sizes the sections from their contents; drag or wheel it to adjust, or right-click to return to automatic sizing. Manual adjustments are remembered. Blank Sends rows and `+` open a destination chooser with feedback protection. Parent and already-connected destinations remain selectable to add another send; their labels describe existing routes. Sends and receives have wheel-adjustable level knobs with right-click/double-click unity reset. Shift-click a route to mute, Alt-click to remove, Ctrl-click to go to its other track, or right-click its name for level, pan, mode, mute, mono and polarity. Click the name or the details' Audio / MIDI routing button for REAPER's full routing window. Hardware outputs, detailed audio/MIDI mappings and routing envelopes remain in that native window. The palette icon opens the theme editor.


If REAPER becomes unresponsive while ReaSpect still responds, `ReaSpect-diagnostics.log` beside the main script records native-action starts/returns and errors. On Windows with JS_ReaScriptAPI, it also records changes in whether REAPER's main window is enabled. The log is capped at 64 KiB and unchanged frames do not write to it. A disabled window can indicate a native modal dialog; this is diagnostic evidence, not proof of the lockup's cause. Restart ReaSpect after updating to load the changes.

Diagnostics are off by default. To enable them for troubleshooting, run `reaper.SetExtState('ReaSpect','diagnostics_enabled','1',true)` in a ReaScript, then restart ReaSpect. Set the value to `0` and restart to disable them. Logs stay on your computer.

## Publishing updates

The package metadata lives in `ReaSpect/ReaSpect.lua`. This is a ReaPack manifest; the executable source remains at the repository root. The manifest maps the modules into the directory structure required by the executable.

Upload only the contents of the prepared `releases/reapack` folder to the `main` branch. It contains the required Lua files, EULA, README, and publishing configuration. GitHub Actions validates the package, then generates and commits `index.xml` with download URLs pinned to the source commit. The import URL becomes usable after that workflow completes. Repository Actions must have permission to write repository contents; branch protection must allow the index bot's commit.

For each update, increase `@version` and update `@changelog` in the manifest before pushing. ReaPack preserves prior versions in the index, so do not delete `index.xml` between releases. Synchronize in ReaPack to receive new versions.

ZIP archives, diagnostic logs, screenshots, and native test profiles are excluded from Git through `.gitignore`.
