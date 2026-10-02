-- Native item dialogs must run after ImGui's windows have been ended.
local M = {}
local pending = {}
local resolved = {}
local actions = {
  normalize = {id=42460, name='Item properties: Normalize items (peak/RMS/LUFS)...', kind='audio'},
  reverse = {id=41051, name='Item properties: Toggle take reverse', kind='audio'},
  properties = {id=40009, name='Item properties: Show media item/take properties'},
  source_properties = {id=40011, name='Item properties: Show media item source properties', single=true, take=true},
  midi_editor = {id=40153, name='Item: Open in built-in MIDI editor (set default behavior in preferences)', kind='midi'},
  take_fx = {single=true, take=true},
}

local function command(name)
  local action = actions[name]
  if not action then return nil end
  if resolved[name] ~= nil then return resolved[name] or nil end
  local section = reaper.SectionFromUniqueID and reaper.SectionFromUniqueID(0)
  -- IDs are REAPER's built-in main-section actions. Checking the installed
  -- action text also keeps newer actions unavailable on older REAPER versions.
  if section and reaper.kbd_getTextFromCmd then
    local description = reaper.kbd_getTextFromCmd(action.id, section)
    if description and description ~= '' then
      resolved[name] = action.id
      return action.id
    end
  end
  -- Only an exact native description can resolve a missing ID; never use a
  -- partial match that could select a script or a destructive variation.
  if section and reaper.kbd_enumerateActions then
    for index=0,100000 do
      local id, description = reaper.kbd_enumerateActions(section, index)
      if not id or id == 0 then break end
      if description == action.name then
        local named = reaper.ReverseNamedCommandLookup and reaper.ReverseNamedCommandLookup(id)
        if not named or named == '' then resolved[name]=id; return id end
      end
    end
  end
  resolved[name] = false
end

local function ready()
  return reaper.Main_OnCommandEx and reaper.EnumProjects and reaper.ValidatePtr2
    and reaper.CountSelectedMediaItems and reaper.GetSelectedMediaItem
    and reaper.SelectAllMediaItems and reaper.SetMediaItemSelected and reaper.GetActiveTake
end

function M.available(name)
  if name == 'take_fx' then
    return reaper.EnumProjects ~= nil and reaper.ValidatePtr2 ~= nil
      and reaper.GetActiveTake ~= nil and reaper.TakeFX_Show ~= nil
  end
  return ready() and command(name) ~= nil or false
end

local function valid_target(project, target, action)
  if not reaper.ValidatePtr2(project, target.item, 'MediaItem*') then return false end
  local take = reaper.GetActiveTake(target.item)
  if take ~= target.take then return false end
  if action.take or action.kind then
    if not take or not reaper.ValidatePtr2(project, take, 'MediaItem_Take*') then return false end
  end
  if action.kind then
    if not reaper.TakeIsMIDI then return false end
    local midi = reaper.TakeIsMIDI(take)
    if (action.kind == 'midi') ~= midi then return false end
  end
  return true
end

function M.queue(name, items)
  if not M.available(name) or type(items) ~= 'table' or #items == 0 then return false end
  local action = actions[name]
  if action.single and #items ~= 1 then return false end
  local project = reaper.EnumProjects(-1, '')
  if not project then return false end
  local targets, seen = {}, {}
  for _,item in ipairs(items) do
    if not reaper.ValidatePtr2(project, item, 'MediaItem*') then return false end
    local target = {item=item, take=reaper.GetActiveTake(item)}
    if not valid_target(project, target, action) then return false end
    if not seen[item] then targets[#targets+1]=target; seen[item]=true end
  end
  pending[#pending+1] = {project=project, targets=targets, name=name,
    command=name ~= 'take_fx' and command(name) or nil}
  return true
end

local function project_open(project)
  for index=0,10000 do
    local current = reaper.EnumProjects(index, '')
    if not current then return false end
    if current == project then return true end
  end
  return false
end

local function perform(request)
  local project, action = request.project, actions[request.name]
  -- A queued click never switches tabs or writes into a background project.
  if reaper.EnumProjects(-1, '') ~= project then return end
  for _,target in ipairs(request.targets) do
    if not valid_target(project, target, action) then return end
  end
  if request.name == 'take_fx' then
    reaper.TakeFX_Show(request.targets[1].take, -1, 1)
    return
  end
  local selected = {}
  for index=0,reaper.CountSelectedMediaItems(project)-1 do
    selected[#selected+1] = reaper.GetSelectedMediaItem(project, index)
  end
  local ok, err = pcall(function()
    reaper.SelectAllMediaItems(project, false)
    for _,target in ipairs(request.targets) do reaper.SetMediaItemSelected(target.item, true) end
    -- The native action owns its undo point. Do not hold UI refresh suppression
    -- or a script undo block open across a modal dialog.
    reaper.Main_OnCommandEx(request.command, 0, project)
  end)
  if project_open(project) then
    reaper.SelectAllMediaItems(project, false)
    for _,item in ipairs(selected) do
      if reaper.ValidatePtr2(project, item, 'MediaItem*') then reaper.SetMediaItemSelected(item, true) end
    end
    if reaper.UpdateArrange then reaper.UpdateArrange() end
  end
  if not ok then
    require('ReaSpect.core.diagnostics').event('action_error','item.'..request.name..': '..tostring(err))
    if reaper.ShowConsoleMsg then reaper.ShowConsoleMsg('ReaSpect: '..tostring(err)..'\n') end
  end
  return ok
end

function M.process()
  local requests = pending
  pending = {}
  local diagnostics=require('ReaSpect.core.diagnostics')
  for _,request in ipairs(requests) do
    diagnostics.event('action_begin','item.'..request.name)
    if perform(request)~=false then diagnostics.event('action_end','item.'..request.name) end
  end
end

return M
