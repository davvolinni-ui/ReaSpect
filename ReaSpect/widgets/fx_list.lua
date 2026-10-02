local undo = require('ReaSpect.core.undo')
local M = {}

function M.draw(ctx, track, fx)
  if #fx == 0 then reaper.ImGui_TextDisabled(ctx,'No inserts'); return end
  for _, f in ipairs(fx) do
    local enabled = f.enabled and not f.offline
    local changed, new = reaper.ImGui_Checkbox(ctx, '##fxen'..f.index, enabled)
    if changed then undo.edit('Toggle FX: '..f.name, function() reaper.TrackFX_SetEnabled(track,f.index,new) end) end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Selectable(ctx, f.name, false) and reaper.TrackFX_Show then reaper.TrackFX_Show(track,f.index,1) end
    if f.offline then reaper.ImGui_SameLine(ctx); reaper.ImGui_TextDisabled(ctx,'offline') end
  end
end

return M
