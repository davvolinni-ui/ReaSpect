local c = require('ReaSpect.widgets.controls')
local theme = require('ReaSpect.core.theme')
local M = {}
local undo=require('ReaSpect.core.undo')
local scopes, mixed_inputs = {}, {}
local function soften(a,b)
  local function part(shift) return math.floor(((a>>shift)&255)*.76+((b>>shift)&255)*.24+.5) end
  return (part(24)<<24)|(part(16)<<16)|(part(8)<<8)|255
end

function M.row(ctx, label, draw, opts)
  opts = opts or {}
  local avail = reaper.ImGui_GetContentRegionAvail and reaper.ImGui_GetContentRegionAvail(ctx) or 240
  local lw = opts.label_width or math.min(112, math.max(78, avail*0.42))
  if reaper.ImGui_TextColored then
    local palette=theme.colors
    reaper.ImGui_TextColored(ctx,soften(palette.text or 0xD4D7DBFF,palette.panel or 0x1D2024FF),label)
  else reaper.ImGui_Text(ctx,label) end
  reaper.ImGui_SameLine(ctx, lw)
  if reaper.ImGui_SetNextItemWidth then reaper.ImGui_SetNextItemWidth(ctx, -1) end
  draw()
end

function M.set_scope(ctx, key) scopes[tostring(ctx)] = key end

function M.tooltip(ctx, text)
  if text and reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx,text) end
end

-- REAPER enums often start at -1, use flags, or leave gaps. Never treat their
-- values as menu indices, or replace an unfamiliar value just by displaying it.
function M.enum(ctx, label, id, value, labels, values, on_change, opts)
  M.row(ctx,label,function()
    local changed,out=c.enum_combo(ctx,id,value,labels,values,opts)
    if changed then on_change(out) end
  end)
end

function M.section(ctx,state,key,title,default_open,context_key)
  local open=state.sections[key]
  if open==nil then open=default_open or false end
  local flags=open and reaper.ImGui_TreeNodeFlags_DefaultOpen() or 0
  local colors=0
  if theme.heading_colors and reaper.ImGui_PushStyleColor and reaper.ImGui_PopStyleColor then
    local ink,background,hover=theme.heading_colors()
    local function push(name,color)
      local slot=reaper['ImGui_Col_'..name]
      if slot then reaper.ImGui_PushStyleColor(ctx,slot(),color);colors=colors+1 end
    end
    push('Text',ink);push('Header',background);push('HeaderHovered',hover);push('HeaderActive',hover)
  end
  if reaper.ImGui_Dummy then reaper.ImGui_Dummy(ctx,0,3) end
  if reaper.ImGui_SetNextItemOpen then reaper.ImGui_SetNextItemOpen(ctx,open) end
  local shown=reaper.ImGui_CollapsingHeader(ctx,title:upper()..'##'..key..tostring(context_key or ''),nil,flags)
  if shown and not open and reaper.ImGui_SetScrollHereY then reaper.ImGui_SetScrollHereY(ctx,0) end
  if colors>0 then reaper.ImGui_PopStyleColor(ctx,colors) end
  if shown and reaper.ImGui_Dummy then reaper.ImGui_Dummy(ctx,0,3) end
  if shown~=open then state.set_section(key,shown) end
  return shown
end

function M.combo(ctx, label, id, value, values, on_change, opts)
  local indices={}; for i=1,#values do indices[i]=i-1 end
  M.enum(ctx,label,id,value,values,indices,on_change,opts)
end

function M.checkbox(ctx, label, id, value, on_change, default)
  M.row(ctx,label,function()
    local mixed=value=='__MIXED__'
    if default==nil then default=false end
    local changed, out = reaper.ImGui_Checkbox(ctx,id,not mixed and value or false)
    local edited,next_value=c.toggle(ctx,value,default)
    if edited then changed,out=true,next_value end
    if mixed then
      local x,y=reaper.ImGui_GetItemRectMin(ctx)
      local _,bottom=reaper.ImGui_GetItemRectMax(ctx)
      local size=bottom-y
      reaper.ImGui_DrawList_AddRectFilled(reaper.ImGui_GetWindowDrawList(ctx),x+4,y+size/2-1,x+size-4,y+size/2+1,theme.colors.text)
    end
    M.tooltip(ctx,(mixed and 'Mixed selection. ' or '')..'Wheel up: enable; down: disable. Right-click: reset.')
    if changed then on_change(out) end
  end)
end

