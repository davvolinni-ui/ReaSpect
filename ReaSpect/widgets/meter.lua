local theme = require('ReaSpect.core.theme')
local M = {levels={}}
local FLOOR, MIN_DB, MAX_DB = 0.00003, -60, 12

local function now() return reaper.time_precise and reaper.time_precise() or os.clock() end
-- Native loudness values share Track_GetPeakInfo's linear meter interface.
-- REAPER performs the measurement; the inspector only renders its result.
function M.read_channels(track,peak_l,peak_r,armed)
  local mode=track and reaper.GetMediaTrackInfo_Value and math.floor(reaper.GetMediaTrackInfo_Value(track,'I_VUMODE') or 0) or 0
  if mode&1~=0 then return 0,0,'Disabled','dB',0,1,mode end
  local kind=mode&30
  if armed and kind>=4 then kind=0;mode=mode&(~30) end
  local labels={[4]='Stereo RMS',[8]='Combined RMS',[12]='LUFS-M',[16]='LUFS-S (maximum)',[20]='LUFS-S (current)'}
  if labels[kind] and reaper.Track_GetPeakInfo then
    return reaper.Track_GetPeakInfo(track,1024) or 0,reaper.Track_GetPeakInfo(track,1025) or 0,
      labels[kind],kind>=12 and 'LUFS' or 'dB RMS',1024,1025,mode
  end
  if kind==2 and reaper.Track_GetPeakInfo then
    local l,r=0,0
    local count=math.floor(reaper.GetMediaTrackInfo_Value(track,'I_NCHAN') or 2)
    for channel=0,count-1 do
      local peak=reaper.Track_GetPeakInfo(track,channel) or 0
      if channel%2==0 then l=math.max(l,peak) else r=math.max(r,peak) end
    end
    return l,r,'Multichannel peaks (odd/even channel maxima)','dB',0,1,mode
  end
  return peak_l,peak_r,'Stereo peaks','dB',0,1,mode
end
-- Show the strongest reported compressor reduction; never infer GR from peaks.
function M.read_gain_reduction(track)
  if not track or not (reaper.TrackFX_GetCount and reaper.TrackFX_GetNamedConfigParm) then return nil end
  if reaper.GetMediaTrackInfo_Value and reaper.GetMediaTrackInfo_Value(track,'I_FXEN')==0 then return nil end
  local reduction
  local visited={}
  local function scan(fx,depth)
    if depth>16 or visited[fx] then return end
    visited[fx]=true
    if reaper.TrackFX_GetEnabled and not reaper.TrackFX_GetEnabled(track,fx) then return end
    if reaper.TrackFX_GetOffline and reaper.TrackFX_GetOffline(track,fx) then return end
    local ok,value=reaper.TrackFX_GetNamedConfigParm(track,fx,'GainReduction_dB')
    local number=ok and tonumber(value)
    -- Cooperative JSFX expose an explicit readout; never guess from control names.
    if not number and reaper.TrackFX_GetNumParams and reaper.TrackFX_GetParamName and reaper.TrackFX_GetParam then
      local typed,kind=reaper.TrackFX_GetNamedConfigParm(track,fx,'fx_type')
      if typed and kind=='JS' then
        for param=0,reaper.TrackFX_GetNumParams(track,fx)-1 do
          local named,name=reaper.TrackFX_GetParamName(track,fx,param,'')
          if named and name:gsub('^%-','')=='ReaSpect GR Readout (dB)' then
            local reading,minimum,maximum=reaper.TrackFX_GetParam(track,fx,param)
            if minimum<0 and maximum==0 and reading>=minimum and reading<=0 then number=reading end
            break
          end
        end
      end
    end
    if number and number==number and math.abs(number)<math.huge then
      reduction=math.max(reduction or 0,math.abs(number))
    end
    local container,count=reaper.TrackFX_GetNamedConfigParm(track,fx,'container_count')
    for index=0,(container and tonumber(count) or 0)-1 do
      local found,child=reaper.TrackFX_GetNamedConfigParm(track,fx,'container_item.'..index)
      if found and tonumber(child) then scan(tonumber(child),depth+1) end
    end
  end
  for fx=0,reaper.TrackFX_GetCount(track)-1 do scan(fx,0) end
  return reduction
end
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

