local M = {}

M.mode_labels = {'Project default','Stereo balance (classic)','Stereo balance','Stereo pan','Dual pan'}
M.mode_values = {-1,0,3,5,6}

function M.mode(track)
  return reaper.GetMediaTrackInfo_Value(track,'I_PANMODE') or -1
end

function M.effective_mode(track)
  local mode=M.mode(track)
  -- The stored -1 means project default. The native UI query resolves it,
  -- including projects whose default is dual pan.
  if mode<0 and reaper.GetTrackUIPan then
    local ok,_,_,effective=reaper.GetTrackUIPan(track)
    if ok and type(effective)=='number' and effective>=0 then return effective end
  end
  return mode
end

function M.set_mode(track,value)
  return reaper.SetMediaTrackInfo_Value(track,'I_PANMODE',value)
end

M.law_labels = {'Project default','0 dB','-2.5 dB','-3 dB','-4.5 dB','-6 dB',
  '-2.5 dB + gain','-3 dB + gain','-4.5 dB + gain','-6 dB + gain'}
M.law_values = {-1,1}
for _,db in ipairs({-2.5,-3,-4.5,-6,2.5,3,4.5,6}) do
  M.law_values[#M.law_values+1]=10^(db/20)
end

function M.law(track)
  local value=reaper.GetMediaTrackInfo_Value(track,'D_PANLAW')
  if not value or value<0 then return -1 end
  -- Native versions use both exact dB gains and rounded -3/-6 dB constants.
  -- Canonicalize only for the menu; simply displaying it never writes a value.
  for _,option in ipairs(M.law_values) do
    if option>0 and math.abs(value-option)<option*0.003 then return option end
  end
  return value
end

function M.set_law(track,value)
  -- D_PANLAW > 1 is REAPER's gain-compensated pan law. Taper flags are
  -- independent and are intentionally preserved when changing attenuation.
  return reaper.SetMediaTrackInfo_Value(track,'D_PANLAW',value)
end

return M
