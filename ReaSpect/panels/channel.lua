local api = require('ReaSpect.core.reaper_api')
local fader = require('ReaSpect.widgets.fader')
local undo = require('ReaSpect.core.undo')
local color = require('ReaSpect.widgets.color')
local controls = require('ReaSpect.widgets.controls')
local meter = require('ReaSpect.widgets.meter')
local rack = require('ReaSpect.widgets.rack')
local theme = require('ReaSpect.core.theme')
local pan = require('ReaSpect.core.pan')
local input_selector = require('ReaSpect.widgets.input_selector')
local M = {knob_drags={}}
local CIRCLE_SEGMENTS=48
local STRIP_SCALE=0.75
local CONTROL_SCALE=0.9
local STRIP_WIDTH=78
local STRIP_FONT_SIZE=(theme.font_sizes and theme.font_sizes.body) or 12
local READOUT_FONT_SIZE=(theme.font_sizes and theme.font_sizes.readout) or 11
local STRIP_STACK_SPACING=2
local function compact_px(value,compact) return compact and value*CONTROL_SCALE or value end
local function seconds() return reaper.time_precise and reaper.time_precise() or os.clock() end

local function db(v) if not v or v <= 0.000001 then return -math.huge end return 20 * math.log(v, 10) end
local function fader_db(v) local d = db(v); return d == -math.huge and select(1,fader.range()) or d end
local function db_text(v) local d = db(v); return d == -math.huge and '-inf' or string.format('%+.2f dB', d) end
local function lin(v) return 10 ^ (v / 20) end
local function each(state, fn)
  local list = state.selected_tracks or {}
  if #list == 0 and state.selected_track then list = {state.selected_track} end
  for _, t in ipairs(list) do fn(t) end
end
local function edit(state, label, setter, value)
  undo.edit(label, function()
    each(state, function(t) setter(t, value) end)
    reaper.UpdateArrange()
  end)
end
local function pan_label(v)
  if math.abs(v or 0) < 0.01 then return 'center' end
  return v < 0 and string.format('L%d', math.floor(-v * 100 + 0.5)) or string.format('R%d', math.floor(v * 100 + 0.5))
end
local function automation_label(v)
  return ({[0]='Auto: Trim',[1]='Auto: Read',[2]='Auto: Touch',[3]='Auto: Write',[4]='Auto: Latch',[5]='Auto: Latch prev'})[v] or 'Auto: Trim'
end
local function automation_short(v)
  return ({[0]='A:Trm',[1]='A:R',[2]='A:T',[3]='A:W',[4]='A:L',[5]='A:LP'})[v] or 'A:Trm'
end

local function small_button(ctx, label, active, on, w, compact, on_set)
  local kind=label:match('^([^#]+)')
  local width,height=compact_px(w or (compact and 24 or 30),compact),compact_px(compact and 23 or 25,compact)
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  local hit=reaper.ImGui_InvisibleButton(ctx,label,width,height)
  local hovered=reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx)
  local held=reaper.ImGui_IsItemActive and reaper.ImGui_IsItemActive(ctx)
  local active_color=kind=='M' and 0xA54D5BFF or (kind=='S' and 0xB89B55FF or 0x666B6CFF)
  local fill=active and active_color or (held and 0x686B6EFF or (hovered and 0x55585BFF or 0x3D4043FF))
  if theme.is_light and not active then fill=held and 0xA8ADB4FF or (hovered and 0xBEC3CAFF or theme.colors.frame) end
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  reaper.ImGui_DrawList_AddRectFilled(dl,x+1,y+1,x+width-1,y+height-1,(theme.is_light and theme.colors.border or 0x191B1DFF),2)
  reaper.ImGui_DrawList_AddRectFilled(dl,x+2,y+2,x+width-2,y+height-2,fill,1)
  reaper.ImGui_DrawList_AddLine(dl,x+3,y+2,x+width-3,y+2,0xB1B4B430,1)
  local large=reaper.ImGui_PushFont and reaper.ImGui_PopFont
  if large then reaper.ImGui_PushFont(ctx,nil,compact and ((theme.font_sizes and theme.font_sizes.button) or 14) or 18) end
  local tw,th=reaper.ImGui_CalcTextSize(ctx,kind)
  local tx,ty=x+(width-tw)/2,y+(height-th)/2-1
  reaper.ImGui_DrawList_AddText(dl,tx,ty,(theme.is_light and not active and theme.colors.text or 0xE8E9E9FF),kind)
  if large then reaper.ImGui_PopFont(ctx) end
  if reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_SetTooltip then
    local tip = label:match('^([^#]+)') or label
    local tips = {M='Mute', S='Solo', ARM='Record arm', MON='Input monitor'}
    local extra=tip=='M' and '\nShift: this track only  •  Ctrl: unmute all  •  Ctrl+Alt: exclusive mute  •  Alt: mute others'
      or (tip=='S' and '\nShift: this track only  •  Ctrl: unsolo all  •  Ctrl+Alt: exclusive solo  •  Ctrl+Shift: solo defeat  •  Alt: ignore routing' or '')
    reaper.ImGui_SetTooltip(ctx, (tips[tip] or tip)..extra)
  end
  local changed,out=controls.toggle(ctx,active,false)
  if changed and on_set then on_set(out)
  elseif hit and on then on(not active) end
end

local function key_mods(ctx)
  local mods=reaper.ImGui_GetKeyMods and reaper.ImGui_GetKeyMods(ctx) or 0
  local function down(name)
    local bit=reaper['ImGui_Mod_'..name]
    return bit and (mods & bit())~=0 or false
  end
  return down('Ctrl'),down('Alt'),down('Shift')
end

local function control_each(state,source,ctx,fn)
  local ctrl,_,shift=key_mods(ctx)
  if ctrl and shift then fn(source); return end
  each(state,fn)
end

local function control_edit(ctx,state,source,label,setter,value)
  undo.edit(label,function()
    control_each(state,source,ctx,function(t) setter(t,value) end)
    reaper.UpdateArrange()
  end)
end

