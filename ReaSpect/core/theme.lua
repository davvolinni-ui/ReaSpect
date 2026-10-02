local persist = require('ReaSpect.core.persistence')
local M = {editor_open=false,suggestions={},is_light=false}
local defaults={window=0x17191CFF,panel=0x1D2024FF,frame=0x292C30FF,text=0xD4D7DBFF,accent=0xC6A4F3FF,gold=0xE5B84DFF,meter=0x7859C9FF,border=0x454A50FF,route_parent=0xC6A4F3FF,route_send=0xF2C43DFF,route_receive=0xEA5264FF}
local keys={'window','panel','frame','text','accent','gold','meter','border','route_parent','route_send','route_receive'}
local labels={window='Window Background',panel='Panel Background',frame='Control Surface',text='Normal Text',accent='Accent / Negative Width',gold='Width / Send Accent',meter='Meter',border='Borders',route_parent='Parent Routing / Accent',route_send='Send Routing / Yellow',route_receive='Receive Routing / Red'}
M.colors={}
M.accent_color = defaults.accent
M.meter_color = defaults.meter
-- ReaperTips-style routing stripes.  Keep their meanings independent of the
-- colors so a theme can change the palette without changing the feedback.
M.routing_colors = {
  parent = defaults.accent,
  send = defaults.route_send,
  receive = defaults.route_receive,
  inactive = 0x666A6DFF,
}
local function copy(source) local out={} for k,v in pairs(source) do out[k]=v end return out end
local function blend(a,b,t)
  local function part(shift) return math.floor((((a>>shift)&255)*(1-t)+((b>>shift)&255)*t)+.5) end
  return (part(24)<<24)|(part(16)<<16)|(part(8)<<8)|255
end
local function luminance(c)
  local r,g,b=(c>>24)&255,(c>>16)&255,(c>>8)&255
  return r*.299+g*.587+b*.114
end
local function ensure_contrast(fg,bg,min_gap)
  if math.abs(luminance(fg)-luminance(bg))>=min_gap then return fg end
  local target=luminance(bg)>=128 and 0x101215FF or 0xF4F5F7FF
  for i=1,64 do
    local candidate=blend(fg,target,i/64)
    if math.abs(luminance(candidate)-luminance(bg))>=min_gap then return candidate end
  end
  return target
end
-- Section titles share one readable accent treatment across custom themes.
function M.heading_colors()
  local c=M.colors
  local accent=c.accent or defaults.accent
  local background=blend(c.frame or defaults.frame,accent,.12)
  return ensure_contrast(accent,background,100),background,blend(background,accent,.16)
end
local function guard_light_palette(c)
  if not M.is_light then return false end
  local changed=false
  local function guard(key,min_gap)
    local adjusted=ensure_contrast(c[key],c.panel or c.window,min_gap)
    if adjusted~=c[key] then c[key]=adjusted;changed=true end
  end
  guard('text',112);guard('frame',28);guard('border',46)
  guard('accent',42);guard('gold',42);guard('meter',42)
  guard('route_parent',42);guard('route_send',42);guard('route_receive',42)
  return changed
end
local function chroma(c)
  local r,g,b=(c>>24)&255,(c>>16)&255,(c>>8)&255
  return math.max(r,g,b)-math.min(r,g,b)
end
local function native(key)
  if not (reaper.GetThemeColor and reaper.ColorFromNative) then return nil end
  local ok,n=pcall(reaper.GetThemeColor,key,0)
  if not ok or not n or n==-1 then return nil end
  local r,g,b=reaper.ColorFromNative(n&0xFFFFFF)
  if not r then return nil end
  return (r<<24)|(g<<16)|(b<<8)|255
end
local function save()
  for _,key in ipairs(keys) do persist.set('theme_'..key,M.colors[key]) end
  M.accent_color=M.colors.accent;M.meter_color=M.colors.meter
  M.routing_colors.parent=M.colors.route_parent
  M.routing_colors.send=M.colors.route_send
  M.routing_colors.receive=M.colors.route_receive
