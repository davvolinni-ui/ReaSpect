local api = require('ReaSpect.core.reaper_api')
local prop = require('ReaSpect.widgets.property')
local color = require('ReaSpect.widgets.color')
local undo = require('ReaSpect.core.undo')
local theme = require('ReaSpect.core.theme')
local selection = require('ReaSpect.core.item_selection')
local controls = require('ReaSpect.widgets.controls')
local pan = require('ReaSpect.core.pan')
local track_actions = require('ReaSpect.core.track_actions')
local fx_parameters = require('ReaSpect.widgets.fx_parameters')
local panel_body = require('ReaSpect.widgets.panel_body')
local track_tools = require('ReaSpect.widgets.track_tools')
local icon_browser = require('ReaSpect.widgets.icon_browser')
local track_notes = require('ReaSpect.widgets.track_notes')
local M = {rename=nil}

local timebases = {'Project default','Time','Beats (pos/len/rate)','Beats (position only)'}
local automodes = {'Trim/Read','Read','Touch','Write','Latch','Latch preview'}
local recmodes = {
  'Input','Stereo output','Disable recording','Stereo output (latency compensated)',
  'MIDI output','Mono output','Mono output (latency compensated)','MIDI overdub','MIDI replace'
}
local monitors = {'Off','On','Tape style (not during playback)'}

local function each_track(state, fn)
  local list = state.selected_tracks or {}
  if #list == 0 and state.selected_track then list = {state.selected_track} end
  for _, t in ipairs(list) do fn(t) end
end
local function shared(state, getter)
  local first = state.selected_track and getter(state.selected_track)
  if first == nil then return nil end
  for _, t in ipairs(state.selected_tracks or {}) do if getter(t) ~= first then return '__MIXED__' end end
  return first
end
local function edit(state,label, setter, value)
  undo.edit(label,function()
    each_track(state,function(t) setter(t,value) end)
    if setter==api.track.set_channels or setter==api.track.set_folder_depth or setter==api.track.set_free_mode then
      reaper.TrackList_AdjustWindows(false)
    end
    reaper.UpdateArrange()
  end)
end

