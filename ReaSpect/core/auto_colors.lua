local presets=require('ReaSpect.core.palettes')
local M={presets=presets}
local roles_model=require('ReaSpect.core.track_roles')
local role_icons=require('ReaSpect.core.role_icons')
local role_palettes=require('ReaSpect.core.role_palettes')
M.role_palettes=role_palettes
local persistence=require('ReaSpect.core.persistence')
M.roles_model=roles_model
local default_hex={}
for i,rgb in ipairs(presets[1].colors) do default_hex[i]=string.format('%06X',rgb) end
default_hex=table.concat(default_hex,' ')
local section='ReaSpect.AutoColors'
local prefix='P_EXT:ReaSpect.AutoColors.'
local last_project,last_change,next_poll
local last_preferences
local project_baselines={}
local observed_project,observed_preferences,observed_filename,observed_guid
local preference_keys={'enabled','palette','children','protect','custom','roles','roles_data','role_icons','child_priority','family_gradients','role_palette','family_bases','role_behaviors','role_children','unmatched','smart_setup'}

local function project() return reaper.EnumProjects(-1,'') end
local function get(proj,key,default)
  if key~='next_slot' then
    local _,v=reaper.GetSetMediaTrackInfo_String(reaper.GetMasterTrack(proj),prefix..'config.'..key,'',false)
    if v=='@empty' then return '' end
    return v~='' and v or default
  end
  local _,v=reaper.GetProjExtState(proj,section,key)
  return v~='' and v or default
end
local function put(proj,key,value)
  value=tostring(value)
  if get(proj,key,nil)==value then return end
  -- Master-track metadata saves with the project and participates in native
  -- track undo. Project ExtState alone is not restored by REAPER's undo.
  if key~='next_slot' then
    reaper.GetSetMediaTrackInfo_String(reaper.GetMasterTrack(proj),prefix..'config.'..key,value=='' and '@empty' or value,true)
  else reaper.SetProjExtState(proj,section,key,tostring(value)) end
end
local function track_get(track,key)
  local _,v=reaper.GetSetMediaTrackInfo_String(track,prefix..key,'',false)
  return v or ''
end
local function track_put(track,key,value)
  value=tostring(value)
  if track_get(track,key)~=value then reaper.GetSetMediaTrackInfo_String(track,prefix..key,value,true) end
end
M.track_get=track_get
local function valid_slot(value)
  local n=tonumber(value)
  if n and n>=1 and n<=0x7FFFFFFF and n%1==0 then return math.tointeger(n) end
end
local function track_slot(track) return valid_slot(track_get(track,'slot')) end
local function allocate_slot(next_slot,used)
  next_slot=valid_slot(next_slot) or 1
  while used[next_slot] do next_slot=next_slot%0x7FFFFFFF+1 end
  used[next_slot]=true
  return next_slot,next_slot%0x7FFFFFFF+1
end
function M.project_allowed(proj)
  if not proj or proj==0 then proj=project() end
  local active,filename=reaper.EnumProjects(-1,'')
  if proj~=active then
    filename=nil
    for i=0,1023 do
      local candidate,path=reaper.EnumProjects(i,'')
      if not candidate then break end
      if candidate==proj then filename=path;break end
    end
    if filename==nil then return false end
  end
  -- Existing saved projects require their own explicit approval. A new,
  -- unsaved project may use the user's remembered preferences immediately.
  return not filename or filename=='' or get(proj,'approved','0')=='1'
end
function M.approve_project() M.apply_project(false) end
function M.config(proj)
  if not proj or proj==0 then proj=project() end
  local initialized=get(proj,'initialized','')=='1'
  local baseline=project_baselines[proj]
  local active,filename=reaper.EnumProjects(-1,'')
  if baseline and active==proj and reaper.GetProjectGUID and baseline.guid~=reaper.GetProjectGUID(proj) then
    project_baselines[proj]=nil;baseline=nil
  end
  if baseline and active==proj and baseline.filename~=(filename or '') then
    if initialized then baseline.filename=filename or '' else project_baselines[proj]=nil;baseline=nil end
  end
  local function pref(key,default)
    local fallback
    if not initialized and baseline then fallback=baseline.values[key] end
    if fallback==nil then fallback=initialized and default or persistence.get('auto_colors_default_'..key,default) end
    if type(fallback)=='boolean' then fallback=fallback and '1' or '0' end
    return get(proj,key,fallback)
  end
  return {enabled=pref('enabled','0')=='1',palette=pref('palette',presets[1].name),
    children=pref('children','independent'),protect=pref('protect','1')=='1',
    custom=pref('custom',default_hex),roles=pref('roles',initialized and '0' or '1')=='1',
    roles_data=pref('roles_data',''),role_icons=pref('role_icons','0')=='1',
    child_priority=pref('child_priority',initialized and 'current' or 'smart'),family_gradients=pref('family_gradients',''),
    role_palette=pref('role_palette',initialized and 'slots' or 'classic'),
    family_bases=pref('family_bases',''),role_behaviors=pref('role_behaviors',''),role_children=pref('role_children',''),
    unmatched=pref('unmatched','separate'),
    smart_setup=pref('smart_setup',initialized and '1' or persistence.get('auto_colors_smart_setup','0'))=='1'}
end
function M.smart_config()
  local config=M.config()
  if not config.smart_setup then
    config.roles=true;config.role_icons=true
    local roles=roles_model.decode(config.roles_data)
    local old_common={drums=true,kick=true,snare=true,bass=true,electric=true,piano=true,lead_vocal=true,returns=true}
    local old_profile=#roles==33
    for _,r in ipairs(roles) do if r.id~='keys' and r.enabled~=(old_common[r.id]==true) then old_profile=false;break end end
    if old_profile then
      local defaults=roles_model.defaults()
      for _,r in ipairs(roles) do r.enabled=roles_model.by_id(defaults,r.id).enabled end
      config.roles_data=roles_model.encode(roles)
    end
  end
  return config
