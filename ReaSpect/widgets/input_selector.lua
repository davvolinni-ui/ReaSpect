local api=require('ReaSpect.core.reaper_api')
local controls=require('ReaSpect.widgets.controls')
local M={}

local function is_midi(value) return value>=0 and (value&4096)~=0 end

local function audio_name(index)
  local name=reaper.GetInputChannelName and reaper.GetInputChannelName(index)
  return name and name~='' and name or ('Input '..(index+1))
end

function M.label(value)
  if not value or value<0 then return 'None' end
  if is_midi(value) then
    local channel,device=value&31,(value>>5)&63
    local name
    if device==63 then name='All MIDI'
    elseif device==62 then name='Virtual MIDI keyboard'
    elseif reaper.GetMIDIInputName then
      local ok,found=reaper.GetMIDIInputName(device,'')
      if ok and found~='' then name=found end
    end
    return (name or ('MIDI '..(device+1)))..(channel==0 and '' or (' ch '..channel))
  end
  local start=value&1023
  local first=audio_name(start):gsub('^Input%s+','In ')
  if (value&2048)~=0 then return first..' multichannel' end
  if (value&1024)~=0 then return first..' / '..audio_name(start+1) end
  return first
end

-- Popup choices use native I_RECINPUT encoding: 1024 stereo, 2048 track-width
-- multichannel, 4096 MIDI with channel in low 5 bits and device in next 6.
-- https://www.reaper.fm/sdk/reascript/reascripthelp.html#GetMediaTrackInfo_Value
function M.options(track,state)
  local count=reaper.GetNumAudioInputs and reaper.GetNumAudioInputs() or 0
  count=math.max(0,math.min(512,math.floor(count)))
  local result={mono={},stereo={},multi={},midi={}}
  for index=0,count-1 do result.mono[#result.mono+1]={label=audio_name(index),value=index} end
  for index=0,count-2 do
    result.stereo[#result.stereo+1]={label=audio_name(index)..' / '..audio_name(index+1),value=1024|index}
  end
  local max_channels=api.track.channels(track)
  for _,selected in ipairs(state.selected_tracks or {}) do max_channels=math.max(max_channels,api.track.channels(selected)) end
  -- A shared start must fit every edited track, since this mode derives its
  -- channel count from each track rather than encoding it in I_RECINPUT.
  if max_channels>2 then
    for index=0,count-max_channels do
      result.multi[#result.multi+1]={label=audio_name(index)..' onward',value=2048|index}
    end
  end
  result.midi={{label='All MIDI inputs',value=4096|(63<<5)},{label='Virtual MIDI keyboard',value=4096|(62<<5)}}
  for device=0,math.min(62,reaper.GetNumMIDIInputs and reaper.GetNumMIDIInputs() or 0)-1 do
    local ok,name=reaper.GetMIDIInputName(device,'')
    if ok then result.midi[#result.midi+1]={label=(name and name~='') and name or ('MIDI '..(device+1)),value=4096|(device<<5)} end
  end
  return result
end

function M.source_value(old,value,preserve_channel)
  if preserve_channel and is_midi(old) and is_midi(value) then return (value&~31)|(old&31) end
  return value
end

local function audio_menu(ctx,title,entries,current,on_change)
  if reaper.ImGui_BeginMenu(ctx,title,#entries>0) then
    for _,entry in ipairs(entries) do
      if reaper.ImGui_MenuItem(ctx,entry.label..'##source_'..entry.value,nil,current==entry.value) then on_change(entry.value,false) end
    end
    reaper.ImGui_EndMenu(ctx)
  end
end

function M.draw(ctx,track,width,state,on_change,height)
  local value=api.track.input(track)
  local popup='##input_sources_'..tostring(track)
  local clicked=reaper.ImGui_Button(ctx,M.label(value)..'  ▾##input',width,height or 21)
  local _,values=api.record_inputs()
  local reset=controls.right_click(ctx)
  local changed,out=controls.choice(ctx,is_midi(value) and (value&~31) or value,values,-1)
  if clicked then reaper.ImGui_OpenPopup(ctx,popup)
  elseif reset then
    local needs_reset=value~=-1
    for _,selected in ipairs(state.selected_tracks or {}) do if api.track.input(selected)~=-1 then needs_reset=true;break end end
    if needs_reset then on_change(-1,false) end
  elseif changed then on_change(out,true) end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetTooltip(ctx,'Input: '..M.label(value)..'\nClick: choose input source  •  Wheel: change input  •  Right-click: None')
  end
  if reaper.ImGui_BeginPopup(ctx,popup) then
    if reaper.ImGui_MenuItem(ctx,'None',nil,value<0) then on_change(-1,false) end
    local options=M.options(track,state)
    audio_menu(ctx,'Mono input',options.mono,value,on_change)
    audio_menu(ctx,'Stereo input',options.stereo,value,on_change)
    if #options.multi>0 then
      audio_menu(ctx,'Multichannel input',options.multi,value,on_change)
    end
    if reaper.ImGui_BeginMenu(ctx,'MIDI input') then
      for _,device in ipairs(options.midi) do
        if reaper.ImGui_BeginMenu(ctx,device.label..'##midi_device_'..device.value) then
          if reaper.ImGui_MenuItem(ctx,'All channels',nil,value==device.value) then on_change(device.value,false) end
          for channel=1,16 do
            local source=device.value|channel
            if reaper.ImGui_MenuItem(ctx,'Channel '..channel,nil,value==source) then on_change(source,false) end
          end
          reaper.ImGui_EndMenu(ctx)
        end
      end
      reaper.ImGui_EndMenu(ctx)
    end
    reaper.ImGui_EndPopup(ctx)
  end
end

return M