local function selected_group(state,source,ignore_selection)
  if ignore_selection then return source and {source} or {} end
  local tracks={}
  for _,t in ipairs(state.selected_tracks or {}) do tracks[#tracks+1]=t end
  if #tracks==0 and source then tracks[1]=source end
  return tracks
end

local function all_project_tracks(include_master)
  local tracks={}
  for i=0,(reaper.CountTracks(0) or 0)-1 do tracks[#tracks+1]=reaper.GetTrack(0,i) end
  if include_master and reaper.GetMasterTrack then tracks[#tracks+1]=reaper.GetMasterTrack(0) end
  return tracks
end

local function set_mute_group(state,source,ctrl,alt,shift)
  local group=selected_group(state,source,shift)
  local is_group={}; for _,t in ipairs(group) do is_group[t]=true end
  if ctrl and not alt then
    undo.edit('Unmute all tracks',function()
      for _,t in ipairs(all_project_tracks(true)) do reaper.SetMediaTrackInfo_Value(t,'B_MUTE',0) end
      reaper.UpdateArrange()
    end)
  elseif alt then
    local exclusive=ctrl
    undo.edit(exclusive and 'Exclusive mute' or 'Mute all other tracks',function()
      for _,t in ipairs(all_project_tracks(false)) do
        local mute
        if is_group[t] then mute=exclusive else mute=true end
        reaper.SetMediaTrackInfo_Value(t,'B_MUTE',mute and 1 or 0)
      end
      reaper.UpdateArrange()
    end)
  else
    local value=not api.track.mute(source)
    undo.edit('Toggle mute',function()
      for _,t in ipairs(group) do api.track.set_mute(t,value) end
      reaper.UpdateArrange()
    end)
  end
end

local function set_solo_group(state,source,ctrl,alt,shift)
  local group=selected_group(state,source,shift and not ctrl)
  local is_group={}; for _,t in ipairs(group) do is_group[t]=true end
  if ctrl and shift then
    local value=(reaper.GetMediaTrackInfo_Value(source,'B_SOLO_DEFEAT') or 0)<=0
    undo.edit('Toggle solo defeat',function()
      for _,t in ipairs(group) do reaper.SetMediaTrackInfo_Value(t,'B_SOLO_DEFEAT',value and 1 or 0) end
      reaper.UpdateArrange()
    end)
  elseif ctrl and alt then
    undo.edit('Exclusive solo',function()
      for _,t in ipairs(all_project_tracks(false)) do
        if is_group[t] then
          if reaper.SetTrackUISolo then reaper.SetTrackUISolo(t,1,0) else reaper.SetMediaTrackInfo_Value(t,'I_SOLO',1) end
        else
          if reaper.SetTrackUISolo then reaper.SetTrackUISolo(t,0,0) else reaper.SetMediaTrackInfo_Value(t,'I_SOLO',0) end
        end
      end
      reaper.UpdateArrange()
    end)
  elseif ctrl then
    undo.edit('Unsolo all tracks',function()
      if reaper.SoloAllTracks then reaper.SoloAllTracks(0)
      else for _,t in ipairs(all_project_tracks(false)) do reaper.SetMediaTrackInfo_Value(t,'I_SOLO',0) end end
      reaper.UpdateArrange()
    end)
  elseif alt then
    local mode=reaper.GetMediaTrackInfo_Value(source,'I_SOLO') or 0
    local next_mode=mode==2 and 0 or 2
    undo.edit('Solo ignoring routing',function()
      for _,t in ipairs(group) do
        if reaper.SetTrackUISolo then reaper.SetTrackUISolo(t,next_mode,0)
        else reaper.SetMediaTrackInfo_Value(t,'I_SOLO',next_mode) end
      end
      reaper.UpdateArrange()
    end)
  else
    local value=not api.track.solo(source)
    undo.edit('Toggle solo',function()
      for _,t in ipairs(group) do api.track.set_solo(t,value) end
      reaper.UpdateArrange()
    end)
  end
end

local function automation_button(ctx, mode, on_click, compact, on_change)
  local u=compact_px(1,compact)
  local w,h=compact_px(compact and 24 or 30,compact),compact_px(compact and 20 or 24,compact)
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  local hit=reaper.ImGui_InvisibleButton(ctx,'##automation',w,h)
  local hovered=reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx)
  local held=reaper.ImGui_IsItemActive and reaper.ImGui_IsItemActive(ctx)
  local bright=hit or held or seconds() < (M.automation_flash_until or 0)
  if dl and reaper.ImGui_DrawList_AddLine and reaper.ImGui_DrawList_AddCircleFilled then
    local ink=bright and 0xF4F7F7FF or (hovered and 0xD3D7D8FF or 0xAFB4B7FF)
    if bright and reaper.ImGui_DrawList_AddRectFilled then
      reaper.ImGui_DrawList_AddRectFilled(dl,x+1,y+1,x+w-1,y+h-1,0x555A5CFF,4)
    end
    local left,right=x+5*u,x+w-5*u
    local low,high=y+h-6*u,y+6*u
    reaper.ImGui_DrawList_AddLine(dl,left,low,left+5*u,low,ink,1.8*u)
    reaper.ImGui_DrawList_AddLine(dl,left+5*u,low,right-5*u,high,ink,1.8*u)
    reaper.ImGui_DrawList_AddLine(dl,right-5*u,high,right,high,ink,1.8*u)
    reaper.ImGui_DrawList_AddCircleFilled(dl,left+5*u,low,2.5*u,ink)
    reaper.ImGui_DrawList_AddCircleFilled(dl,right-5*u,high,2.5*u,ink)
  end
  if hit then
    M.automation_flash_until=seconds()+0.45
    on_click()
  end
  local changed,out=controls.choice(ctx,mode,{0,1,2,3,4,5},0)
  if changed and on_change then on_change(out) end
  if hovered and reaper.ImGui_SetTooltip then
    reaper.ImGui_SetTooltip(ctx,automation_label(mode)..'\nClick: envelopes  •  Wheel: mode  •  Right-click: Trim/Read')
  end
end

local function phase_button(ctx, active, on_click, compact)
  local u=compact_px(1,compact)
  local w,h=compact_px(compact and 24 or 30,compact),compact_px(compact and 20 or 24,compact)
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  local col=active and 0xF5B35AFF or 0xB9BDC0FF
  if dl and reaper.ImGui_DrawList_AddCircle then
    local cx,cy=x+w/2,y+h/2
    reaper.ImGui_DrawList_AddCircleFilled(dl,cx,cy,(compact and 9 or 11)*u,(theme.is_light and theme.colors.frame or 0x303337FF),CIRCLE_SEGMENTS)
    reaper.ImGui_DrawList_AddCircle(dl,cx,cy,(compact and 6 or 8)*u,col,CIRCLE_SEGMENTS,2*u)
    reaper.ImGui_DrawList_AddLine(dl,cx-6*u,cy+6*u,cx+6*u,cy-6*u,col,2*u)
  end
  if reaper.ImGui_InvisibleButton(ctx,'##phase',w,h) then on_click(not active) end
  local changed,out=controls.toggle(ctx,active,false)
  if changed then on_click(out) end
  if reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_SetTooltip then
    reaper.ImGui_SetTooltip(ctx,(active and 'Polarity inverted' or 'Invert polarity')..'\nWheel: enable/disable  •  Right-click: normal polarity')
  end
end

local function draw_arc(dl, cx, cy, radius, a1, a2, col, thickness)
  if not dl or a2 <= a1 then return end
  local arc, stroke = reaper.ImGui_DrawList_PathArcTo, reaper.ImGui_DrawList_PathStroke
  if arc and stroke and reaper.ImGui_DrawList_PathClear and reaper.ImGui_DrawFlags_None then
    reaper.ImGui_DrawList_PathClear(dl)
    arc(dl, cx, cy, radius, a1, a2, math.max(24, math.ceil((a2-a1)*radius)))
    stroke(dl, col, reaper.ImGui_DrawFlags_None(), thickness or 2)
    reaper.ImGui_DrawList_PathClear(dl)
    return
  end
  if reaper.ImGui_DrawList_AddCircle then
    local line=reaper.ImGui_DrawList_AddLine
    if line then
      local steps=math.max(16,math.ceil((a2-a1)*radius))
      local px,py=cx+math.cos(a1)*radius,cy+math.sin(a1)*radius
      for i=1,steps do
        local a=a1+(a2-a1)*i/steps
        local nx,ny=cx+math.cos(a)*radius,cy+math.sin(a)*radius
        line(dl,px,py,nx,ny,col,thickness or 2)
        px,py=nx,ny
      end
    end
  end
end

local function knob(ctx, id, value, minv, maxv, ring, reset, tooltip, feedback, compact)
  local u=compact_px(1,compact)
  local w,h=compact_px(compact and 36 or 50,compact),compact_px(compact and 30 or 38,compact)
  if not reaper.ImGui_InvisibleButton then
    local changed, out = reaper.ImGui_SliderDouble(ctx, id, value, minv, maxv, '%.2f')
    return changed, out, false
  end
  local x, y = reaper.ImGui_GetCursorScreenPos(ctx); local dl = reaper.ImGui_GetWindowDrawList(ctx)
  local cx,cy=x+w/2,y+(compact and 16 or 17)*u
  reaper.ImGui_InvisibleButton(ctx, id, w, h)
  local changed, out = false, value
  local active=reaper.ImGui_IsItemActive and reaper.ImGui_IsItemActive(ctx)
  local mouse_x,mouse_y
  if reaper.ImGui_GetMousePos then mouse_x,mouse_y=reaper.ImGui_GetMousePos(ctx) end
  if reaper.ImGui_IsItemActivated and reaper.ImGui_IsItemActivated(ctx) then
    M.knob_drags[id]={value=value,last_y=mouse_y,alt_restore=false}
  end
  local drag=M.knob_drags[id]
  local ctrl,alt,shift=key_mods(ctx)
  if active and drag then
    if alt then drag.alt_restore=true end
    if mouse_y and drag.last_y then
      local dy=mouse_y-drag.last_y
      out=math.max(minv,math.min(maxv,value-dy*0.008*(maxv-minv)*((ctrl or shift) and 0.1 or 1)))
      drag.last_y=mouse_y
      changed=math.abs(out-value)>0.00001
    elseif reaper.ImGui_GetMouseDragDelta then
      local _,dy=reaper.ImGui_GetMouseDragDelta(ctx,0,0,0,0)
      out=math.max(minv,math.min(maxv,(drag.value or value)-dy*0.008*(maxv-minv)*((ctrl or shift) and 0.1 or 1)))
      changed=math.abs(out-value)>0.00001
    end
  elseif drag then
    if drag.alt_restore then
      out=drag.value or value
      changed=math.abs(out-value)>0.00001
    end
    M.knob_drags[id]=nil
  end
  local reset_hit=controls.double_click(ctx) or (reaper.ImGui_IsItemClicked and reaper.ImGui_IsItemClicked(ctx,1))
  local wh,nv=controls.wheel(ctx,value,0.01,minv,maxv)
  if wh then out,changed=nv,true end
  if reset_hit then out=reset == nil and ((minv<0) and 0 or 1) or reset end
  local hovered=reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx)
  local shown
  if feedback=='width' then
    local percent=out>=0 and math.floor(out*100+.5) or math.ceil(out*100-.5)
    shown=tostring(percent)..'%'
  else shown=pan_label(out) end
  if active and drag and reaper.ImGui_BeginTooltip and reaper.ImGui_EndTooltip and reaper.ImGui_Text then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx,(tooltip or 'Control')..': '..shown)
    if ctrl or shift then
      if reaper.ImGui_TextDisabled then reaper.ImGui_TextDisabled(ctx,'Fine adjust') end
    end
    reaper.ImGui_EndTooltip(ctx)
  elseif hovered and reaper.ImGui_SetTooltip then
    reaper.ImGui_SetTooltip(ctx,(tooltip or 'Control')..': '..shown..'\nShift/Ctrl-drag: fine adjust  •  Ctrl+Shift: this track only  •  Alt-drag: return to start  •  Right/double-click: reset')
  end
  local norm=math.max(0,math.min(1,(out-minv)/math.max(0.0001,maxv-minv)))
  -- The open-bottom halo runs from the lower-left endpoint, over the top,
  -- to the lower-right endpoint. Pan fills one side from center; width fills
  -- symmetrically, using gold for positive and violet for negative values.
  local a1,a2=math.pi*0.75,math.pi*2.25
  local center=(a1+a2)/2
  local pan_a1,pan_a2=math.pi*0.5,math.pi*2.5
  local angle=pan_a1+(pan_a2-pan_a1)*norm
  local feedback_ring=(feedback=='width' and out<0) and theme.accent_color or (ring or 0xE8E9E4FF)
  if dl and reaper.ImGui_DrawList_AddCircleFilled then
    local face=(compact and 7.2 or 9.2)*u
    local track_radius=(compact and 12.5 or 15)*u
    local halo_radius=track_radius-2.5*u
    local halo_border=0x1C2022FF
    local halo_border_width=3.8*u
    local halo_width=3.0*u
    -- Explicit tessellation keeps the small rims circular at high UI scales.
    reaper.ImGui_DrawList_AddCircleFilled(dl,cx+0.5*u,cy+u,track_radius+0.5*u,0x10131588,CIRCLE_SEGMENTS)
    reaper.ImGui_DrawList_AddCircleFilled(dl,cx,cy,track_radius,0x303639FF,CIRCLE_SEGMENTS)

    local function halo(from,to,col)
      draw_arc(dl,cx,cy,halo_radius,from,to,halo_border,halo_border_width)
      reaper.ImGui_DrawList_AddCircleFilled(dl,cx+math.cos(from)*halo_radius,cy+math.sin(from)*halo_radius,halo_border_width/2,halo_border,24)
      reaper.ImGui_DrawList_AddCircleFilled(dl,cx+math.cos(to)*halo_radius,cy+math.sin(to)*halo_radius,halo_border_width/2,halo_border,24)
      draw_arc(dl,cx,cy,halo_radius,from,to,col,halo_width)
      reaper.ImGui_DrawList_AddCircleFilled(dl,cx+math.cos(from)*halo_radius,cy+math.sin(from)*halo_radius,halo_width/2,col,24)
      reaper.ImGui_DrawList_AddCircleFilled(dl,cx+math.cos(to)*halo_radius,cy+math.sin(to)*halo_radius,halo_width/2,col,24)
    end

    if feedback=='width' then
      -- Width has a continuous, open-bottom scale; its active halo grows on
      -- both sides together and changes to the theme accent below zero.
      halo(a1,a2,0x42494CFF)
      local half=math.pi*0.75*math.min(1,math.abs(out))
      if math.abs(out)>0.025 then halo(center-half,center+half,feedback_ring) end
    else
      -- Pan is directional: show only the sweep from center toward its value,
      -- not the symmetric continuous scale used by the width knob.
      local from,to=center,angle
      if to<from then from,to=to,from end
      if math.abs(out)<=0.025 then from,to=center-0.14,center+0.14 end
      halo(from,to,feedback_ring)
    end
    -- Light-gray rotating cap, separated from the halo by a dark outline.
    reaper.ImGui_DrawList_AddCircleFilled(dl,cx+0.3*u,cy+0.6*u,face+u,0x1A1D1FFF,CIRCLE_SEGMENTS)
    reaper.ImGui_DrawList_AddCircleFilled(dl,cx,cy,face,0x252A2DFF,CIRCLE_SEGMENTS)
    reaper.ImGui_DrawList_AddCircleFilled(dl,cx-0.4*u,cy-0.5*u,face-1.3*u,0xA2A8AAFF,CIRCLE_SEGMENTS)
    reaper.ImGui_DrawList_AddCircleFilled(dl,cx-0.8*u,cy-1.2*u,face-3.2*u,0xBCC1C2FF,CIRCLE_SEGMENTS)
    if reaper.ImGui_DrawList_AddCircle then reaper.ImGui_DrawList_AddCircle(dl,cx,cy,face,0x171A1CFF,CIRCLE_SEGMENTS,u) end
  end
  return changed and not reset_hit, out, reset_hit
