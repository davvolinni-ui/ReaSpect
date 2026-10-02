local theme=require('ReaSpect.core.theme')
local color=require('ReaSpect.widgets.color')
local M={}
local rename

function M.reset() rename=nil end

local function fit(ctx,text,width)
  text=tostring(text or '')
  if reaper.ImGui_CalcTextSize(ctx,text)<=width then return text end
  while #text>0 and reaper.ImGui_CalcTextSize(ctx,text..'…')>width do
    local last=utf8.offset(text,-1) or #text
    text=text:sub(1,last-1)
  end
  return text~='' and text..'…' or ''
end

local function icon(ctx,kind,x,y)
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  local ink=theme.colors.text
  local dark=theme.colors.panel
  if kind=='audio' then
    for i,h in ipairs({5,9,14,8,5}) do
      local bx=x+2+(i-1)*3.1
      reaper.ImGui_DrawList_AddRectFilled(dl,bx,y+11-h/2,bx+1.8,y+11+h/2,ink,1)
    end
  elseif kind=='midi' then
    reaper.ImGui_DrawList_AddRectFilled(dl,x+2,y+5,x+16,y+17,ink,1)
    for _,dx in ipairs({6,10,13}) do reaper.ImGui_DrawList_AddLine(dl,x+dx,y+6,x+dx,y+16,dark,1) end
    for _,dx in ipairs({4,8,12}) do reaper.ImGui_DrawList_AddRectFilled(dl,x+dx,y+5,x+dx+2,y+11,dark) end
  elseif kind=='empty' then
    reaper.ImGui_DrawList_AddRect(dl,x+2,y+5,x+17,y+18,ink,1)
  else
    reaper.ImGui_DrawList_AddRect(dl,x+2,y+5,x+14,y+15,ink,1)
    reaper.ImGui_DrawList_AddRect(dl,x+5,y+8,x+17,y+18,ink,1)
  end
end

function M.draw(ctx,opts)
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  local width=reaper.ImGui_GetContentRegionAvail(ctx)
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  -- Match the Track header: 27 high, 13 color strip, 27 identity cell,
  -- a five-pixel name inset, and the same 18-pixel media icon.
  local height=27
  reaper.ImGui_DrawList_AddRectFilled(dl,x,y,x+width,y+height,theme.colors.frame,2)
  color.strip(ctx,'##event_color_'..opts.id,opts.color,13,height,opts.on_color,nil,'Event color — click to change')
  local left,right=x+13,x+40
  reaper.ImGui_DrawList_AddRectFilled(dl,left,y,right,y+height,theme.colors.panel)
  for _,edge in ipairs({left,right}) do reaper.ImGui_DrawList_AddLine(dl,edge,y+4,edge,y+height-4,theme.colors.border,1) end
  local badge=fit(ctx,opts.badge,25)
  local bw,bh=reaper.ImGui_CalcTextSize(ctx,badge)
  reaper.ImGui_DrawList_AddText(dl,left+(27-bw)/2,y+(height-bh)/2,theme.colors.text,badge)
  local nx,ix=right+5,x+width-23
  local nw=math.max(1,ix-nx-4)
  if rename and rename.id~=opts.id then rename=nil end
  reaper.ImGui_SetCursorScreenPos(ctx,nx,y+(rename and 2 or 0))
  if rename then
    if rename.focus then reaper.ImGui_SetKeyboardFocusHere(ctx); rename.focus=false end
    reaper.ImGui_SetNextItemWidth(ctx,nw)
    local entered,text=reaper.ImGui_InputText(ctx,'##event_rename',rename.value,reaper.ImGui_InputTextFlags_EnterReturnsTrue())
    rename.value=text or rename.value
    if reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Escape()) then rename=nil
    elseif entered or reaper.ImGui_IsItemDeactivated(ctx) then
      if rename.value~=rename.original and opts.on_rename then opts.on_rename(rename.value) end
      rename=nil
    end
  else
    reaper.ImGui_InvisibleButton(ctx,'##event_name_'..opts.id,nw,height)
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx,opts.tooltip..(opts.on_rename and '\nDouble-click to rename the active take' or ''))
      if opts.on_rename and reaper.ImGui_IsMouseDoubleClicked(ctx,0) then
        rename={id=opts.id,value=opts.name,original=opts.name,focus=true}
      end
    end
    local title=fit(ctx,opts.name,nw-8)
    local _,th=reaper.ImGui_CalcTextSize(ctx,title)
    reaper.ImGui_DrawList_AddText(dl,nx+4,y+(height-th)/2,theme.colors.text,title)
  end
  reaper.ImGui_SetCursorScreenPos(ctx,ix,y+2)
  reaper.ImGui_Dummy(ctx,18,22)
  icon(ctx,opts.kind,ix,y+2)
  if reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx,opts.caption) end
  reaper.ImGui_SetCursorScreenPos(ctx,x,y+height)
  reaper.ImGui_Dummy(ctx,0,3)
  reaper.ImGui_TextDisabled(ctx,fit(ctx,opts.caption,width))
  if reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx,opts.caption) end
end

return M
