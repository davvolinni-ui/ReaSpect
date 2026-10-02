local controls = require('ReaSpect.widgets.controls')
local prop = require('ReaSpect.widgets.property')
local undo = require('ReaSpect.core.undo')
local M = {}
local pending = {}
local add_action

local function current_project()
  return reaper.EnumProjects and reaper.EnumProjects(-1, '') or 0
end

local function finite(value)
  return type(value)=='number' and value==value and value~=math.huge and value~=-math.huge
end

local function capture(track, fx, param, project)
  if not track or not finite(fx) or fx<0 or not finite(param) or param<0 then return end
  if reaper.ValidatePtr2 and not reaper.ValidatePtr2(project,track,'MediaTrack*') then return end
  if not (reaper.TrackFX_GetFXGUID and reaper.TrackFX_GetNumParams) then return end
  local guid=reaper.TrackFX_GetFXGUID(track,fx)
  if not guid or guid=='' or param>=reaper.TrackFX_GetNumParams(track,fx) then return end
  local ident
  if reaper.TrackFX_GetParamIdent then
    local ok,value=reaper.TrackFX_GetParamIdent(track,fx,param)
    if ok then ident=value end
  end
  return {track=track,fx=fx,param=param,project=project,guid=guid,ident=ident}
end

local function valid(ref)
  if not ref or current_project()~=ref.project then return false end
  local now=capture(ref.track,ref.fx,ref.param,ref.project)
  return now and now.guid==ref.guid and now.ident==ref.ident or false
end

local function touched(track,project)
  if not reaper.GetTouchedOrFocusedFX then return end
  local ok,track_index,item_index,_,fx,param=reaper.GetTouchedOrFocusedFX(0)
  if not ok or item_index~=-1 then return end
  local owner=track_index==-1 and reaper.GetMasterTrack(project) or reaper.GetTrack(project,track_index)
  if owner~=track then return end
  return capture(track,fx,param,project)
end

local function same_parameter(a,b)
  return a and b and a.project==b.project and a.track==b.track and a.fx==b.fx
    and a.guid==b.guid and a.param==b.param and a.ident==b.ident
end

local function assigned(ref)
  for index=0,reaper.CountTCPFXParms(ref.project,ref.track)-1 do
    local ok,fx,param=reaper.GetTCPFXParm(ref.project,ref.track,index)
    if ok and fx==ref.fx and param==ref.param then return true end
  end
  return false
end

local function track_control_action()
  if add_action~=nil then return add_action or nil end
  add_action=false
  if not (reaper.SectionFromUniqueID and reaper.kbd_enumerateActions and reaper.Main_OnCommandEx) then return end
  -- Ask REAPER for the native action instead of relying on a guessed command ID.
  local name='FX: Show/hide track control for last touched FX parameter'
  local localized=reaper.LocalizeString and reaper.LocalizeString(name,'actions',0) or name
  local section=reaper.SectionFromUniqueID(0)
  if not section then return end
  for index=0,65535 do
    local command,label=reaper.kbd_enumerateActions(section,index)
    if not command or command==0 then break end
    if label==name or label==localized then add_action=command;return command end
  end
end

local function parameter_name(ref)
  local ok,name=reaper.TrackFX_GetParamName(ref.track,ref.fx,ref.param)
  return ok and name~='' and name or ('Parameter '..(ref.param+1))
end

local function effect_name(ref)
  local ok,name=reaper.TrackFX_GetFXName(ref.track,ref.fx)
  local result=ok and name~='' and name or ('FX '..(ref.fx+1))
  result=result:gsub('^[^:]+:%s*','')
  return result
end