end

local function input_button(ctx, track, width, state)
  input_selector.draw(ctx,track,width,state,function(value,preserve_channel)
    edit(state,'Set record input',function(t,v)
      api.track.set_input(t,input_selector.source_value(api.track.input(t),v,preserve_channel))
    end,value)
  end,18*CONTROL_SCALE)
end

local function arm_button(ctx, track, active, automatic, on_click)
  local u=CONTROL_SCALE
  local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  if dl and reaper.ImGui_DrawList_AddCircleFilled then
    local cx,cy=x+13*u,y+13*u
    reaper.ImGui_DrawList_AddCircleFilled(dl,cx,cy,13*u,(theme.is_light and theme.colors.frame or (theme.is_light and theme.colors.frame or 0x25282BFF)),CIRCLE_SEGMENTS)
    if automatic then
      -- Auto-arm mode stays identifiable while disarmed, but only lights red
      -- when REAPER currently has the selected track armed.
      reaper.ImGui_DrawList_AddCircleFilled(dl,cx,cy,10*u,active and 0xE84B60FF or (theme.is_light and 0x626970FF or 0x747B7FFF),CIRCLE_SEGMENTS)
      if reaper.ImGui_DrawList_AddLine then
        local ink=0x111315FF
        reaper.ImGui_DrawList_AddLine(dl,cx-4.3*u,cy+4.2*u,cx,cy-5*u,ink,1.8*u)
        reaper.ImGui_DrawList_AddLine(dl,cx,cy-5*u,cx+4.3*u,cy+4.2*u,ink,1.8*u)
        reaper.ImGui_DrawList_AddLine(dl,cx-2.3*u,cy+u,cx+2.3*u,cy+u,ink,1.8*u)
      end
    elseif active then
      if reaper.ImGui_DrawList_AddCircle then reaper.ImGui_DrawList_AddCircle(dl,cx,cy,10*u,0xEA4A5FFF,CIRCLE_SEGMENTS,3*u) end
    elseif reaper.ImGui_DrawList_AddCircle then
      reaper.ImGui_DrawList_AddCircleFilled(dl,cx,cy,10*u,0xA3A8AAFF,CIRCLE_SEGMENTS)
      reaper.ImGui_DrawList_AddCircleFilled(dl,cx,cy,5*u,(theme.is_light and theme.colors.frame or (theme.is_light and theme.colors.frame or 0x25282BFF)),CIRCLE_SEGMENTS)
    end
  end
  if reaper.ImGui_InvisibleButton then
    if reaper.ImGui_InvisibleButton(ctx,'##arm',26*u,26*u) then
      local ctrl,alt=key_mods(ctx)
      if ctrl and alt then
        undo.edit('Exclusive record arm',function()
          for _,t in ipairs(all_project_tracks(false)) do
            if reaper.SetTrackUIRecArm then reaper.SetTrackUIRecArm(t,0,1)
            else reaper.SetMediaTrackInfo_Value(t,'I_RECARM',0) end
          end
          if reaper.SetTrackUIRecArm then reaper.SetTrackUIRecArm(track,1,0)
          else reaper.SetMediaTrackInfo_Value(track,'I_RECARM',1) end
          reaper.UpdateArrange()
        end)
      else on_click(not active) end
    end
    if reaper.ImGui_IsItemClicked and reaper.ImGui_IsItemClicked(ctx,1) then
      local _,_,shift=key_mods(ctx)
      if shift then api.show_native_track_menu('track_input',track)
      else on_click(false) end
    end
    local changed,out=controls.toggle(ctx,active)
    if changed then on_click(out) end
  end
  if reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_SetTooltip then
    local status=automatic and (active and 'Auto-arm when selected • currently armed'
      or 'Auto-arm when selected • currently unarmed')
      or (active and 'Record armed' or 'Record disarmed')
    reaper.ImGui_SetTooltip(ctx,status..'\nClick: arm  •  Ctrl+Alt: exclusive arm\nRight-click: disarm  •  Shift+right-click: REAPER recording options')
  end
