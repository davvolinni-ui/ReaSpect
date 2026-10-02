-- ReaSpect: a narrow, context-sensitive REAPER inspector.
-- Requires REAPER 6.8+ and ReaImGui.
local source = debug.getinfo(1,'S').source:sub(2)
local root = source:match('^(.*)[\\/]') or '.'
package.path = root..'/?.lua;'..root..'/?/init.lua;'..package.path

local state = require('ReaSpect.core.state')
local theme = require('ReaSpect.core.theme')
local undo = require('ReaSpect.core.undo')
local controls = require('ReaSpect.widgets.controls')
local track_panel = require('ReaSpect.panels.track')
local item_panel = require('ReaSpect.panels.item')
local channel_panel = require('ReaSpect.panels.channel')
local rack = require('ReaSpect.widgets.rack')
local item_actions = require('ReaSpect.core.item_actions')
local track_actions = require('ReaSpect.core.track_actions')
local fx_parameters = require('ReaSpect.widgets.fx_parameters')
local native_ui = require('ReaSpect.core.native_ui')
local diagnostics = require('ReaSpect.core.diagnostics')

if not reaper.ImGui_CreateContext then
  reaper.ShowMessageBox('ReaSpect requires the ReaImGui extension.', 'ReaSpect', 0)
  return
end

-- Enable local diagnostics explicitly through ReaSpect's persistent ExtState.
local persistence = require('ReaSpect.core.persistence')
diagnostics.configure(persistence.get_bool('diagnostics_enabled',false) and (root..'/ReaSpect-diagnostics.log') or nil)
local ctx = reaper.ImGui_CreateContext('ReaSpect')
local brand_font
if reaper.ImGui_CreateFont then
  local bold=reaper.ImGui_FontFlags_Bold and reaper.ImGui_FontFlags_Bold() or 0
  local ok,font=pcall(reaper.ImGui_CreateFont,'Segoe UI',bold)
  if ok then brand_font=font end
end
local running = true
local dragging = nil
local function flag(name) local f=reaper['ImGui_WindowFlags_'..name]; return f and f() or 0 end
local window_flags = flag('NoScrollbar') + flag('NoScrollWithMouse')
-- A short dock uses a compact selected-track strip.  At widths too narrow for
-- the side rack, its FX control stays on the strip instead of being clipped.
local channel_child_flags = 0

local function finish_edits()
  undo.flush_gestures()
  -- The rack may have been hidden/collapsed since the drag began, so its own
  -- draw function is not guaranteed to see the mouse release.
  if rack.fx_toggle_drag then
    local changed=rack.fx_toggle_drag.changed
    rack.fx_toggle_drag=nil
    undo.finish('Set FX enable state')
    if changed and reaper.UpdateArrange then reaper.UpdateArrange() end
  end
end

local function panel_button(key)
  local active = state.panels[key]
  local palette=theme.colors
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  local hit=reaper.ImGui_InvisibleButton(ctx,'##panel_'..key,25,24)
  local reverse=key=='channel' and reaper.ImGui_IsItemClicked and reaper.ImGui_IsItemClicked(ctx,1)
  local hovered=reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx)
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  reaper.ImGui_DrawList_AddRectFilled(dl,x,y,x+25,y+24,active and (palette.border or 0x4A525AFF) or (hovered and (palette.frame or 0x373D43FF) or (palette.panel or 0x292C30FF)),3)
  -- Borders are intentionally subdued; using them for inactive glyphs makes
  -- the toolbar icons nearly disappear. Normal text stays legible and adapts
  -- to both dark and light imported themes.
  local ink=active and (palette.accent or 0xC6A4F3FF) or (palette.text or 0xBFC4C8FF)
  if key=='track' then
    for i=0,2 do
      local yy=y+6+i*6
      reaper.ImGui_DrawList_AddLine(dl,x+5,yy,x+20,yy,ink,1)
      reaper.ImGui_DrawList_AddCircleFilled(dl,x+8+i*4,yy,2,ink)
    end
  elseif key=='item' then
    reaper.ImGui_DrawList_AddRect(dl,x+5,y+5,x+20,y+19,ink,2,0,1.4)
    reaper.ImGui_DrawList_AddLine(dl,x+8,y+15,x+11,y+9,ink,1.4)
    reaper.ImGui_DrawList_AddLine(dl,x+11,y+9,x+15,y+13,ink,1.4)
    reaper.ImGui_DrawList_AddLine(dl,x+15,y+13,x+18,y+8,ink,1.4)
  elseif key=='channel' and active and state.channel_rack_only then
    for i=0,2 do
      reaper.ImGui_DrawList_AddRect(dl,x+5,y+5+i*5,x+20,y+8+i*5,ink,1,0,1)
    end
  else
    reaper.ImGui_DrawList_AddLine(dl,x+8,y+5,x+8,y+19,ink,1.4)
    reaper.ImGui_DrawList_AddLine(dl,x+17,y+5,x+17,y+19,ink,1.4)
    reaper.ImGui_DrawList_AddRectFilled(dl,x+5,y+9,x+11,y+13,ink,1)
    reaper.ImGui_DrawList_AddRectFilled(dl,x+14,y+14,x+20,y+18,ink,1)
  end
  if reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_SetTooltip then
    local tips={track='Track / Context',item='Item / Event',channel='Channel'}
    local tip=tips[key] or key
    if key=='channel' then
      tip=not active and 'Channel hidden — click for mixer + FX / Sends'
        or (state.channel_rack_only and 'FX / Sends only — click to hide Channel'
          or 'Mixer + FX / Sends — click for FX / Sends only')
      tip=tip..'\nRight-click: cycle backwards'
    end
    reaper.ImGui_SetTooltip(ctx,tip)
  end
  if hit or reverse then
    if key=='channel' then undo.flush_gestures();state.cycle_channel(reverse)
    else state.set_panel(key,not active) end
  end
