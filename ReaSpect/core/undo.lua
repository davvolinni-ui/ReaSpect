local M = {}
M.gestures = {}

function M.begin(label)
  if reaper.Undo_BeginBlock2 then reaper.Undo_BeginBlock2(0) else reaper.Undo_BeginBlock() end
  M.label = label
end

function M.finish(label)
  local name = label or M.label or 'ReaSpect edit'
  if reaper.Undo_EndBlock2 then reaper.Undo_EndBlock2(0, name, -1) else reaper.Undo_EndBlock(name, -1) end
  M.label = nil
end

function M.edit(label, fn)
  M.begin(label)
  local ok, err = pcall(fn)
  M.finish(label)
  if not ok then reaper.ShowConsoleMsg('ReaSpect: '..tostring(err)..'\n') end
  return ok
end

-- Apply a continuous ImGui edit as one logical REAPER undo point.
function M.gesture(ctx, id, label, changed, fn)
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
