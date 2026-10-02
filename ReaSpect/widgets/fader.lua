local controls = require('ReaSpect.widgets.controls')
local M = {drags={}}
function M.draw(ctx, id, value, on_change, height, compact)
  local h=height or 140; local w=compact and 28 or 34
  if not (reaper.ImGui_GetCursorScreenPos and reaper.ImGui_GetWindowDrawList and reaper.ImGui_InvisibleButton) then
    if reaper.ImGui_VSliderDouble then return reaper.ImGui_VSliderDouble(ctx,id,42,h,value,-60,12,'%.1f dB') end
    return false,value
  end
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx); local dl=reaper.ImGui_GetWindowDrawList(ctx)
  local cx=x+w/2
  local cap_h=math.min(h*0.55,math.min(compact and 62 or 64,
    math.max(compact and 42 or 38,h*(compact and 0.30 or 0.22))))
  local travel=math.max(1,h-cap_h)
  -- The reference fader's 0 dB resting point is about one third of the way
  -- down the slot. Use a curved dB scale instead of placing 0 dB near the top.
  local scale_curve=0.60
  local function value_fraction(v)
    return ((12-math.max(-60,math.min(12,v)))/72)^scale_curve
  end
  local function fraction_value(f)
    return 12-72*math.max(0,math.min(1,f))^(1/scale_curve)
  end
  local function pos(v) return y+cap_h/2+travel*value_fraction(v) end
  local function drag_value(base,dy,sensitivity)
    return fraction_value(value_fraction(base)+dy/travel*sensitivity)
  end
  reaper.ImGui_InvisibleButton(ctx,id,w,h)
  local changed=false; local out=value
  local active=reaper.ImGui_IsItemActive and reaper.ImGui_IsItemActive(ctx)
  local mouse_y
  if reaper.ImGui_GetMousePos then local _,screen_y=reaper.ImGui_GetMousePos(ctx); mouse_y=screen_y end
  if reaper.ImGui_IsItemActivated and reaper.ImGui_IsItemActivated(ctx) then
    M.drags[id]={value=value,last_y=mouse_y or pos(value),alt_restore=false}
  end
  local drag=M.drags[id]
  local mods=reaper.ImGui_GetKeyMods and reaper.ImGui_GetKeyMods(ctx) or 0
  local ctrl=reaper.ImGui_Mod_Ctrl and (mods & reaper.ImGui_Mod_Ctrl())~=0
  local shift=reaper.ImGui_Mod_Shift and (mods & reaper.ImGui_Mod_Shift())~=0
  local alt=reaper.ImGui_Mod_Alt and (mods & reaper.ImGui_Mod_Alt())~=0
  if active and drag and mouse_y then
    if alt then drag.alt_restore=true end
    local dy=mouse_y-(drag.last_y or mouse_y)
    out=drag_value(value,dy,(ctrl or shift) and 0.1 or 1)
    drag.last_y=mouse_y
    changed=math.abs(out-value)>0.001
  elseif active and drag and reaper.ImGui_GetMouseDelta then
    if alt then drag.alt_restore=true end
    local _,dy=reaper.ImGui_GetMouseDelta(ctx)
    out=drag_value(drag.value or value,dy,(ctrl or shift) and 0.1 or 1)
    changed=math.abs(out-value)>0.001
  elseif drag then
    if drag.alt_restore then
      out=drag.value or value
      changed=math.abs(out-value)>0.001
    end
    M.drags[id]=nil
  else
    M.drags[id]=nil
  end
  local wheeled,next_value=controls.wheel(ctx,value,1,-60,12)
  if wheeled then out,changed=next_value,true end
  reaper.ImGui_DrawList_AddRectFilled(dl,cx-2,y+4,cx+2,y+h-4,0x0D0F11FF,2)
  reaper.ImGui_DrawList_AddLine(dl,cx-3,y+4,cx-3,y+h-4,0x32373BFF,1)
  reaper.ImGui_DrawList_AddLine(dl,cx+3,y+4,cx+3,y+h-4,0x32373BFF,1)
  for _,v in ipairs({-54,-42,-30,-18,-6,0}) do
    local yy=pos(v)
    reaper.ImGui_DrawList_AddLine(dl,cx-7,yy,cx+7,yy,v==0 and 0x8C9398AA or 0x555B6066,1)
  end
  local capy=pos(out)
  local top,bottom=capy-cap_h/2,capy+cap_h/2
  local cap_l,cap_r=x+1,x+w-1
  -- Raised cap with dark shoulders and the narrow light-gray center grip.
  reaper.ImGui_DrawList_AddRectFilled(dl,cap_l+1,top+2,cap_r+1,bottom+2,0x090A0C88,6)
  reaper.ImGui_DrawList_AddRectFilled(dl,cap_l,top,cap_r,bottom,0x171A1DFF,6)
  reaper.ImGui_DrawList_AddRectFilled(dl,cap_l+2,top+2,cap_r-2,bottom-2,0x555D61FF,5)
  reaper.ImGui_DrawList_AddRectFilled(dl,cap_l+4,top+4,cap_r-4,bottom-4,0x343A3DFF,4)
  reaper.ImGui_DrawList_AddRectFilled(dl,cx-4,top+7,cx+4,bottom-7,0xBFC5C7FF,2)
  reaper.ImGui_DrawList_AddLine(dl,cap_l+4,top+3,cap_r-4,top+3,0xE8EBECFF,1)
  reaper.ImGui_DrawList_AddLine(dl,cap_l+4,bottom-3,cap_r-4,bottom-3,0x454B4EFF,1)
  for i=-3,3 do
    local yy=capy+i*5
    local left,right=cx-3,cx+3
    if i==0 then
      reaper.ImGui_DrawList_AddLine(dl,left,yy,right,yy,0xE8EBECFF,1)
    else
      reaper.ImGui_DrawList_AddLine(dl,left,yy,right,yy,0x62696DFF,1)
      reaper.ImGui_DrawList_AddLine(dl,left+1,yy+1,right-1,yy+1,0xD0D4D5CC,1)
    end
  end
  local hovered=reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx)
  if active and drag and reaper.ImGui_BeginTooltip and reaper.ImGui_EndTooltip and reaper.ImGui_Text then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx,string.format('%.1f dB',out))
    if shift or ctrl then
      if reaper.ImGui_TextDisabled then reaper.ImGui_TextDisabled(ctx,'Fine adjust') end
    end
    reaper.ImGui_EndTooltip(ctx)
  elseif hovered and reaper.ImGui_SetTooltip then
    reaper.ImGui_SetTooltip(ctx,string.format('Track level: %.1f dB\nShift/Ctrl-drag: fine adjust  •  Ctrl+Shift: this track only  •  Alt-drag: return to start\nRight-click or double-click resets',out))
  end
  return changed,out
end
return M