end

local function theme_button()
  local palette=theme.colors
  local active=theme.editor_open
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  local hit=reaper.ImGui_InvisibleButton(ctx,'##theme_editor_button',25,24)
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  local hovered=reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx)
  reaper.ImGui_DrawList_AddRectFilled(dl,x,y,x+25,y+24,(active or hovered) and (palette.frame or 0x373D43FF) or (palette.panel or 0x292C30FF),3)
  reaper.ImGui_DrawList_AddCircle(dl,x+12,y+12,7,active and (palette.accent or 0xC6A4F3FF) or (palette.text or 0xD7D9DBFF),0,1.5)
  for i=0,2 do
    local a=i*2.1
    local dots=active and {palette.accent or 0xC6A4F3FF} or {palette.gold or 0xE5B84DFF,palette.accent or 0xC6A4F3FF,palette.route_receive or 0xEA5264FF}
    reaper.ImGui_DrawList_AddCircleFilled(dl,x+12+math.cos(a)*4,y+12+math.sin(a)*4,1.4,dots[active and 1 or i+1])
  end
  if hovered then reaper.ImGui_SetTooltip(ctx,'ReaSpect theme editor') end
  if hit then theme.editor_open=true end
end

local function brand_ink()
  local bg=theme.colors.window
  if bg then
    local r,g,b=(bg>>24)&255,(bg>>16)&255,(bg>>8)&255
    if r*0.299+g*0.587+b*0.114<145 then return 0xF4F5F7FF end
  end
  return theme.colors.text or 0x202327FF
end

local function brand_mark(size)
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  local palette=theme.colors
  local accent=palette.accent or 0xC6A4F3FF
  local ink=brand_ink()
  reaper.ImGui_Dummy(ctx,size,size)
  reaper.ImGui_DrawList_AddRectFilled(dl,x,y+1,x+size,y+size-1,palette.panel or 0x1D2024FF,4)
  if reaper.ImGui_DrawList_AddRect then
    reaper.ImGui_DrawList_AddRect(dl,x,y+1,x+size,y+size-1,(accent&0xFFFFFF00)|0xB0,4,0,1)
  end
  local levels={0.34,0.62,0.9,0.58,0.3}
  local bar_w=math.max(1.5,size*0.09)
  local start=x+size*0.19
  local step=size*0.145
  for i,level in ipairs(levels) do
    local h=size*level*0.58
    local bx=start+(i-1)*step
    local col=i==3 and ink or accent
    reaper.ImGui_DrawList_AddRectFilled(dl,bx,y+(size-h)*0.5,bx+bar_w,y+(size+h)*0.5,col,1)
  end
end