end

local function monitor_button(ctx, mode, on_click, width, compact, track)
  local u=compact_px(1,compact)
  local w,h=compact_px(width or 30,compact),compact_px(compact and 20 or 22,compact)
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx); local dl=reaper.ImGui_GetWindowDrawList(ctx)
  local active=mode~=0; local col=active and (mode==2 and 0xE0B64DFF or 0xD5D8DAFF) or 0x697076FF
  if dl and reaper.ImGui_DrawList_AddLine then
    local cx=x+w/2
    reaper.ImGui_DrawList_AddCircleFilled(dl,cx,y+3*u,1.4*u,col,24)
    for i=0,2 do draw_arc(dl,cx,y+4*u,(6+i*4)*u,math.pi*0.25,math.pi*0.75,col,2*u) end
  end
  if reaper.ImGui_InvisibleButton then
    if reaper.ImGui_InvisibleButton(ctx,'##monitor',w,h) then on_click((mode+1)%3) end
    if track and reaper.ImGui_IsItemClicked and reaper.ImGui_IsItemClicked(ctx,1) then
      local _,_,shift=key_mods(ctx)
      if shift then api.show_native_track_menu('track_input',track)
      else on_click(0) end
    end
    local changed,out=controls.choice(ctx,mode,{0,1,2})
    if changed then on_click(out) end
  end
  if reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_SetTooltip then
    local label=({[0]='Monitoring off',[1]='Monitor input',[2]='Tape auto monitoring'})[mode] or 'Input monitoring'
    reaper.ImGui_SetTooltip(ctx,label..'\nClick: cycle  •  Wheel: mode\nRight-click: off  •  Shift+right-click: REAPER recording options')
  end