local function delta_editor(state,label,getter,setter,min,max,quantum)
  local tracks={}
  each_track(state,function(t) tracks[#tracks+1]=t end)
  return selection.delta_editor(tracks,label,getter,setter,min,max,quantum)
end

local media_icon_cache={track=nil,project_state=nil,scanned_at=0,kind='empty'}
local function track_media_kind(track)
  local project_state=reaper.GetProjectStateChangeCount and reaper.GetProjectStateChangeCount(0) or nil
  local now=reaper.time_precise and reaper.time_precise() or os.clock()
  if media_icon_cache.track==track then
    if project_state~=nil and media_icon_cache.project_state==project_state then return media_icon_cache.kind end
    if now-media_icon_cache.scanned_at<0.35 then return media_icon_cache.kind end
  end
  local has_midi,has_audio=false,false
  if reaper.CountTrackMediaItems and reaper.GetTrackMediaItem and reaper.GetActiveTake and reaper.TakeIsMIDI then
    for i=0,(reaper.CountTrackMediaItems(track) or 0)-1 do
      local item=reaper.GetTrackMediaItem(track,i)
      local take=item and reaper.GetActiveTake(item)
      if take then
        if reaper.TakeIsMIDI(take) then has_midi=true else has_audio=true end
        if has_midi and has_audio then
          media_icon_cache={track=track,project_state=project_state,scanned_at=now,kind='mixed'}
          return media_icon_cache.kind
        end
      end
    end
  end
  local kind=has_midi and 'midi' or (has_audio and 'audio' or 'empty')
  media_icon_cache={track=track,project_state=project_state,scanned_at=now,kind=kind}
  return kind
end

local function track_type_icon(ctx,kind)
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  reaper.ImGui_Dummy(ctx,18,22)
  local hovered=reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx)
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  local ink=theme.colors.text or 0xD4D7DBFF
  local dark=theme.colors.panel or 0x1D2024FF
  if kind=='audio' then
    local heights={5,9,14,8,5}
    for i,h in ipairs(heights) do
      local bx=x+2+(i-1)*3.1
      reaper.ImGui_DrawList_AddRectFilled(dl,bx,y+11-h/2,bx+1.8,y+11+h/2,ink,1)
    end
  elseif kind=='midi' then
    reaper.ImGui_DrawList_AddRectFilled(dl,x+2,y+5,x+16,y+17,ink,1)
    reaper.ImGui_DrawList_AddLine(dl,x+6,y+6,x+6,y+16,dark,1)
    reaper.ImGui_DrawList_AddLine(dl,x+10,y+6,x+10,y+16,dark,1)
    reaper.ImGui_DrawList_AddLine(dl,x+13,y+6,x+13,y+16,dark,1)
    reaper.ImGui_DrawList_AddRectFilled(dl,x+4,y+5,x+6,y+11,dark)
    reaper.ImGui_DrawList_AddRectFilled(dl,x+8,y+5,x+10,y+11,dark)
    reaper.ImGui_DrawList_AddRectFilled(dl,x+12,y+5,x+14,y+11,dark)
  elseif kind=='mixed' then
    for i,h in ipairs({4,8,5}) do
      local bx=x+1+(i-1)*2.5
      reaper.ImGui_DrawList_AddRectFilled(dl,bx,y+11-h/2,bx+1.5,y+11+h/2,ink,1)
    end
    reaper.ImGui_DrawList_AddRectFilled(dl,x+10,y+6,x+17,y+16,ink,1)
    reaper.ImGui_DrawList_AddRectFilled(dl,x+12,y+6,x+13,y+11,dark)
    reaper.ImGui_DrawList_AddRectFilled(dl,x+15,y+6,x+16,y+11,dark)
  else
    reaper.ImGui_DrawList_AddRectFilled(dl,x+3,y+5,x+15,y+17,0x899197FF,2)
  end
  local labels={audio='Audio track',midi='MIDI track',mixed='Track contains audio and MIDI',empty='No audio or MIDI items'}
  if hovered and reaper.ImGui_SetTooltip then reaper.ImGui_SetTooltip(ctx,labels[kind] or 'Track media type') end
end

local function header_text_width(ctx,text)
  if reaper.ImGui_CalcTextSize then return reaper.ImGui_CalcTextSize(ctx,text) end
  return #(text or '')*7
end

local function header_text_height(ctx,text)
  if reaper.ImGui_CalcTextSize then
    local _,height=reaper.ImGui_CalcTextSize(ctx,text)
    return height or 14
  end
  return 14
end

local function fit_header_text(ctx,text,max_width)
  text=tostring(text or '')
  if max_width<=0 or header_text_width(ctx,text)<=max_width then return text end
  local short=text
  while #short>0 and header_text_width(ctx,short..'…')>max_width do
    local last=utf8 and utf8.offset and utf8.offset(short,-1) or #short
    short=short:sub(1,(last or #short)-1)
  end
  return #short>0 and short..'…' or ''
end

local function escape_pressed(ctx)
  if not (reaper.ImGui_IsKeyPressed and reaper.ImGui_Key_Escape) then return false end
  return reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Escape())
end

local function track_value(track, key)
  return reaper.GetMediaTrackInfo_Value(track,key) or 0
end

local function supports_version(major,minor)
  local current_major,current_minor=(reaper.GetAppVersion and reaper.GetAppVersion() or ''):match('^(%d+)%.(%d+)')
  current_major,current_minor=tonumber(current_major) or 0,tonumber(current_minor) or 0
  return current_major>major or (current_major==major and current_minor>=minor)
end

local function any_track(state, predicate)
  local found=false
  each_track(state,function(track) if predicate(track) then found=true end end)
  return found
end

local function selection_key(state)
  local keys={}
  each_track(state,function(track) keys[#keys+1]=tostring(track) end)
  return table.concat(keys,'|')
end

local function is_midi_input(value)
  return type(value)=='number' and value>=0 and (math.floor(value)&4096)~=0
end

local function input_device(track)
  local value=api.track.input(track)
  return is_midi_input(value) and (math.floor(value)&~31) or value
end

local function input_combo(ctx, state)
  local labels, values = {'None'}, {-1}
  local input_count=reaper.GetNumAudioInputs and (reaper.GetNumAudioInputs() or 0) or 0
  local function input_name(i)
    local name=reaper.GetInputChannelName and reaper.GetInputChannelName(i) or nil
    return name and name~='' and name or ('Input '..(i+1))
  end
  for i=0,input_count-1 do
    labels[#labels+1],values[#values+1]='Mono: '..input_name(i),i
  end
  for i=0,input_count-2 do
    labels[#labels+1],values[#values+1]='Stereo: '..input_name(i)..' / '..input_name(i+1),1024|i
  end
  labels[#labels+1],values[#values+1]='MIDI: All inputs',4096|(63<<5)
  labels[#labels+1],values[#values+1]='MIDI: Virtual keyboard',4096|(62<<5)
  if reaper.GetNumMIDIInputs and reaper.GetMIDIInputName then
    for i=0,math.min(62,reaper.GetNumMIDIInputs() or 0)-1 do
      local ok,name=reaper.GetMIDIInputName(i,'')
      if ok then
        labels[#labels+1],values[#values+1]='MIDI: '..((name and name~='') and name or ('Input '..(i+1))),4096|(i<<5)
      end
    end
  end
  prop.enum(ctx,'Input','##input',shared(state,input_device),labels,values,function(value)
    edit(state,'Set record input',function(track,new_input)
      -- Changing a MIDI device retains each track's chosen input channel.
      local old=api.track.input(track)
      if is_midi_input(new_input) and is_midi_input(old) then new_input=new_input|(math.floor(old)&31) end
      api.track.set_input(track,new_input)
    end,value)
  end,{default=-1})
  local all_midi=not any_track(state,function(track) return not is_midi_input(api.track.input(track)) end)
  if all_midi then
    local channel_labels,channel_values={'All channels'},{0}
    for channel=1,16 do channel_labels[#channel_labels+1]='Channel '..channel; channel_values[#channel_values+1]=channel end
    prop.enum(ctx,'MIDI channel','##inputchannel',shared(state,function(track) return math.floor(api.track.input(track))&31 end),channel_labels,channel_values,function(value)
      edit(state,'Set MIDI input channel',function(track,channel)
        api.track.set_input(track,(math.floor(api.track.input(track))&~31)|channel)
      end,value)
    end,{default=0})
  end
end

local function playback_offset(ctx,state)
  local function unit(track) return math.floor(track_value(track,'I_PLAY_OFFSET_FLAG'))&2 end
  local units=shared(state,unit)
  local samples=unit(state.selected_track)==2
  local value=units=='__MIXED__' and '__MIXED__' or shared(state,function(track)
    local offset=track_value(track,'D_PLAY_OFFSET')
    return samples and offset or offset*1000
  end)
  local tooltip='Track media playback offset in '..(samples and 'samples' or 'milliseconds')..'. Adjusts playback timing without moving media items.'
  if units=='__MIXED__' then tooltip=tooltip..' Selected tracks use different units. Editing applies '..(samples and 'samples' or 'milliseconds')..' to all selected tracks.' end
  prop.number(ctx,'Offset','##playoffset',value,function(v)
    edit(state,'Set track playback offset',function(track,n)
      local flags=math.floor(track_value(track,'I_PLAY_OFFSET_FLAG'))
      -- Match the units printed on the edit control and preserve bypass/other flags.
      reaper.SetMediaTrackInfo_Value(track,'I_PLAY_OFFSET_FLAG',(flags&~2)|(samples and 2 or 0))
      reaper.SetMediaTrackInfo_Value(track,'D_PLAY_OFFSET',samples and math.floor(n+0.5) or n/1000)
    end,v)
  end,samples and '%.0f samples' or '%.2f ms',{step=samples and 1 or 0.1,drag_step=samples and 1 or 0.1,quantum=samples and 1 or nil,default=0,
    on_delta=function(delta)
      -- Mixed units are adjusted in each track's own displayed unit.
      edit(state,'Adjust track playback offset',function(track)
        local is_samples=unit(track)==2
        local old=track_value(track,'D_PLAY_OFFSET')
        reaper.SetMediaTrackInfo_Value(track,'D_PLAY_OFFSET',is_samples and (old+(delta>0 and math.max(1,math.floor(delta+0.5)) or math.min(-1,math.ceil(delta-0.5)))) or old+delta/1000)
      end)
    end,tooltip=tooltip})
  if any_track(state,function(track) return track_value(track,'D_PLAY_OFFSET')~=0 or (math.floor(track_value(track,'I_PLAY_OFFSET_FLAG'))&1)~=0 end) then
    prop.checkbox(ctx,'Offset enabled','##playoffsetenabled',shared(state,function(track)
      return (math.floor(track_value(track,'I_PLAY_OFFSET_FLAG'))&1)==0
    end),function(v)
      edit(state,'Enable track playback offset',function(track,enabled)
        local flags=math.floor(track_value(track,'I_PLAY_OFFSET_FLAG'))
        reaper.SetMediaTrackInfo_Value(track,'I_PLAY_OFFSET_FLAG',enabled and (flags&~1) or (flags|1))
      end,v)
    end,true)
  end
end

local function routing_summary(ctx,state)
  local function summary(track)
    local parts={}
    if api.track.mainsend(track) then
      local parent=reaper.GetParentTrack and reaper.GetParentTrack(track)
      parts[#parts+1]=parent and 'Parent' or 'Master'
    end
    if reaper.GetTrackNumSends then
      local sends=reaper.GetTrackNumSends(track,0) or 0
      local receives=reaper.GetTrackNumSends(track,-1) or 0
      local hardware=reaper.GetTrackNumSends(track,1) or 0
      if sends>0 then parts[#parts+1]=sends..' send'..(sends==1 and '' or 's') end
      if receives>0 then parts[#parts+1]=receives..' in' end
      if hardware>0 then parts[#parts+1]=hardware..' HW' end
    end
    return #parts>0 and table.concat(parts,' · ') or 'No output'
  end
  local text=shared(state,summary)
  prop.row(ctx,'Routing',function()
    local shown=text=='__MIXED__' and 'Mixed routing' or text
    local width=reaper.ImGui_GetContentRegionAvail(ctx) or 140
    reaper.ImGui_TextDisabled(ctx,fit_header_text(ctx,shown,width))
    if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_SetTooltip then
      reaper.ImGui_SetTooltip(ctx,shown..'\nParent/master output, track sends, receives and hardware outputs. Edit routing in the mixer below or open Advanced for parent send and channels.')
    end
  end)
end

local function placement_controls(ctx,state)
  local fixed_lanes_supported=supports_version(7,0)
  local labels,values={'Normal','Free positioning'},{0,1}
  if fixed_lanes_supported then labels[#labels+1]='Fixed lanes';values[#values+1]=2 end
  prop.enum(ctx,'Placement','##lanemode',shared(state,api.track.free_mode),labels,values,function(v)
    edit(state,'Set item placement',api.track.set_free_mode,v)
    if reaper.UpdateTimeline then reaper.UpdateTimeline() end
  end)
  if fixed_lanes_supported and any_track(state,function(track) return api.track.free_mode(track)==2 end) then
    -- Lanes apply only to tracks already in fixed-lane mode.
    local count,has_count=nil,false
    each_track(state,function(track)
      if api.track.free_mode(track)==2 then
        local value=track_value(track,'I_NUMFIXEDLANES')
        if has_count and count~=value then count='__MIXED__' else count=value end
        has_count=true
      end
    end)
    prop.number(ctx,'Fixed lanes','##fixedlanes',count or 1,function(v)
      edit(state,'Set fixed lanes',function(track,n)
        if api.track.free_mode(track)==2 then reaper.SetMediaTrackInfo_Value(track,'I_NUMFIXEDLANES',n) end
      end,math.max(1,math.floor(v+0.5)))
      if reaper.UpdateTimeline then reaper.UpdateTimeline() end
    end,'%.0f',{step=1,quantum=1,min=1,on_delta=delta_editor(state,'Adjust fixed lanes',function(track) return track_value(track,'I_NUMFIXEDLANES') end,
      function(track,n)
        if api.track.free_mode(track)==2 then
          reaper.SetMediaTrackInfo_Value(track,'I_NUMFIXEDLANES',n)
          if reaper.UpdateTimeline then reaper.UpdateTimeline() end
        end
      end,1,nil,1),tooltip='Number of lanes on the selected fixed-lane tracks.'})
  end
end

local function freeze_controls(ctx,state)
  local tracks={}
  each_track(state,function(track)
    if not reaper.GetMasterTrack or track~=reaper.GetMasterTrack(0) then tracks[#tracks+1]=track end
  end)
  if #tracks==0 then return end
  local frozen=false
  for _,track in ipairs(tracks) do if (track_actions.freeze_count(track) or 0)>0 then frozen=true end end
  local popup='##freeze_options_'..selection_key(state)
  local action=frozen and 'unfreeze' or 'freeze_stereo'
  prop.row(ctx,'Freeze',function()
    local available=track_actions.available(action)
    local width=reaper.ImGui_GetContentRegionAvail(ctx)
    if not available then reaper.ImGui_BeginDisabled(ctx) end
    if reaper.ImGui_Button(ctx,(frozen and 'Unfreeze' or 'Freeze (stereo)')..'##trackfreeze',math.max(1,width-27),0) then
      track_actions.queue(action,tracks)
    end
    controls.wheel_delta(ctx)
    if available and controls.right_click(ctx) then reaper.ImGui_OpenPopup(ctx,popup) end
    prop.tooltip(ctx,frozen and 'Restore the previous freeze pass on frozen selected tracks. Right-click for freeze options.'
      or 'Freeze selected tracks to stereo using REAPER. Right-click for mono and multichannel options.')
    if not available then reaper.ImGui_EndDisabled(ctx) end
    reaper.ImGui_SameLine(ctx,0,4)
    if reaper.ImGui_Button(ctx,'...##trackfreezeoptions',23,0) then reaper.ImGui_OpenPopup(ctx,popup) end
    controls.wheel_delta(ctx)
    prop.tooltip(ctx,'Freeze options')
    if reaper.ImGui_BeginPopup(ctx,popup) then
      for _,option in ipairs({{'Stereo','freeze_stereo'},{'Mono','freeze_mono'},{'Multichannel','freeze_multi'}}) do
        if reaper.ImGui_MenuItem(ctx,'Freeze to '..option[1],nil,false,track_actions.available(option[2])) then
          track_actions.queue(option[2],tracks)
        end
      end
      reaper.ImGui_Separator(ctx)
      local count_known=track_actions.freeze_count(state.selected_track)~=nil
      if reaper.ImGui_MenuItem(ctx,'Unfreeze previous pass',nil,false,track_actions.available('unfreeze') and (frozen or not count_known)) then
        track_actions.queue('unfreeze',tracks)
      end
      reaper.ImGui_EndPopup(ctx)
    end
  end)
  if frozen then
    local count=shared(state,track_actions.freeze_count)
    prop.row(ctx,'Freeze state',function()
      reaper.ImGui_TextDisabled(ctx,count=='__MIXED__' and 'Mixed freeze states'
        or ('Frozen · '..math.floor(count or 0)..' pass'..(count==1 and '' or 'es')))
    end)
  end
end

local function input_fx_control(ctx,track)
  if reaper.GetMasterTrack and track==reaper.GetMasterTrack(0) then return end
  prop.row(ctx,'Input FX',function()
    local count=reaper.TrackFX_GetRecCount and reaper.TrackFX_GetRecCount(track) or 0
    local available=track_actions.available('input_fx')
    if not available then reaper.ImGui_BeginDisabled(ctx) end
    if reaper.ImGui_Button(ctx,('Open chain (%d)##inputfx'):format(count),-1,0) then
      track_actions.queue('input_fx',{track})
    end
    controls.wheel_delta(ctx)
    prop.tooltip(ctx,'Open the focused track\'s input FX chain. Input FX are applied before recording.')
    if not available then reaper.ImGui_EndDisabled(ctx) end
  end)
end

function M.draw(ctx, state)
  local t = state.selected_track
  if not t then reaper.ImGui_TextDisabled(ctx,'No track selected'); return end
  local context_key=selection_key(state)
  prop.set_scope(ctx,'tracks:'..context_key)
  local name = api.track.name(t)
  local hx,hy=reaper.ImGui_GetCursorScreenPos(ctx)
  local hw=reaper.ImGui_GetContentRegionAvail(ctx) or 240
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  local header_h=27
  reaper.ImGui_DrawList_AddRectFilled(dl,hx,hy,hx+hw,hy+header_h,theme.colors.frame or 0x292D31FF,2)
  local strip_w=13
  color.strip(ctx,'##trackcolor_'..tostring(t),api.track.color(t),13,27,function(c)
    edit(state,'Set track color',api.track.set_color,c)
  end)
  local number_left=hx+strip_w
  local number_right=hx+40
  reaper.ImGui_DrawList_AddRectFilled(dl,number_left,hy,number_right,hy+header_h,theme.colors.panel or 0x1D2024FF)
  if reaper.ImGui_DrawList_AddLine then
    local edge=theme.colors.border or 0x454A50FF
    reaper.ImGui_DrawList_AddLine(dl,number_left,hy+4,number_left,hy+header_h-4,edge,1)
    reaper.ImGui_DrawList_AddLine(dl,number_right,hy+4,number_right,hy+header_h-4,edge,1)
  end
  local number=reaper.GetMediaTrackInfo_Value(t,'IP_TRACKNUMBER') or 0
  local number_text=number>0 and tostring(math.floor(number)) or 'M'
  local number_w=header_text_width(ctx,number_text)
  local number_h=header_text_height(ctx,number_text)
  reaper.ImGui_DrawList_AddText(dl,number_left+(number_right-number_left-number_w)*0.5,hy+(header_h-number_h)*0.5,theme.colors.text or 0xD4D7DBFF,number_text)

  local icon_x=hx+hw-23
  local name_x=number_right+5
  local name_w=math.max(1,icon_x-name_x-4)
  if M.rename and M.rename.track~=t then M.rename=nil end
  if M.rename and M.rename.track==t then
    local rename=M.rename
    reaper.ImGui_SetCursorScreenPos(ctx,name_x,hy+2)
    if rename.focus and reaper.ImGui_SetKeyboardFocusHere then
      reaper.ImGui_SetKeyboardFocusHere(ctx)
      rename.focus=false
    end
    if reaper.ImGui_SetNextItemWidth then reaper.ImGui_SetNextItemWidth(ctx,name_w) end
    local colors=0
    if reaper.ImGui_PushStyleColor and reaper.ImGui_Col_FrameBg then
      reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_FrameBg(),theme.colors.panel or 0x1D2024FF);colors=colors+1
      if reaper.ImGui_Col_FrameBgHovered then reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_FrameBgHovered(),theme.colors.panel or 0x1D2024FF);colors=colors+1 end
      if reaper.ImGui_Col_FrameBgActive then reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_FrameBgActive(),theme.colors.panel or 0x1D2024FF);colors=colors+1 end
    end
    local vars=0
    if reaper.ImGui_PushStyleVar and reaper.ImGui_StyleVar_FramePadding then
      reaper.ImGui_PushStyleVar(ctx,reaper.ImGui_StyleVar_FramePadding(),4,2);vars=vars+1
    end
    if reaper.ImGui_PushStyleVar and reaper.ImGui_StyleVar_FrameBorderSize then
      reaper.ImGui_PushStyleVar(ctx,reaper.ImGui_StyleVar_FrameBorderSize(),1);vars=vars+1
    end
    local enter_flag=reaper.ImGui_InputTextFlags_EnterReturnsTrue and reaper.ImGui_InputTextFlags_EnterReturnsTrue() or 0
    local changed,value=reaper.ImGui_InputText(ctx,'##trackname_'..tostring(t),rename.value,enter_flag)
    rename.value=value or rename.value
    local escaped=escape_pressed(ctx)
    local deactivated=reaper.ImGui_IsItemDeactivated and reaper.ImGui_IsItemDeactivated(ctx)
    if vars>0 and reaper.ImGui_PopStyleVar then reaper.ImGui_PopStyleVar(ctx,vars) end
    if colors>0 and reaper.ImGui_PopStyleColor then reaper.ImGui_PopStyleColor(ctx,colors) end
    if escaped then
      M.rename=nil
    elseif changed or deactivated then
      if rename.value~=rename.original then edit(state,'Rename track',api.track.set_name,rename.value) end
      M.rename=nil
    end
  else
    reaper.ImGui_SetCursorScreenPos(ctx,name_x,hy)
    reaper.ImGui_InvisibleButton(ctx,'##trackname_hit_'..tostring(t),name_w,header_h)
    local hovered=reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx)
    if hovered and reaper.ImGui_SetTooltip then reaper.ImGui_SetTooltip(ctx,'Double-click to rename') end
    if hovered and reaper.ImGui_IsMouseDoubleClicked and reaper.ImGui_IsMouseDoubleClicked(ctx,0) then
      M.rename={track=t,value=name,original=name,focus=true}
    end
    local shown=fit_header_text(ctx,name,math.max(0,name_w-8))
    local text_h=header_text_height(ctx,shown)
    reaper.ImGui_DrawList_AddText(dl,name_x+4,hy+(header_h-text_h)*0.5,theme.colors.text or 0xD4D7DBFF,shown)
  end
  reaper.ImGui_SetCursorScreenPos(ctx,icon_x,hy+2)
  local media_kind=track_media_kind(t)
  if track_tools.header_icon(ctx,t,18,22,media_kind,function() track_type_icon(ctx,media_kind) end) then
    icon_browser.open(ctx,t)
  end
  icon_browser.draw(ctx,t)
  reaper.ImGui_SetCursorScreenPos(ctx,hx,hy+header_h)
  reaper.ImGui_Dummy(ctx,0,3)
  local selected_count=#(state.selected_tracks or {})
  if selected_count>1 then reaper.ImGui_TextDisabled(ctx,selected_count..' tracks · edit together') end
  panel_body.draw(ctx,'##track_body',function()
    prop.enum(ctx,'Automation','##trackauto',shared(state,api.track.automation),automodes,{0,1,2,3,4,5},function(v)
      edit(state,'Set automation mode',api.track.set_automation,v)
    end,{default=0})
    prop.enum(ctx,'Timebase','##tracktb',shared(state,api.track.timebase),timebases,{-1,0,1,2},function(v)
      edit(state,'Set track timebase',api.track.set_timebase,v)
    end,{default=-1})
    playback_offset(ctx,state)
    routing_summary(ctx,state)

    local nonstandard_placement=any_track(state,function(track) return api.track.free_mode(track)~=0 end)
    if nonstandard_placement then placement_controls(ctx,state) end
    freeze_controls(ctx,state)

    local recording_relevant=any_track(state,function(track)
      return api.track.arm(track) or api.track.input(track)>=0 or api.track.recmode(track)~=0 or api.track.monitor(track)~=0 or api.track.auto_arm(track)
        or (reaper.TrackFX_GetRecCount and reaper.TrackFX_GetRecCount(track)>0)
    end)
    local recording_key=context_key..':'..tostring(recording_relevant)
    if prop.section(ctx,state,'track_recording','Recording',recording_relevant,recording_key) then
      input_combo(ctx,state)
      input_fx_control(ctx,t)
      prop.enum(ctx,'Record mode','##recmode',shared(state,api.track.recmode),recmodes,{0,1,2,3,4,5,6,7,8},function(v)
        edit(state,'Set record mode',api.track.set_recmode,v)
      end,{default=0})
      prop.enum(ctx,'Monitoring','##recmonitor',shared(state,api.track.monitor),monitors,{0,1,2},function(v)
        edit(state,'Set record monitoring',api.track.set_monitor,v)
      end,{default=0})
      prop.checkbox(ctx,'Auto-arm','##autoarm',shared(state,api.track.auto_arm),function(v)
        edit(state,'Set automatic record arm',function(track,enabled)
          api.track.set_auto_arm(track,enabled)
          if enabled then api.track.set_arm(track,track_value(track,'I_SELECTED')>0) end
        end,v)
      end)
    end

    if prop.section(ctx,state,'track_advanced','Advanced',false) then
      prop.enum(ctx,'Pan mode','##trackpanmode',shared(state,pan.mode),pan.mode_labels,pan.mode_values,function(v)
        edit(state,'Set track pan mode',pan.set_mode,v)
      end,{default=-1,tooltip='Stereo balance, stereo pan or independent left/right pan. Project default follows this project\'s pan mode.'})
      prop.enum(ctx,'Pan law','##trackpanlaw',shared(state,pan.law),pan.law_labels,pan.law_values,function(v)
        edit(state,'Set track pan law',pan.set_law,v)
      end,{default=-1,tooltip='Center attenuation; + gain enables REAPER\'s gain compensation. Existing pan taper is preserved.'})
      prop.number(ctx,'Channels','##trackch',shared(state,api.track.channels),function(v)
        edit(state,'Set track channels',api.track.set_channels,math.max(2,math.min(128,math.floor(v/2+0.5)*2)))
      end,'%.0f',{step=2,quantum=2,min=2,max=128,default=2,on_delta=delta_editor(state,'Adjust track channels',api.track.channels,api.track.set_channels,2,128,2),tooltip='Even channel counts from 2 to 128.'})
      prop.checkbox(ctx,'Parent send','##mainsend',shared(state,api.track.mainsend),function(v)
        edit(state,'Set parent/master send',api.track.set_mainsend,v)
      end,true)
      local folder_labels,folder_values={'Normal','Folder parent','Close 1 folder'},{0,1,-1}
      local closing_depth=1
      each_track(state,function(track) closing_depth=math.max(closing_depth,-api.track.folder_depth(track)) end)
      for depth=2,closing_depth do
        folder_labels[#folder_labels+1]='Close '..depth..' folders'
        folder_values[#folder_values+1]=-depth
      end
      prop.enum(ctx,'Folder role','##folder',shared(state,api.track.folder_depth),folder_labels,folder_values,function(v)
        edit(state,'Set folder state',api.track.set_folder_depth,v)
      end)
      if not nonstandard_placement then placement_controls(ctx,state) end
    end
    fx_parameters.draw(ctx,state)
    track_tools.draw(ctx,state)
    track_notes.draw(ctx,state)
  end)
end

return M
