local M = {}
local controls = require('ReaSpect.widgets.controls')

function M.native_to_rgb(c)
  c = tonumber(c) or 0
  if c == 0 then return 0.22,0.22,0.22 end
  -- Native byte order differs across platforms; strip the custom-color flag
  -- and let REAPER decode it rather than assuming Windows' layout.
  local r,g,b = reaper.ColorFromNative(c & 0xFFFFFF)
  return r/255,g/255,b/255
end
function M.rgb_to_native(r,g,b)
  local c = reaper.ColorToNative(math.floor(r*255+0.5), math.floor(g*255+0.5), math.floor(b*255+0.5))
  return c | 0x1000000
end

local function rgb_to_rgba(r,g,b)
  return (math.floor(r*255+0.5) << 24) | (math.floor(g*255+0.5) << 16) | (math.floor(b*255+0.5) << 8) | 0xFF
end
local function rgba_to_rgb(c)
  return ((c >> 24)&255)/255, ((c >> 16)&255)/255, ((c >> 8)&255)/255
end
function M.native_to_rgba(c)
  local r,g,b=M.native_to_rgb(c)
  return rgb_to_rgba(r,g,b)
end
function M.tint_rgba(c, factor)
  local r,g,b=M.native_to_rgb(c); factor=factor or 1
  return rgb_to_rgba(math.max(0,math.min(1,r*factor)),math.max(0,math.min(1,g*factor)),math.max(0,math.min(1,b*factor)))
end

local palette={0x6E747DFF,0xC94C4CFF,0xD47E3FFF,0xD2B34CFF,0x7BAE57FF,0x4A9B78FF,0x4D8FB8FF,0x6574C7FF,0x9167B5FF,0xB85E95FF,0x8B6655FF,0xB0B5BCFF,0x3B4048FF,0x8E3434FF,0x9E5E2CFF,0x8E772BFF,0x4D7E3BFF,0x347A61FF,0x356B8AFF,0x4A5797FF,0x69458AFF,0x7D3E65FF,0x68483BFF,0x6A7078FF}
local function choose(c,on_change)
  local r,g,b=rgba_to_rgb(c)
  on_change(M.rgb_to_native(r,g,b))
end

local function mouse_color(ctx,native,on_change)
  local choices={}
  for _,packed in ipairs(palette) do
    local r,g,b=rgba_to_rgb(packed)
    choices[#choices+1]=M.rgb_to_native(r,g,b)
  end
  local changed,out=controls.choice(ctx,native,choices,0)
  if changed then on_change(out) end
end

local function palette_popup(ctx,popup,packed,on_change)
  if not (reaper.ImGui_BeginPopup and reaper.ImGui_BeginPopup(ctx,popup)) then return end
  local flags=reaper.ImGui_ColorEditFlags_NoTooltip and reaper.ImGui_ColorEditFlags_NoTooltip() or 0
  for i,c in ipairs(palette) do
    if i>1 and ((i-1)%12)~=0 then reaper.ImGui_SameLine(ctx) end
    if reaper.ImGui_ColorButton(ctx,'##pal'..i,c,flags,18,18) then
      choose(c,on_change)
      if reaper.ImGui_CloseCurrentPopup then reaper.ImGui_CloseCurrentPopup(ctx) end
    end
  end
  if reaper.ImGui_Separator then reaper.ImGui_Separator(ctx) end
  if reaper.ImGui_ColorEdit3 then
    local changed,custom=reaper.ImGui_ColorEdit3(ctx,'Custom',packed)
    if changed and custom then choose(custom,on_change) end
  end
  reaper.ImGui_EndPopup(ctx)
end

function M.swatch(ctx, id, color, on_change)
  local r,g,b = M.native_to_rgb(color)
  local packed=rgb_to_rgba(r,g,b)
  local popup=id..'_palette'
  if reaper.ImGui_ColorButton then
    local flags=reaper.ImGui_ColorEditFlags_NoTooltip and reaper.ImGui_ColorEditFlags_NoTooltip() or 0
    if reaper.ImGui_ColorButton(ctx,id,packed,flags,20,16) and reaper.ImGui_OpenPopup then reaper.ImGui_OpenPopup(ctx,popup) end
    mouse_color(ctx,color,on_change)
    palette_popup(ctx,popup,packed,on_change)
  elseif reaper.ImGui_ColorEdit3 then
    local flags = reaper.ImGui_ColorEditFlags_NoInputs and reaper.ImGui_ColorEditFlags_NoInputs() or 0
    local changed, out = reaper.ImGui_ColorEdit3(ctx, id, packed, flags)
    if changed and out then local nr,ng,nb=rgba_to_rgb(out); on_change(M.rgb_to_native(nr,ng,nb)) end
  else
    reaper.ImGui_Text(ctx, '■')
  end
end

function M.strip(ctx,id,native,w,h,on_change,visible_w,tooltip)
  local r,g,b=M.native_to_rgb(native)
  local packed=rgb_to_rgba(r,g,b)
  local popup=id..'_palette'
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  local hit=reaper.ImGui_InvisibleButton(ctx,id,w,h)
  local hovered=reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx)
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  visible_w=math.min(w,visible_w or w)
  reaper.ImGui_DrawList_AddRectFilled(dl,x,y,x+visible_w,y+h,packed)
  if hovered and reaper.ImGui_DrawList_AddRect then
    reaper.ImGui_DrawList_AddRect(dl,x,y,x+visible_w,y+h,0xE7EBEECC,0,0,1)
  end
  if hovered and reaper.ImGui_SetTooltip then reaper.ImGui_SetTooltip(ctx,(tooltip or 'Click to change color')..'\nWheel: palette colors  •  Right-click: default color') end
  mouse_color(ctx,native,on_change)
  if hit and reaper.ImGui_OpenPopup then reaper.ImGui_OpenPopup(ctx,popup) end
  palette_popup(ctx,popup,packed,on_change)
end

return M
