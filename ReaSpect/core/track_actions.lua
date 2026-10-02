-- Render and native FX windows must run only after ImGui's windows are ended.
local M = {}
local pending,resolved={},{}
-- Native IDs verified against the installed WT_GraphicalAnnex.lua and native
-- action descriptions. API reference: https://www.reaper.fm/sdk/reascript/reascripthelp.html
local actions={
  freeze_stereo={id=41223,name='Track: Freeze to stereo (render pre-fader, save/remove items and online FX)'},
  freeze_mono={id=40901,name='Track: Freeze to mono (render pre-fader, save/remove items and online FX)'},
  freeze_multi={id=40877,name='Track: Freeze to multichannel (render pre-fader, save/remove items and online FX)'},
  unfreeze={id=41644,name='Track: Unfreeze tracks (restore previously saved items and FX)'},
  input_fx={single=true,direct=true},
  icon_set={single=true,direct=true},
  -- Exact native descriptions verified in the installed executable. Resolve
  -- these from REAPER's action list rather than assume their numeric IDs.
  render_stereo={name='Track: Render tracks to stereo stem tracks (and mute originals)'},
  render_mono={name='Track: Render tracks to mono stem tracks (and mute originals)'},
  render_multi={name='Track: Render tracks to multichannel stem tracks (and mute originals)'},
  envelopes={id=40292,name='Track: View envelopes for current/last touched track',single=true,last_touched=true},
  routing={id=40293,name='Track: View I/O for selected tracks',single=true},
  last_touched={id=40914,name='Track: Set first selected track as last touched track',internal=true},
  icon_choose={name='Track: Set track icon...'},
  icon_remove={name='Track: Remove track icon'},
  grouping={name='Track: Set track grouping parameters...'},
  grouping_matrix={name='View: Show track grouping matrix window',show_only=true},
}

local names_scanned=false

local function command(name)
  if resolved[name]~=nil then return resolved[name] or nil end
  local action=actions[name]
  local section=reaper.SectionFromUniqueID and reaper.SectionFromUniqueID(0)
  if action.id and section and reaper.kbd_getTextFromCmd then
    local description=reaper.kbd_getTextFromCmd(action.id,section)
    -- Built-in IDs are stable; localized REAPER action text may differ.
    if description and description~='' then resolved[name]=action.id;return action.id end
  end
  if not names_scanned and section and reaper.kbd_enumerateActions then
    names_scanned=true
    local names={}
    for key,entry in pairs(actions) do
      if entry.name then
        names[entry.name]=key
        local localized=reaper.LocalizeString and reaper.LocalizeString(entry.name,'actions',0)
        if localized then names[localized]=key end
      end
    end
    for index=0,100000 do
      local id,description=reaper.kbd_enumerateActions(section,index)
      if not id or id==0 then break end
      local key=names[description]
      if key then
        local named=reaper.ReverseNamedCommandLookup and reaper.ReverseNamedCommandLookup(id)
        if not named or named=='' then resolved[key]=id end
      end
    end
    if resolved[name] then return resolved[name] end
  end
  resolved[name]=false
end

function M.freeze_count(track)
  local major,minor=(reaper.GetAppVersion and reaper.GetAppVersion() or ''):match('^(%d+)%.(%d+)')
  major,minor=tonumber(major) or 0,tonumber(minor) or 0
  -- I_FREEZECOUNT is a native, read-only API property from REAPER 7.43.
  if major<7 or (major==7 and minor<43) then return nil end
  return math.max(0,math.floor(reaper.GetMediaTrackInfo_Value(track,'I_FREEZECOUNT') or 0))
end

function M.available(name)
  if not actions[name] or actions[name].internal or not reaper.EnumProjects or not reaper.ValidatePtr2 then return false end
  if name=='input_fx' then return reaper.TrackFX_Show~=nil end
  if name=='icon_set' then return reaper.GetSetMediaTrackInfo_String~=nil end
  if actions[name].last_touched and (not reaper.GetLastTouchedTrack or not command('last_touched')) then return false end
  return reaper.Main_OnCommandEx~=nil and reaper.CountTracks~=nil and reaper.GetTrack~=nil
    and reaper.GetMasterTrack~=nil and reaper.IsTrackSelected~=nil and reaper.SetTrackSelected~=nil
    and command(name)~=nil
end

