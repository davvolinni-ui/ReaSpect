local theme = require('ReaSpect.core.theme')
local M = {levels={}}
local FLOOR, MIN_DB, MAX_DB = 0.00003, -60, 12

local function now() return reaper.time_precise and reaper.time_precise() or os.clock() end
local function db(v)
  if not v or v <= FLOOR then return -math.huge end
  return 20*math.log(v,10)
end
local function clamp_db(v)
  return math.max(MIN_DB,math.min(MAX_DB,v == -math.huge and MIN_DB or v))
end
local function fraction(v) return math.max(0,math.min(1,(v-MIN_DB)/(0-MIN_DB))) end
local function readout(v)
  if v <= MIN_DB then return '-inf' end
  return string.format('%+.1f',v)
end
local function mix_color(a,b,t)
  local function mix(shift)
    local ca=(a>>shift)&0xFF
    local cb=(b>>shift)&0xFF
    return math.floor(ca+(cb-ca)*t+0.5)
  end
  return (mix(24)<<24)|(mix(16)<<16)|(mix(8)<<8)|(a&0xFF)
end
local function update_channel(s,suffix,incoming,time,dt)
  local level_key,hold_key,until_key='level_'..suffix,'hold_'..suffix,'until_'..suffix
  local live=clamp_db(db(incoming))
  local level=math.max(live,(s[level_key] or MIN_DB)-dt*18)
  s[level_key]=level
  local held=s[hold_key] or MIN_DB
  if live>=held then
    held=live
    s[until_key]=time+1.5
  elseif time>=(s[until_key] or 0) then
    held=math.max(level,held-dt*9)
  end
  s[hold_key]=held
  return level,held
end

