local M = {}
local undo=require('ReaSpect.core.undo')
local wheel_claimed = {}

function M.begin_frame(ctx) wheel_claimed[tostring(ctx)] = false;undo.wheel_source(false) end

function M.scroll_flags(flags)
  return (flags or 0) | reaper.ImGui_WindowFlags_NoScrollWithMouse()
end

-- ReaImGui does not expose SetItemKeyOwner. Native window scrolling happens
-- before widgets run, so undoing it after a wheel edit is a frame too late.
-- Our scroll regions disable native wheel scrolling and route it once, after
-- drawing their controls. Scrollbars and popup option lists remain native.
function M.scroll_end(ctx)
  if wheel_claimed[tostring(ctx)] or not reaper.ImGui_IsWindowHovered(ctx) then return end
  local vertical, horizontal = reaper.ImGui_GetMouseWheel(ctx)
  local line = reaper.ImGui_GetTextLineHeightWithSpacing(ctx)
  if vertical ~= 0 then
    local maximum = reaper.ImGui_GetScrollMaxY(ctx)
    if maximum > 0 then
      reaper.ImGui_SetScrollY(ctx, math.max(0, math.min(maximum, reaper.ImGui_GetScrollY(ctx)-vertical*line*3)))
    end
  end
  if horizontal and horizontal ~= 0 and reaper.ImGui_GetScrollMaxX then
    local maximum = reaper.ImGui_GetScrollMaxX(ctx)
    if maximum > 0 then
      reaper.ImGui_SetScrollX(ctx, math.max(0, math.min(maximum, reaper.ImGui_GetScrollX(ctx)-horizontal*line*3)))
    end
  end
end

function M.wheel_delta(ctx)
  undo.wheel_source(false)
  if not reaper.ImGui_IsItemHovered(ctx) then return 0 end
  -- Claim even at a limit, over mixed values, or with a zero wheel delta.
  wheel_claimed[tostring(ctx)] = true
  local delta=reaper.ImGui_GetMouseWheel(ctx) or 0
  undo.wheel_source(delta~=0)
  return delta
end

function M.right_click(ctx)
  local clicked=reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsItemClicked(ctx,1)
  if clicked then undo.wheel_source(false) end
  return clicked
end

function M.wheel_step(ctx, step, quantum)
  local mods = reaper.ImGui_GetKeyMods(ctx)
  if (mods & reaper.ImGui_Mod_Shift()) ~= 0 then step = step * 0.1
  elseif (mods & reaper.ImGui_Mod_Ctrl()) ~= 0 then step = step * 10 end
  return quantum and math.max(quantum, step) or step
end