local function valid(project,track)
  return track and reaper.ValidatePtr2(project,track,'MediaTrack*')
    and (not reaper.GetMasterTrack or track~=reaper.GetMasterTrack(project))
end

function M.queue(name,tracks,value)
  if not M.available(name) or type(tracks)~='table' or #tracks==0 then return false end
  if actions[name].single and #tracks~=1 then return false end
  if name=='icon_set' and (type(value)~='string' or value=='' or value:find('\0',1,true)) then return false end
  local project=reaper.EnumProjects(-1,'')
  if not project then return false end
  local targets,seen={},{}
  for _,track in ipairs(tracks) do
    if not valid(project,track) then return false end
    if not seen[track] and (name~='unfreeze' or M.freeze_count(track)~=0) then
      targets[#targets+1]=track;seen[track]=true
    end
  end
  if #targets==0 then return false end
  pending[#pending+1]={project=project,targets=targets,name=name,value=value,
    command=not actions[name].direct and command(name) or nil}
  return true
end

local function project_open(project)
  for index=0,10000 do
    local found=reaper.EnumProjects(index,'')
    if not found then return false end
    if found==project then return true end
  end
  return false
end

local function each_project_track(project,fn)
  local master=reaper.GetMasterTrack(project)
  if master then fn(master) end
  for index=0,reaper.CountTracks(project)-1 do fn(reaper.GetTrack(project,index)) end
end

local function perform(request)
  local project=request.project
  if reaper.EnumProjects(-1,'')~=project then return end
  for _,track in ipairs(request.targets) do
    if not valid(project,track) then return end
  end
  if request.name=='input_fx' then
    -- The record-chain offset also opens an empty input FX chain, without
    -- relying on REAPER's unrelated current/last-touched-track action target.
    reaper.TrackFX_Show(request.targets[1],0x1000000,1)
    return
  end
  if request.name=='icon_set' then
    local track=request.targets[1]
    local _,current=reaper.GetSetMediaTrackInfo_String(track,'P_ICON','',false)
    if current==request.value then return end
    require('ReaSpect.core.undo').edit('Set track icon',function()
      local changed=reaper.GetSetMediaTrackInfo_String(track,'P_ICON',request.value,true)
      if not changed then error('Could not set the selected track icon') end
      if reaper.TrackList_AdjustWindows then reaper.TrackList_AdjustWindows(false) end
      if reaper.UpdateArrange then reaper.UpdateArrange() end
    end)
    return
  end
  local selected={}
  each_project_track(project,function(track)
    if reaper.IsTrackSelected(track) then selected[#selected+1]=track end
  end)
  local ok,err=pcall(function()
    each_project_track(project,function(track) reaper.SetTrackSelected(track,false) end)
    for _,track in ipairs(request.targets) do reaper.SetTrackSelected(track,true) end
    if actions[request.name].last_touched then
      -- Selecting a track does not establish REAPER's last-touched track.
      -- This prerequisite runs with exactly the captured track selected, and
      -- the target is verified before opening the native envelope window.
      reaper.Main_OnCommandEx(command('last_touched'),0,project)
      if reaper.GetLastTouchedTrack()~=request.targets[1] then return end
    end
    if actions[request.name].show_only and reaper.GetToggleCommandStateEx
      and reaper.GetToggleCommandStateEx(0,request.command)==1 then return end
    -- The native action owns its undo entry. No UI suppression or script undo
    -- block is held across REAPER's potentially modal render operation.
    reaper.Main_OnCommandEx(request.command,0,project)
  end)
  if project_open(project) then
    each_project_track(project,function(track) reaper.SetTrackSelected(track,false) end)
    for _,track in ipairs(selected) do
      if reaper.ValidatePtr2(project,track,'MediaTrack*') then reaper.SetTrackSelected(track,true) end
    end
    if reaper.UpdateArrange then reaper.UpdateArrange() end
  end
  if not ok then
    require('ReaSpect.core.diagnostics').event('action_error','track.'..request.name..': '..tostring(err))
    if reaper.ShowConsoleMsg then reaper.ShowConsoleMsg('ReaSpect: '..tostring(err)..'\n') end
  end
  return ok
end

function M.process()
  local requests=pending
  pending={}
  local diagnostics=require('ReaSpect.core.diagnostics')
  for _,request in ipairs(requests) do
    diagnostics.event('action_begin','track.'..request.name)
    if perform(request)~=false then diagnostics.event('action_end','track.'..request.name) end
  end
end

return M