function M.draw(ctx,peak_l,peak_r,width,key,height,armed,track,ui_scale)
  local u=ui_scale or 1
  key=key or 'default'
  local time=now()
  local s=M.levels[key] or {time=time}
  local incoming_l,incoming_r,label,unit,channel_l,channel_r,mode=M.read_channels(track,peak_l,peak_r,armed)
  if s.mode~=mode then s={time=time,mode=mode} end
  local dt=math.max(0,math.min(0.25,time-(s.time or time)))
  s.time=time
  local left,hold_l=update_channel(s,'l',incoming_l,time,dt)
  local right,hold_r=update_channel(s,'r',incoming_r,time,dt)
  local raw_l,raw_r=db(peak_l),db(peak_r)
  -- Native hold catches short overs that occur between ReaImGui frames.
  -- REAPER reports these values in hundredths of a dB.
  if track and reaper.Track_GetPeakHoldDB then
    raw_l=math.max(raw_l,(reaper.Track_GetPeakHoldDB(track,0,false) or -math.huge)*100)
    raw_r=math.max(raw_r,(reaper.Track_GetPeakHoldDB(track,1,false) or -math.huge)*100)
  end
  if raw_l>=0 then s.clip_l=math.max(s.clip_l or 0,raw_l) end
  if raw_r>=0 then s.clip_r=math.max(s.clip_r or 0,raw_r) end
  if mode&1~=0 then s.clip_l,s.clip_r=nil,nil end
  M.levels[key]=s

  local w,h=math.max(36*u,width or 50*u),height or 140
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
  local top,bottom=y,y+h-2*u
  local bar_h=math.max(1,bottom-top)
  -- The reference keeps a dark headroom above the 0 dB line instead of
  -- mapping -6 dB immediately under the meter's upper edge.
  local scale_top=top+math.max(16*u,bar_h*0.08)
  local gap=2*u
  local channel_w=(w-4*u-gap)/2
  local left_x,right_x=x+2*u,x+2*u+channel_w+gap
  local fill=theme.meter_color
  -- Only unarmed meters use a gradient; armed levels use solid bands below.
  local fill_top=armed and 0xFFD13DFF or mix_color(fill,0xFFFFFFFF,0.27)
  local fill_bottom=armed and 0xA78A29FF or mix_color(fill,0x000000FF,0.25)
  local function level_color(value)
    if value>=-6 then
      if armed then return 0xED647AFF end
      return mix_color(mix_color(fill_bottom,fill_top,fraction(-6)),0xED647AFF,math.min(1,(value+6)/6))
    end
    if armed then return value>=-18 and 0xFFD13DFF or 0xA78A29FF end
    return mix_color(fill_bottom,fill_top,fraction(value))
  end
  local function level_y(value) return bottom-fraction(value)*(bottom-scale_top) end
  local function draw_gradient(px,yy)
    local gradient_top=mix_color(fill_bottom,fill_top,math.max(0,math.min(1,(bottom-yy)/(bottom-scale_top))))
    if reaper.ImGui_DrawList_AddRectFilledMultiColor then
      reaper.ImGui_DrawList_AddRectFilledMultiColor(dl,px,yy,px+channel_w,bottom,
        gradient_top,gradient_top,fill_bottom,fill_bottom)
    else
      local segments=math.max(8,math.min(32,math.ceil((bottom-yy)/8)))
      for i=0,segments-1 do
        local y0=yy+(bottom-yy)*i/segments
        local y1=yy+(bottom-yy)*(i+1)/segments
        local color=mix_color(gradient_top,fill_bottom,(i+0.5)/segments)
        reaper.ImGui_DrawList_AddRectFilled(dl,px,y0,px+channel_w,y1,color)
      end
    end
  end
  local function channel(px,value,held,clipped)
    reaper.ImGui_DrawList_AddRectFilled(dl,px,top,px+channel_w,bottom,(theme.is_light and 0xDDE0E3FF or 0x202225FF),1)
    local yy=level_y(value)
    if armed then
      -- Three solid level ranges: gold below -18, yellow to -6, red above -6.
      for _,band in ipairs({{-60,-18,0xA78A29FF},{-18,-6,0xFFD13DFF},{-6,0,0xED647AFF}}) do
        local band_top=math.max(yy,level_y(band[2]))
        local band_bottom=level_y(band[1])
        if band_top<band_bottom then
          reaper.ImGui_DrawList_AddRectFilled(dl,px,band_top,px+channel_w,band_bottom,band[3])
        end
      end
    elseif yy<bottom then
      draw_gradient(px,yy)
      local warning_bottom=level_y(-6)
      if yy<warning_bottom then
        local warning_top=level_color(value)
        local warning_base=level_color(-6)
        if reaper.ImGui_DrawList_AddRectFilledMultiColor then
          reaper.ImGui_DrawList_AddRectFilledMultiColor(dl,px,yy,px+channel_w,warning_bottom,
            warning_top,warning_top,warning_base,warning_base)
        else
          for i=0,7 do
            reaper.ImGui_DrawList_AddRectFilled(dl,px,yy+(warning_bottom-yy)*i/8,
              px+channel_w,yy+(warning_bottom-yy)*(i+1)/8,mix_color(warning_top,warning_base,(i+.5)/8))
          end
        end
      end
    end
    if held>MIN_DB then
      local hy=math.max(top,level_y(held))
      reaper.ImGui_DrawList_AddLine(dl,px,hy,px+channel_w,hy,level_color(held),2*u)
    end
    if clipped then reaper.ImGui_DrawList_AddRectFilled(dl,px,top,px+channel_w,top+3*u,0xF15962FF,u) end
  end
  channel(left_x,left,hold_l,s.clip_l)
  channel(right_x,right,hold_r,s.clip_r)

  local clipped=s.clip_l or s.clip_r
  local loudness=channel_l==1024
  local read_db=not loudness and clipped and math.max(s.clip_l or 0,s.clip_r or 0) or math.max(hold_l,hold_r)
  if loudness then
    if mode&30==20 then read_db=math.max(db(incoming_l),db(incoming_r))
    elseif reaper.Track_GetPeakHoldDB then
      read_db=math.max(reaper.Track_GetPeakHoldDB(track,channel_l,false)*100,
        reaper.Track_GetPeakHoldDB(track,channel_r,false)*100)
    end
  end
  local peak_text=readout(read_db)
  if reaper.ImGui_DrawList_AddText then
    local tw=reaper.ImGui_CalcTextSize and reaper.ImGui_CalcTextSize(ctx,peak_text) or #peak_text*7
    if clipped then
      reaper.ImGui_DrawList_AddRectFilled(dl,left_x,top,right_x+channel_w,scale_top,0xC84153FF)
    end
    local ink=clipped and 0xFFF1F2FF or (theme.is_light and 0x50555AFF or 0x929699FF)
    reaper.ImGui_DrawList_AddText(dl,x+(w-tw)/2,top+(scale_top-top-12*u)/2,ink,peak_text)
  end
  for _,mark in ipairs({-6,-18,-30,-42,-54}) do
    local yy=level_y(mark)
    if reaper.ImGui_DrawList_AddText then
      local label=tostring(mark)
      local tw=reaper.ImGui_CalcTextSize and reaper.ImGui_CalcTextSize(ctx,label) or #label*7
      local tx=x+(w-tw)/2
      local filled=mark<=math.max(left,right)
      local scale_ink=filled and 0x302A38FF or (armed and (theme.is_light and 0xA42F1AFF or 0xFF4B18FF) or (theme.is_light and 0x50555AFF or 0x777D81FF))
      reaper.ImGui_DrawList_AddText(dl,tx,yy-6*u,scale_ink,label)
    end
  end
  if reaper.ImGui_InvisibleButton then
    local clicked=reaper.ImGui_InvisibleButton(ctx,'##meter'..key,w,h)
    if clicked or reaper.ImGui_IsItemClicked(ctx,1) then
      if track and reaper.Track_GetPeakHoldDB then
        reaper.Track_GetPeakHoldDB(track,0,true)
        reaper.Track_GetPeakHoldDB(track,1,true)
        if loudness then
          reaper.Track_GetPeakHoldDB(track,channel_l,true)
          reaper.Track_GetPeakHoldDB(track,channel_r,true)
        end
      end
      s.clip_l,s.clip_r=nil,nil
      s.hold_l,s.hold_r=left,right
      s.until_l,s.until_r=time,time
    end
  else reaper.ImGui_Dummy(ctx,w,h) end
  if reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_SetTooltip then
    reaper.ImGui_SetTooltip(ctx,string.format('%s\nL %s %s   R %s %s\n%s %s  •  Click or right-click to clear clip/hold',
      label,readout(left),unit,readout(right),unit,peak_text,unit)
)
  end
