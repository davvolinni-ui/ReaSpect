local api = require('ReaSpect.core.reaper_api')
local persist = require('ReaSpect.core.persistence')
local M = {}

M.panels = {
  track = persist.get_bool('panel_track', true),
  item = persist.get_bool('panel_item', true),
  channel = persist.get_bool('panel_channel', true),
}
M.channel_rack_only = persist.get_bool('channel_rack_only', false)
function M.cycle_channel(backwards)
  local mode=not M.panels.channel and 2 or (M.channel_rack_only and 1 or 0)
  mode=(mode+(backwards and -1 or 1))%3
  M.panels.channel=mode~=2
  M.channel_rack_only=mode==1
  persist.set_bool('panel_channel',M.panels.channel)
  persist.set_bool('channel_rack_only',M.channel_rack_only)
end
M.heights = {track=persist.get_num('height_track', 0.24), item=persist.get_num('height_item', 0.30), channel=persist.get_num('height_channel', 0.46)}
if persist.get_num('layout_version',0) < 2 then
  M.heights = {track=0.24,item=0.30,channel=0.46}
  persist.set('height_track',M.heights.track); persist.set('height_item',M.heights.item); persist.set('height_channel',M.heights.channel); persist.set('layout_version',2)
end
if persist.get_num('layout_version',0) < 3 then
  -- Rebalance only the old untouched defaults. Preserve splitter positions
  -- the user has already adjusted and saved.
  if math.abs(M.heights.track-0.24)<0.001
      and math.abs(M.heights.item-0.30)<0.001
      and math.abs(M.heights.channel-0.46)<0.001 then
    M.heights={track=0.33,item=0.42,channel=0.25}
    persist.set('height_track',M.heights.track)
    persist.set('height_item',M.heights.item)
    persist.set('height_channel',M.heights.channel)
  end
  persist.set('layout_version',3)
end
M.sections = {
  inserts=persist.get_bool('section_inserts', true), sends=persist.get_bool('section_sends', false), receives=persist.get_bool('section_receives', false),
  item_fades=persist.get_bool('section_item_fades', false), item_source=persist.get_bool('section_item_source', false), item_stretch=persist.get_bool('section_item_stretch', false),
  item_timing=persist.get_bool('section_item_timing', false),
  item_audio_subset=persist.get_bool('section_item_audio_subset', true), item_midi_subset=persist.get_bool('section_item_midi_subset', true),
  track_advanced=persist.get_bool('section_track_advanced', false),
  track_tools=persist.get_bool('section_track_tools', false),
  track_fx_parameters=persist.get_bool('section_track_fx_parameters', false),
  -- A nil preference lets the Recording section follow the track's context
  -- until the user chooses to expand or collapse it.
  track_recording=persist.get_bool('section_track_recording', nil),
}
M.selected_track, M.selected_tracks, M.selected_items, M.active_take = nil, {}, {}, nil
M.project_change, M.project = -1, nil

local function valid_track(t, enumerate)
  if not t then return false end
  if reaper.ValidatePtr2 and not reaper.ValidatePtr2(0,t,'MediaTrack*') then return false end
  if not enumerate then return true end
  if reaper.GetMasterTrack and reaper.GetMasterTrack(0)==t then return true end
  -- Enumerating tracks is only done when validating the latched context, not every frame.
  for i=0,(reaper.CountTracks(0) or 0)-1 do if reaper.GetTrack(0,i)==t then return true end end
  return false
end

local previous_tracks, previous_items, previous_owners = {}, {}, {}
local previous_touched
local function same(a,b)
  if #a~=#b then return false end
  for i=1,#a do if a[i]~=b[i] then return false end end
  return true
end
local function contains(list,object)
  for _,value in ipairs(list) do if value==object then return true end end
  return false
