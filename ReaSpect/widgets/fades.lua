local api = require('ReaSpect.core.reaper_api')
local selection = require('ReaSpect.core.item_selection')
local prop = require('ReaSpect.widgets.property')
local controls = require('ReaSpect.widgets.controls')
local M = {}

-- REAPER documents shape 0 as linear and supports native shapes 0..6.
-- Use the menu's ordinal for the remaining curves rather than guessing names.
local labels = { 'Linear', 'Curve 2', 'Curve 3', 'Curve 4', 'Curve 5', 'Curve 6', 'Curve 7' }
local values = { 0, 1, 2, 3, 4, 5, 6 }

local function set_length(items, label, setter, value)
  selection.edit(items, label, function(item, length)
    setter(item, math.max(0, math.min(length, api.item.length(item))))
  end, value)
end

local function shape_combo(ctx, id, value, width, change)
  reaper.ImGui_SetNextItemWidth(ctx, width)
  local changed,out=controls.enum_combo(ctx,id,value,labels,values,{default=0,tooltip='REAPER fade curve. Curves 2–7 follow the native fade menu order.'})
  if changed then change(out) end
end

local function auto_fade_note(ctx, items)
  local affected = 0
  for _, item in ipairs(items) do
    local fade_in = reaper.GetMediaItemInfo_Value(item, 'D_FADEINLEN_AUTO') or 0
    local fade_out = reaper.GetMediaItemInfo_Value(item, 'D_FADEOUTLEN_AUTO') or 0
    if fade_in > 0 or fade_out > 0 then affected = affected + 1 end
  end
  if affected == 0 then return end
  local note = #items == 1 and 'Auto crossfade active' or ('Auto crossfades · '..affected..' events')
  reaper.ImGui_TextDisabled(ctx, note)
  prop.tooltip(ctx, 'Automatic fade lengths are active. The Fade in / out fields edit manual fades; automatic crossfades are preserved.')
end

function M.draw(ctx, state, items)
  if #items == 0 then return end
  prop.dual_number(ctx,
    'Fade in', '##item_fade_in', selection.shared(items, api.item.fade_in),
    'Fade out', '##item_fade_out', selection.shared(items, api.item.fade_out),
    function(value) set_length(items, 'Set item fade in', api.item.set_fade_in, value) end,
    function(value) set_length(items, 'Set item fade out', api.item.set_fade_out, value) end,
    '%.3f s', '%.3f s',
    { step = 0.05, min = 0, default=0, on_delta=selection.delta_editor(items,'Adjust fade in',api.item.fade_in,function(i,v) api.item.set_fade_in(i,math.min(v,api.item.length(i))) end,0),tooltip = 'Manual fade-in length. Limited to each event’s length; automatic crossfades are preserved.' },
    { step = 0.05, min = 0, default=0, on_delta=selection.delta_editor(items,'Adjust fade out',api.item.fade_out,function(i,v) api.item.set_fade_out(i,math.min(v,api.item.length(i))) end,0),tooltip = 'Manual fade-out length. Limited to each event’s length; automatic crossfades are preserved.' })
  auto_fade_note(ctx, items)
  if not prop.section(ctx, state, 'item_fades', 'Fade shapes', false) then return end
  local fade_in = selection.shared(items, api.item.fade_in_shape)
  local fade_out = selection.shared(items, api.item.fade_out_shape)
  local function set_in(value) selection.edit(items, 'Set fade-in shape', api.item.set_fade_in_shape, value) end
  local function set_out(value) selection.edit(items, 'Set fade-out shape', api.item.set_fade_out_shape, value) end
  local available = reaper.ImGui_GetContentRegionAvail(ctx)
  if available < 190 then
    prop.enum(ctx, 'In shape', '##fade_in_shape', fade_in, labels, values, set_in,{default=0})
    prop.enum(ctx, 'Out shape', '##fade_out_shape', fade_out, labels, values, set_out,{default=0})
  else
    local width = (available - 6) / 2
    reaper.ImGui_BeginGroup(ctx)
    reaper.ImGui_TextDisabled(ctx, 'In shape')
    shape_combo(ctx, '##fade_in_shape', fade_in, width, set_in)
    reaper.ImGui_EndGroup(ctx)
    reaper.ImGui_SameLine(ctx, 0, 6)
    reaper.ImGui_BeginGroup(ctx)
    reaper.ImGui_TextDisabled(ctx, 'Out shape')
    shape_combo(ctx, '##fade_out_shape', fade_out, width, set_out)
    reaper.ImGui_EndGroup(ctx)
  end
end

return M