local function fit(ctx,text,width)
  if not reaper.ImGui_CalcTextSize then return text end
  while #text>0 and reaper.ImGui_CalcTextSize(ctx,text)>width do
    local last=utf8.offset(text,-1)
    text=text:sub(1,(last or #text)-1)
  end
  return text
end

local function default_value(ref)
  if not reaper.TrackFX_GetNamedConfigParm then return end
  -- Native normalized plug-in defaults are optional; 0 or 0.5 is not a default.
  local ok,value=reaper.TrackFX_GetNamedConfigParm(ref.track,ref.fx,'param.'..ref.param..'.default_value')
  value=tonumber(value)
  if ok and finite(value) and value>=0 and value<=1 then return value end
end

local function envelope_supported(ref)
  if (ref.fx&0x1000000)~=0 then return false end
  if not (reaper.GetFXEnvelope and reaper.GetSetEnvelopeInfo_String) then return false end
  if reaper.TrackFX_GetNamedConfigParm then
    local ok,value=reaper.TrackFX_GetNamedConfigParm(ref.track,ref.fx,'param.'..ref.param..'.automatable')
    if ok and tonumber(value)==0 then return false end
  end
  return true
end

local function envelope_visible(ref)
  local env=reaper.GetFXEnvelope(ref.track,ref.fx,ref.param,false)
  if not env then return false end
  local ok,value=reaper.GetSetEnvelopeInfo_String(env,'VISIBLE','',false)
  if not ok then return nil end
  return value=='1'
end

local function refresh()
  if reaper.TrackList_AdjustWindows then reaper.TrackList_AdjustWindows(false) end
  if reaper.UpdateArrange then reaper.UpdateArrange() end
end

function M.process()
  local jobs=pending
  pending={}
  for _,job in ipairs(jobs) do
    local ref=job.ref
    if valid(ref) then
      if job.kind=='add' then
        -- The action is global-last-touched. Revalidate immediately before it
        -- runs, and skip already assigned controls so a double click cannot hide one.
        local now=touched(ref.track,ref.project)
        if same_parameter(ref,now) and not assigned(ref) and track_control_action() then
          undo.edit('Show FX parameter in track controls',function()
            reaper.Main_OnCommandEx(track_control_action(),0,ref.project)
            refresh()
          end)
        end
      elseif job.kind=='envelope' and envelope_supported(ref) then
        undo.edit(job.visible and 'Show FX parameter envelope' or 'Hide FX parameter envelope',function()
          local env=reaper.GetFXEnvelope(ref.track,ref.fx,ref.param,false)
          -- create=true also unbypasses existing envelopes. Never pass it for an
          -- existing envelope: visibility must preserve bypass, arm and points.
          if not env and job.visible then env=reaper.GetFXEnvelope(ref.track,ref.fx,ref.param,true) end
          if env then
            reaper.GetSetEnvelopeInfo_String(env,'VISIBLE',job.visible and '1' or '0',true)
            refresh()
          end
        end)
      end
    end
  end
end

local function draw_parameter(ctx,ref,index)
  local name=parameter_name(ref)
  local title=effect_name(ref)..' · '..name
  local width=reaper.ImGui_GetContentRegionAvail(ctx)
  reaper.ImGui_TextDisabled(ctx,fit(ctx,title,width))
  prop.tooltip(ctx,title)
  local suffix=tostring(ref.project)..':'..tostring(ref.track)..':'..ref.guid..':'..ref.param..':'..index
  local value=reaper.TrackFX_GetParamNormalized(ref.track,ref.fx,ref.param)
  if not finite(value) then reaper.ImGui_TextDisabled(ctx,'Parameter unavailable');return end
  local ok,formatted=reaper.TrackFX_GetFormattedParamValue(ref.track,ref.fx,ref.param)
  if not ok or not formatted or formatted=='' then formatted=string.format('%.3f',value) end
  local format=formatted:gsub('%%','%%%%')
  local env_supported=envelope_supported(ref)
  local visible=env_supported and envelope_visible(ref)
  local env_label=visible and 'Hide env' or 'Show env'
  local env_width=reaper.ImGui_CalcTextSize and reaper.ImGui_CalcTextSize(ctx,env_label)+12 or 72
  reaper.ImGui_SetNextItemWidth(ctx,math.max(24,width-(env_supported and (env_width+4) or 0)))
  local flags=reaper.ImGui_SliderFlags_NoInput and reaper.ImGui_SliderFlags_NoInput() or 0
  local changed,out=reaper.ImGui_SliderDouble(ctx,'##fxparam_'..suffix,value,0,1,format,flags)
  local wheel,next_value=controls.wheel(ctx,value,.01,0,1)
  local default=default_value(ref)
  if default~=nil and controls.right_click(ctx) then changed,out=default~=value,default
  elseif wheel then changed,out=true,next_value end
  local held=reaper.ImGui_IsItemActive(ctx)
  local released=reaper.ImGui_IsItemDeactivatedAfterEdit(ctx)
  undo.gesture(ctx,'fxparam:'..suffix,'Set '..name,changed,function()
    if valid(ref) then reaper.TrackFX_SetParamNormalized(ref.track,ref.fx,ref.param,math.max(0,math.min(1,out))) end
  end)
  if reaper.TrackFX_EndParamEdit and ((changed and not held) or released) and valid(ref) then
    reaper.TrackFX_EndParamEdit(ref.track,ref.fx,ref.param)
  end
  local hint=title..'\n'..formatted..'\nWheel: adjust  •  Shift: fine  •  Ctrl: coarse'
  if default~=nil then hint=hint..'\nRight-click: reset to plug-in default' end
  prop.tooltip(ctx,hint)
  if env_supported then
    reaper.ImGui_SameLine(ctx,0,4)
    if reaper.ImGui_Button(ctx,env_label..'##fxenv_'..suffix,env_width) and visible~=nil then
      pending[#pending+1]={kind='envelope',ref=ref,visible=not visible}
    end
    prop.tooltip(ctx,visible and 'Hide this envelope; keep its points, arm and bypass states.'
      or 'Show this parameter envelope. Existing points, arm and bypass states are preserved.')
  end
end

function M.draw(ctx,state)
  local track=state.selected_track
  if not track or not (reaper.CountTCPFXParms and reaper.GetTCPFXParm) then return end
  local project=current_project()
  if state.project and state.project~=project then return end
  if reaper.ValidatePtr2 and not reaper.ValidatePtr2(project,track,'MediaTrack*') then return end
  if not prop.section(ctx,state,'track_fx_parameters','FX parameters',false) then return end
  if #(state.selected_tracks or {})>1 then reaper.ImGui_TextDisabled(ctx,'Focused track only') end
  local count=reaper.CountTCPFXParms(project,track)
  for index=0,count-1 do
    local ok,fx,param=reaper.GetTCPFXParm(project,track,index)
    local ref=ok and capture(track,fx,param,project)
    if ref then draw_parameter(ctx,ref,index) end
  end
  if count==0 then reaper.ImGui_TextDisabled(ctx,'No exposed FX parameters') end
  local ref=touched(track,project)
  local action=track_control_action()
  if ref and not assigned(ref) and action then
    if reaper.ImGui_Button(ctx,'Add last touched##fxparam_add') then
      pending[#pending+1]={kind='add',ref=ref}
    end
    prop.tooltip(ctx,'Show '..effect_name(ref)..' · '..parameter_name(ref)..' in track controls and here.')
  else
    reaper.ImGui_TextDisabled(ctx,ref and assigned(ref) and 'Last touched parameter is already shown'
      or 'Expose a parameter from the FX Param menu')
    prop.tooltip(ctx,'In an FX window, touch a parameter and choose Param > Show in track controls.\nOnly parameters on the focused track are shown here.')
  end
end

return M