function M.choice(ctx, value, values, default)
  local wheel = M.wheel_delta(ctx)
  if default ~= nil and M.right_click(ctx) then return value ~= default, default end
  if wheel == 0 or #values == 0 then return false, value end
  local index
  for i,v in ipairs(values) do if v == value then index = i; break end end
  -- Unknown/mixed values become the first/last option in the wheel direction.
  local next_index = index and math.max(1, math.min(#values, index+(wheel>0 and 1 or -1)))
    or (wheel>0 and 1 or #values)
  local out = values[next_index]
  return out ~= value, out
end

function M.enum_combo(ctx, id, value, labels, values, opts)
  opts = opts or {}
  local preview = value == '__MIXED__' and '—' or ('Custom ('..tostring(value)..')')
  for i,v in ipairs(values) do if value == v then preview = labels[i]; break end end
  local changed, out = false, value
  if reaper.ImGui_BeginCombo(ctx,id,preview) then
    for i,v in ipairs(values) do
      if reaper.ImGui_Selectable(ctx,labels[i]..'##'..i,value==v) then changed,out = true,v end
      if value==v then reaper.ImGui_SetItemDefaultFocus(ctx) end
    end
    reaper.ImGui_EndCombo(ctx)
  else
    changed,out = M.choice(ctx,value,values,opts.default)
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx,(opts.tooltip and (opts.tooltip..'\n') or '')..
        'Wheel: change option'..(opts.default~=nil and '  •  Right-click: reset' or ''))
    end
  end
  return changed,out
end

function M.label_value(ctx, label, value, width)
  reaper.ImGui_Text(ctx, label)
  reaper.ImGui_SameLine(ctx, width or 112)
  if reaper.ImGui_SetNextItemWidth then reaper.ImGui_SetNextItemWidth(ctx, -1) end
  return value
end

function M.combo(ctx, id, current, values, width, opts)
  if width and reaper.ImGui_SetNextItemWidth then reaper.ImGui_SetNextItemWidth(ctx,width) end
  local indices = {}; for i=1,#values do indices[i] = i-1 end
  return M.enum_combo(ctx,id,current,values,indices,opts)
end

-- Compact wheel support. The caller remains responsible for applying the returned value.
function M.wheel(ctx, value, step, min, max, quantum)
  local wheel = M.wheel_delta(ctx)
  if wheel == 0 then return false, value end
  step = M.wheel_step(ctx,step,quantum)
  if quantum then wheel = wheel>0 and math.max(1,math.floor(wheel)) or math.min(-1,math.ceil(wheel)) end
  local out = value + wheel * step
  if quantum then out = math.floor(out/quantum+0.5)*quantum end
  if min then out = math.max(min, out) end
  if max then out = math.min(max, out) end
  return out ~= value, out
end
function M.double_click(ctx)
  return reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked and reaper.ImGui_IsMouseDoubleClicked(ctx,0)
end

function M.toggle(ctx, value, default)
  local wheel = M.wheel_delta(ctx)
  if default ~= nil and M.right_click(ctx) then return value ~= default, default end
  if wheel == 0 then return false,value end
  local out = wheel > 0
  return out ~= value,out
end

function M.checkbox(ctx, id, value, default)
  if not reaper.ImGui_Checkbox then return false, value end
  local changed, out = reaper.ImGui_Checkbox(ctx, id, value)
  local edited, next_value = M.toggle(ctx,value,default)
  if edited then changed,out = true,next_value end
  return changed, out
end

function M.input_double(ctx, id, value, fmt, width)
  if not reaper.ImGui_InputDouble then return false, value end
  if width and reaper.ImGui_SetNextItemWidth then reaper.ImGui_SetNextItemWidth(ctx,width) end
  local changed, out = reaper.ImGui_InputDouble(ctx, id, value, 0, 0, fmt or '%.3f')
  return changed, out
end

function M.drag_double(ctx,id,value,fmt,opts)
  opts=opts or {}
  if not reaper.ImGui_DragDouble then return M.input_double(ctx,id,value,fmt) end
  local speed=opts.drag_step or math.max((opts.step or .1)*.1,opts.quantum or 0)
  local flags=reaper.ImGui_SliderFlags_AlwaysClamp and reaper.ImGui_SliderFlags_AlwaysClamp() or 0
  local min,max=0,0
  if opts.min or opts.max then min,max=opts.min or -1e100,opts.max or 1e100 end
  return reaper.ImGui_DragDouble(ctx,id,value,speed,min,max,fmt or '%.3f',flags)
end

function M.slider_double(ctx, id, value, min, max, fmt, width)
  if not reaper.ImGui_SliderDouble then return false, value end
  if width and reaper.ImGui_SetNextItemWidth then reaper.ImGui_SetNextItemWidth(ctx,width) end
  local changed, out = reaper.ImGui_SliderDouble(ctx, id, value, min, max, fmt or '%.2f')
  return changed, out
end

function M.text_or_mixed(ctx, value)
  reaper.ImGui_Text(ctx, value == nil and '--' or tostring(value))
end

function M.set_id(ctx, id)
  if reaper.ImGui_PushID then reaper.ImGui_PushID(ctx,id) end
end
function M.pop_id(ctx) if reaper.ImGui_PopID then reaper.ImGui_PopID(ctx) end end

return M