local function brand_wordmark()
  local available=reaper.ImGui_GetContentRegionAvail(ctx) or 280
  local _,row_y=reaper.ImGui_GetCursorScreenPos(ctx)
  local compact=available<248
  local font_size=compact and 17 or 20
  local mark_size=available>=220 and (compact and 20 or 24) or nil
  if mark_size then
    brand_mark(mark_size)
    reaper.ImGui_SameLine(ctx,0,compact and 5 or 8)
  end
  local pushed=false
  if reaper.ImGui_PushFont then
    pushed=pcall(reaper.ImGui_PushFont,ctx,brand_font,font_size)
  end
  if reaper.ImGui_CalcTextSize and reaper.ImGui_DrawList_AddText then
    local text_x=reaper.ImGui_GetCursorScreenPos(ctx)
    local rea_w,rea_h=reaper.ImGui_CalcTextSize(ctx,'Rea')
    local spect_w,spect_h=reaper.ImGui_CalcTextSize(ctx,'Spect')
    local text_h=math.max(rea_h or 0,spect_h or 0)
    local row_h=mark_size or 24
    local text_y=row_y+(row_h-text_h)*0.5
    local dl=reaper.ImGui_GetWindowDrawList(ctx)
    reaper.ImGui_DrawList_AddText(dl,text_x,text_y,brand_ink(),'Rea')
    reaper.ImGui_DrawList_AddText(dl,text_x+(rea_w or 0),text_y,theme.colors.accent or 0xC6A4F3FF,'Spect')
    reaper.ImGui_Dummy(ctx,(rea_w or 0)+(spect_w or 0),text_h)
  else
    reaper.ImGui_Text(ctx,'ReaSpect')
  end
  if pushed and reaper.ImGui_PopFont then reaper.ImGui_PopFont(ctx) end
end

local function splitter(index, visible, available)
  if not reaper.ImGui_InvisibleButton then return end
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  local region_w=reaper.ImGui_GetContentRegionAvail(ctx) or 0
  reaper.ImGui_InvisibleButton(ctx,'##split'..index,-1,6)
  local active=reaper.ImGui_IsItemActive and reaper.ImGui_IsItemActive(ctx)
  local hovered=reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx)
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  if dl and reaper.ImGui_DrawList_AddRectFilled then
    local handle_w,handle_h=34,4
    local hx=x+math.max(0,(region_w-handle_w)/2)
    local handle=active and 0xD9DDE0FF or (hovered and 0xC5CACDFF or 0xA6ADB1FF)
    reaper.ImGui_DrawList_AddRectFilled(dl,hx+1,y+2,hx+handle_w+1,y+2+handle_h,0x111416AA,3)
    reaper.ImGui_DrawList_AddRectFilled(dl,hx,y+1,hx+handle_w,y+1+handle_h,handle,3)
  end
  if hovered and reaper.ImGui_SetTooltip then reaper.ImGui_SetTooltip(ctx,'Drag to resize panels') end
  if active and reaper.ImGui_GetMouseDelta then
    local _,dy = reaper.ImGui_GetMouseDelta(ctx)
    local a,b = visible[index],visible[index+1]
    local total = state.heights[a]+state.heights[b]
    local delta = dy / math.max(1,available)
    local na = math.max(0.12,math.min(total-0.12,state.heights[a]+delta))
    state.heights[a], state.heights[b] = na, total-na
    dragging = index
  elseif dragging == index then
    state.set_height(visible[index],state.heights[visible[index]])
    state.set_height(visible[index+1],state.heights[visible[index+1]])
    dragging=nil
  end
end

local function draw_panel(name, height, draw)
  -- ReaImGui expects numeric child flags here (not the legacy boolean border argument).
  local child_flags = 0
  local fixed_header=name=='track' or name=='item'
  local child_window_flags = controls.scroll_flags(fixed_header and flag('NoScrollbar') or channel_child_flags)
  local visible = reaper.ImGui_BeginChild(ctx,'##'..name,-1,height,child_flags,child_window_flags)
  if visible then
    if fixed_header then reaper.ImGui_SetScrollY(ctx,0) end
    draw()
    if not fixed_header then controls.scroll_end(ctx) end
    reaper.ImGui_EndChild(ctx)
  end
end