end
function M.import(mode)
  local main=native('col_main_bg2') or defaults.window
  local r,g,b=(main>>24)&255,(main>>16)&255,(main>>8)&255
  local light=mode=='light' or (mode=='auto' and r*.299+g*.587+b*.114>=145)
  M.colors=copy(defaults)
  local c=M.colors
  c.window=light and blend(main,0xE3E5E8FF,.82) or blend(main,0x101215FF,.55)
  c.panel=light and blend(c.window,0xFFFFFFFF,.24) or blend(c.window,0x343A40FF,.22)
  M.is_light=light
  c.frame=light and blend(c.panel,0x000000FF,.12) or blend(c.panel,0xFFFFFFFF,.08)
  c.text=light and 0x202327FF or 0xE2E5E8FF
  c.accent=blend(native('genlist_selbg') or defaults.accent,0xFFFFFFFF,.36)
  c.gold=native('col_toolbar_text_on') or defaults.gold
  c.meter=blend(c.accent,defaults.meter,.45)
  c.border=native('col_toolbar_frame') or defaults.border
  -- Routing stripes carry state, not decoration.  REAPER's timeline and
  -- toolbar colors are often near-grey, making an active stripe look off.
  c.route_parent=c.accent
  c.route_send=defaults.route_send
  c.route_receive=defaults.route_receive
  guard_light_palette(c)
  M.suggestions={}
  local source={window={'col_main_bg','genlist_bg'},panel={'genlist_bg','col_tracklistbg'},frame={'col_toolbar_frame'},text={'genlist_fg','col_main_text'},accent={'genlist_selbg','col_toolbar_text_on'},gold={'col_toolbar_text_on','col_tl_bgsel2'},meter={'genlist_selbg','col_tl_bgsel2'},border={'col_toolbar_frame','col_main_3dsh'},route_parent={'col_tl_bgsel2','genlist_selbg'},route_send={'col_toolbar_text_on','genlist_selbg'},route_receive={'genlist_selbg','col_toolbar_text_on'}}
  for key,list in pairs(source) do
    local choices={};for _,name in ipairs(list) do local color=native(name);if color then choices[#choices+1]={name=name,color=color} end end
    M.suggestions[key]=choices
  end
  save()
  persist.set('accent_palette_version',1)
  persist.set('routing_palette_version',2)
end
function M.reset(light)
  M.colors=copy(defaults)
  if light then M.colors.window=0xE3E5E8FF;M.colors.panel=0xF2F3F5FF;M.colors.frame=0xD8DBDFFF;M.colors.text=0x202327FF;M.colors.border=0xA9AFB6FF end
  M.is_light=not not light
  guard_light_palette(M.colors)
  M.suggestions={};save()
  persist.set('accent_palette_version',1)
  persist.set('routing_palette_version',2)
end
local function load()
  if M.loaded then return end
  M.loaded=true
  if persist.get('theme_window',nil)==nil then M.import('auto');return end
  for _,key in ipairs(keys) do M.colors[key]=persist.get_num('theme_'..key,defaults[key]) end
  M.is_light=luminance(M.colors.panel or M.colors.window or defaults.panel)>=145
  local changed=false
  if persist.get_num('accent_palette_version',0)<1 then
    M.colors.accent=blend(M.colors.accent,0xFFFFFFFF,.14)
    M.colors.route_parent=M.colors.accent
    persist.set('accent_palette_version',1)
    changed=true
  end
  local routing_version=persist.get_num('routing_palette_version',0)
  if routing_version<1 then
    for _,key in ipairs({'route_parent','route_send','route_receive'}) do
      if chroma(M.colors[key])<32 then M.colors[key]=defaults[key];changed=true end
    end
    routing_version=1
  end
  if routing_version<2 then
    M.colors.route_parent=M.colors.accent
    M.colors.route_send=defaults.route_send
    M.colors.route_receive=defaults.route_receive
    changed=true
    routing_version=2
  end
  if guard_light_palette(M.colors) then changed=true end
  persist.set('routing_palette_version',routing_version)
  if changed then save() end
  persist.set('accent_palette_version',1)
  M.accent_color=M.colors.accent;M.meter_color=M.colors.meter
  M.routing_colors.parent=M.colors.route_parent
  M.routing_colors.send=M.colors.route_send
  M.routing_colors.receive=M.colors.route_receive
end
local function to_widget(c) return ((c&255)<<24)|((c>>8)&0xFFFFFF) end
local function from_widget(c) return ((c&0xFFFFFF)<<8)|((c>>24)&255) end
local function draw_editor_contents(ctx)
  reaper.ImGui_TextDisabled(ctx,'Import from the current REAPER theme')
  if reaper.ImGui_Button(ctx,'Auto Detect') then M.import('auto') end
  reaper.ImGui_SameLine(ctx);if reaper.ImGui_Button(ctx,'Import Dark') then M.import('dark') end
  reaper.ImGui_SameLine(ctx);if reaper.ImGui_Button(ctx,'Import Light') then M.import('light') end
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_SetCursorPosX(ctx,215);reaper.ImGui_TextDisabled(ctx,'Active')
  reaper.ImGui_SameLine(ctx,290);reaper.ImGui_TextDisabled(ctx,'Alternates')
  local flags=(reaper.ImGui_ColorEditFlags_NoAlpha and reaper.ImGui_ColorEditFlags_NoAlpha() or 0)
    |(reaper.ImGui_ColorEditFlags_NoInputs and reaper.ImGui_ColorEditFlags_NoInputs() or 0)
    |(reaper.ImGui_ColorEditFlags_NoOptions and reaper.ImGui_ColorEditFlags_NoOptions() or 0)
  for _,key in ipairs(keys) do
    reaper.ImGui_Text(ctx,labels[key]);reaper.ImGui_SameLine(ctx,215)
    if reaper.ImGui_SetNextItemWidth then reaper.ImGui_SetNextItemWidth(ctx,22) end
    local changed,value=reaper.ImGui_ColorEdit4(ctx,'##theme_'..key,to_widget(M.colors[key]),flags)
    if changed then
      M.colors[key]=from_widget(value)
      if key=='accent' then M.colors.route_parent=M.colors.accent
      elseif key=='gold' then M.colors.route_send=M.colors.gold end
      if key=='window' or key=='panel' then M.is_light=luminance(M.colors.panel or M.colors.window or defaults.panel)>=145 end
      guard_light_palette(M.colors)
      save()
    end
    for i,choice in ipairs((M.suggestions or {})[key] or {}) do
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_ColorButton(ctx,'##choice_'..key..i,to_widget(choice.color),flags,18,18) then
        M.colors[key]=key=='accent' and blend(choice.color,0xFFFFFFFF,.36) or choice.color
        if key=='accent' then M.colors.route_parent=M.colors.accent
        elseif key=='gold' then M.colors.route_send=M.colors.gold end
        if key=='window' or key=='panel' then M.is_light=luminance(M.colors.panel or M.colors.window or defaults.panel)>=145 end
        guard_light_palette(M.colors)
        save()
      end
      if reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx,choice.name) end
    end
  end
  reaper.ImGui_Separator(ctx)
  if reaper.ImGui_Button(ctx,'Reset Dark') then M.reset(false) end
  reaper.ImGui_SameLine(ctx);if reaper.ImGui_Button(ctx,'Reset Light') then M.reset(true) end
