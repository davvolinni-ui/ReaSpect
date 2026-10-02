local api=require('ReaSpect.core.reaper_api')
local undo=require('ReaSpect.core.undo')
local M={MIXED='__MIXED__'}

function M.shared(objects,getter)
  if #objects==0 then return nil end
  local value=getter(objects[1])
  for n=2,#objects do
    local other=getter(objects[n])
    if type(value)=='number' and type(other)=='number' then
      if math.abs(value-other)>1e-8 then return M.MIXED end
    elseif value~=other then return M.MIXED end
  end
  return value
end

function M.describe(items)
  local selection={items=items,takes={},audio={},midi={},empty={},scope={}}
  for _,item in ipairs(items) do
    local take=api.item.take(item)
    selection.scope[#selection.scope+1]=tostring(item)..':'..tostring(take)
    if take then
      selection.takes[#selection.takes+1]=take
      local list=api.take.is_midi(take) and selection.midi or selection.audio
      list[#list+1]=item
    else selection.empty[#selection.empty+1]=item end
  end
  selection.kind=#selection.audio==#items and 'audio' or (#selection.midi==#items and 'midi' or (#selection.empty==#items and 'empty' or 'mixed'))
  selection.scope=table.concat(selection.scope,'|')
  return selection
end

function M.edit(objects,label,setter,value)
  undo.edit(label,function()
    for _,object in ipairs(objects) do setter(object,value) end
    reaper.UpdateArrange()
  end)
end

function M.takes(items)
  local takes={}
  for _,item in ipairs(items) do
    local take=api.item.take(item)
    if take then takes[#takes+1]=take end
  end
  return takes
end

-- Relative wheel edits keep mixed selections mixed, including at bounds.
function M.delta_editor(objects,label,getter,setter,min,max,quantum)
  return function(delta)
    M.edit(objects,label,function(object)
      local value=getter(object)+delta
      if min then value=math.max(min,value) end
      if max then value=math.min(max,value) end
      if quantum then value=math.floor(value/quantum+0.5)*quantum end
      setter(object,value)
    end)
  end
end

return M