local function draw_frame()
  state.update()
  controls.begin_frame(ctx)
  -- Push theme colors for this frame and always pop them before the frame ends.
  theme.apply(ctx)
  if reaper.ImGui_SetNextWindowSize and reaper.ImGui_Cond_FirstUseEver then reaper.ImGui_SetNextWindowSize(ctx,280,760,reaper.ImGui_Cond_FirstUseEver()) end
  local visible, open = reaper.ImGui_Begin(ctx,'ReaSpect',true,window_flags)
  if visible then
    brand_wordmark()
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_GetContentRegionAvail and reaper.ImGui_GetCursorPosX then
      local cursor_x=reaper.ImGui_GetCursorPosX(ctx)
      local avail_w=reaper.ImGui_GetContentRegionAvail(ctx)
      local icons_w=4*25+3*4
      reaper.ImGui_SameLine(ctx,math.max(cursor_x,cursor_x+avail_w-icons_w),0)
    end
    panel_button('track');reaper.ImGui_SameLine(ctx);panel_button('item');reaper.ImGui_SameLine(ctx);panel_button('channel');reaper.ImGui_SameLine(ctx);theme_button()
    reaper.ImGui_Separator(ctx)
    local aw,ah = reaper.ImGui_GetContentRegionAvail(ctx)
    ah = ah or 600
    local names={}
    if state.panels.track then names[#names+1]='track' end
    if state.panels.item then names[#names+1]='item' end
    if state.panels.channel then names[#names+1]='channel' end
    if #names==0 then reaper.ImGui_TextDisabled(ctx,'All panels hidden')
    else
      local split_space=(#names-1)*6
      local usable=math.max(80,ah-split_space)
      local sum=0; for _,n in ipairs(names) do sum=sum+state.heights[n] end
      if sum<=0 then sum=1 end
      local y=0
      for i,n in ipairs(names) do
        local h=(i==#names) and (usable-y) or math.max(70,usable*(state.heights[n]/sum))
        draw_panel(n,h,function()
          if n=='track' then track_panel.draw(ctx,state) elseif n=='item' then item_panel.draw(ctx,state) else channel_panel.draw(ctx,state) end
        end)
        y=y+h
        if i<#names then splitter(i,names,usable) end
      end
    end
  end
  -- ReaImGui's Lua binding expects End only when Begin reports the window as
  -- visible (unlike Dear ImGui's C++ API). A collapsed window remains open but
  -- has no matching window scope to end.
  if visible then
    -- Keep transport available after clicking inspector controls. Active
    -- text fields and open popups retain their own Space key behavior.
    if reaper.ImGui_IsWindowFocused and reaper.ImGui_FocusedFlags_RootAndChildWindows
        and reaper.ImGui_IsKeyPressed and reaper.ImGui_Key_Space
        and reaper.ImGui_IsAnyItemActive and reaper.ImGui_IsPopupOpen
        and reaper.ImGui_PopupFlags_AnyPopupId and reaper.ImGui_PopupFlags_AnyPopupLevel
        and reaper.ImGui_IsWindowFocused(ctx,reaper.ImGui_FocusedFlags_RootAndChildWindows())
        and not reaper.ImGui_IsAnyItemActive(ctx)
        and not reaper.ImGui_IsPopupOpen(ctx,'',reaper.ImGui_PopupFlags_AnyPopupId() | reaper.ImGui_PopupFlags_AnyPopupLevel())
        and reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Space(),false)
        and (not reaper.ImGui_GetKeyMods or reaper.ImGui_GetKeyMods(ctx)==0) then
      reaper.Main_OnCommand(40044,0)
    end
    reaper.ImGui_End(ctx)
  end
  if reaper.ImGui_IsMouseDown and not reaper.ImGui_IsMouseDown(ctx,0) then finish_edits() end
  theme.draw_editor(ctx)
  theme.pop(ctx)
  return open
end

local function step()
  -- Let REAPER finish the previous deferred callback (including ReaImGui's
  -- frame submission) before entering a native menu, dialog or plug-in. End()
  -- alone only closes a window; it does not finish the ImGui frame.
  diagnostics.poll()
  rack.process_pending_actions()
  item_actions.process()
  track_actions.process()
  fx_parameters.process()
  native_ui.process()
  return draw_frame()
end

local released=false
local function cleanup()
  if released then return end
  released=true
  running=false
  native_ui.clear()
  pcall(finish_edits)
  diagnostics.event('session_end')
  if reaper.ImGui_DestroyContext then pcall(reaper.ImGui_DestroyContext,ctx) end
end
if reaper.atexit then reaper.atexit(cleanup) end

local in_loop=false
local function loop()
  if not running or in_loop then return end
  -- ReaImGui contexts must be used on every defer cycle. Skipping callbacks
  -- for a wall-clock FPS cap lets the host garbage-collect this context,
  -- especially when another script or a native action changes callback timing.
  in_loop=true
  local ok,open=xpcall(step,debug.traceback)
  in_loop=false
  if not ok then
    -- A failed nested ImGui scope cannot safely be unwound by guessing which
    -- windows remain open. Stop once, preserving the original diagnostic.
    diagnostics.event('script_error',tostring(open))
    cleanup()
    reaper.ShowConsoleMsg('ReaSpect stopped: '..tostring(open)..'\n')
    return
  end
  if open then
    reaper.defer(loop)
  else
    cleanup()
  end
end

loop()