end

function M.draw_gain_reduction(ctx,reduction,width,height,key,ui_scale)
  local u=ui_scale or 1
  local w,h=width or 10*u,height or 140
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  local top,bottom=y+(h-2*u)*.08,y+h-2*u
  local background=theme.is_light and 0xDDE0E3FF or 0x202225FF
  local ink=theme.is_light and 0x50555AFF or 0xB7BDC3FF
  reaper.ImGui_DrawList_AddRectFilled(dl,x+u,top,x+w-u,bottom,background,1)
  if reduction and reduction>0 then
    reaper.ImGui_DrawList_AddRectFilled(dl,x+u,top,x+w-u,
      top+math.min(1,reduction/24)*(bottom-top),0xF2D13DFF)
  end
  if reaper.ImGui_DrawList_AddLine then
    for _,mark in ipairs({6,12,18,24}) do
      local yy=top+mark/24*(bottom-top)
      reaper.ImGui_DrawList_AddLine(dl,x,yy,x+2*u,yy,ink,u)
    end
  end
  if reaper.ImGui_InvisibleButton then reaper.ImGui_InvisibleButton(ctx,'##gr'..(key or ''),w,h)
  else reaper.ImGui_Dummy(ctx,w,h) end
  if reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_SetTooltip then
    reaper.ImGui_SetTooltip(ctx,reduction and string.format('Gain reduction %.1f dB\nStrongest reported enabled FX; scale 0–24 dB',reduction)
      or 'Gain reduction unavailable: no enabled FX reports it')
  end
end

return M
