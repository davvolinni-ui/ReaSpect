-- Native windows and modal menus must run between complete ImGui frames.
local M = {}
local pending,processing={},false
local generation=0

local function now()
  return reaper.time_precise and reaper.time_precise() or os.clock()
end

local function event(name,job,started,reason)
  local detail=tostring(job.label)..' elapsed='..string.format('%.4f',math.max(0,now()-started))
  if reason then detail=detail..' '..tostring(reason):sub(1,240):gsub('[\r\n]',' ') end
  require('ReaSpect.core.diagnostics').event(name,detail)
end

local function current_project()
  return reaper.EnumProjects and select(1,reaper.EnumProjects(-1,'')) or nil
end

local function valid_track(project,track,guid)
  return track and reaper.ValidatePtr2 and reaper.ValidatePtr2(project,track,'MediaTrack*')
    and reaper.GetTrackGUID and reaper.GetTrackGUID(track)==guid
end

local function resolve_fx(job)
  if job.fx_index==nil then return nil,true end
  if not reaper.TrackFX_GetFXGUID then return nil,false end
  if reaper.TrackFX_GetFXGUID(job.track,job.fx_index)==job.fx_guid then return job.fx_index,true end
  local input=(job.fx_index & 0x1000000)~=0
  local count=input and reaper.TrackFX_GetRecCount or reaper.TrackFX_GetCount
  if not count then return nil,false end
  local offset=input and 0x1000000 or 0
  for i=0,count(job.track)-1 do
    local index=offset+i
    if reaper.TrackFX_GetFXGUID(job.track,index)==job.fx_guid then return index,true end
  end
  return nil,false
end

function M.queue(label,track,callback,fx_index)
  if type(callback)~='function' then return false end
  local project=current_project()
  if not project or not track or not reaper.GetTrackGUID or not reaper.ValidatePtr2
      or not reaper.ValidatePtr2(project,track,'MediaTrack*') then return false end
  local guid=reaper.GetTrackGUID(track)
  if not guid or guid=='' then return false end
  local fx_guid
  if fx_index~=nil then
    if type(fx_index)~='number' or fx_index<0 or fx_index%1~=0 or not reaper.TrackFX_GetFXGUID then return false end
    fx_guid=reaper.TrackFX_GetFXGUID(track,fx_index)
    if not fx_guid or fx_guid=='' then return false end
  end
  pending[#pending+1]={label=tostring(label or 'native_ui'),project=project,track=track,guid=guid,
    callback=callback,fx_index=fx_index,fx_guid=fx_guid}
  return true
end

function M.has_pending() return #pending>0 end

function M.clear()
  pending={}
  generation=generation+1
end

function M.process()
  if processing or #pending==0 then return end
  processing=true
  -- Remove this batch before invoking native code: a modal window may reenter
  -- the script, and callbacks may enqueue work for a later defer tick.
  local batch,epoch=pending,generation
  pending={}
  for _,job in ipairs(batch) do
    local started=now()
    local ok,err=xpcall(function()
      local reason
      if epoch~=generation then reason='cleared'
      elseif current_project()~=job.project then reason='project_changed'
      elseif not valid_track(job.project,job.track,job.guid) then reason='track_deleted' end
      if reason then event('action_drop',job,started,reason);return end
      local index,found=resolve_fx(job)
      if not found then event('action_drop',job,started,'fx_deleted');return end
      event('action_begin',job,started)
      local completed,reason=job.callback(job.track,index)
      if completed==false then event('action_drop',job,started,reason or 'target_changed');return end
      event('action_end',job,started)
    end,debug.traceback)
    if not ok then
      event('action_error',job,started,err)
      if reaper.ShowConsoleMsg then
        -- The failed job has already left the queue and cannot repeat next frame.
        pcall(reaper.ShowConsoleMsg,'ReaSpect '..job.label..': '..tostring(err)..'\n')
      end
    end
  end
  processing=false
end

return M
