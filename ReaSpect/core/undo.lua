local M = {}
M.gestures = {}
local wheel_source=false
local wheel_edit
local inline_depth=0
local context

function M.set_context(value)
  if context~=value then M.flush_wheel();M.flush_gestures();context=value end
end

function M.property_gesture(ctx,id,label,changed,fn)
  M.gesture(ctx,id,label,changed,function()
    inline_depth=inline_depth+1
    local ok,err=pcall(fn)
    inline_depth=inline_depth-1
    if not ok then error(err) end
  end)
end

function M.wheel_source(value) wheel_source=value end

function M.flush_wheel()
  local pending=wheel_edit
  wheel_edit=nil
  if pending then
    reaper.Undo_OnStateChangeEx2(pending.project,pending.label,-1,-1)
  end
end

function M.poll()
  if wheel_edit and (reaper.time_precise()-wheel_edit.time>=0.25
      or (reaper.EnumProjects and reaper.EnumProjects(-1,'')~=wheel_edit.project)) then M.flush_wheel() end
end

function M.begin(label)
  M.flush_wheel()
  M.project=reaper.EnumProjects and reaper.EnumProjects(-1,'') or 0
  if reaper.Undo_BeginBlock2 then reaper.Undo_BeginBlock2(M.project) else reaper.Undo_BeginBlock() end
  M.label = label
end

function M.finish(label)
  local name = label or M.label or 'ReaSpect edit'
  if reaper.Undo_EndBlock2 then reaper.Undo_EndBlock2(M.project or 0, name, -1) else reaper.Undo_EndBlock(name, -1) end
  M.label = nil
  M.project = nil
end

function M.edit(label, fn)
  if inline_depth>0 then return fn() end
  -- Wheel changes are live, but publishing an undo point for every detent
  -- repeatedly redraws REAPER's menu. Deferred scripts can snapshot state
  -- once after a short idle period without holding an undo block open.
  if wheel_source and reaper.Undo_OnStateChangeEx2 and reaper.time_precise then
    local project=reaper.EnumProjects and reaper.EnumProjects(-1,'') or 0
    if wheel_edit and (wheel_edit.label~=label or wheel_edit.project~=project) then M.flush_wheel() end
    local ok,err=pcall(fn)
    wheel_edit={project=project,label=label,time=reaper.time_precise()}
    if not ok then
      M.flush_wheel()
      if reaper.ShowConsoleMsg then reaper.ShowConsoleMsg('ReaSpect: '..tostring(err)..'\n') end
    end
    return ok
  end
  M.begin(label)
  local ok, err = pcall(fn)
  M.finish(label)
  if not ok then reaper.ShowConsoleMsg('ReaSpect: '..tostring(err)..'\n') end
  return ok
end

-- Apply a continuous ImGui edit as one logical REAPER undo point.
function M.gesture(ctx, id, label, changed, fn)
  if changed and wheel_source and not M.gestures[id] then return M.edit(label,fn) end
  local active = M.gestures[id]
  local held = reaper.ImGui_IsItemActive and reaper.ImGui_IsItemActive(ctx)
  local deactivated = reaper.ImGui_IsItemDeactivatedAfterEdit and reaper.ImGui_IsItemDeactivatedAfterEdit(ctx)
  if changed then
    if not held then
      -- Wheel changes are discrete edits, not a mouse gesture.  They must not
      -- leave an undo block open waiting for an item-deactivation event.
      if active then
        local ok,err=pcall(fn)
        M.finish(label)
        M.gestures[id]=nil
        if not ok and reaper.ShowConsoleMsg then reaper.ShowConsoleMsg('ReaSpect: '..tostring(err)..'\n') end
      else
        M.edit(label, fn)
      end
      return
    end
    if not active then M.begin(label); M.gestures[id]=label; active=label end
    local ok,err=pcall(fn)
    if not ok then
      M.finish(label)
      M.gestures[id]=nil
      if reaper.ShowConsoleMsg then reaper.ShowConsoleMsg('ReaSpect: '..tostring(err)..'\n') end
      return
    end
  end
  if active and (deactivated or not held) then
    M.finish(label)
    M.gestures[id]=nil
  end
end

function M.flush_gestures()
  for id,label in pairs(M.gestures) do
    M.finish(label)
    M.gestures[id]=nil
  end
end

return M
