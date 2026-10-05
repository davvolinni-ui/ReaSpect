local api=require('ReaSpect.core.reaper_api')
local prop=require('ReaSpect.widgets.property')
local selection=require('ReaSpect.core.item_selection')
local audio=require('ReaSpect.inspectors.audio')
local midi=require('ReaSpect.inspectors.midi')
local header=require('ReaSpect.widgets.event_header')
local take_source=require('ReaSpect.widgets.take_source')
local actions=require('ReaSpect.core.item_actions')
local theme=require('ReaSpect.core.theme')
local controls=require('ReaSpect.widgets.controls')
local panel_body=require('ReaSpect.widgets.panel_body')
local M={}

local function event_color(item)
  local take=api.item.take(item)
  local native=take and reaper.GetMediaItemTakeInfo_Value(take,'I_CUSTOMCOLOR') or 0
  if native and (math.floor(native)&0x1000000)~=0 then return native end
  native=reaper.GetMediaItemInfo_Value(item,'I_CUSTOMCOLOR') or 0
  if (math.floor(native)&0x1000000)~=0 then return native end
  local track=reaper.GetMediaItem_Track(item)
  return track and api.track.color(track) or 0
end

local function set_event_color(item,value)
  local take=api.item.take(item)
  if take then reaper.SetMediaItemTakeInfo_Value(take,'I_CUSTOMCOLOR',value)
  else reaper.SetMediaItemInfo_Value(item,'I_CUSTOMCOLOR',value) end
end

local function event_name(item)
  local take=api.item.take(item)
  if take then
    local name=api.take.name(take)
    if name~='' then return name end
    local source=reaper.GetMediaItemTake_Source(take)
    local filename=source and reaper.GetMediaSourceFileName(source) or ''
    if filename~='' then return filename:match('[^/\\\\]+$') or filename end
    return api.take.is_midi(take) and 'MIDI event' or 'Audio event'
  end
  local _,notes=reaper.GetSetMediaItemInfo_String(item,'P_NOTES','',false)
  return notes and notes~='' and (notes:match('[^\r\n]+') or 'Empty event') or 'Empty event'
end