end
local function pref_value(config,key)
  local value=config[key]
  if type(value)=='boolean' then return value and '1' or '0' end
  return value
end
local function snapshot(proj)
  if get(proj,'initialized','')=='1' then return end
  local config=M.config(proj)
  local _,filename=reaper.EnumProjects(-1,'')
  if not project_baselines[proj] then project_baselines[proj]={values=config,filename=filename or '',
    guid=reaper.GetProjectGUID and reaper.GetProjectGUID(proj) or nil} end
  for _,key in ipairs(preference_keys) do put(proj,key,pref_value(config,key)) end
  put(proj,'initialized','1')
end
local function remember(proj)
  local config=M.config(proj)
  for _,key in ipairs(preference_keys) do
    local value=pref_value(config,key)
    if persistence.get('auto_colors_default_'..key,nil)~=value then persistence.set('auto_colors_default_'..key,value) end
  end
  local setup=config.smart_setup and '1' or '0'
  if persistence.get('auto_colors_smart_setup','0')~=setup then persistence.set('auto_colors_smart_setup',setup) end
end
local function signature(config)
  local values={};for i,key in ipairs(preference_keys) do values[i]=pref_value(config,key) end
  return table.concat(values,'\31')
end
function M.role_palette_color(config,role)
  local flat,explicit_shades=false,false
  for name in (config.family_gradients or ''):gmatch('[^,]+') do
    if name=='!'..role.group then flat=true end
    if name==role.group then explicit_shades=true end
  end
  for group,hex in (config.family_bases or ''):gmatch('([^\n=]+)=(%x%x%x%x%x%x)') do
    if group==role.group then
      local rgb=tonumber(hex,16)
      local preset=role_palettes.find(config.role_palette)
      local shaded=not flat and (explicit_shades or (preset and preset.colors[role.group]~=nil))
      return shaded and role_palettes.shade(rgb,role.id) or rgb
    end
  end
  local themed=role_palettes.color(config.role_palette,role,flat)
  if themed then return themed end
  local palette=M.palette(config)
  if role.group=='Custom' then
    local preset=role_palettes.find(config.role_palette)
    local base=preset and preset.fallback[1] or palette[1]
    return explicit_shades and not flat and role_palettes.shade(base,role.id) or base
  end
  if config.role_palette~='families' and config.role_palette~='contrast' then
    return palette[((role.palette_slot or 1)-1)%#palette+1]
  end
  local anchors={Drums=1,Bass=4,Guitars=7,Keys=9,Orchestral=11,Vocals=13,Utility=16}
  local anchor=anchors[role.group]
  if not anchor then return palette[((role.palette_slot or 1)-1)%#palette+1] end
  local index,count=1,0
  for _,definition in ipairs(roles_model.definitions) do
    if definition[3]==role.group then count=count+1;if definition[1]==role.id then index=count end end
  end
  local rgb=palette[math.floor((anchor-1)*(#palette-1)/15)+1]
  if index==1 or count<=1 then return rgb end
  local spread=config.role_palette=='contrast' and 0.24 or 0.12
  local amount=-spread+2*spread*(index-2)/math.max(1,count-2)
  local function shade(v) return math.floor((amount<0 and v*(1+amount) or v+(255-v)*amount)+0.5) end
  return (shade((rgb>>16)&255)<<16)|(shade((rgb>>8)&255)<<8)|shade(rgb&255)
end
function M.roles(config)
  config=config or M.config()
  local roles=roles_model.decode(config.roles_data)
  local palette=M.palette(config)
  for _,r in ipairs(roles) do
    if not r.color_custom then r.color=M.role_palette_color(config,r) end
  end
  return roles
end
function M.parse_custom(text)
  local colors={}
  for token in tostring(text):gmatch('[^,%s]+') do
    token=token:gsub('^#','')
    if not token:match('^%x%x%x%x%x%x$') then return nil,'Use six-digit RGB hex colors, separated by spaces or commas.' end
    colors[#colors+1]=tonumber(token,16)
  end
  if #colors<2 or #colors>64 then return nil,'Use between 2 and 64 colors.' end
  return colors
end
function M.palette(config)
  if config.palette=='Custom' then return M.parse_custom(config.custom) or presets[1].colors end
  for _,p in ipairs(presets) do if p.name==config.palette then return p.colors end end
  return presets[1].colors
end
local function native(rgb)
  return reaper.ColorToNative((rgb>>16)&255,(rgb>>8)&255,rgb&255)|0x1000000
end
function M.track_palette(config)
  local theme=role_palettes.find(config.role_palette)
  return config.unmatched=='theme' and theme and theme.fallback or M.palette(config)
end
function M.manual_palette(config)
  local preset=role_palettes.find(config.role_palette)
  if config.unmatched~='theme' or not preset then return M.track_palette(config) end
  local colors,seen={},{}
  local function add(rgb) if rgb and not seen[rgb] then colors[#colors+1]=rgb;seen[rgb]=true end end
  for _,group in ipairs({'Drums','Bass','Guitars','Keys','Orchestral','Vocals','Utility'}) do add(M.family_color(group,config)) end
  for _,rgb in ipairs(preset.fallback) do add(rgb) end
  add(preset.buses);add(preset.reference)
  return colors
end
local assigned_role
local function role_children(config,id)
  for role,value in (config.role_children or ''):gmatch('([%w_]+):([%w_]+)') do if role==id then return value end end
  local legacy={role='independent',match='uniform',shade='shades'}
  for role,value in (config.role_behaviors or ''):gmatch('([%w_]+):([%w_]+)') do if role==id then return legacy[value] or 'auto' end end
  return 'auto'
end
local function folder_policy(parent,config,skip_override)
  while parent do
    local rule=parent~=skip_override and track_get(parent,'children') or ''
    if rule=='parent' then
      parent=reaper.GetParentTrack(parent)
    else
    if rule=='smart' then return 'gradient','smart' end
    if rule=='shades' then return 'gradient','strict' end
    if rule=='inherit' or rule=='uniform' or rule=='independent' or rule=='gradient' then return rule end
    local role=assigned_role(parent,config,M.roles(config))
    local behavior=role and role_children(config,role.id) or 'auto'
    if behavior=='smart' then return 'gradient','smart' end
    if behavior=='shades' then return 'gradient','strict' end
    if behavior=='uniform' or behavior=='independent' then return behavior end
    -- A folder boundary stops policy propagation unless explicitly requested.
    break
    end
  end
  if config.children=='smart' then return 'gradient','smart' end
  if config.children=='shades' then return 'gradient','strict' end
  return config.children
end
local function children_policy(track,config)
  local ancestor=reaper.GetParentTrack(track)
  local owner
  while ancestor do
    if track_get(ancestor,'children_scope')=='all' then owner=ancestor;break end
    ancestor=reaper.GetParentTrack(ancestor)
  end
  if owner then
    local rule,priority=folder_policy(owner,config)
    return rule,priority,owner
  end
  return folder_policy(reaper.GetParentTrack(track),config)
end
function M.folder_default(track)
  local config=M.config()
  local rule,priority=folder_policy(track,config,track)
  if rule=='gradient' and priority=='smart' then return 'smart' end
  if rule=='gradient' and priority=='strict' then return 'shades' end
  return rule
end
function M.gradient_color(rgb,index,count)
  if count<=1 then return rgb end
  -- One continuous tint ramp from the folder color toward a lighter shade.
  -- Use the whole folder length rather than cycling through fixed bands.
  local position=math.max(0,math.min(1,(index-1)/(count-1)))
  local amount=0.40*position
  local function channel(value)
    return math.floor(math.max(0,math.min(255,amount<0 and value*(1+amount) or value+(255-value)*amount))+0.5)
  end
  return (channel((rgb>>16)&255)<<16)|(channel((rgb>>8)&255)<<8)|channel(rgb&255)
end
local function track_name(track)
  local _,name=reaper.GetSetMediaTrackInfo_String(track,'P_NAME','',false)
  return name or ''
end
local function folder_shade_position(track,parent,config,resolved)
  resolved.folder_shades=resolved.folder_shades or {}
  local sequence=resolved.folder_shades[parent]
  if not sequence then
    sequence={count=0};resolved.folder_shades[parent]=sequence
    for i=0,reaper.CountTracks(project())-1 do
      local child=reaper.GetTrack(project(),i)
      local _,_,owner=children_policy(child,config)
      if (owner or reaper.GetParentTrack(child))==parent then
        sequence.count=sequence.count+1;sequence[child]=sequence.count
      end
    end
  end
  return sequence[track] or 1,sequence.count
end
assigned_role=function(track,config,roles,for_icons)
  local role=roles_model.by_id(roles,track_get(track,'role'))
  if role then return role,'Assigned role: '..role.name end
  if config.roles or (for_icons and config.role_icons) then
    local detected,word=roles_model.detect(track_name(track),roles)
    if detected then return detected,detected.name..' · matched "'..word..'"' end
    if word then return nil,word end
  end
end
local function target_color(track,config,roles,palette,slot,resolved,mode_override)
  local mode=mode_override or track_get(track,'mode')
  local parent=reaper.GetParentTrack(track)
  local role,reason=assigned_role(track,config,roles)
  if track_get(track,'role')~='' and role and mode~='inherit' and mode~='independent' then return native(role.color),reason end
  if mode=='role' then
    local detected,word=roles_model.detect(track_name(track),roles)
    if detected then return native(detected.color),'Detected role color: '..detected.name end
    reason=word or 'No matching role'
    -- This explicit request bypasses folder treatment, even without a match.
    return native(palette[(slot-1)%#palette+1]),reason..' · unmatched track palette'
  end
  if mode=='inherit' and not parent then
    return native(palette[(slot-1)%#palette+1]),'No parent · unmatched track color'
  end
  local policy,priority,scope_owner=children_policy(track,config)
  if mode~='inherit' and mode~='independent' then parent=scope_owner or parent end
  priority=priority or config.child_priority
  local folder_applies=parent and (policy=='inherit' or policy=='uniform' or policy=='gradient')
  local roles_first=priority=='roles' or (priority=='current' and role and role.color_custom)
  if priority=='smart' and role and folder_applies then
    -- A customized swatch changes appearance, never routing authority.
    -- Same-family children belong to their folder's visual treatment;
    -- a distinct family (for example FX inside Drums) may stand out.
    local parent_role=assigned_role(parent,config,roles)
    roles_first=(parent_role~=nil and parent_role.group~=role.group) or role.id=='returns' or role.id=='fx' or role.id=='reference'
  end
  if role and parent and policy~='uniform' and priority~='strict' then
    for id,behavior in (config.role_behaviors or ''):gmatch('([%w_]+):([%w_]+)') do
      if id==role.id then roles_first=behavior=='role' end
      if id==role.id and behavior=='match' then policy='uniform';folder_applies=true;roles_first=false end
      if id==role.id and behavior=='shade' then policy='gradient';folder_applies=true;roles_first=false end
    end
  end
  if policy=='uniform' then roles_first=false end
  if role and mode~='inherit' and mode~='independent' and (not folder_applies or roles_first) then return native(role.color),reason end
  if parent and (mode=='inherit' or (mode~='independent' and folder_applies)) then
    local parent_color=resolved[parent] or reaper.GetTrackColor(parent)
    if mode~='inherit' and policy=='gradient' then
      local anchor=resolved.bases and resolved.bases[parent] or parent_color
      local r,g,b=56,56,56
      if anchor~=0 then r,g,b=reaper.ColorFromNative(anchor&0xFFFFFF) end
      local base=(r<<16)|(g<<8)|b
      local shade
      if priority=='strict' or not role then
        local index,count=folder_shade_position(track,parent,config,resolved)
        shade=M.gradient_color(base,index,count)
      else shade=role_palettes.shade(base,role.id) end
      return native(shade),priority~='strict' and role and ('Parent color gradient · '..role.name..' shade') or 'Parent color gradient',anchor
    end
    return parent_color,'Inherited from parent'
  end
  if mode~='independent' and mode~='inherit' and role then return native(role.color),reason end
  local fallback=config.unmatched=='theme' and role_palettes.find(config.role_palette) and 'Role theme · unmatched track color' or ('Palette: '..config.palette)
  if mode~='independent' and mode~='inherit' and reason then fallback=reason..' · '..fallback end
  return native(palette[(slot-1)%#palette+1]),fallback
end

function M.icon_mode(track)
  local _,current=reaper.GetSetMediaTrackInfo_String(track,'P_ICON','',false)
  local last=track_get(track,'last_icon')
  local mode=track_get(track,'icon_mode')
  local valid=track_get(track,'last_icon_valid')
  local owned=valid=='1' or (valid=='' and (last~='' or (mode=='auto' and track_get(track,'original_icon_saved')=='1')))
  local protected=mode=='keep' or (owned and current~=last) or (not owned and current~='' and mode~='auto')
  return protected and 'keep' or 'auto',current
end
local function proposed_icon(track,config,roles)
  local mode,current=M.icon_mode(track)
  if mode=='keep' then return current,true,current end
  local role=assigned_role(track,config,roles,true)
  local target=config.role_icons and role_icons.resolve(role) or ''
  local explicit_none=config.role_icons and role and role.icon==''
  if target=='' and not explicit_none and track_get(track,'original_icon_saved')=='1' then target=track_get(track,'original_icon') end
  if target~='' and reaper.file_exists and not reaper.file_exists(target) then return current,false,current end
  return target,false,current
end
local function apply_icon(track,config,roles)
  local target,protected,current=proposed_icon(track,config,roles)
  if protected then track_put(track,'icon_mode','keep');return false end
  if current==target then
    track_put(track,'last_icon',target);track_put(track,'last_icon_valid','1');track_put(track,'icon_mode','auto')
    return false
  end
  if track_get(track,'original_icon_saved')=='' then track_put(track,'original_icon',current);track_put(track,'original_icon_saved','1') end
  reaper.GetSetMediaTrackInfo_String(track,'P_ICON',target,true)
  track_put(track,'last_icon',target)
  track_put(track,'last_icon_valid','1')
  track_put(track,'icon_mode','auto')
  return true
end

-- Track metadata moves with the track and survives project save/reload. Slots
-- are allocated once; array position is never used as the color assignment.
function M.tick(force)
  local now=reaper.time_precise()
  if not force and next_poll and now<next_poll then return end
  next_poll=now+0.5
  local proj=project()
  local _,current_filename=reaper.EnumProjects(-1,'');current_filename=current_filename or ''
  local current_guid=reaper.GetProjectGUID and reaper.GetProjectGUID(proj) or ''
  if proj~=observed_project then
    local open={}
    for i=0,1023 do local candidate=reaper.EnumProjects(i,'');if not candidate then break end;open[candidate]=true end
    for candidate in pairs(project_baselines) do if not open[candidate] then project_baselines[candidate]=nil end end
  end
  local config=M.config(proj)
  local preferences=signature(config)
  -- Undo of an explicit settings edit also restores future-project defaults,
  -- even while automation is off or project approval is still pending.
  if proj==observed_project and current_filename==observed_filename and current_guid==observed_guid
      and observed_preferences and preferences~=observed_preferences then remember(proj) end
  observed_project,observed_preferences,observed_filename,observed_guid=proj,preferences,current_filename,current_guid
  -- Check permission before snapshotting settings, marking manual overrides,
  -- assigning colors, or touching icons. Opening a project is read-only.
  if not M.project_allowed(proj) then last_project=nil;last_preferences=nil;return end
  if not config.enabled then
    last_project=nil;last_preferences=nil;return
  end
  local _,filename=reaper.EnumProjects(-1,'')
  if not filename or filename=='' then put(proj,'approved','1') end
  snapshot(proj)
  local change=reaper.GetProjectStateChangeCount(proj)
  if not force and proj==last_project and change==last_change and preferences==last_preferences then return end
  local palette=M.track_palette(config)
  local roles=M.roles(config)
  local tracks={}
  local used_slots={}
  local next_slot=valid_slot(get(proj,'next_slot','1')) or 1
  for i=0,reaper.CountTracks(proj)-1 do
    local t=reaper.GetTrack(proj,i)
    tracks[#tracks+1]=t
    if track_get(t,'mode')~='keep' then
      local slot=track_slot(t)
      if slot then used_slots[slot]=true end
      next_slot=math.max(next_slot,(slot or 0)+1)
    end
  end
  local original_next=next_slot
  local changed=false
  local icons_changed=false
  local resolved={bases={}}
  for _,t in ipairs(tracks) do
    local current=reaper.GetTrackColor(t)
    local mode=track_get(t,'mode')
    local previous=tonumber(track_get(t,'last'))
    local slot=track_slot(t)
    -- Manual edits, including edits outside ReaSpect, become protected. The
    -- explicit "Follow" command clears last before requesting a new color.
    if mode~='keep' and previous and current~=previous then
      track_put(t,'mode','keep');track_put(t,'protect_reason','manual');mode='keep'
    elseif mode~='keep' and not slot and mode=='' and current~=0 and config.protect then
      track_put(t,'mode','keep');track_put(t,'protect_reason','imported');mode='keep'
    end
    if mode~='keep' then
      if track_get(t,'original_color')=='' then track_put(t,'original_color',current) end
      if not slot then slot,next_slot=allocate_slot(next_slot,used_slots);track_put(t,'slot',slot) end
      local target,_,base=target_color(t,config,roles,palette,slot,resolved)
      resolved.bases[t]=base or target
      if target~=current then reaper.SetTrackColor(t,target);changed=true end
      track_put(t,'last',target)
      current=target
    end
    if config.role_icons or track_get(t,'last_icon')~='' or track_get(t,'last_icon_valid')=='1' then icons_changed=apply_icon(t,config,roles) or icons_changed end
    resolved[t]=current
    resolved.bases[t]=resolved.bases[t] or current
  end
  if next_slot~=original_next or get(proj,'next_slot','')=='' then put(proj,'next_slot',next_slot) end
  if icons_changed and reaper.TrackList_AdjustWindows then reaper.TrackList_AdjustWindows(false) end
  if changed or icons_changed then reaper.UpdateArrange() end
  last_project=proj
  last_preferences=signature(config)
  last_change=reaper.GetProjectStateChangeCount(proj)
end

function M.set_config(key,value)
  local proj=project()
  snapshot(proj)
  if (key=='roles' or key=='role_icons') and not M.config(proj).smart_setup then
    local smart=M.smart_config()
    put(proj,'roles',smart.roles and '1' or '0');put(proj,'role_icons',smart.role_icons and '1' or '0');put(proj,'roles_data',smart.roles_data)
  end
  put(proj,key,value)
  if key=='roles' or key=='role_icons' then put(proj,'smart_setup','1') end
  remember(proj)
  M.tick(true)
end
function M.set_custom(hex)
  local colors,message=M.parse_custom(hex)
  if not colors then return false,message end
  local proj=project()
  snapshot(proj)
  -- Commit both settings before scanning, so the old custom palette cannot
  -- flash onto tracks when saving a newly edited palette.
  put(proj,'custom',hex)
  put(proj,'palette','Custom')
  put(proj,'unmatched','separate')
  remember(proj)
  M.tick(true)
  return true
end
function M.use_name_defaults()
  local proj=project();snapshot(proj)
  put(proj,'roles','1');put(proj,'children','independent')
  put(proj,'unmatched','separate');put(proj,'child_priority','smart')
  -- Reset default routing rules, while retaining explicit track/folder choices.
  put(proj,'role_children','');put(proj,'role_behaviors','')
  put(proj,'smart_setup','1')
  remember(proj);M.tick(true)
end
local function apply_selected_colors(tracks)
  local config=M.config()
  local roles,palette=M.roles(config),M.track_palette(config)
  local selected,used,resolved={},{},{bases={}}
  local proj=project()
  local next_slot=valid_slot(get(proj,'next_slot','1')) or 1
  for _,t in ipairs(tracks) do selected[t]=true end
  for i=0,reaper.CountTracks(proj)-1 do
    local slot=track_slot(reaper.GetTrack(proj,i));if slot then used[slot]=true end
  end
  for i=0,reaper.CountTracks(proj)-1 do
    local t=reaper.GetTrack(proj,i)
    local current=reaper.GetTrackColor(t)
    if selected[t] and track_get(t,'mode')~='keep' then
      if track_get(t,'original_color')=='' then track_put(t,'original_color',current) end
      local slot=track_slot(t)
      if not slot then slot,next_slot=allocate_slot(next_slot,used);track_put(t,'slot',slot) end
      local target,_,base=target_color(t,config,roles,palette,slot,resolved)
      reaper.SetTrackColor(t,target);track_put(t,'last',target)
      current=target;resolved.bases[t]=base or target
    end
    resolved[t]=current;resolved.bases[t]=resolved.bases[t] or current
  end
  put(proj,'next_slot',next_slot)
  reaper.UpdateArrange()
end
function M.detect_roles(tracks)
  local config=M.config()
  for _,track in ipairs(tracks) do
    local current=reaper.GetTrackColor(track)
    local last=tonumber(track_get(track,'last'))
    if last and last~=current then M.protect(track)
    elseif not track_slot(track) and track_get(track,'mode')=='' and current~=0 and config.protect then
      track_put(track,'mode','keep');track_put(track,'protect_reason','imported')
    end
    track_put(track,'role','')
  end
  apply_selected_colors(tracks)
  M.tick(true)
end
function M.set_modes(tracks,mode)
  -- Explicit opt-in must also claim an existing manually colored track.
  for _,track in ipairs(tracks) do
    track_put(track,'mode',mode=='' and 'auto' or mode)
    track_put(track,'protect_reason',mode=='keep' and 'manual' or '')
    track_put(track,'last','')
  end
  apply_selected_colors(tracks)
  M.tick(true)
end
function M.set_mode(track,mode) M.set_modes({track},mode) end
function M.assign_role(tracks,id)
  local role=roles_model.by_id(M.roles(),id)
  if not role then return end
  for _,track in ipairs(tracks) do
    if track_get(track,'original_color')=='' then track_put(track,'original_color',reaper.GetTrackColor(track)) end
    track_put(track,'role',id);track_put(track,'mode','auto');track_put(track,'protect_reason','');track_put(track,'last','')
    -- Explicit assignment authorizes these selected tracks only, without
    -- granting background automation permission for the whole project.
    reaper.SetTrackColor(track,native(role.color));track_put(track,'last',native(role.color))
  end
  reaper.UpdateArrange()
  M.tick(true)
end
function M.save_roles(roles,enabled,icons)
  local proj=project();snapshot(proj)
  local palette=M.palette(M.config(proj))
  for _,r in ipairs(roles) do
    if r.color_custom==false and r.color~=M.role_palette_color(M.config(proj),r) then r.color_custom=true end
  end
  put(proj,'roles_data',roles_model.encode(roles))
  put(proj,'roles',enabled and '1' or '0')
  put(proj,'role_icons',icons and '1' or '0')
  put(proj,'smart_setup','1')
  remember(proj);M.tick(true)
end
local function manual_override(track)
  local previous=tonumber(track_get(track,'last'))
  return track_get(track,'protect_reason')=='manual' or (previous and reaper.GetTrackColor(track)~=previous)
end
local function set_role_colors(selected,rgb,use_palette)
  local config=M.config()
  local roles=M.roles(config)
  local palette=M.palette(config)
  for _,role in ipairs(roles) do
    if selected[role.id] then
      role.color=use_palette and M.role_palette_color(config,role) or (type(rgb)=='table' and rgb[role.id] or rgb)
      role.color_custom=not use_palette
    end
  end
  if M.project_allowed() and config.enabled then
    local proj=project()
    for i=0,reaper.CountTracks(proj)-1 do
      local track=reaper.GetTrack(proj,i)
      local matched=assigned_role(track,config,roles)
      -- Imported-color protection must not silently swallow an explicit role
      -- color edit. Later manual track choices remain protected.
      if matched and selected[matched.id] and track_get(track,'mode')=='keep' and not manual_override(track) then
        track_put(track,'mode','auto');track_put(track,'protect_reason','');track_put(track,'last','')
      end
    end
  end
  M.save_roles(roles,config.roles,config.role_icons)
end
function M.set_role_color(id,rgb,use_palette) set_role_colors({[id]=true},rgb,use_palette) end
function M.family_color(group,config)
  config=config or M.config()
  for name,hex in config.family_bases:gmatch('([^\n=]+)=(%x%x%x%x%x%x)') do
    if name==group then return tonumber(hex,16) end
  end
  local preset=role_palettes.find(config.role_palette)
  if preset and preset.colors[group] then return preset.colors[group] end
  if group=='Custom' then return preset and preset.fallback[1] or M.palette(config)[1] end
  for _,role in ipairs(M.roles(config)) do if role.group==group then return M.role_palette_color(config,role) end end
end
function M.set_role_group_color(group,rgb)
  local proj=project();snapshot(proj)
  local bases={}
  for name,hex in M.config().family_bases:gmatch('([^\n=]+)=(%x%x%x%x%x%x)') do if name~=group then bases[#bases+1]=name..'='..hex end end
  bases[#bases+1]=group..'='..string.format('%06X',rgb)
  put(proj,'family_bases',table.concat(bases,'\n'))
  local selected={}
  for _,r in ipairs(M.roles()) do if r.group==group and not r.color_custom then selected[r.id]=true end end
  set_role_colors(selected,nil,true)
end
function M.group_gradient(group)
  local config=M.config()
  for name in config.family_gradients:gmatch('[^,]+') do
    if name==group then return true end
    if name=='!'..group then return false end
  end
  local preset=role_palettes.find(config.role_palette)
  return preset~=nil and preset.colors[group]~=nil
end
function M.set_group_gradient(group,on)
  local config=M.config()
  local base
  if on and not role_palettes.find(config.role_palette) then
    local existing=false
    for name in config.family_bases:gmatch('([^\n=]+)=%x%x%x%x%x%x') do if name==group then existing=true end end
    if not existing then base=M.family_color(group) end
  end
  local groups={}
  for name in config.family_gradients:gmatch('[^,]+') do if name~=group and name~='!'..group then groups[#groups+1]=name end end
  groups[#groups+1]=on and group or '!'..group
  local proj=project();snapshot(proj);put(proj,'family_gradients',table.concat(groups,','))
  if base then M.set_role_group_color(group,base) else remember(proj);M.tick(true) end
end
function M.reset_role_colors()
  local proj=project();snapshot(proj);put(proj,'family_gradients','');put(proj,'family_bases','')
  local selected={};for _,r in ipairs(M.roles()) do selected[r.id]=true end
  set_role_colors(selected,nil,true)
end
function M.reset_role_group(group)
  local proj=project();snapshot(proj)
  local groups={}
  for name in M.config().family_gradients:gmatch('[^,]+') do
    if name~=group and name~='!'..group then groups[#groups+1]=name end
  end
  put(proj,'family_gradients',table.concat(groups,','))
  local bases={}
  for name,hex in M.config().family_bases:gmatch('([^\n=]+)=(%x%x%x%x%x%x)') do if name~=group then bases[#bases+1]=name..'='..hex end end
  put(proj,'family_bases',table.concat(bases,'\n'))
  local selected={};for _,r in ipairs(M.roles()) do if r.group==group then selected[r.id]=true end end
  set_role_colors(selected,nil,true)
end
function M.role_behavior(id)
  for role,behavior in M.config().role_behaviors:gmatch('([%w_]+):([%w_]+)') do if role==id then return behavior end end
  return 'auto'
end
function M.set_role_behavior(id,behavior)
  if behavior~='auto' and behavior~='folder' and behavior~='role' and behavior~='match' and behavior~='shade' then return end
  local values={}
  for role,value in M.config().role_behaviors:gmatch('([%w_]+):([%w_]+)') do if role~=id then values[#values+1]=role..':'..value end end
  if behavior~='auto' then values[#values+1]=id..':'..behavior end
  M.set_config('role_behaviors',table.concat(values,','))
end
function M.role_children(id) return role_children(M.config(),id) end
function M.set_role_children(id,behavior)
  if behavior~='auto' and behavior~='smart' and behavior~='uniform' and behavior~='shades' and behavior~='independent' then return end
  local config=M.config()
  local values,legacy={},{}
  for role,value in (config.role_children or ''):gmatch('([%w_]+):([%w_]+)') do if role~=id then values[#values+1]=role..':'..value end end
  values[#values+1]=id..':'..behavior
  for role,value in (config.role_behaviors or ''):gmatch('([%w_]+):([%w_]+)') do if role~=id then legacy[#legacy+1]=role..':'..value end end
  M.set_config('role_behaviors',table.concat(legacy,','))
  M.set_config('role_children',table.concat(values,','))
end
function M.clear_role_folder_rules()
  local proj=project();snapshot(proj)
  put(proj,'role_children','');put(proj,'role_behaviors','')
  remember(proj);M.tick(true)
end
function M.apply_project(replace_existing)
  local proj=project();snapshot(proj)
  local smart=M.smart_config();put(proj,'roles',smart.roles and '1' or '0');put(proj,'role_icons',smart.role_icons and '1' or '0');put(proj,'roles_data',smart.roles_data)
  put(proj,'smart_setup','1')
  for i=0,reaper.CountTracks(proj)-1 do
    local track=reaper.GetTrack(proj,i)
    if not manual_override(track) then
      local current=reaper.GetTrackColor(track)
      if replace_existing then
        if track_get(track,'original_color')=='' then track_put(track,'original_color',current) end
        if track_get(track,'mode')=='keep' or track_get(track,'mode')=='' then track_put(track,'mode','auto') end
        track_put(track,'protect_reason','');track_put(track,'last','')
      elseif current~=0 and (track_get(track,'last')=='' or track_get(track,'mode')=='keep') then
        track_put(track,'mode','keep');track_put(track,'protect_reason','imported');track_put(track,'last','')
      elseif current==0 and track_get(track,'mode')=='keep' and track_get(track,'protect_reason')=='imported' then
        track_put(track,'mode','auto');track_put(track,'protect_reason','');track_put(track,'last','')
      end
    end
  end
  put(proj,'approved','1');put(proj,'enabled','1');put(proj,'protect','1')
  persistence.set('auto_colors_replace_existing',replace_existing and '1' or '0')
  remember(proj);M.tick(true)
end
function M.enable_smart()
  local proj=project();snapshot(proj)
  if not M.config(proj).smart_setup then
    local smart=M.smart_config()
    put(proj,'roles','1');put(proj,'role_icons','1');put(proj,'roles_data',smart.roles_data)
    put(proj,'smart_setup','1')
  end
  put(proj,'enabled','1');remember(proj);M.tick(true)
end
function M.preview(config,replace_existing)
  config=config or M.config()
  local roles=M.roles(config);local palette=M.track_palette(config)
  local rows,resolved={},{bases={}}
  local proj=project()
  local next_slot=valid_slot(get(proj,'next_slot','1')) or 1
  local used_slots={}
  for i=0,reaper.CountTracks(proj)-1 do
    local track=reaper.GetTrack(proj,i)
    local reclaim_blank=replace_existing==false and reaper.GetTrackColor(track)==0
      and track_get(track,'mode')=='keep' and track_get(track,'protect_reason')=='imported'
    if track_get(track,'mode')~='keep' or (replace_existing and not manual_override(track)) or reclaim_blank then
      local slot=track_slot(track)
      if slot then used_slots[slot]=true end
      next_slot=math.max(next_slot,(slot or 0)+1)
    end
  end
  for i=0,reaper.CountTracks(proj)-1 do
    local track=reaper.GetTrack(proj,i);local current=reaper.GetTrackColor(track)
    local slot=track_slot(track)
    local previous=tonumber(track_get(track,'last'))
    local protected=track_get(track,'mode')=='keep' or (previous and current~=previous)
      or (not slot and track_get(track,'mode')=='' and current~=0 and config.protect)
    local mode_override
    if replace_existing~=nil then
      if replace_existing and not manual_override(track) then
        protected=false
        if track_get(track,'mode')=='keep' or track_get(track,'mode')=='' then mode_override='auto' end
      elseif not replace_existing and current~=0 and (track_get(track,'last')=='' or track_get(track,'mode')=='keep') then protected=true end
      if not replace_existing and current==0 and track_get(track,'mode')=='keep' and track_get(track,'protect_reason')=='imported' then
        protected=false;mode_override='auto'
      end
    end
    if not slot then
      if protected then slot=valid_slot(next_slot) or 1 else slot,next_slot=allocate_slot(next_slot,used_slots) end
    end
    local target,reason,base=target_color(track,config,roles,palette,slot,resolved,mode_override)
    if protected then target=current;base=current;reason='Manual / protected color' end
    resolved[track]=target
    resolved.bases[track]=base or target
    local icon,_,current_icon=proposed_icon(track,config,roles)
    local matched=assigned_role(track,config,roles)
    if track_get(track,'mode')=='role' and track_get(track,'role')=='' then matched=roles_model.detect(track_name(track),roles) end
    rows[#rows+1]={track=track,name=track_name(track),color=target,reason=reason,changed=target~=current,
      icon=icon,icon_changed=icon~=current_icon,group=protected and 'Protected' or (matched and matched.group or 'Unmatched')}
  end
  return rows
end
function M.restore()
  local proj=project();snapshot(proj)
  put(proj,'enabled','0')
  for i=0,reaper.CountTracks(proj)-1 do
    local t=reaper.GetTrack(proj,i);local original=tonumber(track_get(t,'original_color'))
    if original then
      reaper.SetTrackColor(t,original);track_put(t,'mode','keep');track_put(t,'protect_reason','imported')
      track_put(t,'last','');track_put(t,'original_color','')
    end
    if track_get(t,'original_icon_saved')=='1' then
      reaper.GetSetMediaTrackInfo_String(t,'P_ICON',track_get(t,'original_icon'),true)
      track_put(t,'icon_mode','keep');track_put(t,'last_icon','');track_put(t,'last_icon_valid','0');track_put(t,'original_icon_saved','')
    end
  end
  remember(proj)
  if reaper.TrackList_AdjustWindows then reaper.TrackList_AdjustWindows(false) end
  reaper.UpdateArrange()
end
function M.protect_icon(track) track_put(track,'icon_mode','keep');track_put(track,'last_icon','');track_put(track,'last_icon_valid','0') end
function M.resume_icons(tracks)
  for _,t in ipairs(tracks) do track_put(t,'icon_mode','auto');track_put(t,'last_icon','');track_put(t,'last_icon_valid','0') end
  M.tick(true)
end
local function apply_folder_choice(folder)
  local config=M.config()
  local targets={}
  for i=0,reaper.CountTracks(project())-1 do
    local t=reaper.GetTrack(project(),i)
    local parent=reaper.GetParentTrack(t)
    local covered=parent==folder
    if track_get(folder,'children_scope')=='all' then
      while parent do
        if parent==folder then covered=true;break end
        parent=reaper.GetParentTrack(parent)
      end
    end
    local policy,_,scope_owner=children_policy(t,config)
    local nested_scope=false
    local scope_parent=scope_owner and reaper.GetParentTrack(scope_owner)
    while scope_parent do
      if scope_parent==folder then nested_scope=true;break end
      scope_parent=reaper.GetParentTrack(scope_parent)
    end
    if covered and not nested_scope and not manual_override(t) then
      -- A new explicit folder choice replaces older per-track color routing.
      -- Keep role identity, but rejoin the chosen folder treatment now.
      if policy=='uniform' or policy=='gradient' or policy=='independent' then
        track_put(t,'mode','auto');track_put(t,'protect_reason','');track_put(t,'last','')
      end
      targets[#targets+1]=t
    end
  end
  apply_selected_colors(targets)
end
function M.set_children(track,rule)
  track_put(track,'children',rule)
  apply_folder_choice(track)
  M.tick(true)
end
function M.set_children_scope(tracks,include)
  for _,track in ipairs(tracks) do track_put(track,'children_scope',include and 'all' or '') end
  for _,track in ipairs(tracks) do apply_folder_choice(track) end
  M.tick(true)
end
function M.protect(track)
  -- Called inside the manual color edit's undo block, even while disabled.
  track_put(track,'mode','keep')
  track_put(track,'protect_reason','manual')
  track_put(track,'last','')
end
function M.redistribute()
  local proj=project()
  for i=0,reaper.CountTracks(proj)-1 do
    local t=reaper.GetTrack(proj,i)
    if manual_override(t) then track_put(t,'mode','keep');track_put(t,'protect_reason','manual') end
    if track_get(t,'mode')~='keep' then
      if track_get(t,'mode')=='' then track_put(t,'mode','auto') end
      track_put(t,'slot','');track_put(t,'last','')
    end
  end
  put(proj,'next_slot',1)
  M.tick(true)
end
function M.color_source(track)
  local config=M.config()
  local current=reaper.GetTrackColor(track)
  local last=tonumber(track_get(track,'last'))
  if track_get(track,'mode')=='keep' or (last and last~=current) then
    local manual=track_get(track,'protect_reason')=='manual' or (last and last~=current)
    return {label=manual and 'Manual color' or 'Existing color',kind='track',track=track}
  end
  if not M.project_allowed() or (not config.enabled and not last) then
    return {label='Existing color',kind='track',track=track}
  end
  if not track_slot(track) and track_get(track,'mode')=='' and current~=0 and config.protect then
    return {label='Existing color',kind='track',track=track}
  end
  local roles=M.roles(config)
  local _,reason=target_color(track,config,roles,M.track_palette(config),track_slot(track) or 1,{})
  local parent=reaper.GetParentTrack(track)
  if parent and (reason=='Inherited from parent' or reason:find('Parent color gradient',1,true)) then
    local _,_,owner=children_policy(track,config)
    if track_get(track,'mode')~='inherit' then parent=owner or parent end
    local name=track_name(parent);if name=='' then name='Unnamed folder' end
    return {label=name..(reason=='Inherited from parent' and ' · folder color' or ' · folder gradient'),kind='folder',track=parent}
  end
  local role=assigned_role(track,config,roles)
  if track_get(track,'mode')=='role' and track_get(track,'role')=='' then role=roles_model.detect(track_name(track),roles) end
  if role and not reason:find('unmatched',1,true) and track_get(track,'mode')~='independent' then
    return {label=role.name..' role color',kind='role',role=role}
  end
  return {label='Track palette',kind='palette'}
end
function M.role_label(track)
  local config=M.config()
  local roles=M.roles(config)
  local id=track_get(track,'role')
  local role=roles_model.by_id(roles,id)
  if role then return 'Role: '..role.name..' (assigned)' end
  if id~='' then return 'Role: unavailable (assigned)' end
  if config.roles or config.role_icons or track_get(track,'mode')=='role' then
    local detected=roles_model.detect(track_name(track),roles)
    if detected then return 'Role: '..detected.name..' (detected)' end
  end
  return 'Role: None'
end
function M.status(track)
  local config=M.config()
  if not M.project_allowed() then return 'Auto colors paused · This saved project needs your permission' end
  if not config.enabled then return 'Auto colors: off for this project' end
  local mode=track_get(track,'mode')
  if mode=='keep' then
    return track_get(track,'protect_reason')=='manual' and 'Manual color protected · Follow automatic colors to resume'
      or 'Existing color preserved · Follow automatic colors to resume'
  end
  local _,reason=target_color(track,config,M.roles(config),M.track_palette(config),track_slot(track) or 1,{})
  return 'Auto: '..reason
end
return M