end

local function light_button(ctx, id, enabled, on_click)
  local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  if dl and reaper.ImGui_DrawList_AddCircleFilled then
    reaper.ImGui_DrawList_AddCircleFilled(dl, x + 9, y + 11, 5, enabled and 0xB98AE8FF or 0x34383DFF)
    if reaper.ImGui_DrawList_AddCircle then reaper.ImGui_DrawList_AddCircle(dl, x + 9, y + 11, 7, 0x17191CFF, 0, 2) end
  end
  if reaper.ImGui_InvisibleButton then
    if reaper.ImGui_InvisibleButton(ctx, id, 18, 22) and on_click then on_click() end
  elseif reaper.ImGui_Button(ctx, (enabled and '●' or '○') .. id, 18, 22) and on_click then on_click() end
end

local function safe_child(ctx, id, w, h, flags, fn)
  local visible = reaper.ImGui_BeginChild(ctx, id, w, h, 0, controls.scroll_flags(flags))
  if visible then
    fn()
    if ((flags or 0) & reaper.ImGui_WindowFlags_NoScrollWithMouse())==0 then controls.scroll_end(ctx) end
    reaper.ImGui_EndChild(ctx)
  end
  return visible
end

local function slot_button(ctx, label, id, enabled, on_click, on_toggle, offline)
  local avail = reaper.ImGui_GetContentRegionAvail(ctx) or 120
  local row_w = on_toggle and math.max(20, avail - 22) or avail
  local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  if dl and reaper.ImGui_DrawList_AddRectFilled then
    local bg = label == '' and 0x352E32FF or (offline and 0x29272AFF or (enabled and 0x56554BFF or 0x3B3538FF))
    local fg = offline and 0x777C77FF or (enabled and 0xEEE7D7FF or 0xAAAFAAFF)
    reaper.ImGui_DrawList_AddRectFilled(dl, x, y, x + row_w, y + 22, bg, 5)
    if label ~= '' and reaper.ImGui_DrawList_AddText then reaper.ImGui_DrawList_AddText(dl, x + 6, y + 4, fg, label) end
  end
  local hit = reaper.ImGui_InvisibleButton and reaper.ImGui_InvisibleButton(ctx, '##' .. id, row_w, 22)
  if reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_SetTooltip and label ~= '' then
    reaper.ImGui_SetTooltip(ctx, label .. (offline and ' (offline)' or (enabled and ' (enabled)' or ' (bypassed)')))
  end
  if hit and on_click then on_click() end
  if on_toggle then
    reaper.ImGui_SameLine(ctx)
    light_button(ctx, '##' .. id .. '_bypass', enabled, function() on_toggle(not enabled) end)
  end