local function draw_header(ctx,context)
  local items=context.items
  local item=items[1]
  local take=api.item.take(item)
  local kind_names={audio='Audio event',midi='MIDI event',empty='Empty event',mixed='Mixed events'}
  local track=reaper.GetMediaItem_Track(item)
  local caption=kind_names[context.kind]
  local name=event_name(item)
  local badge=tostring(math.floor(reaper.GetMediaItemInfo_Value(item,'IP_ITEMNUMBER') or 0)+1)
  if #items>1 then
    badge=tostring(#items)
    name=#items..' events selected'
    local parts={}
    if #context.audio>0 then parts[#parts+1]=#context.audio..' audio' end
    if #context.midi>0 then parts[#parts+1]=#context.midi..' MIDI' end
    if #context.empty>0 then parts[#parts+1]=#context.empty..' empty' end
    caption=table.concat(parts,' · ')..' · edit together'
  elseif track then
    local number=reaper.GetMediaTrackInfo_Value(track,'IP_TRACKNUMBER')
    caption=caption..' · Track '..math.floor(number)
    if take and reaper.CountTakes(item)>1 then
      caption=caption..' · Take '..(math.floor(reaper.GetMediaItemInfo_Value(item,'I_CURTAKE'))+1)..'/'..reaper.CountTakes(item)
    end
  end
  header.draw(ctx,{
    id=context.scope,name=name,badge=badge,kind=context.kind,color=event_color(item),caption=caption,show_caption=context.kind=='mixed',
    tooltip=name..'\n'..caption..(track and '\n'..api.track.name(track) or ''),
    on_color=function(v) selection.edit(items,'Set event color',set_event_color,v) end,
    on_rename=#items==1 and take and function(v) selection.edit({take},'Rename active take',api.take.set_name,v) end or nil,
  })
end

local function draw_flags(ctx,items)
  local fields={
    {'Loop','##event_loop',api.item.loop,api.item.set_loop,'Loop the source when the event extends beyond its source length.'},
    {'Lock','##event_lock',api.item.lock,api.item.set_lock,'Protect the event from arrange edits.'},
    {'Mute','##event_mute',api.item.mute,api.item.set_mute,'Mute the selected events.'},
  }
  local width=(reaper.ImGui_GetContentRegionAvail(ctx)-8)/3
  for index,field in ipairs(fields) do
    if index>1 then reaper.ImGui_SameLine(ctx,0,4) end
    local value=selection.shared(items,field[3])
    local mixed=value==selection.MIXED
    local active=value==true
    reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_Button(),theme.colors.frame)
    reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_Text(),(active or mixed) and theme.colors.accent or theme.colors.text)
    local pressed=reaper.ImGui_Button(ctx,field[1]..(mixed and ' —' or '')..field[2],width,21)
    reaper.ImGui_PopStyleColor(ctx,2)
    if active then
      local x,y=reaper.ImGui_GetItemRectMin(ctx)
      local right,bottom=reaper.ImGui_GetItemRectMax(ctx)
      reaper.ImGui_DrawList_AddLine(reaper.ImGui_GetWindowDrawList(ctx),x+5,bottom-2,right-5,bottom-2,theme.colors.accent,2)
    end
    local changed,out=controls.toggle(ctx,value,field[1]=='Loop')
    prop.tooltip(ctx,field[5]..'\nWheel up: enable; down: disable. Right-click: reset.'..(mixed and '\nMixed states: click to enable for all.' or (active and '\nEnabled' or '\nDisabled')))
    if pressed and not changed then out=not active end
    if pressed or changed then selection.edit(items,'Set event '..field[1]:lower(),field[4],out) end
  end
end

