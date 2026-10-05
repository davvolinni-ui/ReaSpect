local theme = require('ReaSpect.core.theme')
local controls = require('ReaSpect.widgets.controls')
local M = {drags={}}
-- Read the live preference, not a saved copy of reaper.ini. Invalid or
-- unavailable values retain the inspector's original range.
function M.range()
  local function preference(key,default,lo,hi)
    if not reaper.get_config_var_string then return default end
    local ok,text=reaper.get_config_var_string(key)
    local value=ok and tonumber(text)
    if not value or value~=value or value<lo or value>hi then return default end
    return value
  end
  return preference('sliderminv',-60,-160,-6),preference('slidermaxv',12,0,60)
end
function M.draw(ctx, id, value, on_change, height, compact, ui_scale)
  local min_db,max_db=M.range()
  local u=ui_scale or 1
  -- The narrower strip still needs a full-height, easily recognizable cap.
  local cap_scale=compact and math.max(1,u) or u
  local h=height or 140; local w=(compact and 28 or 34)*u
  if not (reaper.ImGui_GetCursorScreenPos and reaper.ImGui_GetWindowDrawList and reaper.ImGui_InvisibleButton) then
    if reaper.ImGui_VSliderDouble then return reaper.ImGui_VSliderDouble(ctx,id,42*u,h,value,min_db,max_db,'%.1f dB') end
    return false,value
  end
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx); local dl=reaper.ImGui_GetWindowDrawList(ctx)
  local cx=x+w/2
  local cap_h=math.min(h*0.55,math.min((compact and 48 or 52)*cap_scale,
    math.max(38*cap_scale,h*0.20)))
  local travel=math.max(1,h-cap_h)
  -- The reference fader's 0 dB resting point is about one third of the way
  -- down the slot. Use a curved dB scale instead of placing 0 dB near the top.
  local scale_curve=0.80
  local function value_fraction(v)
    return ((max_db-math.max(min_db,math.min(max_db,v)))/(max_db-min_db))^scale_curve
  end
  local function fraction_value(f)
    return max_db-(max_db-min_db)*math.max(0,math.min(1,f))^(1/scale_curve)
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
  local wheeled,next_value=controls.wheel(ctx,value,1,min_db,max_db)
  if wheeled then out,changed=next_value,true end
  reaper.ImGui_DrawList_AddRectFilled(dl,cx-u,y+4*u,cx+u,y+h-4*u,(theme.is_light and 0x747B83FF or 0x111315FF),u)
  for _,v in ipairs({-54,-42,-30,-18,-6,0}) do
    if v>=min_db and v<=max_db then
    local yy=pos(v)
    reaper.ImGui_DrawList_AddLine(dl,cx-3*u,yy,cx+3*u,yy,v==0 and 0x8C939866 or 0x555B6022,u)
    end
  end
  local capy=pos(out)
  local top,bottom=capy-cap_h/2,capy+cap_h/2
  local inset=compact and u<1 and u or 3*u
  local cap_l,cap_r=x+inset,x+w-inset
  -- Raised cap with dark shoulders and the narrow light-gray center grip.
  reaper.ImGui_DrawList_AddRectFilled(dl,cap_l+u,top+2*u,cap_r+u,bottom+2*u,0x090A0C55,5)
  reaper.ImGui_DrawList_AddRectFilled(dl,cap_l,top,cap_r,bottom,(theme.is_light and 0x858D96FF or 0x171A1DFF),5)
  reaper.ImGui_DrawList_AddRectFilled(dl,cap_l+u,top+u,cap_r-u,bottom-u,(theme.is_light and 0xD1D6DCFF or 0x55595BFF),4)
  reaper.ImGui_DrawList_AddRectFilled(dl,cap_l+2*u,top+2*u,cap_r-2*u,bottom-2*u,(theme.is_light and 0xBEC5CDFF or 0x414547FF),3)
  -- Quiet bevels on the shoulders and a recessed frame around the grip.
  reaper.ImGui_DrawList_AddLine(dl,cap_l+3*u,top+2*u,cap_r-3*u,top+2*u,0xADB3B58C,u)
  reaper.ImGui_DrawList_AddLine(dl,cap_l+2*u,top+4*u,cap_l+2*u,bottom-4*u,0x737A7D99,u)
  reaper.ImGui_DrawList_AddLine(dl,cap_r-2*u,top+4*u,cap_r-2*u,bottom-4*u,0x252A2CBB,u)
  reaper.ImGui_DrawList_AddLine(dl,cap_l+3*u,bottom-2*u,cap_r-3*u,bottom-2*u,0x252A2CFF,u)
  local g=cap_scale
  reaper.ImGui_DrawList_AddRectFilled(dl,cx-5*g,top+6*g,cx+5*g,bottom-6*g,(theme.is_light and 0x858D96FF or 0x292E31FF),3*g)
  reaper.ImGui_DrawList_AddRectFilled(dl,cx-4*g,top+7*g,cx+4*g,bottom-7*g,0xBEC4C6FF,2*g)
  if reaper.ImGui_DrawList_AddRectFilledMultiColor then
    reaper.ImGui_DrawList_AddRectFilledMultiColor(dl,cx-3*g,top+8*g,cx+3*g,bottom-8*g,
      0xCFD4D5FF,0xCFD4D5FF,0xA9B1B4FF,0xA9B1B4FF)
  end
  reaper.ImGui_DrawList_AddLine(dl,cx-2*g,top+7*g,cx+2*g,top+7*g,0xE5E8E9FF,g)
  reaper.ImGui_DrawList_AddLine(dl,cx+3*g,top+9*g,cx+3*g,bottom-9*g,0x9AA2A5FF,g)
  local groove_count=math.min(5,math.floor(math.max(0,cap_h/2-9*g)/(2*g)))
  for i=-groove_count,groove_count do
    local yy=capy+i*2*g
    local left,right=cx-3*g,cx+3*g
    if i==0 then
      reaper.ImGui_DrawList_AddLine(dl,left,yy,right,yy,0xE0E4E5FF,g)
    else
      reaper.ImGui_DrawList_AddLine(dl,left,yy,right,yy,0x747D80FF,0.65*g)
      reaper.ImGui_DrawList_AddLine(dl,left+0.5*g,yy+0.75*g,right-0.5*g,yy+0.75*g,0xD5DADBCC,0.65*g)
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