end

local function compact_fx_name(name)
  local out = (name or ''):gsub('^[^:]+:%s*', ''):gsub('%s*%([^%)]*%)%s*$', '')
  if #out > 17 then out = out:sub(1, 16) .. '…' end
  return out
end

local function routing_button(ctx, track, on_click, compact)
  local u=compact_px(1,compact)
  local w,h=compact_px(compact and 24 or 30,compact),(compact and 26 or 36)*u
  local x, y = reaper.ImGui_GetCursorScreenPos(ctx); local dl = reaper.ImGui_GetWindowDrawList(ctx)
  local route=api.routing_state(track)
  local palette=theme.routing_colors
  if dl and reaper.ImGui_DrawList_AddRectFilled then
    reaper.ImGui_DrawList_AddRectFilled(dl,x+1,y+1,x+w-1,y+h-1,(theme.is_light and theme.colors.frame or 0x3A3D3FFF),3)
    local function stripe(yy,active,tint)
      reaper.ImGui_DrawList_AddRectFilled(dl,x+5*u,y+yy*u,x+w-5*u,y+(yy+4)*u,active and tint or palette.inactive,2*u)
    end
    stripe(compact and 4 or 7,route.parent,palette.parent)
    stripe(compact and 11 or 16,route.sends+route.hardware>0,palette.send)
    stripe(compact and 18 or 25,route.receives>0,palette.receive)
  end
  if reaper.ImGui_InvisibleButton then
    if reaper.ImGui_InvisibleButton(ctx, '##routing', w, h) and on_click then on_click() end
    if reaper.ImGui_IsItemClicked and reaper.ImGui_IsItemClicked(ctx,1) then
      api.show_native_track_menu('track_routing',track)
    end
  elseif reaper.ImGui_Button(ctx, 'I/O##routing', w, h) then on_click() end
  if reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_SetTooltip then
    reaper.ImGui_SetTooltip(ctx,string.format(
      'Routing: Master/Parent %s  •  %d sends  •  %d hardware outputs  •  %d receives',
      route.parent and 'on' or 'off',route.sends,route.hardware,route.receives))
  end
end

local function muted_track_color(native)
  if not native or native == 0 then return 0x68696BFF end
  local r, g, b = color.native_to_rgb(native)
  -- Preserve the track's actual hue: the reference shows distinct gray,
  -- blue, green and mauve channel tops, not one universal mauve tint.
  r, g, b = 0.15 + r * 0.55, 0.15 + g * 0.55, 0.15 + b * 0.55
  return (math.floor(math.min(1, r) * 255 + 0.5) << 24)
    | (math.floor(math.min(1, g) * 255 + 0.5) << 16)
    | (math.floor(math.min(1, b) * 255 + 0.5) << 8) | 0xFF
end

local function footer_track_color(native)
  if not native or native == 0 then return 0xA7A7A9FF end
  local r,g,b=color.native_to_rgb(native)
  return (math.floor((0.48+r*0.28)*255+0.5)<<24)
    | (math.floor((0.48+g*0.28)*255+0.5)<<16)
    | (math.floor((0.48+b*0.28)*255+0.5)<<8) | 0xFF
end

