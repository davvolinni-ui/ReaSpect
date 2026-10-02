local api = require('ReaSpect.core.reaper_api')
local prop = require('ReaSpect.widgets.property')
local undo = require('ReaSpect.core.undo')
local actions = require('ReaSpect.core.item_actions')
local selection = require('ReaSpect.core.item_selection')
local M = {}
local MIXED = '__MIXED__'

local function matching_takes(items, kind)
  local takes, targets = {}, {}
  for _, item in ipairs(items) do
    local take = api.item.take(item)
    if take then
      local midi = api.take.is_midi(take)
      if (kind ~= 'audio' or not midi) and (kind ~= 'midi' or midi) then
        takes[#takes + 1], targets[#targets + 1] = take, item
      end
    end
  end
  return takes, targets
end

local function shared(objects, getter)
  if #objects == 0 then return nil end
  local value = getter(objects[1])
  for i = 2, #objects do
    local other = getter(objects[i])
    if type(value) == 'number' and type(other) == 'number' then
      if math.abs(value - other) > 0.0000001 then return MIXED end
    elseif value ~= other then return MIXED end
  end
  return value
end

local function edit(takes, label, setter, value)
  undo.edit(label, function()
    for _, take in ipairs(takes) do setter(take, value) end
    reaper.UpdateArrange()
  end)
end

local function tooltip(ctx, value)
  if reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_SetTooltip then
    reaper.ImGui_SetTooltip(ctx, value)
  end
end

local function short_text(ctx, value)
  local text = tostring(value)
  local width = reaper.ImGui_GetContentRegionAvail and reaper.ImGui_GetContentRegionAvail(ctx) or 240
  if reaper.ImGui_CalcTextSize and reaper.ImGui_CalcTextSize(ctx, text) > width then
    local chars = {}
    for ch in text:gmatch('[\1-\127\194-\244][\128-\191]*') do chars[#chars + 1] = ch end
    while #chars > 0 and reaper.ImGui_CalcTextSize(ctx, table.concat(chars)..'…') > width do
      table.remove(chars)
    end
    text = table.concat(chars)..'…'
  end
  reaper.ImGui_TextDisabled(ctx, text)
end

function M.draw_selector(ctx, state, items)
  if #items ~= 1 then state.take_name_draft = nil end
  if #items ~= 1 or not reaper.SetActiveTake then return end
  local count_takes = reaper.CountTakes or reaper.GetMediaItemNumTakes
  local get_take = reaper.GetTake or reaper.GetMediaItemTake
  if not count_takes or not get_take then return end
  local item = items[1]
  local count = count_takes(item)
  if count < 2 then return end
  local active = api.item.take(item)
  local labels, values, current = {}, {}, -1
  for i = 0, count - 1 do
    local take = get_take(item, i)
    if take then
      local name = api.take.name(take)
      labels[#labels + 1] = tostring(i + 1)..' · '..(name ~= '' and name or 'Unnamed take')
      values[#values + 1] = i
      if take == active then current = i end
    end
  end
  prop.enum(ctx, 'Active take', '##active_take', current, labels, values, function(index)
    local take = get_take(item, index)
    if take and take ~= active then
      undo.edit('Select active take', function()
        reaper.SetActiveTake(take)
        reaper.UpdateArrange()
      end)
      state.active_take = take
    end
  end)
end

local function draw_name(ctx, state, take)
  local name = api.take.name(take)
  local draft = state.take_name_draft
  if not draft or draft.take ~= take then
    draft = { take = take, value = name, original = name }
    state.take_name_draft = draft
  elseif draft.value == draft.original then
    draft.value, draft.original = name, name
  end
  prop.row(ctx, 'Take name', function()
    local flags = reaper.ImGui_InputTextFlags_EnterReturnsTrue and reaper.ImGui_InputTextFlags_EnterReturnsTrue() or 0
    local committed, value = reaper.ImGui_InputText(ctx, '##take_name_'..tostring(take), draft.value, flags)
    draft.value = value or draft.value
    local escape = reaper.ImGui_IsKeyPressed and reaper.ImGui_Key_Escape
      and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape())
    if escape then
      draft.value, draft.original = name, name
    elseif committed and flags ~= 0 and draft.value ~= name then
      edit({ take }, 'Rename take', api.take.set_name, draft.value)
      draft.original = draft.value
    elseif reaper.ImGui_IsItemDeactivated and reaper.ImGui_IsItemDeactivated(ctx) then
      -- Take names commit only on Enter; losing focus cancels an unfinished rename.
      draft.value, draft.original = api.take.name(take), api.take.name(take)
    end
    tooltip(ctx, 'Enter to rename the active take; Escape or click away to cancel.')
  end)
end

local function source_info(take)
  local source = reaper.GetMediaItemTake_Source and reaper.GetMediaItemTake_Source(take)
  if not source then return { missing = true } end
  local original = source
  -- Sections and reverse playback wrap their underlying source. Stop on a
  -- repeated pointer as well as a nil parent to guard unusual source providers.
  local seen = { [source] = true }
  if reaper.GetMediaSourceParent then
    while true do
      local parent = reaper.GetMediaSourceParent(source)
      if not parent or seen[parent] then break end
      seen[parent], source = true, parent
    end
  end
  local length, qn
  if reaper.GetMediaSourceLength then length, qn = reaper.GetMediaSourceLength(source) end
  return {
    source = source,
    filename = reaper.GetMediaSourceFileName and reaper.GetMediaSourceFileName(source) or '',
    type = reaper.GetMediaSourceType and reaper.GetMediaSourceType(source) or '',
    rate = reaper.GetMediaSourceSampleRate and reaper.GetMediaSourceSampleRate(source) or 0,
    channels = reaper.GetMediaSourceNumChannels and reaper.GetMediaSourceNumChannels(source) or 0,
    length = length,
    qn = qn,
    wrapped = original ~= source,
  }
end

local function draw_metadata(ctx, takes)
  local sources, seen, distinct = {}, {}, 0
  for _, take in ipairs(takes) do
    local info = source_info(take)
    sources[#sources + 1] = info
    local identity = info.filename ~= nil and info.filename ~= '' and info.filename or info.source
    if identity and not seen[identity] then seen[identity], distinct = true, distinct + 1 end
  end
  local filename = shared(sources, function(s) return s.filename or '' end)
  local source_type = shared(sources, function(s) return s.type or '' end)
  local file_label
  if filename == MIXED then file_label = tostring(distinct)..' sources'
  elseif filename ~= '' then file_label = filename:match('[^/\\]+$') or filename
  elseif source_type == 'MIDI' then file_label = 'In-project MIDI'
  elseif distinct > 1 then file_label = tostring(distinct)..' sources'
  else file_label = 'No source file' end
  prop.row(ctx, 'Source', function()
    short_text(ctx, file_label)
    if filename ~= MIXED and filename ~= '' then tooltip(ctx, filename) end
  end)
  local format = shared(sources, function(s)
    local bits = { s.type and s.type ~= '' and s.type or 'Unknown' }
    if s.rate and s.rate > 0 then bits[#bits + 1] = string.format('%g kHz', s.rate / 1000) end
    if s.channels and s.channels > 0 and s.type ~= 'MIDI' then bits[#bits + 1] = tostring(s.channels)..' ch' end
    return table.concat(bits, ' · ')
  end)
  prop.row(ctx, 'Format', function()
    short_text(ctx, format == MIXED and 'Mixed formats' or format)
    if format ~= MIXED then tooltip(ctx, format) end
  end)
  local length = shared(sources, function(s) return s.length end)
  local qn = shared(sources, function(s) return s.qn end)
  if length ~= nil then
    prop.row(ctx, 'Source length', function()
      local value
      if length == MIXED or qn == MIXED then value = '—'
      else value = string.format(qn and '%.3f beats' or '%.3f s', length) end
      short_text(ctx, value)
      tooltip(ctx, 'Length of the underlying source before section or reverse processing.')
    end)
  end
end

function M.draw(ctx, state, items, kind)
  if #items ~= 1 then state.take_name_draft = nil end
  if #items == 0 then return end
  if not prop.section(ctx, state, 'item_source', 'Take / Source', false, kind) then return end
  local takes, targets = matching_takes(items, kind)
  if #takes > 0 then
    if #items == 1 then draw_name(ctx, state, takes[1])
    else
      reaper.ImGui_TextDisabled(ctx, tostring(#takes)..' active takes')
    end
    prop.number(ctx, 'Source offset', '##source_offset', shared(takes, api.take.start), function(value)
      edit(takes, 'Set take source offset', api.take.set_start, value)
    end, '%.3f s', { step = 0.01, default=0,on_delta=selection.delta_editor(takes,'Adjust take source offset',api.take.start,api.take.set_start),tooltip = 'Start offset in source seconds for each active take.' })
    local audio_only = true
    for _, take in ipairs(takes) do if api.take.is_midi(take) then audio_only = false; break end end
    if audio_only then
      prop.enum(ctx, 'Channels', '##source_channel_mode', shared(takes, api.take.chanmode),
        { 'Normal', 'Reverse stereo', 'Mono mix', 'Mono left', 'Mono right' }, { 0, 1, 2, 3, 4 }, function(value)
          edit(takes, 'Set take channel mode', api.take.set_chanmode, value)
        end,{default=0})
    end
    draw_metadata(ctx, takes)
  else
    reaper.ImGui_TextDisabled(ctx, 'No active take')
  end
  local source_available = #targets == 1 and actions.available('source_properties')
  local properties_available = actions.available('properties')
  if source_available or properties_available then
    local width = reaper.ImGui_GetContentRegionAvail and reaper.ImGui_GetContentRegionAvail(ctx) or 240
    local gap = 4
    if source_available then
      local button_width = properties_available and math.max(1, (width - gap) / 2) or -1
      if reaper.ImGui_Button(ctx, 'Source…##source_properties', button_width, 21) then actions.queue('source_properties', targets) end
    end
    if properties_available then
      if source_available then reaper.ImGui_SameLine(ctx, 0, gap) end
      if reaper.ImGui_Button(ctx, 'Properties…##item_properties', -1, 21) then actions.queue('properties', items) end
    end
  end
end

return M