local function number_input(ctx,id,value,on_change,fmt,opts,label)
  opts=opts or {}
  local widget_id=id..'##scope_'..tostring(scopes[tostring(ctx)] or '')
  local function commit(v)
    if type(v)~='number' or v~=v or v==math.huge or v==-math.huge then return end
    if opts.min then v=math.max(opts.min,v) end
    if opts.max then v=math.min(opts.max,v) end
    if opts.quantum then v=math.floor(v/opts.quantum+0.5)*opts.quantum end
    if opts.min then v=math.max(opts.min,v) end
    if opts.max then v=math.min(opts.max,v) end
    if v==value then return end
    on_change(v)
  end
  if value=='__MIXED__' then
    local key=tostring(ctx)..id
    local scope=scopes[tostring(ctx)]
    local draft=mixed_inputs[key]
    if not draft or draft.scope~=scope then draft={scope=scope,text=''}; mixed_inputs[key]=draft end
    -- Track the draft every frame; EnterReturnsTrue hides intermediate text
    -- from ReaImGui and would discard a mixed-value edit on focus loss.
    local flags=0
    local entered,text
    if reaper.ImGui_InputTextWithHint then
      entered,text=reaper.ImGui_InputTextWithHint(ctx,widget_id,'—',draft.text,flags)
    else entered,text=reaper.ImGui_InputText(ctx,widget_id,draft.text,flags) end
    draft.text=text or draft.text
    local done=reaper.ImGui_IsItemDeactivatedAfterEdit(ctx)
      or (reaper.ImGui_IsItemActive(ctx) and reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Enter()))
    local wheel,delta=c.wheel(ctx,0,opts.step or 0.1,nil,nil,opts.quantum)
    if opts.default~=nil and c.right_click(ctx) then draft.text='';commit(opts.default)
    elseif wheel and opts.on_delta then draft.text='';opts.on_delta(delta)
    elseif done then
      local number=tonumber(draft.text)
      draft.text=''
      if number then commit(number) end
    end
  else
    mixed_inputs[tostring(ctx)..id]=nil
    local changed,out=c.drag_double(ctx,widget_id,value or 0,fmt,opts)
    local wh,nv=c.wheel(ctx,value or 0,opts.step or 0.1,opts.min,opts.max,opts.quantum)
    if opts.default~=nil and c.right_click(ctx) then
      if value~=opts.default then commit(opts.default) end
    elseif wh then commit(nv)
    else
      undo.property_gesture(ctx,widget_id,'Adjust '..(label or 'value'),changed,function() commit(out) end)
    end
  end
  local hint='Drag left/right: adjust  •  Alt: fine  •  Shift: faster\nDouble-click or Ctrl-click: type a value\nWheel: adjust  •  Shift: fine  •  Ctrl: coarse'
  if value=='__MIXED__' then hint='Click to type a value\nWheel: adjust  •  Shift: fine  •  Ctrl: coarse\nWheel preserves value differences; typing sets all selected values.' end
  if opts.default~=nil then hint=hint..'\nRight-click: reset to '..string.format(fmt or '%.3f',opts.default) end
  M.tooltip(ctx,(opts.tooltip and (opts.tooltip..'\n') or '')..hint)
end

function M.number(ctx, label, id, value, on_change, fmt, opts)
  M.row(ctx,label,function() number_input(ctx,id,value,on_change,fmt,opts,label) end)
end

function M.dual_number(ctx, label_a, id_a, value_a, label_b, id_b, value_b, on_a, on_b, fmt_a, fmt_b, opts_a, opts_b)
  local avail=reaper.ImGui_GetContentRegionAvail(ctx)
  if avail<190 then
    M.number(ctx,label_a,id_a,value_a,on_a,fmt_a,opts_a)
    M.number(ctx,label_b,id_b,value_b,on_b,fmt_b,opts_b)
    return
  end
  local width=(avail-6)/2
  local function field(label,id,value,callback,fmt,opts)
    reaper.ImGui_BeginGroup(ctx)
    reaper.ImGui_TextColored(ctx,soften(theme.colors.text,theme.colors.panel),label)
    reaper.ImGui_SetNextItemWidth(ctx,width)
    number_input(ctx,id,value,callback,fmt,opts,label)
    reaper.ImGui_EndGroup(ctx)
  end
  field(label_a,id_a,value_a,on_a,fmt_a,opts_a)
  reaper.ImGui_SameLine(ctx,0,6)
  field(label_b,id_b,value_b,on_b,fmt_b,opts_b)
end

return M