local function draw_compact(ctx,state,ah,expanded,narrow)
  local t=state.selected_track
  local u=STRIP_SCALE
  local strip_w=STRIP_WIDTH
  local right_padding=3*u
  -- Keep the compact controls intact; an exceptionally short parent panel
  -- can scroll instead of silently clipping its footer and lower buttons.
  local strip_h=math.max(narrow and 150 or 128,ah)
  local no_scroll=(reaper.ImGui_WindowFlags_NoScrollbar and reaper.ImGui_WindowFlags_NoScrollbar() or 0)
    | (reaper.ImGui_WindowFlags_NoScrollWithMouse and reaper.ImGui_WindowFlags_NoScrollWithMouse() or 0)
  safe_child(ctx,'##compact_strip',strip_w,strip_h,no_scroll,function()
    local tight=reaper.ImGui_PushStyleVar and reaper.ImGui_PopStyleVar and reaper.ImGui_StyleVar_ItemSpacing
    if tight then reaper.ImGui_PushStyleVar(ctx,reaper.ImGui_StyleVar_ItemSpacing(),2*u,u) end
    -- When the dock cannot fit both the fixed strip and its side rack, keep
    -- the native FX-chain/bypass control on the strip instead of clipping it.
    if narrow then
      rack.draw_fx_header(ctx,t,state,true)
      reaper.ImGui_Dummy(ctx,0,2)
    end
    local strip_font=reaper.ImGui_PushFont and reaper.ImGui_PopFont
    if strip_font then reaper.ImGui_PushFont(ctx,nil,STRIP_FONT_SIZE) end
    local name=api.track.name(t)
    if name=='' then name='Track' end
    local zx,zy=reaper.ImGui_GetCursorScreenPos(ctx)
    local zw=reaper.ImGui_GetContentRegionAvail(ctx) or strip_w
    local window_x,window_y=reaper.ImGui_GetWindowPos(ctx)
    local window_w,window_h=reaper.ImGui_GetWindowSize(ctx)
    local dl=reaper.ImGui_GetWindowDrawList(ctx)
    local header_h=(expanded and 64 or 40)*u
    reaper.ImGui_DrawList_AddRectFilled(dl,window_x,window_y,window_x+window_w,zy+header_h,muted_track_color(api.track.color(t)))
    reaper.ImGui_DrawList_AddLine(dl,window_x+2,window_y+1,window_x+window_w-2,window_y+1,0xFFFFFF25,1)
    local panmode=pan.effective_mode(t)
    local left_value=panmode==6 and api.track.dualpan_l(t) or api.track.pan(t)
    local left_native=panmode==6 and api.track.set_dualpan_l or api.track.set_pan
    local function left_setter(tr,value)
      local mode=pan.effective_mode(tr)
      if (panmode==6 and mode==6) or (panmode~=6 and mode~=6) then left_native(tr,value) end
    end
    local pan_x=zx+8*u
    local width_x=zx+zw-45*u
    reaper.ImGui_SetCursorScreenPos(ctx,pan_x,zy+2*u)
    local changed,out,reset=knob(ctx,'##compact_pan',left_value,-1,1,0xE7E8E3FF,panmode==6 and -1 or 0,panmode==6 and 'Left pan' or 'Pan',nil,true)
    if reset then control_edit(ctx,state,t,'Reset track pan',left_setter,out)
    else undo.gesture(ctx,'compact_pan','Set track pan',changed,function()
      control_each(state,t,ctx,function(tr) left_setter(tr,out) end)
    end) end
    if panmode==5 or panmode==6 then
      reaper.ImGui_SetCursorScreenPos(ctx,width_x,zy+2*u)
      local second_value=panmode==6 and api.track.dualpan_r(t) or api.track.width(t)
      local second_native=panmode==6 and api.track.set_dualpan_r or api.track.set_width
      local function second_setter(tr,value)
        if pan.effective_mode(tr)==panmode then second_native(tr,value) end
      end
      local second_feedback='width'
      if panmode==6 then second_feedback=nil end
      local wchanged,wout,wreset=knob(ctx,'##compact_width',second_value,-1,1,0xF0B525FF,1,
        panmode==6 and 'Right pan' or 'Stereo width',second_feedback,true)
      if wreset then control_edit(ctx,state,t,panmode==6 and 'Reset right pan' or 'Reset stereo width',second_setter,wout)
      else undo.gesture(ctx,'compact_width',panmode==6 and 'Set right pan' or 'Set stereo width',wchanged,function()
        control_each(state,t,ctx,function(tr) second_setter(tr,wout) end)
      end) end
    end
    if expanded then
      reaper.ImGui_SetCursorScreenPos(ctx,zx+4*u,zy+40*u)
      input_button(ctx,t,math.min(56*u,zw-38*u),state)
      local resume_x,resume_y=reaper.ImGui_GetCursorScreenPos(ctx)
      reaper.ImGui_SetCursorScreenPos(ctx,zx+zw-26*CONTROL_SCALE-right_padding,zy+40*u)
      arm_button(ctx,t,api.track.arm(t),api.track.auto_arm(t),
        function(v) edit(state,'Set record arm',api.track.set_arm,v) end)
      reaper.ImGui_SetCursorScreenPos(ctx,resume_x,resume_y)
      reaper.ImGui_Dummy(ctx,0,u)
    else
      reaper.ImGui_SetCursorScreenPos(ctx,zx,zy+40*u)
    end
    local value_text=string.format('%.2f',fader_db(api.track.volume(t)))
    if strip_font then reaper.ImGui_PushFont(ctx,nil,READOUT_FONT_SIZE) end
    local tw=reaper.ImGui_CalcTextSize(ctx,value_text)
    if reaper.ImGui_SetCursorPosX and reaper.ImGui_GetCursorPosX then
      reaper.ImGui_SetCursorPosX(ctx,reaper.ImGui_GetCursorPosX(ctx)+math.max(0,(zw-tw)/2-5*u))
    end
    reaper.ImGui_TextDisabled(ctx,value_text)
    if strip_font then reaper.ImGui_PopFont(ctx) end
    local _,by=reaper.ImGui_GetCursorScreenPos(ctx)
    local bx=zx
    -- Anchor to the actual child window, not the content cursor (which includes
    -- theme-dependent padding). Both footer bands finish at the visible edge.
    local footer_y=window_y+window_h-41*u
    local bottom_y=footer_y-2*u
    local travel=math.max(50*u,bottom_y-by)
    local reduction=meter.read_gain_reduction(t)
    -- Reserve the widest scaled button as well as the fader and its gap.
    -- Their scales differ, so a fixed gain-reduction width can push the
    -- right-hand controls past the strip's content edge.
    local button_width=26*CONTROL_SCALE
    local gr_width=math.max(0,math.min(10*u,zw-36*u-28*u-2*u-button_width-right_padding))
    local fader_x=bx+36*u+gr_width
    local buttons_x=fader_x+28*u+2*u
    reaper.ImGui_DrawList_AddRectFilled(dl,bx,by,bx+zw,by+travel,(theme.is_light and theme.colors.panel or 0x242629FF),1)
    local peak_l,peak_r=api.track.peak(t)
    reaper.ImGui_SetCursorScreenPos(ctx,bx,by)
    if strip_font then reaper.ImGui_PushFont(ctx,nil,READOUT_FONT_SIZE) end
    meter.draw(ctx,peak_l,peak_r,36*u,'compact_'..tostring(t),travel,api.track.arm(t),t,u)
    if strip_font then reaper.ImGui_PopFont(ctx) end
    if gr_width>0 then
      reaper.ImGui_SetCursorScreenPos(ctx,bx+36*u,by)
      meter.draw_gain_reduction(ctx,reduction,gr_width,travel,tostring(t),u)
    end
    reaper.ImGui_SetCursorScreenPos(ctx,fader_x,by)
    local fchanged,fvalue=fader.draw(ctx,'##compact_fader',fader_db(api.track.volume(t)),nil,travel,true,u)
    local freset=controls.double_click(ctx) or (reaper.ImGui_IsItemClicked and reaper.ImGui_IsItemClicked(ctx,1))
    if freset then control_edit(ctx,state,t,'Reset track volume',api.track.set_volume,1)
    else undo.gesture(ctx,'compact_volume','Set track volume',fchanged,function()
      control_each(state,t,ctx,function(tr) api.track.set_volume(tr,lin(fvalue)) end)
    end) end
    local monitor_y=math.max(by-16*CONTROL_SCALE,zy+40*u+26*CONTROL_SCALE+2*u)
    local button_y=expanded and math.max(by+14*u,monitor_y+20*CONTROL_SCALE+STRIP_STACK_SPACING*u) or by+4*u
    local button_step=23*CONTROL_SCALE+STRIP_STACK_SPACING*u
    reaper.ImGui_SetCursorScreenPos(ctx,buttons_x,button_y)
    small_button(ctx,'M##compact_mute',api.track.mute(t),function()
      local ctrl,alt,shift=key_mods(ctx); set_mute_group(state,t,ctrl,alt,shift)
    end,24,true,function(v) edit(state,'Set track mute',api.track.set_mute,v) end)
    reaper.ImGui_SetCursorScreenPos(ctx,buttons_x,button_y+button_step)
    small_button(ctx,'S##compact_solo',api.track.solo(t),function()
      local ctrl,alt,shift=key_mods(ctx); set_solo_group(state,t,ctrl,alt,shift)
    end,24,true,function(v) edit(state,'Set track solo',api.track.set_solo,v) end)
    if expanded then
      reaper.ImGui_SetCursorScreenPos(ctx,buttons_x,monitor_y)
      monitor_button(ctx,api.track.monitor(t),function(v) edit(state,'Set input monitoring',api.track.set_monitor,v) end,24,true,t)
      reaper.ImGui_SetCursorScreenPos(ctx,buttons_x,button_y+2*button_step+3*u)
      routing_button(ctx,t,function() api.show_routing(t) end,true)
    end

    if expanded then
      -- Position each control independently: placing the monitor above M/S
      -- must not move the routing row back over those buttons.
      reaper.ImGui_SetCursorScreenPos(ctx,buttons_x,bottom_y-40*CONTROL_SCALE-STRIP_STACK_SPACING*u)
      automation_button(ctx,api.track.automation(t),function() api.show_automation(t) end,true,
        function(v) edit(state,'Set automation mode',api.track.set_automation,v) end)
      reaper.ImGui_SetCursorScreenPos(ctx,buttons_x,bottom_y-20*CONTROL_SCALE)
      phase_button(ctx,api.track.phase(t),function(v) edit(state,'Toggle track phase',api.track.set_phase,v) end,true)
    end

    reaper.ImGui_SetCursorScreenPos(ctx,window_x,footer_y)
    local foot_x,foot_y=reaper.ImGui_GetCursorScreenPos(ctx)
    reaper.ImGui_DrawList_AddRectFilled(dl,foot_x,foot_y,foot_x+window_w,foot_y+22*u,(theme.is_light and theme.colors.frame or 0x262326FF))
    local short_name=name
    if reaper.ImGui_CalcTextSize(ctx,name)>window_w-8 then
      while #short_name>0 and reaper.ImGui_CalcTextSize(ctx,short_name..'…')>window_w-8 do
        local last=utf8 and utf8.offset and utf8.offset(short_name,-1) or #short_name
        short_name=short_name:sub(1,(last or #short_name)-1)
      end
    end
    if short_name~=name then short_name=short_name..'…' end
    local name_w=reaper.ImGui_CalcTextSize(ctx,short_name)
    reaper.ImGui_DrawList_AddText(dl,foot_x+(window_w-name_w)/2,foot_y+3*u,(theme.is_light and theme.colors.text or 0xE2E0DEFF),short_name)
    local number=reaper.GetMediaTrackInfo_Value(t,'IP_TRACKNUMBER') or 0
    local number_text=number>0 and tostring(math.floor(number)) or ' '
    reaper.ImGui_DrawList_AddRectFilled(dl,foot_x,foot_y+22*u,foot_x+window_w,foot_y+41*u,footer_track_color(api.track.color(t)))
    if strip_font then reaper.ImGui_PushFont(ctx,nil,(theme.font_sizes and theme.font_sizes.caption) or 11) end
    local number_w=reaper.ImGui_CalcTextSize(ctx,number_text)
    reaper.ImGui_DrawList_AddText(dl,foot_x+(window_w-number_w)/2,foot_y+24*u,0x222427FF,number_text)
    if strip_font then reaper.ImGui_PopFont(ctx) end
    reaper.ImGui_Dummy(ctx,window_w,41*u)
    if strip_font then reaper.ImGui_PopFont(ctx) end
    if tight then reaper.ImGui_PopStyleVar(ctx) end
  end)
end

function M.draw(ctx,state)
  local track=state.selected_track
  if not track then reaper.ImGui_TextDisabled(ctx,'No track selected');return end
  local available_width,available_height=reaper.ImGui_GetContentRegionAvail(ctx)
  available_width,available_height=available_width or 280,available_height or 400
  local rack_only=state.channel_rack_only==true
  local strip_width=STRIP_WIDTH
  local narrow=available_width<=strip_width
  -- Budget the actual scaled header, readout, six controls and footer.
  -- The standalone strip also needs its FX header above the pan controls.
  local stack_height=(23+23+26)*CONTROL_SCALE+(3+14+4*STRIP_STACK_SPACING)*STRIP_SCALE
  local bottom_row=40*CONTROL_SCALE+STRIP_STACK_SPACING*STRIP_SCALE
  local full_height=(64+41+2)*STRIP_SCALE+STRIP_FONT_SIZE+stack_height+bottom_row
  local compact=available_height<full_height+(narrow and 28 or 0)
  if M.last_compact~=nil and M.last_compact~=compact then undo.flush_gestures() end
  M.last_compact=compact
  if not rack_only then
    draw_compact(ctx,state,available_height,not compact,narrow)
    if narrow then return end
    reaper.ImGui_SameLine(ctx,0,0)
  end
  local rack_width=rack_only and math.max(1,available_width) or math.max(1,available_width-strip_width)
  if reaper.ImGui_PushStyleColor and reaper.ImGui_Col_ChildBg then
    reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_ChildBg(),theme.colors.panel or 0x2C272BFF)
  end
  safe_child(ctx,'##channel_rack',rack_width,available_height,reaper.ImGui_WindowFlags_NoScrollbar(),function()
    local _,rack_height=reaper.ImGui_GetContentRegionAvail(ctx)
    rack.draw(ctx,track,state,rack_height or available_height)
  end)
  if reaper.ImGui_PopStyleColor and reaper.ImGui_Col_ChildBg then reaper.ImGui_PopStyleColor(ctx) end
end
return M
