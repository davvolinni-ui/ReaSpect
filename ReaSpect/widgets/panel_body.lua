local controls=require('ReaSpect.widgets.controls')
local M={}

-- Headers belong to the fixed outer panel. Only the remaining body gets a
-- scroll region, so editing or scrolling never moves the track/event identity.
function M.draw(ctx,id,draw)
  local _,height=reaper.ImGui_GetContentRegionAvail(ctx)
  if not height or height<=0 then return false end
  reaper.ImGui_PushStyleVar(ctx,reaper.ImGui_StyleVar_WindowPadding(),0,0)
  reaper.ImGui_PushStyleVar(ctx,reaper.ImGui_StyleVar_ScrollbarSize(),8)
  local visible=reaper.ImGui_BeginChild(ctx,id,-1,height,0,controls.scroll_flags())
  reaper.ImGui_PopStyleVar(ctx,2)
  if visible then
    draw()
    controls.scroll_end(ctx)
    reaper.ImGui_EndChild(ctx)
  end
  return visible
end

return M
