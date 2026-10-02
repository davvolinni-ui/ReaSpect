local undo = require('ReaSpect.core.undo')
local M = {}

local function track_name(t)
  if not t then return '(unknown)' end
  local _, n = reaper.GetSetMediaTrackInfo_String(t,'P_NAME','',false)
  return (n and n ~= '') and n or ('Track '..tostring(reaper.GetMediaTrackInfo_Value(t,'IP_TRACKNUMBER') or '?'))
end

function M.draw_sends(ctx, track, sends)
  if #sends == 0 then reaper.ImGui_TextDisabled(ctx,'No sends'); return end
  for _, s in ipairs(sends) do
    reaper.ImGui_Text(ctx, track_name(s.dest))
    reaper.ImGui_SameLine(ctx)
    local changed, v = reaper.ImGui_SliderDouble(ctx,'##sendvol'..s.index,s.volume,0,2,'%.2f')
    undo.gesture(ctx,'send_volume_'..s.index,'Set send volume',changed,function() reaper.SetTrackSendInfo_Value(track,0,s.index,'D_VOL',v); reaper.UpdateArrange() end)
    reaper.ImGui_SameLine(ctx)
    local cm, m = reaper.ImGui_Checkbox(ctx,'M##sendmute'..s.index,s.mute)
    if cm then undo.edit('Mute send', function() reaper.SetTrackSendInfo_Value(track,0,s.index,'B_MUTE',m and 1 or 0) end) end
  end
end

function M.draw_receives(ctx, track, receives)
  if #receives == 0 then reaper.ImGui_TextDisabled(ctx,'No receives'); return end
  for _, s in ipairs(receives) do
    reaper.ImGui_Text(ctx, track_name(s.src))
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, string.format('%.2f',s.volume))
  end
end

return M