end
local function read_tracks()
  local tracks={}
  local count=reaper.CountSelectedTracks2 and reaper.CountSelectedTracks2(0,true) or reaper.CountSelectedTracks(0)
  for i=0,count-1 do
    tracks[#tracks+1]=reaper.GetSelectedTrack2 and reaper.GetSelectedTrack2(0,i,true) or reaper.GetSelectedTrack(0,i)
  end
  return tracks
end

local function refresh_selection(project)
  local switched=project~=M.project
  if switched then
    previous_tracks,previous_items,previous_owners={},{},{}
    previous_touched=nil
    M.selected_track=nil
    M.project=project
  end
  local tracks = read_tracks()
  local raw_items,owners = {},{}
  local n = reaper.CountSelectedMediaItems(0)
  for i=0,n-1 do
    local item=reaper.GetSelectedMediaItem(0,i)
    raw_items[#raw_items+1]=item
    owners[item]=reaper.GetMediaItem_Track(item)
  end
  local touched=reaper.GetLastTouchedTrack and reaper.GetLastTouchedTrack()
  local track_changed=not same(tracks,previous_tracks)
    or (touched~=previous_touched and contains(tracks,touched))
  local item_changed=not same(raw_items,previous_items)
  local new_item
  for _,item in ipairs(raw_items) do
    if not previous_owners[item] or previous_owners[item]~=owners[item] then
      new_item=new_item or item
      if owners[item]==touched then new_item=item;break end
    end
  end
  -- The newest event selection (or moving it to another track) owns focus.
  -- A track-only change wins over an old event selection on another track.
  local tr=M.selected_track
  if new_item then tr=owners[new_item]
  elseif track_changed then
    tr=contains(tracks,touched) and touched or tracks[1]
  elseif item_changed and #raw_items>0 then
    local on_track=false
    for _,item in ipairs(raw_items) do if owners[item]==tr then on_track=true;break end end
    if not on_track then tr=owners[raw_items[1]] end
  end
  if not valid_track(tr,false) then tr=tracks[1] end
  if (new_item or (item_changed and not track_changed)) and tr and not contains(tracks,tr) and reaper.SetOnlyTrackSelected then
    reaper.SetOnlyTrackSelected(tr)
    tracks=read_tracks()
    touched=reaper.GetLastTouchedTrack and reaper.GetLastTouchedTrack()
  end
  -- Keep REAPER's cross-track arrange selection intact, but never expose an
  -- event from a different track in this inspector or edit it accidentally.
  local items={}
  for _,item in ipairs(raw_items) do if owners[item]==tr then items[#items+1]=item end end
  M.other_track_items=#raw_items-#items
  previous_tracks,previous_items,previous_owners=tracks,raw_items,owners
  previous_touched=touched
  local take = #items > 0 and api.item.take(items[1]) or nil
  local changed = switched or tr~=M.selected_track or not same(tracks,M.selected_tracks)
    or not same(items,M.selected_items) or take~=M.active_take
  M.selected_track,M.selected_tracks,M.selected_items,M.active_take=tr,tracks,items,take
  return changed
end

function M.update()
  local pc = reaper.GetProjectStateChangeCount and reaper.GetProjectStateChangeCount(0) or 0
  local current_project = reaper.EnumProjects and select(1,reaper.EnumProjects(-1,'')) or M.project
  local sel_changed = refresh_selection(current_project)
  local changed = sel_changed or pc ~= M.project_change
  M.project_change = pc
  if changed then
    M.fx, M.sends, M.receives = nil, nil, nil
  end
  return changed
end

function M.get_fx() if not M.fx then M.fx=api.track_fx(M.selected_track) end return M.fx end
function M.get_sends() if not M.sends then M.sends=api.sends(M.selected_track) end return M.sends end
function M.get_receives() if not M.receives then M.receives=api.receives(M.selected_track) end return M.receives end
function M.set_panel(name, value) M.panels[name]=value; persist.set_bool('panel_'..name,value) end
function M.set_height(name, value) M.heights[name]=value; persist.set('height_'..name,value) end
function M.set_section(name, value) M.sections[name]=value; persist.set_bool('section_'..name,value) end

return M