local function draw_timing(ctx,items)
  local position=api.item.position(items[1])
  for n=2,#items do position=math.min(position,api.item.position(items[n])) end
  prop.dual_number(ctx,'Position','##itempos',position,
    'Length','##itemlen',selection.shared(items,api.item.length),
    function(v)
      local delta=v-position
      selection.edit(items,'Move selected events',function(item) api.item.set_position(item,api.item.position(item)+delta) end)
    end,
    function(v) selection.edit(items,'Set event length',api.item.set_length,v) end,
    '%.3f s','%.3f s',
    {step=0.01,drag_step=0.01,tooltip=#items>1 and 'Start of the selection. Moves all selected events together, preserving their spacing.' or 'Event position in project seconds.'},
    {step=0.01,drag_step=0.01,min=0.001,on_delta=selection.delta_editor(items,'Adjust event lengths',api.item.length,api.item.set_length,0.001),tooltip='Event duration. Entering a length applies that duration to each selected event.'})
end

local function draw_timing_details(ctx,state,items)
  if not prop.section(ctx,state,'item_timing','Timing / More',false) then return end
  prop.number(ctx,'End','##itemend',selection.shared(items,function(i) return api.item.position(i)+api.item.length(i) end),function(v)
    selection.edit(items,'Set event end',function(i,value) api.item.set_length(i,math.max(0.001,value-api.item.position(i))) end,v)
  end,'%.3f s',{step=0.01,drag_step=0.01,on_delta=selection.delta_editor(items,'Adjust event ends',api.item.length,api.item.set_length,0.001),tooltip='Right edge in project seconds. Changes length while keeping each event start fixed.'})
  prop.number(ctx,'Snap offset','##snap',selection.shared(items,api.item.snap),function(v)
    selection.edit(items,'Set event snap offset',api.item.set_snap,v)
  end,'%.3f s',{step=0.001,min=0,default=0,on_delta=selection.delta_editor(items,'Adjust snap offsets',api.item.snap,api.item.set_snap,0),tooltip='Snap/sync point, measured from the start of each event.'})
  local function timebase(i)
    local value=api.item.timebase(i)
    if value==1 and reaper.GetMediaItemInfo_Value(i,'C_AUTOSTRETCH')==1 then return 3 end
    return value
  end
  prop.enum(ctx,'Timebase','##item_timebase',selection.shared(items,timebase),
    {'Track / project','Time','Beats (pos/len/rate)','Beats (position)','Beats (auto-stretch)'},{-1,0,1,2,3},function(v)
      selection.edit(items,'Set event timebase',function(i,value)
        api.item.set_timebase(i,value==3 and 1 or value)
        reaper.SetMediaItemInfo_Value(i,'C_AUTOSTRETCH',value==3 and 1 or 0)
      end,v)
    end,{default=-1})
end

local function draw_fx(ctx,items)
  local targets={}
  for _,item in ipairs(items) do if api.item.take(item) then targets[#targets+1]=item end end
  if #targets==0 or not actions.available('take_fx') then return end
  local function count(item)
    return reaper.TakeFX_GetCount and reaper.TakeFX_GetCount(api.item.take(item)) or 0
  end
  prop.row(ctx,'Event FX',function()
    if #targets==1 then
      local n=count(targets[1])
      local label=n>0 and (n..' FX · Open') or 'Add / Open…'
      if reaper.ImGui_Button(ctx,label..'##event_take_fx',-1,22) then actions.queue('take_fx',targets) end
      prop.tooltip(ctx,'Open the active take FX chain.')
    elseif reaper.ImGui_BeginCombo(ctx,'##choose_take_fx','Choose event…') then
      for i,item in ipairs(targets) do
        if reaper.ImGui_Selectable(ctx,i..' · '..event_name(item)..' ('..count(item)..' FX)##fx_'..i,false) then
          actions.queue('take_fx',{item})
        end
      end
      reaper.ImGui_EndCombo(ctx)
    end
  end)
end

function M.draw(ctx,state)
  local items=state.selected_items or {}
  if #items==0 then
    state.take_name_draft=nil
    header.reset()
    reaper.ImGui_TextDisabled(ctx,'Select an event on this track')
    return
  end
  local context=selection.describe(items)
  prop.set_scope(ctx,'items:'..context.scope)
  reaper.ImGui_PushID(ctx,context.scope)
  draw_header(ctx,context)
  reaper.ImGui_PopID(ctx)
  panel_body.draw(ctx,'##event_body',function()
    if (state.other_track_items or 0)>0 then
      reaper.ImGui_TextDisabled(ctx,'Editing events on this track only')
      prop.tooltip(ctx,state.other_track_items..' selected events on other tracks are outside this inspector.')
    end
    reaper.ImGui_PushID(ctx,context.scope)
    take_source.draw_selector(ctx,state,items)
    reaper.ImGui_PopID(ctx)
    -- Choosing another take can change the inspector from audio to MIDI.
    context=selection.describe(items)
    prop.set_scope(ctx,'items:'..context.scope)
    reaper.ImGui_PushID(ctx,context.scope)
    draw_timing(ctx,items)
    draw_flags(ctx,items)
    if context.kind=='audio' then audio.draw(ctx,state,items)
    elseif context.kind=='midi' then midi.draw(ctx,state,items)
    elseif context.kind=='mixed' then
      if #context.audio>0 and prop.section(ctx,state,'item_audio_subset','Audio events ('..#context.audio..')',true) then
        audio.draw(ctx,state,context.audio)
      end
      if #context.midi>0 and prop.section(ctx,state,'item_midi_subset','MIDI events ('..#context.midi..')',true) then
        midi.draw(ctx,state,context.midi)
      end
    end
    draw_fx(ctx,items)
    draw_timing_details(ctx,state,items)
    take_source.draw(ctx,state,items,context.kind)
    reaper.ImGui_PopID(ctx)
  end)
end

return M
