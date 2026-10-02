local prop=require('ReaSpect.widgets.property')
local controls=require('ReaSpect.widgets.controls')
local actions=require('ReaSpect.core.track_actions')
local M={}
local images,owners={},{}
local group_cache={}

local function targets(state)
  local tracks={}
  local master=reaper.GetMasterTrack and reaper.GetMasterTrack(0)
  for _,track in ipairs(state.selected_tracks or {}) do
    if track~=master then tracks[#tracks+1]=track end
  end
  if #tracks==0 and state.selected_track and state.selected_track~=master then tracks[1]=state.selected_track end
  return tracks
end

local function icon_path(track)
  if not reaper.GetSetMediaTrackInfo_String then return '' end
  local ok,path=reaper.GetSetMediaTrackInfo_String(track,'P_ICON','',false)
  return ok and path or ''
end

local function basename(path) return path:match('[^/\\]+$') or path end

local function fit(ctx,text,width)
  if not reaper.ImGui_CalcTextSize or reaper.ImGui_CalcTextSize(ctx,text)<=width then return text end
  while #text>0 and reaper.ImGui_CalcTextSize(ctx,text..'…')>width do
    local last=utf8.offset(text,-1)
    text=text:sub(1,(last or #text)-1)
  end
  return text..'…'
end

-- Returns false without advancing the cursor when an icon is absent, missing,
-- unsupported, or cannot be decoded; callers can draw their normal fallback.
function M.draw_icon(ctx,track,width,height)
  if not (reaper.ImGui_CreateImage and reaper.ImGui_ValidatePtr and reaper.ImGui_ImageFlags_NoErrors
    and reaper.ImGui_Image_GetSize and reaper.ImGui_DrawList_AddImage) then return false end
  local path=icon_path(track)
  if path=='' then return false end
  if not path:match('^%a:[/\\]') and not path:match('^[/\\]') then
    if not reaper.GetResourcePath then return false end
    path=reaper.GetResourcePath()..'/Data/track_icons/'..path
  end
  local entry=images[path]
  if not entry then entry={};images[path]=entry end
  if not entry.image or not reaper.ImGui_ValidatePtr(entry.image,'ImGui_Image*') then
    local now=reaper.time_precise and reaper.time_precise() or os.clock()
    if entry.retry_after and now<entry.retry_after then return false end
    if entry.image then owners[entry.image]=nil end
    -- NoErrors is essential: native ReaImGui errors cannot reliably be caught
    -- with pcall, and a missing/corrupt user icon must never abort the frame.
    entry.image=reaper.ImGui_CreateImage(path,reaper.ImGui_ImageFlags_NoErrors())
    if not entry.image then entry.retry_after=now+2;return false end
    entry.retry_after=nil
    if owners[entry.image] and owners[entry.image]~=entry then owners[entry.image].image=nil end
    owners[entry.image]=entry
  end
  local iw,ih=reaper.ImGui_Image_GetSize(entry.image)
  if iw<=0 or ih<=0 then return false end
  local scale=math.min(width/iw,height/ih)
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  reaper.ImGui_Dummy(ctx,width,height)
  local left,top=x+(width-iw*scale)/2,y+(height-ih*scale)/2
  reaper.ImGui_DrawList_AddImage(reaper.ImGui_GetWindowDrawList(ctx),entry.image,left,top,left+iw*scale,top+ih*scale)
  prop.tooltip(ctx,'Track icon: '..basename(path))
  return true
end

-- Custom identity belongs to the track. Its media contents remain available
-- in the tooltip; the Event header independently describes the active take.
function M.header_icon(ctx,track,width,height,kind,draw_fallback)
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  if not M.draw_icon(ctx,track,width,height) then draw_fallback() end
  reaper.ImGui_SetCursorScreenPos(ctx,x,y)
  local master=reaper.GetMasterTrack and reaper.GetMasterTrack(0)
  local ready=track~=master and actions.available('icon_set')
  if not ready then reaper.ImGui_BeginDisabled(ctx) end
  local clicked=reaper.ImGui_InvisibleButton(ctx,'##track_icon_'..tostring(track),width,height)
  controls.wheel_delta(ctx)
  local path=icon_path(track)
  if ready and path~='' and controls.right_click(ctx) then actions.queue('icon_remove',{track}) end
  if not ready then reaper.ImGui_EndDisabled(ctx) end
  local types={audio='Audio items',midi='MIDI items',mixed='Audio and MIDI items',empty='No media items'}
  local tip=path~='' and ('Track icon: '..basename(path)) or 'Track icon'
  tip=tip..'\n'..(types[kind] or 'Track contents')
  if ready then
    tip=tip..'\nClick: browse icons'
    if path~='' then tip=tip..'  •  Right-click: remove icon' end
  end
  prop.tooltip(ctx,tip)
  return ready and clicked
end

local roles={
  'MEDIA_EDIT_LEAD','MEDIA_EDIT_FOLLOW','VOLUME_LEAD','VOLUME_FOLLOW','VOLUME_VCA_LEAD','VOLUME_VCA_FOLLOW',
  'PAN_LEAD','PAN_FOLLOW','WIDTH_LEAD','WIDTH_FOLLOW','MUTE_LEAD','MUTE_FOLLOW','SOLO_LEAD','SOLO_FOLLOW',
  'RECARM_LEAD','RECARM_FOLLOW','POLARITY_LEAD','POLARITY_FOLLOW','AUTOMODE_LEAD','AUTOMODE_FOLLOW',
}

function M.group_memberships(tracks)
  if not reaper.GetSetTrackGroupMembership then return nil end
  local low,high,mixed=0,0,false
  local first_low,first_high
  for _,track in ipairs(tracks) do
    local tl,th=0,0
    for _,role in ipairs(roles) do
      -- Zero masks query membership without changing any grouping properties.
      tl=tl|(reaper.GetSetTrackGroupMembership(track,role,0,0) or 0)
      if reaper.GetSetTrackGroupMembershipHigh then
        th=th|(reaper.GetSetTrackGroupMembershipHigh(track,role,0,0) or 0)
      end
    end
    if first_low==nil then first_low,first_high=tl,th
    elseif first_low~=tl or first_high~=th then mixed=true end
    low,high=low|tl,high|th
  end
  local groups={}
  for bit=0,31 do if (low&(1<<bit))~=0 then groups[#groups+1]=bit+1 end end
  for bit=0,31 do if (high&(1<<bit))~=0 then groups[#groups+1]=bit+33 end end
  return groups,mixed
end

local function group_summary(tracks)
  local project=reaper.EnumProjects and reaper.EnumProjects(-1,'') or 0
  local change=reaper.GetProjectStateChangeCount and reaper.GetProjectStateChangeCount(project)
  local key={tostring(project)}
  for _,track in ipairs(tracks) do key[#key+1]=tostring(track) end
  key=table.concat(key,'|')
  local now=reaper.time_precise and reaper.time_precise() or os.clock()
  if group_cache.key~=key or group_cache.change~=change or now-(group_cache.at or 0)>0.5 then
    local groups,mixed=M.group_memberships(tracks)
    group_cache={key=key,change=change,at=now,groups=groups,mixed=mixed}
  end
  return group_cache.groups,group_cache.mixed
end

local function button(ctx,label,name,tracks,width,tip,enabled)
  local ready=actions.available(name) and enabled~=false
  if not ready then reaper.ImGui_BeginDisabled(ctx) end
  local clicked=reaper.ImGui_Button(ctx,label,width or -1,0)
  controls.wheel_delta(ctx)
  prop.tooltip(ctx,tip)
  if not ready then reaper.ImGui_EndDisabled(ctx) end
  if ready and clicked then actions.queue(name,tracks) end
  return ready
end

local function render_controls(ctx,tracks)
  prop.row(ctx,'Render stems',function()
    local width=reaper.ImGui_GetContentRegionAvail(ctx)
    local tip='Render selected tracks to new stereo stem tracks and mute the originals. Uses REAPER\'s native stem render settings. Right-click for mono and multichannel.'
    local ready=button(ctx,'Stereo##renderstereo','render_stereo',tracks,math.max(1,width-27),tip)
    if ready and controls.right_click(ctx) then reaper.ImGui_OpenPopup(ctx,'##renderstems') end
    reaper.ImGui_SameLine(ctx,0,4)
    if reaper.ImGui_Button(ctx,'...##renderoptions',23,0) then reaper.ImGui_OpenPopup(ctx,'##renderstems') end
    controls.wheel_delta(ctx)
    prop.tooltip(ctx,'Stem render options')
    if reaper.ImGui_BeginPopup(ctx,'##renderstems') then
      for _,option in ipairs({{'Stereo','render_stereo'},{'Mono','render_mono'},{'Multichannel','render_multi'}}) do
        if reaper.ImGui_MenuItem(ctx,option[1]..' stems (mute originals)',nil,false,actions.available(option[2])) then
          actions.queue(option[2],tracks)
        end
      end
      reaper.ImGui_EndPopup(ctx)
    end
  end)
  reaper.ImGui_TextDisabled(ctx,'Creates stems and mutes originals.')
end

local function icon_controls(ctx,tracks)
  local assigned,first,mixed=0,nil,false
  for _,track in ipairs(tracks) do
    local path=icon_path(track)
    if path~='' then assigned=assigned+1 end
    if first==nil then first=path elseif first~=path then mixed=true end
  end
  prop.row(ctx,'Track icon',function()
    local width=reaper.ImGui_GetContentRegionAvail(ctx)
    button(ctx,(assigned>0 and 'Change...' or 'Choose...')..'##trackicon','icon_choose',tracks,math.max(1,(width-4)*0.55),
      'Choose an icon for selected tracks using REAPER\'s icon browser. Right-click to remove assigned icons.')
    if assigned>0 and controls.right_click(ctx) and actions.available('icon_remove') then actions.queue('icon_remove',tracks) end
    reaper.ImGui_SameLine(ctx,0,4)
    button(ctx,'Remove##trackicon','icon_remove',tracks,math.max(1,(width-4)*0.45),'Remove icons from selected tracks.',assigned>0)
  end)
  if assigned>0 then
    prop.row(ctx,'Assigned',function()
      local label=mixed and (assigned..' of '..#tracks..' tracks') or basename(first or '')
      reaper.ImGui_TextDisabled(ctx,fit(ctx,label,reaper.ImGui_GetContentRegionAvail(ctx)))
      prop.tooltip(ctx,mixed and 'Selected tracks use different icons.' or (first or ''))
    end)
  end
end

function M.draw(ctx,state)
  local track=state.selected_track
  if not track or (reaper.GetMasterTrack and track==reaper.GetMasterTrack(0)) then return end
  if not prop.section(ctx,state,'track_tools','Track tools',false) then return end
  local tracks=targets(state)
  render_controls(ctx,tracks)
  prop.row(ctx,'Envelopes',function()
    button(ctx,'Open...##trackenvelopes','envelopes',{track},-1,
      'Open the focused track\'s envelope window, including track and FX parameter automation.')
  end)
  icon_controls(ctx,tracks)
  prop.row(ctx,'Grouping',function()
    local width=reaper.ImGui_GetContentRegionAvail(ctx)
    button(ctx,'Setup...##trackgroups','grouping',tracks,math.max(1,(width-4)*0.55),'Edit grouping parameters for selected tracks.')
    reaper.ImGui_SameLine(ctx,0,4)
    button(ctx,'Matrix##trackgroups','grouping_matrix',tracks,math.max(1,(width-4)*0.45),'Open REAPER\'s track grouping matrix.')
  end)
  local groups,mixed=group_summary(tracks)
  if groups then
    prop.row(ctx,'Membership',function()
      local label=#groups==0 and 'No groups' or (#groups..' group'..(#groups==1 and '' or 's')..(mixed and ' · mixed' or ''))
      reaper.ImGui_TextDisabled(ctx,label)
      prop.tooltip(ctx,#groups==0 and 'No explicit media or control group membership.'
        or ('Groups '..table.concat(groups,', ')..(mixed and '\nSelected tracks have different memberships.' or '')))
    end)
  end
end

return M