function M.draw(ctx,peak_l,peak_r,width,key,height,armed,track)
  key=key or 'default'
  local time=now()
  local s=M.levels[key] or {time=time}
  local dt=math.max(0,math.min(0.25,time-(s.time or time)))
  s.time=time
  local left,hold_l=update_channel(s,'l',peak_l,time,dt)
  local right,hold_r=update_channel(s,'r',peak_r,time,dt)
  local raw_l,raw_r=db(peak_l),db(peak_r)
  -- Native hold catches short overs that occur between ReaImGui frames.
  -- REAPER reports these values in hundredths of a dB.
  if track and reaper.Track_GetPeakHoldDB then
    raw_l=math.max(raw_l,(reaper.Track_GetPeakHoldDB(track,0,false) or -math.huge)*100)
    raw_r=math.max(raw_r,(reaper.Track_GetPeakHoldDB(track,1,false) or -math.huge)*100)
  end
  if raw_l>=0 then s.clip_l=math.max(s.clip_l or 0,raw_l) end
  if raw_r>=0 then s.clip_r=math.max(s.clip_r or 0,raw_r) end
  M.levels[key]=s

  local w,h=math.max(36,width or 50),height or 140
  if not (reaper.ImGui_GetWindowDrawList and reaper.ImGui_GetCursorScreenPos and reaper.ImGui_DrawList_AddRectFilled) then
    if reaper.ImGui_ProgressBar then
      reaper.ImGui_ProgressBar(ctx,fraction(left),w/2,h,'')
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_ProgressBar(ctx,fraction(right),w/2,h,'')
    end
    return
  end

  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  local top,bottom=y,y+h-2
  local bar_h=math.max(1,bottom-top)
  -- The reference keeps a dark headroom above the 0 dB line instead of
  -- mapping -6 dB immediately under the meter's upper edge.
  local scale_top=top+bar_h*0.18
  local gap=2
  local channel_w=(w-4-gap)/2
  local left_x,right_x=x+2,x+2+channel_w+gap
  local fill=armed and 0xD84B5FFF or theme.meter_color
  local fill_top=mix_color(fill,0xFFFFFFFF,0.27)
  local fill_bottom=mix_color(fill,0x000000FF,0.25)
  local hold_color=armed and 0xFFE5E8FF or 0xD8C7FFFF
  local function level_y(value) return bottom-fraction(value)*(bottom-scale_top) end
  local function draw_gradient(px,yy)
    if reaper.ImGui_DrawList_AddRectFilledMultiColor then
      reaper.ImGui_DrawList_AddRectFilledMultiColor(dl,px,yy,px+channel_w,bottom,
        fill_top,fill_top,fill_bottom,fill_bottom)
    else
      local segments=math.max(8,math.min(32,math.ceil((bottom-yy)/8)))
      for i=0,segments-1 do
        local y0=yy+(bottom-yy)*i/segments
        local y1=yy+(bottom-yy)*(i+1)/segments
        local color=mix_color(fill_top,fill_bottom,(i+0.5)/segments)
        reaper.ImGui_DrawList_AddRectFilled(dl,px,y0,px+channel_w,y1,color)
      end
    end
  end
  local function channel(px,value,held,clipped)
    reaper.ImGui_DrawList_AddRectFilled(dl,px,top,px+channel_w,bottom,0x101214FF,2)
    local yy=level_y(value)
    if yy<bottom then draw_gradient(px,yy) end
    if held>MIN_DB then
      local hy=math.max(top,level_y(held))
      reaper.ImGui_DrawList_AddLine(dl,px,hy,px+channel_w,hy,hold_color,2)
    end
    if clipped then reaper.ImGui_DrawList_AddRectFilled(dl,px,top,px+channel_w,top+3,0xF15962FF,1) end
  end
  channel(left_x,left,hold_l,s.clip_l)
  channel(right_x,right,hold_r,s.clip_r)

  local clipped=s.clip_l or s.clip_r
  local read_db=clipped and math.max(s.clip_l or 0,s.clip_r or 0) or math.max(hold_l,hold_r)
  local peak_text=readout(read_db)
  if reaper.ImGui_DrawList_AddText then
    local tw=reaper.ImGui_CalcTextSize and reaper.ImGui_CalcTextSize(ctx,peak_text) or #peak_text*7
    if clipped then
      reaper.ImGui_DrawList_AddRectFilled(dl,x+(w-tw)/2-3,y,x+(w+tw)/2+3,y+16,0xC84153FF,2)
    end
    local ink=clipped and 0xFFF1F2FF or (armed and 0xED9AA4FF or 0xBEB3D4FF)
    reaper.ImGui_DrawList_AddText(dl,x+(w-tw)/2,y+1,ink,peak_text)
  end
  for _,mark in ipairs({-6,-18,-30,-42,-54}) do
    local yy=level_y(mark)
    reaper.ImGui_DrawList_AddLine(dl,x+2,yy,x+w-2,yy,0xA5ADB14C,1)
    if reaper.ImGui_DrawList_AddText then
      local label=tostring(mark)
      local tw=reaper.ImGui_CalcTextSize and reaper.ImGui_CalcTextSize(ctx,label) or #label*7
      local tx=x+(w-tw)/2
      reaper.ImGui_DrawList_AddRectFilled(dl,tx-2,yy-7,tx+tw+2,yy+7,0x151719C8,2)
      reaper.ImGui_DrawList_AddText(dl,tx,yy-6,armed and 0xE85C62FF or 0x92999DFF,label)
    end
  end
  if reaper.ImGui_InvisibleButton then
    local clicked=reaper.ImGui_InvisibleButton(ctx,'##meter'..key,w,h)
    if clicked or reaper.ImGui_IsItemClicked(ctx,1) then
      if track and reaper.Track_GetPeakHoldDB then
        reaper.Track_GetPeakHoldDB(track,0,true)
        reaper.Track_GetPeakHoldDB(track,1,true)
      end
      s.clip_l,s.clip_r=nil,nil
      s.hold_l,s.hold_r=left,right
      s.until_l,s.until_r=time,time
    end
  else reaper.ImGui_Dummy(ctx,w,h) end
  if reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_SetTooltip then
    reaper.ImGui_SetTooltip(ctx,string.format('L %s dB   R %s dB\nPeak %s dB  •  Click or right-click to clear clip/hold',
      readout(left),readout(right),peak_text))
  end
end

return M
