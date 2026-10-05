local prop = require('ReaSpect.widgets.property')
local undo = require('ReaSpect.core.undo')
local M = {}
local key = 'P_EXT:ReaSpect_notes'
local editing_track
local focus_editor=false
local draft
local function project() return reaper.EnumProjects and reaper.EnumProjects(-1,'') or 0 end

function M.flush()
  local pending=draft
  draft=nil
  if not pending or pending.value==pending.original then return end
  if reaper.ValidatePtr2 and not reaper.ValidatePtr2(pending.project,pending.track,'MediaTrack*') then return end
  undo.flush_wheel()
  -- Commit once, outside a typing gesture. Use the captured project even if
  -- the user has switched tabs, and restrict the undo snapshot to tracks.
  reaper.Undo_BeginBlock2(pending.project)
  local ok,err=pcall(function()
    reaper.GetSetMediaTrackInfo_String(pending.track,key,pending.value,true)
    if reaper.MarkProjectDirty then reaper.MarkProjectDirty(pending.project) end
  end)
  reaper.Undo_EndBlock2(pending.project,'Edit track notes',1)
  if not ok and reaper.ShowConsoleMsg then reaper.ShowConsoleMsg('ReaSpect: '..tostring(err)..'\n') end
end

function M.process(state)
  if draft and (draft.track~=state.selected_track or draft.project~=project()
      or (state.panels and not state.panels.track) or not state.sections.track_notes) then M.flush() end
end

function M.draw(ctx,state)
  M.process(state)
  local track=state.selected_track
  if not track or not prop.section(ctx,state,'track_notes','Notes',false) then M.flush();return end
  if reaper.ValidatePtr2 and not reaper.ValidatePtr2(0,track,'MediaTrack*') then return end
  -- An unset extension key returns false: a new track still needs an editor.
  local _,text=reaper.GetSetMediaTrackInfo_String(track,key,'',false)
  text=text or ''
  if draft then text=draft.value end
  if #(state.selected_tracks or {})>1 then
    reaper.ImGui_TextDisabled(ctx,'Notes apply to the focused track only')
  end
  local height=math.max(80,reaper.ImGui_GetTextLineHeight(ctx)*6)
  local id='##track_notes_'..tostring(track)
  local wrap_flag=reaper.ImGui_InputTextFlags_WordWrap and reaper.ImGui_InputTextFlags_WordWrap()
  if not wrap_flag then
    if editing_track~=track then editing_track=nil;focus_editor=false end
    if not editing_track then
      -- Older ReaImGui versions support wrapping for display text only.
      -- Never insert artificial line breaks into the saved notes.
      local visible=reaper.ImGui_BeginChild(ctx,id..'_wrapped',0,height,0)
      if visible then
        reaper.ImGui_PushTextWrapPos(ctx,0)
        if text=='' then reaper.ImGui_TextDisabled(ctx,'Click to add notes…')
        else reaper.ImGui_Text(ctx,text) end
        reaper.ImGui_PopTextWrapPos(ctx)
        if reaper.ImGui_IsWindowHovered(ctx) then
          reaper.ImGui_SetTooltip(ctx,'Click to edit notes')
          if reaper.ImGui_IsMouseClicked(ctx,0) then editing_track=track;focus_editor=true end
        end
        reaper.ImGui_EndChild(ctx)
      end
      return
    end
  end
  if focus_editor then reaper.ImGui_SetKeyboardFocusHere(ctx);focus_editor=false end
  local changed,value=reaper.ImGui_InputTextMultiline(ctx,id,text,-1,height,wrap_flag or 0)
  local deactivated=reaper.ImGui_IsItemDeactivated(ctx)
  prop.tooltip(ctx,'Notes are saved with this track in the project. Collapse Notes to hide them.')
  if changed and value~=text then
    draft=draft or {track=track,project=project(),original=text}
    draft.value=value
  end
  if deactivated then M.flush();editing_track=nil end
end

return M
