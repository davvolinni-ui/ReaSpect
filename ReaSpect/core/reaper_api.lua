local M = {}

function M.record_inputs()
  local labels,values={'None'},{-1}
  local count=reaper.GetNumAudioInputs and reaper.GetNumAudioInputs() or 0
  local function name(i) return reaper.GetInputChannelName(i) or ('Input '..(i+1)) end
  for i=0,count-1 do labels[#labels+1],values[#values+1]='Mono: '..name(i),i end
  for i=0,count-2 do labels[#labels+1],values[#values+1]='Stereo: '..name(i)..' / '..name(i+1),1024|i end
  labels[#labels+1],values[#values+1]='MIDI: All inputs',4096|(63<<5)
  labels[#labels+1],values[#values+1]='MIDI: Virtual keyboard',4096|(62<<5)
  for i=0,math.min(62,reaper.GetNumMIDIInputs and reaper.GetNumMIDIInputs() or 0)-1 do
    local ok,n=reaper.GetMIDIInputName(i,'')
    if ok then labels[#labels+1],values[#values+1]='MIDI: '..n,4096|(i<<5) end
  end
  return labels,values
end

local function getv(obj, parm, default)
  local v = reaper.GetMediaTrackInfo_Value(obj, parm)
  return v ~= nil and v or default
end
local function setv(obj, parm, value)
  return reaper.SetMediaTrackInfo_Value(obj, parm, value)
end
local function itemv(obj, parm, default)
  local v = reaper.GetMediaItemInfo_Value(obj, parm)
  return v ~= nil and v or default
end

M.track = {
  name = function(t) local _, s = reaper.GetSetMediaTrackInfo_String(t, 'P_NAME', '', false); return s or '' end,
  set_name = function(t, s) return reaper.GetSetMediaTrackInfo_String(t, 'P_NAME', s, true) end,
  color = function(t) return reaper.GetTrackColor(t) end,
  set_color = function(t, c) return setv(t, 'I_CUSTOMCOLOR', c) end,
  timebase = function(t) return getv(t, 'C_BEATATTACHMODE', 0) end,
  set_timebase = function(t, v) return setv(t, 'C_BEATATTACHMODE', v) end,
  automation = function(t) return getv(t, 'I_AUTOMODE', 0) end,
  set_automation = function(t, v) return setv(t, 'I_AUTOMODE', v) end,
  folder_depth = function(t) return getv(t, 'I_FOLDERDEPTH', 0) end,
  set_folder_depth = function(t, v) return setv(t, 'I_FOLDERDEPTH', v) end,
  channels = function(t) return getv(t, 'I_NCHAN', 2) end,
  set_channels = function(t, v) return setv(t, 'I_NCHAN', v) end,
  arm = function(t) return getv(t, 'I_RECARM', 0) > 0 end,
  set_arm = function(t, v) return setv(t, 'I_RECARM', v and 1 or 0) end,
  auto_arm = function(t) return getv(t, 'B_AUTO_RECARM', 0) > 0 end,
  set_auto_arm = function(t, v) return setv(t, 'B_AUTO_RECARM', v and 1 or 0) end,
  input = function(t) return getv(t, 'I_RECINPUT', -1) end,
  set_input = function(t, v) return setv(t, 'I_RECINPUT', v) end,
  recmode = function(t) return getv(t, 'I_RECMODE', 0) end,
  set_recmode = function(t, v) return setv(t, 'I_RECMODE', v) end,
  monitor = function(t) return getv(t, 'I_RECMON', 0) end,
  set_monitor = function(t, v) return setv(t, 'I_RECMON', v) end,
  mainsend = function(t) return getv(t, 'B_MAINSEND', 1) > 0 end,
  set_mainsend = function(t, v) return setv(t, 'B_MAINSEND', v and 1 or 0) end,
  mute = function(t) return getv(t, 'B_MUTE', 0) > 0 end,
  set_mute = function(t, v) return setv(t, 'B_MUTE', v and 1 or 0) end,
  solo = function(t) return getv(t, 'I_SOLO', 0) > 0 end,
  set_solo = function(t, v) return setv(t, 'I_SOLO', v and 1 or 0) end,
  volume = function(t) return getv(t, 'D_VOL', 1) end,
  set_volume = function(t, v) return setv(t, 'D_VOL', v) end,
  pan = function(t) return getv(t, 'D_PAN', 0) end,
  set_pan = function(t, v) return setv(t, 'D_PAN', v) end,
  width = function(t) return getv(t, 'D_WIDTH', 1) end,
  set_width = function(t, v) return setv(t, 'D_WIDTH', v) end,
  dualpan_l = function(t) return getv(t, 'D_DUALPANL', -1) end,
  set_dualpan_l = function(t, v) return setv(t, 'D_DUALPANL', v) end,
  dualpan_r = function(t) return getv(t, 'D_DUALPANR', 1) end,
  set_dualpan_r = function(t, v) return setv(t, 'D_DUALPANR', v) end,
  panmode = function(t) return getv(t, 'I_PANMODE', 0) end,
  set_panmode = function(t, v) return setv(t, 'I_PANMODE', v) end,
  phase = function(t) return getv(t, 'B_PHASE', 0) > 0 end,
  set_phase = function(t, v) return setv(t, 'B_PHASE', v and 1 or 0) end,
  free_mode = function(t) return getv(t, 'I_FREEMODE', 0) end,
  set_free_mode = function(t, v) return setv(t, 'I_FREEMODE', v) end,
  peak = function(t)
    if reaper.Track_GetPeakInfo then
      local l = reaper.Track_GetPeakInfo(t, 0) or 0
      local r = reaper.Track_GetPeakInfo(t, 1) or 0
      return l, r
    end
    return 0, 0
  end,
}

M.item = {
  position = function(i) return itemv(i, 'D_POSITION', 0) end,
  set_position = function(i, v) return reaper.SetMediaItemInfo_Value(i, 'D_POSITION', v) end,
  length = function(i) return itemv(i, 'D_LENGTH', 0) end,
  set_length = function(i, v) return reaper.SetMediaItemInfo_Value(i, 'D_LENGTH', v) end,
  snap = function(i) return itemv(i, 'D_SNAPOFFSET', 0) end,
  set_snap = function(i, v) return reaper.SetMediaItemInfo_Value(i, 'D_SNAPOFFSET', v) end,
  mute = function(i) return itemv(i, 'B_MUTE', 0) > 0 end,
  set_mute = function(i, v) return reaper.SetMediaItemInfo_Value(i, 'B_MUTE', v and 1 or 0) end,
  lock = function(i) return (math.floor(itemv(i, 'C_LOCK', 0)) & 1) ~= 0 end,
  set_lock = function(i, v) return reaper.SetMediaItemInfo_Value(i, 'C_LOCK', (math.floor(itemv(i, 'C_LOCK', 0)) & ~1) | (v and 1 or 0)) end,
  loop = function(i) return itemv(i, 'B_LOOPSRC', 0) > 0 end,
  set_loop = function(i, v) return reaper.SetMediaItemInfo_Value(i, 'B_LOOPSRC', v and 1 or 0) end,
  timebase = function(i) return itemv(i, 'C_BEATATTACHMODE', -1) end,
  set_timebase = function(i, v) return reaper.SetMediaItemInfo_Value(i, 'C_BEATATTACHMODE', v) end,
  take = function(i) return reaper.GetActiveTake(i) end,
  fade_in = function(i) return itemv(i, 'D_FADEINLEN', 0) end,
  set_fade_in = function(i, v) return reaper.SetMediaItemInfo_Value(i, 'D_FADEINLEN', v) end,
  fade_out = function(i) return itemv(i, 'D_FADEOUTLEN', 0) end,
  set_fade_out = function(i, v) return reaper.SetMediaItemInfo_Value(i, 'D_FADEOUTLEN', v) end,
  fade_in_shape = function(i) return itemv(i, 'C_FADEINSHAPE', 0) end,
  set_fade_in_shape = function(i, v) return reaper.SetMediaItemInfo_Value(i, 'C_FADEINSHAPE', v) end,
  fade_out_shape = function(i) return itemv(i, 'C_FADEOUTSHAPE', 0) end,
  set_fade_out_shape = function(i, v) return reaper.SetMediaItemInfo_Value(i, 'C_FADEOUTSHAPE', v) end,
}

M.take = {
  name = function(t) local _, s = reaper.GetSetMediaItemTakeInfo_String(t, 'P_NAME', '', false); return s or '' end,
  set_name = function(t, s) return reaper.GetSetMediaItemTakeInfo_String(t, 'P_NAME', s, true) end,
  start = function(t) return reaper.GetMediaItemTakeInfo_Value(t, 'D_STARTOFFS') or 0 end,
  set_start = function(t, v) return reaper.SetMediaItemTakeInfo_Value(t, 'D_STARTOFFS', v) end,
  rate = function(t) return reaper.GetMediaItemTakeInfo_Value(t, 'D_PLAYRATE') or 1 end,
  set_rate = function(t, v) return reaper.SetMediaItemTakeInfo_Value(t, 'D_PLAYRATE', v) end,
  pitch = function(t) return reaper.GetMediaItemTakeInfo_Value(t, 'D_PITCH') or 0 end,
  set_pitch = function(t, v) return reaper.SetMediaItemTakeInfo_Value(t, 'D_PITCH', v) end,
  preserve_pitch = function(t) return (reaper.GetMediaItemTakeInfo_Value(t, 'B_PPITCH') or 0) > 0 end,
  set_preserve_pitch = function(t, v) return reaper.SetMediaItemTakeInfo_Value(t, 'B_PPITCH', v and 1 or 0) end,
  volume = function(t) return reaper.GetMediaItemTakeInfo_Value(t, 'D_VOL') or 1 end,
  set_volume = function(t, v) return reaper.SetMediaItemTakeInfo_Value(t, 'D_VOL', v) end,
  pan = function(t) return reaper.GetMediaItemTakeInfo_Value(t, 'D_PAN') or 0 end,
  set_pan = function(t, v) return reaper.SetMediaItemTakeInfo_Value(t, 'D_PAN', v) end,
  chanmode = function(t) return reaper.GetMediaItemTakeInfo_Value(t, 'I_CHANMODE') or 0 end,
  set_chanmode = function(t, v) return reaper.SetMediaItemTakeInfo_Value(t, 'I_CHANMODE', v) end,
  is_midi = function(t) return reaper.TakeIsMIDI and reaper.TakeIsMIDI(t) or false end,
  source_type = function(t) local s = reaper.GetMediaItemTake_Source(t); return s and reaper.GetMediaSourceType(s, '') or '' end,
}

function M.track_fx(t)
  local out = {}
  if not t or not reaper.TrackFX_GetCount then return out end
  for i = 0, reaper.TrackFX_GetCount(t)-1 do
    local _, name = reaper.TrackFX_GetFXName(t, i, '')
    out[#out+1] = {index=i, name=name or ('FX '..(i+1)), enabled=reaper.TrackFX_GetEnabled(t,i), offline=reaper.TrackFX_GetOffline and reaper.TrackFX_GetOffline(t,i) or false}
  end
  return out
end

function M.fx_chain_enabled(t)
  if not t then return false end
  if reaper.GetMediaTrackInfo_Value then
    local master = reaper.GetMediaTrackInfo_Value(t, 'I_FXEN')
    if master ~= nil then return master > 0 end
  end
  if not reaper.TrackFX_GetCount then return false end
  local n = reaper.TrackFX_GetCount(t)
  if n <= 0 then return true end
  for i = 0, n - 1 do if reaper.TrackFX_GetEnabled(t, i) then return true end end
  return false
end

function M.set_fx_chain_enabled(t, enabled)
  if not t then return end
  if reaper.SetMediaTrackInfo_Value and reaper.GetMediaTrackInfo_Value then
    local master = reaper.GetMediaTrackInfo_Value(t, 'I_FXEN')
    if master ~= nil then reaper.SetMediaTrackInfo_Value(t, 'I_FXEN', enabled and 1 or 0); return end
  end
  if reaper.TrackFX_GetCount and reaper.TrackFX_SetEnabled then
    for i = 0, reaper.TrackFX_GetCount(t) - 1 do reaper.TrackFX_SetEnabled(t, i, enabled) end
  end
end

local function native_action_target(track,last_touched)
  -- Actions without an explicit track argument must not follow a new selection
  -- or last-touched track while waiting for the next defer tick.
  if not reaper.CountSelectedTracks2 or not reaper.GetSelectedTrack2
      or reaper.CountSelectedTracks2(0,true)~=1 or reaper.GetSelectedTrack2(0,0,true)~=track then return false end
  return not last_touched or (reaper.GetLastTouchedTrack and reaper.GetLastTouchedTrack()==track)
end

function M.show_fx_chain(t)
  if not t then return false end
  return require('ReaSpect.core.native_ui').queue('fx_chain',t,function(track)
    if reaper.TrackFX_Show and reaper.TrackFX_GetCount and reaper.TrackFX_GetCount(track)>0 then
      reaper.TrackFX_Show(track,0,1)
    elseif reaper.Main_OnCommand then
      if not native_action_target(track,true) then return false,'target_changed' end
      -- Native REAPER action: Track: View FX chain for current/last touched track.
      reaper.Main_OnCommand(40291,0)
    end
  end)
end

function M.show_fx_browser(t)
  if not t or not reaper.Main_OnCommand then return end
  return require('ReaSpect.core.native_ui').queue('fx_browser',t,function()
    -- Avoid toggling an already-open browser closed. JS_ReaScriptAPI can focus
    -- its window when available; otherwise leave the existing browser open.
    if reaper.GetToggleCommandState and reaper.GetToggleCommandState(40271)==1 then
      if reaper.JS_Window_Find and reaper.JS_Window_SetForeground then
        local window=reaper.JS_Window_Find('FX Browser',true)
        if window then reaper.JS_Window_SetForeground(window) end
      end
      return
    end
    reaper.Main_OnCommand(40271,0)
  end)
end

function M.show_native_track_menu(name,t)
  if not t or not reaper.ShowPopupMenu then return false end
  local x,y=0,0
  if reaper.GetMousePosition then x,y=reaper.GetMousePosition() end
  return require('ReaSpect.core.native_ui').queue('track_menu_'..tostring(name),t,function(track)
    reaper.ShowPopupMenu(name,x or 0,y or 0,nil,track)
  end)
end

function M.show_routing(t)
  if not t or not reaper.Main_OnCommand then return end
  if not reaper.GetMasterTrack or t~=reaper.GetMasterTrack(0) then
    return require('ReaSpect.core.track_actions').queue('routing',{t})
  end
  -- Native REAPER action: Track: View I/O for selected tracks.
  return require('ReaSpect.core.native_ui').queue('master_routing',t,function(track)
    if not native_action_target(track,false) then return false,'target_changed' end
    reaper.Main_OnCommand(40293,0)
  end)
end

function M.show_automation(t)
  if not t or not reaper.Main_OnCommand then return end
  if not reaper.GetMasterTrack or t~=reaper.GetMasterTrack(0) then
    return require('ReaSpect.core.track_actions').queue('envelopes',{t})
  end
  -- Native action: Track: View envelopes for current/last touched track.
  return require('ReaSpect.core.native_ui').queue('master_automation',t,function(track)
    if not native_action_target(track,true) then return false,'target_changed' end
    reaper.Main_OnCommand(40292,0)
  end)
end

function M.sends(t)
  local out = {}
  if not t or not reaper.GetTrackNumSends then return out end
  for i = 0, reaper.GetTrackNumSends(t, 0)-1 do
    local d = reaper.GetTrackSendInfo_Value(t, 0, i, 'P_DESTTRACK')
    out[#out+1] = {index=i, category=0, dest=d, volume=reaper.GetTrackSendInfo_Value(t,0,i,'D_VOL') or 1, pan=reaper.GetTrackSendInfo_Value(t,0,i,'D_PAN') or 0, mute=(reaper.GetTrackSendInfo_Value(t,0,i,'B_MUTE') or 0)>0, phase=(reaper.GetTrackSendInfo_Value(t,0,i,'B_PHASE') or 0)>0}
  end
  return out
end

local send_cycle_cache
function M.send_cycle_targets(source,force_refresh)
  local blocked={}
  if not source or not reaper.GetTrackNumSends or not reaper.GetTrackSendInfo_Value then return blocked end
  local project=reaper.EnumProjects and select(1,reaper.EnumProjects(-1,'')) or nil
  local change=reaper.GetProjectStateChangeCount and reaper.GetProjectStateChangeCount(0) or nil
  if not force_refresh and send_cycle_cache and send_cycle_cache.source==source
      and send_cycle_cache.project==project and send_cycle_cache.change==change then
    return send_cycle_cache.blocked
  end

  -- Build reverse routing edges once. A destination is unsafe when it can
  -- already reach the source; adding source -> destination would close a loop.
  local incoming={}
  local function add_edge(from,to)
    if not from or not to or from==to then return end
    local rows=incoming[to]
    if not rows then rows={};incoming[to]=rows end
    rows[#rows+1]=from
  end
  local count=reaper.CountTracks and (reaper.CountTracks(0) or 0) or 0
  local master=reaper.GetMasterTrack and reaper.GetMasterTrack(0) or nil
  for i=0,count-1 do
    local track=reaper.GetTrack(0,i)
    if track then
      for send=0,reaper.GetTrackNumSends(track,0)-1 do
        add_edge(track,reaper.GetTrackSendInfo_Value(track,0,send,'P_DESTTRACK'))
      end
      if (reaper.GetMediaTrackInfo_Value(track,'B_MAINSEND') or 0)>0 then
        local parent=reaper.GetParentTrack and reaper.GetParentTrack(track) or nil
        add_edge(track,parent or master)
      end
    end
  end
  if master then
    for send=0,reaper.GetTrackNumSends(master,0)-1 do
      add_edge(master,reaper.GetTrackSendInfo_Value(master,0,send,'P_DESTTRACK'))
    end
  end

  local seen,stack={[source]=true},{source}
  while #stack>0 do
    local node=table.remove(stack)
    for _,upstream in ipairs(incoming[node] or {}) do
      if not seen[upstream] then seen[upstream]=true;stack[#stack+1]=upstream end
    end
  end
  blocked=seen
  send_cycle_cache={source=source,project=project,change=change,blocked=blocked}
  return blocked
end

function M.create_send(source, destination)
  if source and destination and source ~= destination and reaper.CreateTrackSend then
    -- Rebuild on commit rather than trusting the menu's cached preview: a
    -- newly introduced feedback route can overwhelm REAPER's audio/UI thread.
    if M.send_cycle_targets(source,true)[destination] then return -2 end
    return reaper.CreateTrackSend(source, destination)
  end
  return -1
end

function M.set_send_volume(track, index, value)
  return reaper.SetTrackSendInfo_Value(track, 0, index, 'D_VOL', value)
end

function M.set_send_pan(track, index, value)
  return reaper.SetTrackSendInfo_Value(track, 0, index, 'D_PAN', value)
end

function M.set_send_mute(track, index, value)
  return reaper.SetTrackSendInfo_Value(track, 0, index, 'B_MUTE', value and 1 or 0)
end

function M.receives(t)
  local out = {}
  if not t or not reaper.GetTrackNumSends then return out end
  for i = 0, reaper.GetTrackNumSends(t, -1)-1 do
    local src = reaper.GetTrackSendInfo_Value(t, -1, i, 'P_SRCTRACK')
    out[#out+1] = {index=i, category=-1, src=src, volume=reaper.GetTrackSendInfo_Value(t,-1,i,'D_VOL') or 1, pan=reaper.GetTrackSendInfo_Value(t,-1,i,'D_PAN') or 0, mute=(reaper.GetTrackSendInfo_Value(t,-1,i,'B_MUTE') or 0)>0}
  end
  return out
end

-- Keep the compact I/O indicator tied to REAPER's routing graph.  A parent
-- send is distinct from an explicit track or hardware send, and receives are
-- a third independent state.
function M.routing_state(t)
  local count = reaper.GetTrackNumSends
  local get = reaper.GetTrackSendInfo_Value
  local function active(category)
    local n = count and count(t, category) or 0
    if not get then return n end
    local enabled = 0
    for i = 0, n - 1 do
      if (get(t, category, i, 'B_MUTE') or 0) <= 0 then
        enabled = enabled + 1
      end
    end
    return enabled
  end
  return {
    parent = M.track.mainsend(t),
    sends = active(0),
    hardware = active(1),
    receives = active(-1),
  }
end

return M