end
function M.draw_editor(ctx)
  if not M.editor_open then return end
  load()
  if reaper.ImGui_SetNextWindowSize and reaper.ImGui_Cond_FirstUseEver then reaper.ImGui_SetNextWindowSize(ctx,520,480,reaper.ImGui_Cond_FirstUseEver()) end
  local visible,open=reaper.ImGui_Begin(ctx,'ReaSpect / Theme',true)
  M.editor_open=open
  if not visible then return end
  local ok,err=pcall(draw_editor_contents,ctx)
  reaper.ImGui_End(ctx)
  if not ok then
    M.editor_open=false
    if reaper.ShowConsoleMsg then reaper.ShowConsoleMsg('ReaSpect theme editor: '..tostring(err)..'\n') end
  end
end
function M.apply(ctx)
  load()
  local push = reaper.ImGui_PushStyleColor
  if not push then M.count=0; return end
  local function C(name) local f=reaper['ImGui_Col_'..name]; return f and f() end
  if not C('WindowBg') then M.count=0; return end
  local c=M.colors
  push(ctx,C('WindowBg'),c.window);push(ctx,C('ChildBg'),c.panel);push(ctx,C('FrameBg'),c.frame)
  push(ctx,C('FrameBgHovered'),blend(c.frame,c.text,.12));push(ctx,C('FrameBgActive'),blend(c.frame,c.text,.20));push(ctx,C('Button'),c.frame)
  push(ctx,C('ButtonHovered'),blend(c.frame,c.text,.16));push(ctx,C('ButtonActive'),blend(c.frame,c.accent,.30));push(ctx,C('Header'),c.frame)
  push(ctx,C('HeaderHovered'),blend(c.frame,c.text,.16));push(ctx,C('Separator'),c.border);push(ctx,C('Border'),c.border);push(ctx,C('Text'),c.text)
  push(ctx,C('TextDisabled'),M.is_light and blend(c.text,c.panel,.36) or blend(c.text,c.window,.52))
  M.count=14
  M.vars=0
  if reaper.ImGui_PushStyleVar then
    local sv=reaper.ImGui_StyleVar_ScrollbarSize
    if sv then reaper.ImGui_PushStyleVar(ctx,sv(),5); M.vars=M.vars+1 end
    local fp=reaper.ImGui_StyleVar_FramePadding
    if fp then reaper.ImGui_PushStyleVar(ctx,fp(),3,2); M.vars=M.vars+1 end
    local fb=reaper.ImGui_StyleVar_FrameBorderSize
    if M.is_light and fb then reaper.ImGui_PushStyleVar(ctx,fb(),1);M.vars=M.vars+1 end
    local fr=reaper.ImGui_StyleVar_FrameRounding
    if fr then reaper.ImGui_PushStyleVar(ctx,fr(),4);M.vars=M.vars+1 end
    local spacing=reaper.ImGui_StyleVar_ItemSpacing
    if spacing then reaper.ImGui_PushStyleVar(ctx,spacing(),4,2);M.vars=M.vars+1 end
  end
end
function M.pop(ctx)
  if reaper.ImGui_PopStyleVar and (M.vars or 0)>0 then reaper.ImGui_PopStyleVar(ctx,M.vars) end
  if reaper.ImGui_PopStyleColor and (M.count or 0)>0 then reaper.ImGui_PopStyleColor(ctx, M.count) end
  M.count=0; M.vars=0
end
return M
