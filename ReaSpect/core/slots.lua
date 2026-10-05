-- Visual slot positions are separate from the indices used to edit FX/sends.
local M = {}
local function integer(value)
  value=tonumber(value)
  if value and value==value and value>=0 and value<0x800000 and value%1==0 then return value end
end
function M.fx_supported(track)
  if not reaper.TrackFX_GetNamedConfigParm then return false end
  local ok,value=reaper.TrackFX_GetNamedConfigParm(track,0,'chain_slot_to_index')
  return ok and (integer(value)~=nil or tostring(value):match('^empty:%d+$')~=nil) or false
end

function M.fx_slot(track,index)
  if not reaper.TrackFX_GetNamedConfigParm then return index end
  local ok,value=reaper.TrackFX_GetNamedConfigParm(track,index,'chain_index_to_slot')
  return ok and integer(value) or index
end

function M.fx_index(track,slot)
  if reaper.TrackFX_GetNamedConfigParm then
    local ok,value=reaper.TrackFX_GetNamedConfigParm(track,slot,'chain_slot_to_index')
    if ok then return integer(value),integer(tostring(value):match('^empty:(%d+)$')) end
  end
  local count=reaper.TrackFX_GetCount(track)
  return slot<count and slot or nil,math.min(slot,count)
end

function M.fx_rows(track,items)
  local rows,last={},-1
  for _,fx in ipairs(items) do
    local slot=math.max(last+1,M.fx_slot(track,fx.index))
    for gap=last+1,slot-1 do rows[#rows+1]={slot=gap} end
    rows[#rows+1]={slot=slot,item=fx}
    last=slot
  end
  return rows
end

function M.send_slots_supported(track)
  return reaper.GetTrackNumSends and reaper.GetTrackNumSends(track,0x10000001)==0x10000000
end

function M.send_rows(track,items)
  if not M.send_slots_supported(track) then
    local rows={}
    for i,item in ipairs(items) do rows[i]={slot=i-1,item=item} end
    return rows
  end
  if reaper.GetTrackSendName and reaper.GetTrackSendUIVolPan then
    -- Read native UI order rather than guessing how conflicting hints resolve.
    -- Hints break ties between otherwise identical routes to one destination.
    local candidates,rows={},{}
    local hardware=reaper.GetTrackNumSends(track,1)
    local function candidate(category,index,item,flat)
      local ok,name=reaper.GetTrackSendName(track,flat)
      local valid,volume,pan=reaper.GetTrackSendUIVolPan(track,flat)
      if ok and valid then
        candidates[#candidates+1]={item=item,name=name,volume=volume,pan=pan,
          hint=integer(reaper.GetTrackSendInfo_Value(track,category,index,'I_SLOT_HINT'))}
      end
    end
    for i=0,hardware-1 do candidate(1,i,nil,i) end
    for _,item in ipairs(items) do candidate(0,item.index,item,hardware+item.index) end
    local count=reaper.GetTrackNumSends(track,0x10000000)
    for slot=0,count-1 do
      local ok,name=reaper.GetTrackSendName(track,0x10000000|slot)
      local valid,volume,pan=reaper.GetTrackSendUIVolPan(track,0x10000000|slot)
      local match
      if ok and valid then
        local best=-1
        for i,c in ipairs(candidates) do
          if not c.used and c.name==name then
            -- Hint and stable route order still bind automated sends when
            -- their volume changes between native snapshot reads.
            local score=(c.hint==slot and 4 or 0)
              +(math.abs(c.volume-volume)<1e-9 and 1 or 0)
              +(math.abs(c.pan-pan)<1e-9 and 1 or 0)
            if score>best then match,best=i,score end
          end
        end
      end
      local c=match and candidates[match]
      if c then c.used=true end
      rows[#rows+1]={slot=slot,item=c and c.item,reserved=ok and valid and not (c and c.item) or false}
    end
    -- If the snapshot changed midway, retain all routes and try again next
    -- frame instead of dropping controls or binding one to an unrelated send.
    for _,c in ipairs(candidates) do
      if not c.used and c.item then rows[#rows+1]={slot=#rows,item=c.item} end
    end
    return rows
  end
  local rows,last={},-1
  -- Hardware outputs occupy the beginning of REAPER's combined send list.
  -- Leave their positions reserved; their controls remain in native routing.
  local function append(category,index,item)
    local hint=reaper.GetTrackSendInfo_Value(track,category,index,'I_SLOT_HINT')
    local slot=math.max(last+1,integer(hint) or 0)
    for gap=last+1,slot-1 do rows[#rows+1]={slot=gap} end
    rows[#rows+1]={slot=slot,item=item,reserved=not item}
    last=slot
  end
  for i=0,reaper.GetTrackNumSends(track,1)-1 do append(1,i) end
  for _,item in ipairs(items) do append(0,item.index,item) end
  return rows
end

return M
