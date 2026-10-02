local api = require('ReaSpect.core.reaper_api')
local undo = require('ReaSpect.core.undo')
local controls = require('ReaSpect.widgets.controls')
local theme = require('ReaSpect.core.theme')
local persistence = require('ReaSpect.core.persistence')
local prop = require('ReaSpect.widgets.property')
local native_ui = require('ReaSpect.core.native_ui')
local fx_search = require('ReaSpect.core.fx_search')
local M = {knob_drags={}}

local C = {
  bg=0x302A2EFF, header=0x3C3639FF, well=0x3A3336FF,
  active=0x56504CFF, text=0xEAE3DBFF, muted=0xAAA09CFF,
  line=0x755562FF, gold=0xE5B84DFF, white=0xE0E2DFFF,
  violet=0xBD9BE9FF, shadow=0x211E20FF,
}
local MIN_SEND_SLOTS=4
local FX_ROW_HEIGHT,FX_TOGGLE_WIDTH=23,16
local RACK_GUTTER,RACK_DIVIDER_HEIGHT=8,7
local function sync_theme()
  local c=theme.colors
  if not c or not c.panel then return end
  C.bg=c.panel;C.header=c.frame;C.text=c.text
  C.gold=c.gold;C.violet=c.accent
  C.heading=theme.heading_colors and theme.heading_colors() or C.violet
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function db(v) return v <= 0.000001 and -60 or 20*math.log(v, 10) end
local function lin(v) return 10^(v/20) end
local function cut(s, max_chars)
  s=s or ''
  if #s <= max_chars then return s end
  return s:sub(1, math.max(1,max_chars-1)) .. '…'
end
local function fx_name(name)
  return ((name or ''):gsub('^[^:]+:%s*',''):gsub('%s*%([^%)]*%)%s*$',''))
end
local function fx_display_name(name)
  return ((name or ''):gsub('^[^:]+:%s*',''))
end
local ALPHA_RANGES={
  {label='A–F',first='A',last='F'},
  {label='G–L',first='G',last='L'},
  {label='M–R',first='M',last='R'},
  {label='S–Z',first='S',last='Z'},
  {label='0–9 and other',other=true},
}
local DEVELOPER_RANGES={
  {label='1-B',first='1',last='B'},
  {label='C-F',first='C',last='F'},
  {label='G-M',first='G',last='M'},
  {label='N-R',first='N',last='R'},
  {label='S-T',first='S',last='T'},
  {label='U-Z',first='U',last='Z'},
}
local CATEGORY_RANGES={
  {label='Categories A-M',first='A',last='M'},
  {label='Categories O-W',first='O',last='W'},
  {label='Categories Other',other=true},
}
local function trim(s) return (s or ''):match('^%s*(.-)%s*$') or '' end
local function alpha_range(letter)
  for _,range in ipairs(ALPHA_RANGES) do
    if range.other and letter=='#' then return range.label end
    if not range.other and letter>=range.first and letter<=range.last then return range.label end
  end
  return ALPHA_RANGES[#ALPHA_RANGES].label
end
local function alpha_letter(name)
  return ((name or ''):upper():match('^%s*([A-Z])') or '#')
end
local function developer_range(name)
  local first=(name or ''):upper():match('^%s*([%w])') or '#'
  for _,range in ipairs(DEVELOPER_RANGES) do
    if first>=range.first and first<=range.last then return range.label end
  end
  return DEVELOPER_RANGES[1].label
end
local function category_range(name)
  local first=(name or ''):upper():match('^%s*([A-Z])')
  for _,range in ipairs(CATEGORY_RANGES) do
    if range.other and not first then return range.label end
    if first and first>=range.first and first<=range.last then return range.label end
  end
  return CATEGORY_RANGES[#CATEGORY_RANGES].label
end

local function read_ini_sections(path)
  local sections={}
  if not (io and io.open) then return sections end
  local ok,file=pcall(io.open,path,'r')
  if not (ok and file) then return sections end
  local section=''
  for line in file:lines() do
    local header=line:match('^%s*%[([^%]]+)%]%s*$')
    if header then
      section=header:lower()
      sections[section]=sections[section] or {}
    else
      local key,value=line:match('^%s*([^=]-)%s*=%s*(.-)%s*$')
      if section~='' and key and key~='' and value then
        sections[section][key:lower()]=value
      end
    end
  end
  file:close()
  return sections
end

local function fx_config_files()
  if M.fx_config then return M.fx_config end
  local config={tags={},folders={}}
  local resource=reaper.GetResourcePath and reaper.GetResourcePath()
  if resource and resource~='' then
    local sep=(package and package.config and package.config:sub(1,1)) or '\\'
    config.tags=read_ini_sections(resource..sep..'reaper-fxtags.ini')
    config.folders=read_ini_sections(resource..sep..'reaper-fxfolders.ini')
  end
  M.fx_config=config
  return config
end

-- REAPER stores native developer/category tags separately from its ordered
-- user-created FX folders. Both are read-only inputs to this picker.
local function read_fx_tags()
  if M.fx_tags then return M.fx_tags end
  local config=fx_config_files()
  local tags={developer=config.tags.developer or {},category={}}
  for key,value in pairs(config.tags.category or {}) do tags.category[key]=value end
  for key,value in pairs(config.folders.category or {}) do
    local prior=tags.category[key]
    if prior and prior~='' and prior:lower()~=value:lower() then
      tags.category[key]=prior..'|'..value
    else
      tags.category[key]=value
    end
  end
  M.fx_tags=tags
  return tags
end

local function read_user_fx_folders()
  if M.fx_user_folders then return M.fx_user_folders end
  local sections=fx_config_files().folders
  local list=sections.folders or {}
  local count=tonumber(list.nbfolders) or 0
  local folders={}
  for i=0,count-1 do
    local id=tonumber(list['id'..i]) or i
    local name=list['name'..i]
    local contents=sections['folder'..id] or {}
    local item_count=tonumber(contents.nb) or 0
    local folder={name=name,items={}}
    for item_index=0,item_count-1 do
      local path=contents['item'..item_index]
      if path and path~='' then
        folder.items[#folder.items+1]={path=path,type=contents['type'..item_index]}
      end
    end
    if name and name~='' and #folder.items>0 then folders[#folders+1]=folder end
  end
  M.fx_user_folders=folders
  return folders
end

local function normalized_fx_path(path)
  path=trim(path)
  if path=='' then return '' end
  if not path:match('^%a:[/\\]') then path=path:gsub('^[%w_%-]+:%s*','') end
  return path:gsub('^"(.*)"$','%1'):gsub('\\','/'):gsub('/+','/'):lower()
end

local function path_leaf(path)
  return normalized_fx_path(path):match('([^/]+)$') or ''
end

local function without_vst3_uid(leaf)
  return ((leaf or ''):gsub('<[^>]*>.*$',''))
end

local function resolve_user_folder_fx(path,rows,by_path)
  local target=normalized_fx_path(path)
  local exact=by_path and by_path[target]
  if exact then return exact end
  local target_leaf=path_leaf(path)
  local target_leaf_no_uid=without_vst3_uid(target_leaf)
  local best,best_score=nil,0
  for _,fx in ipairs(rows) do
    local identity=fx._normalized_ident or normalized_fx_path(fx.ident)
    local identity_leaf=fx._ident_leaf or path_leaf(fx.ident)
    local score=0
    if target~='' and identity==target then score=1000
    elseif target~='' and identity~='' and (target:find(identity,1,true) or identity:find(target,1,true)) then score=700
    elseif target_leaf~='' and identity_leaf==target_leaf then score=500
    elseif target_leaf_no_uid~='' and (fx._ident_leaf_no_uid or without_vst3_uid(identity_leaf))==target_leaf_no_uid then score=400 end
    if score>best_score then best=fx;best_score=score end
  end
  return best
end

local function fx_tag_value(tag_map,identity,name)
  local function lookup(source)
    source=trim(source)
    if source=='' then return nil end
    if not source:match('^%a:[/\\]') then
      source=source:gsub('^[%w_%-]+:%s*','')
    end
    source=source:gsub('^"(.*)"$','%1'):gsub('\\','/')
    local base=source:match('([^/]+)$') or source
    -- gsub returns both the transformed text and a replacement count. Wrap
    -- these expressions so the final one cannot append that count to the list.
    local candidates={source,base,(base:gsub('>%s*$','')),(base:gsub('<[^>]*>%s*$',''))}
    for _,candidate in ipairs(candidates) do
      local value=tag_map[candidate:lower()]
      if value then return value end
    end
  end
  return lookup(identity) or lookup(name)
end

local FX_CACHE_VERSION=1
local FX_CACHE_MAX_AGE=30*24*60*60
local function fx_cache_path()
  local resource=reaper.GetResourcePath and reaper.GetResourcePath()
  if not resource or resource=='' then return nil end
  local sep=(package and package.config and package.config:sub(1,1)) or '\\'
  return resource..sep..'ReaSpect_fx_catalog.cache'
end

local function cache_hash(value)
  local hash=2166136261
  for i=1,#value do hash=((hash ~ value:byte(i))*16777619)&0xFFFFFFFF end
  return string.format('%08x',hash)
end

local function cache_encode(value)
  return (tostring(value or ''):gsub('%%','%%25'):gsub('\t','%%09'):gsub('\r','%%0D'):gsub('\n','%%0A'))
end

local function cache_decode(value)
  local escapes={['25']='%', ['09']='\t', ['0D']='\r', ['0A']='\n'}
  return (value:gsub('%%(%x%x)',function(code) return escapes[code:upper()] or ('%'..code) end))
end

local function load_fx_cache()
  local path=fx_cache_path()
  if not path or not (io and io.open) then return nil end
  local opened,file=pcall(io.open,path,'rb')
  if not opened or not file then return nil end
  local read_ok,contents=pcall(function() return file:read('*a') end)
  pcall(file.close,file)
  if not read_ok or type(contents)~='string' or #contents>8*1024*1024 then return nil end
  local header,body=contents:match('^([^\r\n]*)\r?\n(.*)$')
  if not header or not body then return nil end
  local version,created,count,digest=header:match('^ReaSpect%-FX%-Cache\t(%d+)\t(%d+)\t(%d+)\t(%x%x%x%x%x%x%x%x)$')
  version,created,count=tonumber(version),tonumber(created),tonumber(count)
  if version~=FX_CACHE_VERSION or not created or not count or count>10001 then return nil end
  local now=os and os.time and os.time() or created
  if now-created>FX_CACHE_MAX_AGE or created>now+86400 then return nil end
  if cache_hash(body)~=digest:lower() then return nil end
  local rows={}
  for line in body:gmatch('([^\n]*)\n') do
    local name,ident=line:match('^([^\t]*)\t([^\t]*)$')
    if not name or not ident then return nil end
    name,ident=cache_decode(name),cache_decode(ident)
    if name=='' or ident=='' then return nil end
    rows[#rows+1]={name=name,ident=ident}
    if #rows>count then return nil end
  end
  if #rows~=count then return nil end
  return rows
end

local function save_fx_cache(rows)
  local path=fx_cache_path()
  if not path or not (io and io.open and os and os.rename and os.remove) then return end
  local encoded={}
  for _,fx in ipairs(rows) do encoded[#encoded+1]=cache_encode(fx.name)..'\t'..cache_encode(fx.ident)..'\n' end
  local body=table.concat(encoded)
  local created=os.time and os.time() or 0
  local header=string.format('ReaSpect-FX-Cache\t%d\t%d\t%d\t%s',FX_CACHE_VERSION,created,#rows,cache_hash(body))
  local temp=path..'.tmp'
  local opened,file=pcall(io.open,temp,'wb')
  if not opened or not file then return end
  local write_ok,write_result=pcall(function() return file:write(header,'\n',body) end)
  local close_ok=pcall(file.close,file)
  if not write_ok or not write_result or not close_ok then pcall(os.remove,temp);return end
  pcall(os.remove,path)
  local renamed,result=pcall(os.rename,temp,path)
  if not renamed or not result then pcall(os.remove,temp) end
end

local function tooltip(ctx, message)
  if reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_SetTooltip then
    reaper.ImGui_SetTooltip(ctx,message)
  end
end
local function has_mod(ctx,name)
  local bit=reaper['ImGui_Mod_'..name]
  local mods=reaper.ImGui_GetKeyMods and reaper.ImGui_GetKeyMods(ctx) or 0
  return bit and (mods & bit())~=0 or false
end
local function matching_tracks(source,all)
  local out={}
  if all then
    for i=0,(reaper.CountTracks(0) or 0)-1 do out[#out+1]=reaper.GetTrack(0,i) end
  elseif reaper.CountSelectedTracks and reaper.GetSelectedTrack then
    for i=0,(reaper.CountSelectedTracks(0) or 0)-1 do out[#out+1]=reaper.GetSelectedTrack(0,i) end
  end
  if #out==0 then out[1]=source end
  return out
end

local function installed_fx(force_scan)
  if M.installed_fx and not force_scan then return M.installed_fx end
  local tags=read_fx_tags()
  local inventory=not force_scan and load_fx_cache() or nil
  if not inventory then
    inventory={}
    if reaper.EnumInstalledFX then
      for i=0,10000 do
        local ok,name,ident=reaper.EnumInstalledFX(i)
        if not ok then break end
        if name and ident and ident~='' then inventory[#inventory+1]={name=name,ident=ident} end
      end
    end
    save_fx_cache(inventory)
  end
  local rows={}
  for _,entry in ipairs(inventory) do
    local name,ident=entry.name,entry.ident
    local display=fx_display_name(name)
    -- Do not infer a developer from parenthesized display-name suffixes:
    -- REAPER/plugin names commonly use these for bitness or format labels.
    local developer=fx_tag_value(tags.developer,ident,name) or 'Other'
    local raw_categories=fx_tag_value(tags.category,ident,name) or ''
    local categories,seen={},{}
    for category in raw_categories:gmatch('[^|]+') do
      local category=trim(category)
      local key=category:lower()
      if category~='' and not seen[key] then categories[#categories+1]=category;seen[key]=true end
    end
    if #categories==0 then categories[1]='Uncategorized' end
    local letter=alpha_letter(display)
    rows[#rows+1]={name=name,ident=ident,display=display,vendor=developer,
      developer=developer,categories=categories,alpha_letter=letter,alpha_group=alpha_range(letter)}
  end
  table.sort(rows,function(a,b) return a.display:lower()<b.display:lower() end)
  local by_path={}
  for _,fx in ipairs(rows) do
    fx._normalized_ident=normalized_fx_path(fx.ident)
    fx._ident_leaf=path_leaf(fx.ident)
    fx._ident_leaf_no_uid=without_vst3_uid(fx._ident_leaf)
    if by_path[fx._normalized_ident]==nil then by_path[fx._normalized_ident]=fx end
  end
  local user_folders={}
  for _,folder in ipairs(read_user_fx_folders()) do
    local matched,seen={},{}
    for _,item in ipairs(folder.items) do
      local fx=resolve_user_folder_fx(item.path,rows,by_path)
      if fx and not seen[fx.ident] then
        matched[#matched+1]=fx;seen[fx.ident]=true
        fx.user_folders=fx.user_folders or {}
        fx.user_folders[#fx.user_folders+1]=folder.name
      end
    end
    user_folders[#user_folders+1]={name=folder.name,fx=matched}
  end
  local by_letter,letters,by_alpha_group,by_vendor,vendors,by_category,categories={},{},{},{},{},{},{}
  local developer_groups,category_groups={},{}
  for _,fx in ipairs(rows) do
    local letter=fx.alpha_letter
    local alpha=by_alpha_group[fx.alpha_group]
    if not alpha then alpha={by_letter={},letters={}};by_alpha_group[fx.alpha_group]=alpha end
    if not alpha.by_letter[letter] then
      alpha.by_letter[letter]={}
      alpha.letters[#alpha.letters+1]=letter
    end
    alpha.by_letter[letter][#alpha.by_letter[letter]+1]=fx
    local searchable_categories=table.concat(fx.categories or {},' ')
    local searchable_folders=table.concat(fx.user_folders or {},' ')
    fx.search_text=table.concat({fx.display,fx.ident,fx.developer,searchable_categories,searchable_folders},' '):lower()
    if not by_letter[letter] then by_letter[letter]={};letters[#letters+1]=letter end
    by_letter[letter][#by_letter[letter]+1]=fx
    if not by_vendor[fx.developer] then
      by_vendor[fx.developer]={};vendors[#vendors+1]=fx.developer
      local group=developer_range(fx.developer)
      developer_groups[group]=developer_groups[group] or {}
      developer_groups[group][#developer_groups[group]+1]=fx.developer
    end
    by_vendor[fx.developer][#by_vendor[fx.developer]+1]=fx
    for _,category in ipairs(fx.categories) do
      if not by_category[category] then by_category[category]={};categories[#categories+1]=category end
      by_category[category][#by_category[category]+1]=fx
      local group=category_range(category)
      category_groups[group]=category_groups[group] or {}
      if #by_category[category]==1 then category_groups[group][#category_groups[group]+1]=category end
    end
  end
  table.sort(letters,function(a,b)
    if a=='#' then return false end
    if b=='#' then return true end
    return a<b
  end)
  table.sort(vendors,function(a,b) return a:lower()<b:lower() end)
  table.sort(categories,function(a,b) return a:lower()<b:lower() end)
  for _,group in pairs(developer_groups) do table.sort(group,function(a,b) return a:lower()<b:lower() end) end
  for _,group in pairs(category_groups) do table.sort(group,function(a,b) return a:lower()<b:lower() end) end
  for _,group in pairs(by_alpha_group) do table.sort(group.letters) end
  local by_ident={}
  for _,fx in ipairs(rows) do by_ident[fx.ident]=fx end
  M.installed_fx=rows
  M.installed_fx_by_ident=by_ident
  M.installed_fx_by_letter=by_letter;M.installed_fx_letters=letters
  M.installed_fx_alpha_groups=by_alpha_group
  M.installed_fx_by_vendor=by_vendor;M.installed_fx_vendors=vendors
  M.installed_fx_by_category=by_category;M.installed_fx_categories=categories
  M.installed_fx_developer_groups=developer_groups
  M.installed_fx_category_groups=category_groups
  M.installed_fx_user_folders=user_folders
  return rows
end

function M.refresh_fx_catalog()
  for _,key in ipairs({
    'installed_fx','installed_fx_by_ident','installed_fx_by_letter','installed_fx_letters',
    'installed_fx_alpha_groups',
    'installed_fx_by_vendor','installed_fx_vendors','installed_fx_by_category','installed_fx_categories',
    'installed_fx_developer_groups','installed_fx_category_groups','installed_fx_user_folders',
  }) do M[key]=nil end
  M.fx_config=nil;M.fx_tags=nil;M.fx_user_folders=nil
  local path=fx_cache_path()
  if path and os and os.remove then pcall(os.remove,path) end
  return installed_fx(true)
end

local function recent_fx()
  local rows,seen={},{}
  local raw=persistence.get('recent_fx','') or ''
  installed_fx()
  local by_ident=M.installed_fx_by_ident or {}
  for ident in raw:gmatch('[^\n]+') do
    if #rows>=12 then break end
    local fx=by_ident[ident]
    if fx and not seen[ident] then rows[#rows+1]=fx;seen[ident]=true end
  end
  return rows
end

local function remember_fx(identity)
  local ids={identity}
  local raw=persistence.get('recent_fx','') or ''
  for ident in raw:gmatch('[^\n]+') do
    if ident~=identity and #ids<12 then ids[#ids+1]=ident end
  end
  persistence.set('recent_fx',table.concat(ids,'\n'))
end

local function menu_item(ctx,label,shortcut,selected,enabled)
  return reaper.ImGui_MenuItem(ctx,label,shortcut or '',selected or false,enabled~=false)
end

local function menu_begin(ctx,label,enabled)
  return reaper.ImGui_BeginMenu and reaper.ImGui_BeginMenu(ctx,label,enabled~=false) or false
end

local function menu_end(ctx)
  if reaper.ImGui_EndMenu then reaper.ImGui_EndMenu(ctx) end
end

local function menu_separator(ctx)
  if reaper.ImGui_Separator then reaper.ImGui_Separator(ctx) end
end
local function child(ctx,id,w,h,flags,fn,opts)
  local styles=0
  if opts and opts.padding==0 then
    reaper.ImGui_PushStyleVar(ctx,reaper.ImGui_StyleVar_WindowPadding(),0,0)
    styles=styles+1
  end
  if opts and opts.scrollbar then
    reaper.ImGui_PushStyleVar(ctx,reaper.ImGui_StyleVar_ScrollbarSize(),opts.scrollbar)
    styles=styles+1
  end
  local visible=reaper.ImGui_BeginChild(ctx,id,w,h,0,controls.scroll_flags(flags))
  -- Window geometry is captured by BeginChild. Restore the surrounding style
  -- immediately so menus opened inside the child keep normal popup padding.
  if styles>0 then reaper.ImGui_PopStyleVar(ctx,styles) end
  if visible then
    if opts and opts.fixed then reaper.ImGui_SetScrollY(ctx,0) end
    fn()
    if not (opts and opts.fixed) then controls.scroll_end(ctx) end
    reaper.ImGui_EndChild(ctx)
  end
  return visible
end
local function arc(dl,cx,cy,r,a,b,col,thick)
  if not (reaper.ImGui_DrawList_PathClear and reaper.ImGui_DrawList_PathArcTo and reaper.ImGui_DrawList_PathStroke) then return end
  reaper.ImGui_DrawList_PathClear(dl)
  reaper.ImGui_DrawList_PathArcTo(dl,cx,cy,r,a,b,32)
  reaper.ImGui_DrawList_PathStroke(dl,col,0,thick)
end

local function lamp(ctx,id,enabled,on_click)
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  local hit=reaper.ImGui_InvisibleButton(ctx,id,18,22)
  local hovered=reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx)
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  reaper.ImGui_DrawList_AddCircleFilled(dl,x+9,y+11,7,hovered and 0x686469FF or C.shadow)
  reaper.ImGui_DrawList_AddCircleFilled(dl,x+9,y+11,4.5,enabled and C.violet or 0x625A60FF)
  if hit and on_click then on_click() end
  tooltip(ctx,enabled and 'Bypass FX' or 'Enable FX')
end

local function current_project()
  return reaper.EnumProjects and select(1,reaper.EnumProjects(-1,'')) or 0
end

local function valid_project_track(track,project)
  return current_project()==project
    and (not reaper.ValidatePtr2 or reaper.ValidatePtr2(project,track,'MediaTrack*'))
end

local function resolve_fx_after_modal(track,project,guid)
  if not guid or guid=='' or not valid_project_track(track,project) then return nil end
  for i=0,reaper.TrackFX_GetCount(track)-1 do
    if reaper.TrackFX_GetFXGUID(track,i)==guid then return i end
  end
end

local function add_fx(track,state,identity,name,index)
  if not reaper.TrackFX_AddByName then return false end
  local project=current_project()
  local position=clamp(index or reaper.TrackFX_GetCount(track),0,reaper.TrackFX_GetCount(track))
  local added_index=-1
  undo.edit('Add FX: '..(name or identity),function()
    local added=reaper.TrackFX_AddByName(track,identity,false,-1000-position)
    if added < 0 and name and name~=identity and valid_project_track(track,project) then
      added=reaper.TrackFX_AddByName(track,name,false,-1000-position)
    end
    if added >= 0 and valid_project_track(track,project) then
      added_index=added;remember_fx(identity)
      state.fx=nil; reaper.UpdateArrange()
    end
  end)
  if added_index>=0 and reaper.TrackFX_Show then reaper.TrackFX_Show(track,added_index,3) end
  return added_index>=0
end
local function replace_fx(track,state,index,identity,name)
  if not reaper.TrackFX_AddByName or not reaper.TrackFX_Delete then return false end
  local project=current_project()
  local guid=reaper.TrackFX_GetFXGUID and reaper.TrackFX_GetFXGUID(track,index)
  if not guid or guid=='' then return false end
  local added=false
  undo.edit('Replace FX: '..(name or identity),function()
    local result=reaper.TrackFX_AddByName(track,identity,false,-1000-index)
    local old_index=resolve_fx_after_modal(track,project,guid)
    if result<0 and name and name~=identity and old_index then
      result=reaper.TrackFX_AddByName(track,name,false,-1000-old_index)
      old_index=resolve_fx_after_modal(track,project,guid)
    end
    if result>=0 and valid_project_track(track,project) then
      -- Loading a plugin can pump a native dialog. Delete only the original
      -- instance if the chain changed while that dialog was open.
      if old_index then reaper.TrackFX_Delete(track,old_index);added=true end
      remember_fx(identity);state.fx=nil;reaper.UpdateArrange()
    end
  end)
  return added
end

local function move_fx(track,state,source,destination)
  if not reaper.TrackFX_CopyToTrack or source==nil or source==destination then return end
  undo.edit('Move track FX',function()
    reaper.TrackFX_CopyToTrack(track,source,track,destination,true)
    state.fx=nil; reaper.UpdateArrange()
  end)
end

-- Close the exact drag scope before propagating a callback error. Parent
-- windows must never try to EndChild while a drag tooltip is still active.
local function drag_scope(ctx,finish,fn)
  local ok,err=pcall(fn)
  local ended,end_err=pcall(finish,ctx)
  if not ok then error(err,0) end
  if not ended then error(end_err,0) end
end

local function track_identity(track)
  return reaper.GetTrackGUID and reaper.GetTrackGUID(track) or tostring(track)
end

local function fx_drop(ctx,track,state,destination)
  if not (reaper.ImGui_BeginDragDropTarget and reaper.ImGui_BeginDragDropTarget(ctx)) then return end
  drag_scope(ctx,reaper.ImGui_EndDragDropTarget,function()
    local moved,payload=reaper.ImGui_AcceptDragDropPayload(ctx,'REASPECT_FX_MOVE',nil)
    if not moved or type(payload)~='string' or not reaper.TrackFX_GetFXGUID then return end
    local owner,guid=payload:match('^([^|]+)|(.+)$')
    if owner~=track_identity(track) then return end
    -- Track selection and FX indices can change during a drag. Resolve the
    -- captured instance only within its original track at delivery time.
    for source=0,reaper.TrackFX_GetCount(track)-1 do
      if reaper.TrackFX_GetFXGUID(track,source)==guid then
        move_fx(track,state,source,destination)
        return
      end
    end
  end)
end

local function choose_fx(ctx,track,state,position,replace_index,fx)
  if replace_index~=nil then
    native_ui.queue('Replace FX',track,function(target,index)
      replace_fx(target,state,index,fx.ident,fx.name)
    end,replace_index)
  else
    local count=reaper.TrackFX_GetCount(track)
    local anchor=position and position>0 and position<=count and position-1 or nil
    native_ui.queue('Add FX',track,function(target,index)
      add_fx(target,state,fx.ident,fx.name,anchor and index+1 or position)
    end,anchor)
  end
  if reaper.ImGui_CloseCurrentPopup then reaper.ImGui_CloseCurrentPopup(ctx) end
end

local function fx_menu_item(ctx,fx,index,label)
  -- Different formats and variants can share the same display name.
  local identity=tostring(fx.ident or fx.name or ''):gsub('#','%%23')
  return menu_item(ctx,(label or fx.display)..'##fx_catalog_'..identity..'_'..index,'',false,true)
end

local function add_recent_menu(ctx,track,state,position,replace_index,label)
  local recent=recent_fx()
  if menu_begin(ctx,label or 'Recently used',#recent>0) then
    for i,fx in ipairs(recent) do
      if fx_menu_item(ctx,fx,i) then choose_fx(ctx,track,state,position,replace_index,fx) end
    end
    menu_end(ctx)
  end
end

local function draw_fx_items(ctx,track,state,rows,position,replace_index)
  for i,fx in ipairs(rows or {}) do
    if fx_menu_item(ctx,fx,i) then choose_fx(ctx,track,state,position,replace_index,fx) end
  end
end

local function user_fx_folders_menu(ctx,track,state,position,replace_index)
  installed_fx()
  for _,folder in ipairs(M.installed_fx_user_folders or {}) do
    if menu_begin(ctx,folder.name,#folder.fx>0) then
      draw_fx_items(ctx,track,state,folder.fx,position,replace_index)
      menu_end(ctx)
    end
  end
end

local function alphabetical_menu(ctx,track,state,position,replace_index)
  local rows=installed_fx()
  if not menu_begin(ctx,'All installed FX',#rows>0) then return end
  for _,range in ipairs(ALPHA_RANGES) do
    local group=M.installed_fx_alpha_groups and M.installed_fx_alpha_groups[range.label]
    if group and #group.letters>0 and menu_begin(ctx,range.label,true) then
      for _,letter in ipairs(group.letters) do
        local letter_rows=group.by_letter[letter]
        if menu_begin(ctx,letter,true) then
          draw_fx_items(ctx,track,state,letter_rows,position,replace_index)
          menu_end(ctx)
        end
      end
      menu_end(ctx)
    end
  end
  menu_end(ctx)
end

local function category_menu(ctx,track,state,position,replace_index)
  installed_fx()
  for _,range in ipairs(CATEGORY_RANGES) do
    local categories=M.installed_fx_category_groups and M.installed_fx_category_groups[range.label] or {}
    if #categories>0 and menu_begin(ctx,range.label,true) then
      for _,category in ipairs(categories) do
        local rows=M.installed_fx_by_category[category] or {}
        if menu_begin(ctx,category,#rows>0) then
          draw_fx_items(ctx,track,state,rows,position,replace_index)
          menu_end(ctx)
        end
      end
      menu_end(ctx)
    end
  end
end

local function developer_menu(ctx,track,state,position,replace_index)
  installed_fx()
  for _,range in ipairs(DEVELOPER_RANGES) do
    local group=M.installed_fx_developer_groups and M.installed_fx_developer_groups[range.label] or {}
    if #group>0 and menu_begin(ctx,'Developers '..range.label,true) then
      for _,vendor in ipairs(group) do
        local rows=M.installed_fx_by_vendor[vendor] or {}
        if menu_begin(ctx,vendor,#rows>0) then
          draw_fx_items(ctx,track,state,rows,position,replace_index)
          menu_end(ctx)
        end
      end
      menu_end(ctx)
    end
  end
end

local function fx_search_input(ctx,id,width)
  local value=M.fx_search or ''
  if reaper.ImGui_IsWindowAppearing and reaper.ImGui_IsWindowAppearing(ctx)
      and reaper.ImGui_SetKeyboardFocusHere then reaper.ImGui_SetKeyboardFocusHere(ctx) end
  if reaper.ImGui_SetNextItemWidth then reaper.ImGui_SetNextItemWidth(ctx,width or 260) end
  local changed,out=reaper.ImGui_InputText(ctx,'Search FX##'..id,value)
  if changed then M.fx_search=out or '' end
  return (M.fx_search or ''):lower()
end

local function matching_fx(query)
  return fx_search.match(installed_fx(),query)
end

local function draw_fx_matches(ctx,track,state,rows,position,replace_index)
  if #rows==0 then
    if reaper.ImGui_TextDisabled then reaper.ImGui_TextDisabled(ctx,'No matching installed FX') end
    return
  end
  for i,fx in ipairs(rows) do
    local label=replace_index~=nil and ('Replace with '..fx.display) or fx.display
    if fx_menu_item(ctx,fx,i,label) then choose_fx(ctx,track,state,position,replace_index,fx) end
  end
end

local function fx_catalog_menu(ctx,track,state,position,replace_index,id)
  local query=fx_search_input(ctx,id or 'picker',205)
  reaper.ImGui_SameLine(ctx)
  local refresh_hit=reaper.ImGui_Button(ctx,'Refresh##fx_catalog_refresh',54,20)
  tooltip(ctx,'Re-scan REAPER’s installed FX list and update the persistent cache')
  if refresh_hit then
    M.refresh_fx_catalog()
    query=(M.fx_search or ''):lower()
  end
  menu_separator(ctx)
  if query~='' then
    draw_fx_matches(ctx,track,state,matching_fx(query),position,replace_index)
    return
  end
  add_recent_menu(ctx,track,state,position,replace_index,'Recently used')
  category_menu(ctx,track,state,position,replace_index)
  developer_menu(ctx,track,state,position,replace_index)
  user_fx_folders_menu(ctx,track,state,position,replace_index)
  alphabetical_menu(ctx,track,state,position,replace_index)
  if reaper.ImGui_TextDisabled then reaper.ImGui_TextDisabled(ctx,'Search or browse all installed FX') end
end

local function set_fx_enabled(track,state,index,enabled,label)
  undo.edit(label,function()
    if reaper.TrackFX_GetCount(track)>index then reaper.TrackFX_SetEnabled(track,index,enabled) end
    state.fx=nil;reaper.UpdateArrange()
  end)
end

local function set_fx_offline(track,state,index,offline)
  if not reaper.TrackFX_SetOffline then return end
  local label=offline and 'Offline FX' or 'Online FX'
  native_ui.queue(label,track,function(target,resolved)
    undo.edit(label,function()
      reaper.TrackFX_SetOffline(target,resolved,offline)
      state.fx=nil;reaper.UpdateArrange()
    end)
  end,index)
end

local function set_fx_slot_group(track,state,index,all_tracks)
  local tracks=matching_tracks(track,all_tracks)
  local enabled=reaper.TrackFX_GetCount(track)>index and reaper.TrackFX_GetEnabled(track,index) or true
  undo.edit('Toggle FX slot bypass',function()
    for _,target in ipairs(tracks) do
      if target and reaper.TrackFX_GetCount(target)>index then reaper.TrackFX_SetEnabled(target,index,not enabled) end
    end
    state.fx=nil;reaper.UpdateArrange()
  end)
end

local function show_fx_chain_at(track,index)
  if not reaper.TrackFX_Show then api.show_fx_chain(track);return end
  native_ui.queue('Show FX chain',track,function(target,resolved)
    reaper.TrackFX_Show(target,resolved,1)
  end,index)
end

local function show_fx_window(track,index,toggle)
  if not reaper.TrackFX_Show then return end
  native_ui.queue('Show FX window',track,function(target,resolved)
    local floating=toggle and reaper.TrackFX_GetFloatingWindow and reaper.TrackFX_GetFloatingWindow(target,resolved)
    reaper.TrackFX_Show(target,resolved,floating and 2 or 3)
  end,index)
end

local function rename_fx(track,state,index,current_name)
  if not reaper.GetUserInputs or not reaper.TrackFX_SetNamedConfigParm then
    show_fx_chain_at(track,index);return
  end
  native_ui.queue('Rename FX instance',track,function(target,resolved)
    local project=current_project()
    local guid=reaper.TrackFX_GetFXGUID(target,resolved)
    local ok,value=reaper.GetUserInputs('Rename FX instance',1,'FX name:',current_name or '')
    resolved=resolve_fx_after_modal(target,project,guid)
    if ok and value and value~='' and resolved then
      undo.edit('Rename FX instance',function()
        reaper.TrackFX_SetNamedConfigParm(target,resolved,'renamed_name',value)
        state.fx=nil;reaper.UpdateArrange()
      end)
    end
  end,index)
end

local function fx_toggle_button(ctx,track,state,fx,index,width)
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  local hit=reaper.ImGui_InvisibleButton(ctx,'##fxenable'..index,width,FX_ROW_HEIGHT)
  local hovered=reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx)
  local activated=reaper.ImGui_IsItemActivated and reaper.ImGui_IsItemActivated(ctx)
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  if hovered then reaper.ImGui_DrawList_AddRectFilled(dl,x+1,y+1,x+width-1,y+22,0xFFFFFF12,3) end
  local enabled=fx and fx.enabled or false
  local marker=enabled and C.violet or (fx and 0x777174FF or 0x5B5559FF)
  reaper.ImGui_DrawList_AddRectFilled(dl,x+math.floor(width/2)-2,y+5,x+math.floor(width/2)+2,y+18,marker,2)
  if fx then
    local wheeled,next_enabled=controls.toggle(ctx,fx.enabled)
    if wheeled then set_fx_enabled(track,state,index,next_enabled,'Set FX bypass') end
    local drag=M.fx_toggle_drag
    if activated and not drag then
      drag={track=track,enable=not fx.enabled,applied={},changed=false}
      M.fx_toggle_drag=drag
      undo.begin('Set FX enable state')
    end
    drag=M.fx_toggle_drag
    local down=reaper.ImGui_IsMouseDown and reaper.ImGui_IsMouseDown(ctx,0)
    if drag and drag.track==track and hovered and down and not drag.applied[index] then
      drag.applied[index]=true
      if reaper.TrackFX_GetCount(track)>index and reaper.TrackFX_GetEnabled(track,index)~=drag.enable then
        reaper.TrackFX_SetEnabled(track,index,drag.enable)
        drag.changed=true;state.fx=nil
      end
    elseif hit and not drag then
      set_fx_enabled(track,state,index,not fx.enabled,'Toggle FX bypass')
    end
  end
  tooltip(ctx,fx and (fx.enabled and 'Bypass this FX  •  drag across other FX toggles' or 'Enable this FX  •  drag across other FX toggles') or 'FX enable toggle')
  return hit,hovered
end

local function finish_fx_toggle_drag(ctx)
  local drag=M.fx_toggle_drag
  if not drag then return end
  if reaper.ImGui_IsMouseDown and reaper.ImGui_IsMouseDown(ctx,0) then return end
  undo.finish('Set FX enable state')
  if drag.changed then reaper.UpdateArrange() end
  M.fx_toggle_drag=nil
end

local function fx_slot_menu(ctx,track,state,fx,index,popup)
  if not (reaper.ImGui_BeginPopup and reaper.ImGui_BeginPopup(ctx,popup,controls.scroll_flags())) then return end
  if not fx then
    fx_catalog_menu(ctx,track,state,index,nil,'slot_'..index)
    controls.scroll_end(ctx)
    reaper.ImGui_EndPopup(ctx)
    return
  end
  local query=fx_search_input(ctx,'slot_'..index)
  if query~='' then
    local matches=matching_fx(query)
    if #matches==0 then
      if reaper.ImGui_TextDisabled then reaper.ImGui_TextDisabled(ctx,'No matching installed FX') end
    else
      if menu_begin(ctx,'Add after this FX',#matches>0) then
        draw_fx_matches(ctx,track,state,matches,index+1,nil)
        menu_end(ctx)
      end
      if menu_begin(ctx,'Replace this FX',#matches>0) then
        draw_fx_matches(ctx,track,state,matches,index,index)
        menu_end(ctx)
      end
    end
    controls.scroll_end(ctx)
    reaper.ImGui_EndPopup(ctx)
    return
  end
  if fx then
    local wet_param=reaper.TrackFX_GetParamFromIdent and reaper.TrackFX_GetParamFromIdent(track,index,':wet') or -1
    if wet_param>=0 and reaper.TrackFX_GetParamNormalized and reaper.TrackFX_SetParamNormalized then
      prop.set_scope(ctx,'fx:'..tostring(track)..':'..index)
      local wet=reaper.TrackFX_GetParamNormalized(track,index,wet_param)*100
      prop.number(ctx,'Wet / dry','##fx_wet',wet,function(value)
        undo.edit('Set FX wet/dry',function() reaper.TrackFX_SetParamNormalized(track,index,wet_param,value/100) end)
      end,'%.1f %%',{step=1,min=0,max=100,default=100})
      menu_separator(ctx)
    end
    if menu_begin(ctx,'Add FX…',true) then
      fx_catalog_menu(ctx,track,state,index+1,nil,'add_after_'..index)
      menu_end(ctx)
    end
    add_recent_menu(ctx,track,state,index+1,nil,'Quick add FX')
    local rows=installed_fx()
    local quick=recent_fx()
    if menu_begin(ctx,'Replace FX…',#rows>0) then
      fx_catalog_menu(ctx,track,state,index,index,'replace_'..index)
      menu_end(ctx)
    end
    if menu_begin(ctx,'Quick replace FX',#quick>0) then
      for i,entry in ipairs(quick) do
        if fx_menu_item(ctx,entry,i) then choose_fx(ctx,track,state,index,index,entry) end
      end
      menu_end(ctx)
    end
    menu_separator(ctx)
    local parallel='0'
    if reaper.TrackFX_GetNamedConfigParm then
      local ok,value=reaper.TrackFX_GetNamedConfigParm(track,index,'parallel')
      if ok then parallel=value end
    end
    if menu_item(ctx,'Run FX in series','',parallel=='0',reaper.TrackFX_SetNamedConfigParm~=nil) then
      undo.edit('Run FX in series',function()
        reaper.TrackFX_SetNamedConfigParm(track,index,'parallel','0');state.fx=nil;reaper.UpdateArrange()
      end)
    end
    if menu_item(ctx,'Run FX in parallel with previous FX','',false,
      index>0 and reaper.TrackFX_SetNamedConfigParm~=nil) then
      if reaper.TrackFX_SetNamedConfigParm and index>0 then
        undo.edit('Run FX in parallel',function()
          reaper.TrackFX_SetNamedConfigParm(track,index,'parallel','1');state.fx=nil;reaper.UpdateArrange()
        end)
      end
    end
    if menu_item(ctx,'Run FX in parallel with previous FX (merge MIDI)','',false,
      index>0 and reaper.TrackFX_SetNamedConfigParm~=nil) then
      if reaper.TrackFX_SetNamedConfigParm and index>0 then
        undo.edit('Run FX in parallel (merge MIDI)',function()
          reaper.TrackFX_SetNamedConfigParm(track,index,'parallel','2');state.fx=nil;reaper.UpdateArrange()
        end)
      end
    end
    menu_separator(ctx)
    if menu_item(ctx,'Float FX configuration','Click',false,reaper.TrackFX_Show~=nil) and reaper.TrackFX_Show then
      show_fx_window(track,index,false)
    end
    if menu_item(ctx,'Show FX chain','Ctrl+Click',false,true) then show_fx_chain_at(track,index) end
    menu_separator(ctx)
    if menu_item(ctx,'Bypass chain','',not api.fx_chain_enabled(track),true) then
      local next_enabled=not api.fx_chain_enabled(track)
      undo.edit(next_enabled and 'Enable FX chain' or 'Bypass FX chain',function()
        api.set_fx_chain_enabled(track,next_enabled);state.fx=nil;reaper.UpdateArrange()
      end)
    end
    if menu_item(ctx,fx.enabled and 'Bypass FX' or 'Enable FX','Shift+Click',not fx.enabled,true) then set_fx_enabled(track,state,index,not fx.enabled,'Toggle FX bypass') end
    if menu_item(ctx,fx.offline and 'Online FX' or 'Offline FX','Ctrl+Shift+Click',fx.offline,reaper.TrackFX_SetOffline~=nil) then set_fx_offline(track,state,index,not fx.offline) end
    if menu_item(ctx,'Delete FX','Alt+Click',false,true) then
      undo.edit('Delete FX: '..fx.name,function()
        reaper.TrackFX_Delete(track,index);state.fx=nil;reaper.UpdateArrange()
      end)
    end
    if menu_item(ctx,'Rename FX instance…','',false,reaper.GetUserInputs~=nil and reaper.TrackFX_SetNamedConfigParm~=nil) then rename_fx(track,state,index,fx.name) end
    menu_separator(ctx)
    if menu_item(ctx,'Bypass FX slot for selected tracks','Alt+Shift+Click',false,true) then set_fx_slot_group(track,state,index,false) end
    if menu_item(ctx,'Bypass FX slot for all tracks','Alt+Ctrl+Shift+Click',false,true) then set_fx_slot_group(track,state,index,true) end
  end
  controls.scroll_end(ctx)
  reaper.ImGui_EndPopup(ctx)
end

local function fx_row_surface(dl,x,y,width,label_width)
  reaper.ImGui_DrawList_AddRectFilled(dl,x+1,y+2,x+width,y+FX_ROW_HEIGHT+2,C.shadow,5)
  reaper.ImGui_DrawList_AddRectFilled(dl,x,y,x+width,y+FX_ROW_HEIGHT,C.header,5)
  reaper.ImGui_DrawList_AddLine(dl,x+4,y+1,x+width-4,y+1,0xBEB4AF24,1)
  reaper.ImGui_DrawList_AddLine(dl,x+label_width,y+4,x+label_width,y+FX_ROW_HEIGHT-4,0x211F20AA,1)
end

local function fx_row(ctx,track,state,fx,index)
  local avail=reaper.ImGui_GetContentRegionAvail(ctx) or 120
  local body=math.max(32,avail)
  local toggle_width=FX_TOGGLE_WIDTH
  local label_width=math.max(16,body-toggle_width)
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  fx_row_surface(dl,x,y,body,label_width)
  if fx then
    local name=fx_name(fx.name)
    reaper.ImGui_DrawList_AddText(dl,x+7,y+4,(fx.enabled and not fx.offline) and C.text or C.muted,cut((fx.offline and '[off] ' or '')..name,math.max(2,math.floor((label_width-12)/7))))
  end
  local hit=reaper.ImGui_InvisibleButton(ctx,'##fxrow'..index,label_width,FX_ROW_HEIGHT)
  local right_click=reaper.ImGui_IsItemClicked and reaper.ImGui_IsItemClicked(ctx,1)
  local popup='##fx_slot_menu_'..tostring(track)..'_'..index
  if right_click and reaper.ImGui_OpenPopup then
    M.fx_search=''
    reaper.ImGui_OpenPopup(ctx,popup)
  end
  if reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_DrawList_AddRectFilled(dl,x,y,x+body,y+23,0xFFFFFF12,5)
  end
  tooltip(ctx,fx and (fx.name..(fx.offline and ' (offline)' or '')..'\nClick: float  •  Ctrl: chain  •  Shift: bypass  •  Ctrl+Shift: offline  •  Alt: delete\nAlt+Shift: bypass same slot on selected tracks  •  Alt+Ctrl+Shift: all tracks  •  Drag: reorder') or 'Click to search and insert an FX. Right-click for installed-FX options.')
  if hit then
    if fx then
      local alt,shift,ctrl=has_mod(ctx,'Alt'),has_mod(ctx,'Shift'),has_mod(ctx,'Ctrl')
      if alt and shift and reaper.TrackFX_SetEnabled then
        undo.edit('Toggle FX slot bypass',function()
          for _,target in ipairs(matching_tracks(track,ctrl)) do
            if target and reaper.TrackFX_GetCount(target)>fx.index then
              reaper.TrackFX_SetEnabled(target,fx.index,not reaper.TrackFX_GetEnabled(target,fx.index))
            end
          end
          state.fx=nil;reaper.UpdateArrange()
        end)
      elseif alt and not ctrl and not shift and reaper.TrackFX_Delete then
        undo.edit('Delete FX: '..fx.name,function()
          reaper.TrackFX_Delete(track,fx.index); state.fx=nil; reaper.UpdateArrange()
        end)
      elseif ctrl and shift and reaper.TrackFX_SetOffline then
        set_fx_offline(track,state,fx.index,not fx.offline)
      elseif shift and not ctrl and reaper.TrackFX_SetEnabled then
        undo.edit('Toggle FX bypass: '..fx.name,function()
          reaper.TrackFX_SetEnabled(track,fx.index,not fx.enabled)
          state.fx=nil; reaper.UpdateArrange()
        end)
      elseif ctrl then show_fx_chain_at(track,fx.index)
      elseif reaper.TrackFX_Show then
        show_fx_window(track,fx.index,true)
      end
    else
      M.fx_search=''
      if reaper.ImGui_OpenPopup then reaper.ImGui_OpenPopup(ctx,popup) end
    end
  end
  if fx and reaper.ImGui_BeginDragDropSource and reaper.ImGui_BeginDragDropSource(ctx) then
    drag_scope(ctx,reaper.ImGui_EndDragDropSource,function()
      local guid=reaper.TrackFX_GetFXGUID and reaper.TrackFX_GetFXGUID(track,fx.index)
      if guid and guid~='' then
        reaper.ImGui_SetDragDropPayload(ctx,'REASPECT_FX_MOVE',track_identity(track)..'|'..guid,reaper.ImGui_Cond_Once())
      end
      reaper.ImGui_Text(ctx,fx_name(fx.name))
    end)
  end
  fx_drop(ctx,track,state,index)
  reaper.ImGui_SameLine(ctx,0,0)
  local toggle_hit,toggle_hover=fx_toggle_button(ctx,track,state,fx,index,toggle_width)
  local toggle_right=reaper.ImGui_IsItemClicked and reaper.ImGui_IsItemClicked(ctx,1)
  if (toggle_right or (toggle_hit and not fx)) and reaper.ImGui_OpenPopup then
    if not fx then M.fx_search='' end
    reaper.ImGui_OpenPopup(ctx,popup)
  end
  if toggle_hover then fx_drop(ctx,track,state,index) end
  fx_slot_menu(ctx,track,state,fx,index,popup)
end

local function small_knob(ctx,id,value,minv,maxv,tint,reset,feedback)
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  local cx,cy=x+11,y+11
  local a1,a2=math.pi*.75,math.pi*2.25
  local fraction=clamp((value-minv)/(maxv-minv),0,1)
  local angle=a1+(a2-a1)*fraction
  reaper.ImGui_DrawList_AddCircleFilled(dl,cx+0.4,cy+0.8,10.5,C.shadow)
  reaper.ImGui_DrawList_AddCircleFilled(dl,cx,cy,9.8,0x252A2DFF)
  arc(dl,cx,cy,8.8,0,math.pi*2,0x697074FF,1.2)
  if feedback=='pan' then
    local center=(a1+a2)/2
    if math.abs(value)>.01 then arc(dl,cx,cy,8.8,math.min(center,angle),math.max(center,angle),tint,1.9) end
  elseif fraction>.015 then arc(dl,cx,cy,8.8,a1,angle,tint,1.9) end
  reaper.ImGui_DrawList_AddCircleFilled(dl,cx,cy,6.5,0x3C4245FF)
  if reaper.ImGui_DrawList_AddCircle then reaper.ImGui_DrawList_AddCircle(dl,cx,cy,6.5,0x202427FF,0,1) end
  reaper.ImGui_DrawList_AddLine(dl,cx,cy,cx+math.cos(angle)*5,cy+math.sin(angle)*5,
    feedback=='pan' and math.abs(value)<.01 and 0xD5D9D8FF or C.white,1.9)
  reaper.ImGui_InvisibleButton(ctx,id,22,22)
  local out=value
  local active=reaper.ImGui_IsItemActive and reaper.ImGui_IsItemActive(ctx)
  if reaper.ImGui_IsItemActivated and reaper.ImGui_IsItemActivated(ctx) then M.knob_drags[id]=value end
  local reset_hit=controls.double_click(ctx) or
    (reaper.ImGui_IsItemClicked and reaper.ImGui_IsItemClicked(ctx,1))
  if active and reaper.ImGui_GetMouseDragDelta then
    local _,dy=reaper.ImGui_GetMouseDragDelta(ctx,0,0,0,0)
    out=clamp((M.knob_drags[id] or value)-dy*(maxv-minv)*.006,minv,maxv)
  elseif active and reaper.ImGui_GetMouseDelta then
    local _,dy=reaper.ImGui_GetMouseDelta(ctx)
    if dy~=0 then out=clamp(value-dy*(maxv-minv)*.006,minv,maxv) end
  end
  if not active then M.knob_drags[id]=nil end
  local wheel,new=controls.wheel(ctx,value,feedback=='pan' and 0.01 or 0.5,minv,maxv)
  if wheel then out=new end
  if reset_hit then out=reset end
  return out~=value and not reset_hit,out,reset_hit
end

local function send_bypass(ctx,id,muted,on_click)
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  local hit=reaper.ImGui_InvisibleButton(ctx,id,18,22)
  local hovered=reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx)
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  local ink=muted and 0xEE6272FF or (hovered and 0xF3F3F0FF or 0xC5C8C7FF)
  reaper.ImGui_DrawList_AddCircleFilled(dl,x+9,y+11,9,hovered and 0x606367FF or 0x34383AFF)
  if reaper.ImGui_DrawList_AddCircle then reaper.ImGui_DrawList_AddCircle(dl,x+9,y+11,6,ink,0,1.5) end
  reaper.ImGui_DrawList_AddLine(dl,x+9,y+4,x+9,y+11,ink,1.8)
  tooltip(ctx,muted and 'Enable send' or 'Bypass send')
  if hit then on_click() end
end

local function route_details(ctx,track,state,send,popup,label)
  if not reaper.ImGui_BeginPopup(ctx,popup,controls.scroll_flags()) then return end
  local category,index=send.category or 0,send.index
  local kind=category==-1 and 'receive' or 'send'
  local other=category==-1 and send.src or send.dest
  local function get(key) return reaper.GetTrackSendInfo_Value(track,category,index,key) or 0 end
  local function set(key,value,caption)
    undo.edit(caption or ('Set '..kind),function()
      reaper.SetTrackSendInfo_Value(track,category,index,key,value)
      state.sends,state.receives=nil,nil
    end)
  end
  prop.set_scope(ctx,'route:'..tostring(track)..':'..category..':'..index)
  reaper.ImGui_Text(ctx,label)
  prop.number(ctx,'Level','##route_level',db(get('D_VOL')),function(v) set('D_VOL',lin(v),'Set '..kind..' level') end,
    '%.1f dB',{step=0.5,min=-60,max=12,default=0})
  prop.number(ctx,'Pan','##route_pan',get('D_PAN')*100,function(v) set('D_PAN',v/100,'Set '..kind..' pan') end,
    '%+.0f %%',{step=1,min=-100,max=100,default=0})
  local mode=math.floor(get('I_SENDMODE'))
  -- Legacy mode 2 is equivalent to post-FX; never present it as an unknown.
  if mode==2 then mode=3 end
  prop.enum(ctx,'Mode','##route_mode',mode,
    {'Post-fader / post-pan','Pre-FX','Post-FX / pre-fader'},{0,1,3},function(v) set('I_SENDMODE',v,'Set '..kind..' mode') end,{default=0})
  prop.checkbox(ctx,'Mute','##route_mute',get('B_MUTE')>0,function(v) set('B_MUTE',v and 1 or 0,'Mute '..kind) end)
  prop.checkbox(ctx,'Mono','##route_mono',get('B_MONO')>0,function(v) set('B_MONO',v and 1 or 0,'Set '..kind..' mono') end)
  prop.checkbox(ctx,'Invert polarity','##route_phase',get('B_PHASE')>0,function(v) set('B_PHASE',v and 1 or 0,'Set '..kind..' polarity') end)
  reaper.ImGui_Separator(ctx)
  if reaper.ImGui_Button(ctx,'Audio / MIDI routing…##route_native',-1) then
    api.show_routing(track)
    reaper.ImGui_CloseCurrentPopup(ctx)
  end
  prop.tooltip(ctx,'Open REAPER routing for channel mapping, sidechains, MIDI buses/channels, hardware outputs and envelopes.')
  if other and reaper.ImGui_Button(ctx,category==-1 and 'Go to source track' or 'Go to destination track',-1) then
    reaper.SetOnlyTrackSelected(other)
    reaper.ImGui_CloseCurrentPopup(ctx)
  end
  if reaper.ImGui_Button(ctx,'Remove '..kind,-1) then
    undo.edit('Remove '..kind,function() reaper.RemoveTrackSend(track,category,index);state.sends,state.receives=nil,nil end)
    reaper.ImGui_CloseCurrentPopup(ctx)
  end
  controls.scroll_end(ctx)
  reaper.ImGui_EndPopup(ctx)
end

local function send_row(ctx,track,state,send)
  local category=send.category or 0
  local kind=category==-1 and 'receive' or 'send'
  local row_id=tostring(track)..'_'..category..'_'..send.index
  local function set(key,value)
    reaper.SetTrackSendInfo_Value(track,category,send.index,key,value)
    state.sends,state.receives=nil,nil
  end
  local avail=reaper.ImGui_GetContentRegionAvail(ctx) or 120
  local dest=category==-1 and send.src or send.dest
  local number=dest and reaper.GetMediaTrackInfo_Value(dest,'IP_TRACKNUMBER') or 0
  local name=dest and api.track.name(dest) or '(missing track)'
  local label=(number>0 and (tostring(math.floor(number))..':') or '')..(name~='' and name or 'Track')
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  reaper.ImGui_DrawList_AddRectFilled(dl,x+1,y+2,x+avail,y+27,C.shadow,5)
  reaper.ImGui_DrawList_AddRectFilled(dl,x,y,x+avail,y+25,send.mute and 0x302D30FF or C.well,5)
  reaper.ImGui_DrawList_AddLine(dl,x+4,y+1,x+avail-4,y+1,0xBEB4AF24,1)
  local title_w=math.max(20,avail-30)
  reaper.ImGui_DrawList_AddText(dl,x+6,y+5,send.mute and C.muted or C.gold,cut(label,math.max(2,math.floor((title_w-10)/7))))
  local send_hit=reaper.ImGui_InvisibleButton(ctx,'##sendlabel'..row_id,title_w,25)
  local send_right=reaper.ImGui_IsItemClicked and reaper.ImGui_IsItemClicked(ctx,1)
  if send_hit then
    local alt,shift,ctrl=has_mod(ctx,'Alt'),has_mod(ctx,'Shift'),has_mod(ctx,'Ctrl')
    if ctrl and not alt and not shift and dest then
      reaper.SetOnlyTrackSelected(dest)
    elseif alt and shift then
      undo.edit('Toggle send slot mute',function()
        for _,target in ipairs(matching_tracks(track,ctrl)) do
          if target and reaper.GetTrackNumSends(target,category)>send.index then
            local old=reaper.GetTrackSendInfo_Value(target,category,send.index,'B_MUTE') or 0
            reaper.SetTrackSendInfo_Value(target,category,send.index,'B_MUTE',old<=0 and 1 or 0)
          end
        end
        state.sends,state.receives=nil,nil;reaper.UpdateArrange()
      end)
    elseif alt and reaper.RemoveTrackSend then
      undo.edit('Remove '..kind,function()
        reaper.RemoveTrackSend(track,category,send.index)
        state.sends,state.receives=nil,nil; reaper.UpdateArrange()
      end)
      return -- The following route now occupies this index.
    elseif shift then
      undo.edit('Toggle '..kind..' mute',function()
        set('B_MUTE',send.mute and 0 or 1)
        reaper.UpdateArrange()
      end)
    else api.show_routing(track)
    end
  end
  local popup='##route_details_'..row_id
  if send_right then reaper.ImGui_OpenPopup(ctx,popup) end
  tooltip(ctx,label..'\nClick: REAPER routing  •  Shift: mute  •  Alt: remove  •  Ctrl: go to track\nRight-click: level, pan, mode, mute, mono and polarity')
  reaper.ImGui_SameLine(ctx)
  local changed,volume,reset_volume=small_knob(ctx,'##sendvol'..row_id,db(send.volume),-60,12,send.mute and C.muted or C.gold,0)
  tooltip(ctx,string.format('%s level: %.1f dB\nDrag or wheel; right-click or double-click for unity',label,db(send.volume)))
  if reset_volume then
    undo.edit('Reset '..kind..' level',function()
      set('D_VOL',1)
      reaper.UpdateArrange()
    end)
  else
    undo.gesture(ctx,'rack_send_volume_'..row_id,'Set '..kind..' level',changed,function()
      set('D_VOL',lin(volume))
    end)
  end
  route_details(ctx,track,state,send,popup,label)
end

local function header_button(ctx,label,id,width,action,help)
  local hit=reaper.ImGui_Button(ctx,label..'##'..id,width,21)
  tooltip(ctx,help)
  if hit then action() end
end

local function fx_header(ctx,track,state,compact,available_width)
  sync_theme()
  local avail=available_width or reaper.ImGui_GetContentRegionAvail(ctx) or 120
  local count=reaper.TrackFX_GetCount(track)
  local enabled=api.fx_chain_enabled(track)
  local combined=math.max(32,avail)
  local body=combined-FX_TOGGLE_WIDTH
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  local open_hit=reaper.ImGui_InvisibleButton(ctx,'##fxchain',body,FX_ROW_HEIGHT)
  local body_hover=reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx)
  local open_right=reaper.ImGui_IsItemClicked and reaper.ImGui_IsItemClicked(ctx,1)
  tooltip(ctx,count>0 and 'Click: open the track FX chain  •  Right-click: search and add FX' or 'Click or right-click to search and add an FX')
  if (open_right or (open_hit and count==0)) and reaper.ImGui_OpenPopup then
    M.fx_search=''
    reaper.ImGui_OpenPopup(ctx,'##fx_header_menu')
  end
  fx_drop(ctx,track,state,reaper.TrackFX_GetCount(track))
  reaper.ImGui_SameLine(ctx,0,0)
  local bypass_hit=reaper.ImGui_InvisibleButton(ctx,'##fxchainlamp',FX_TOGGLE_WIDTH,FX_ROW_HEIGHT)
  local bypass_hover=reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx)
  local bypass_changed,next_enabled=controls.toggle(ctx,enabled,true)
  tooltip(ctx,enabled and 'Bypass all track FX' or 'Enable all track FX')
  local line=enabled and C.violet or 0xF25F75FF
  local text_col=enabled and (C.heading or C.violet) or 0xF26471FF
  if count==0 and enabled then line=0x7E7880FF end
  fx_row_surface(dl,x,y,combined,body)
  if body_hover then reaper.ImGui_DrawList_AddRectFilled(dl,x,y,x+combined,y+FX_ROW_HEIGHT,0xFFFFFF12,5) end
  if bypass_hover then reaper.ImGui_DrawList_AddRectFilled(dl,x+body+1,y+1,x+combined-1,y+FX_ROW_HEIGHT-1,0xFFFFFF12,3) end
  reaper.ImGui_DrawList_AddText(dl,x+7,y+4,text_col,'FX')
  local marker_x=x+body+math.floor(FX_TOGGLE_WIDTH/2)
  reaper.ImGui_DrawList_AddRectFilled(dl,marker_x-2,y+5,marker_x+2,y+18,line,2)
  if open_hit and count>0 then show_fx_chain_at(track,0) end
  if reaper.ImGui_BeginPopup and reaper.ImGui_BeginPopup(ctx,'##fx_header_menu') then
    fx_catalog_menu(ctx,track,state,count)
    reaper.ImGui_EndPopup(ctx)
  end
  if bypass_hit or bypass_changed then
    if not bypass_changed then next_enabled=not enabled end
    undo.edit('Toggle track FX chain',function()
      api.set_fx_chain_enabled(track,next_enabled)
      state.fx=nil; reaper.UpdateArrange()
    end)
  end
end
M.draw_fx_header=fx_header

local function send_popup_id(track)
  return '##send_target_'..tostring(track)
end

local function open_send_picker(ctx,track)
  M.send_search=''
  if reaper.ImGui_OpenPopup then reaper.ImGui_OpenPopup(ctx,send_popup_id(track)) end
end

local function queue_send_creation(source,destination,state)
  M.pending_send_creation={source=source,destination=destination,state=state}
end

function M.process_pending_actions()
  local pending=M.pending_send_creation
  M.pending_send_creation=nil
  if not pending then return end
  -- This is called after the ImGui frame has ended. Ignore track pointers
  -- invalidated while the picker was closing or the project was switching.
  if reaper.ValidatePtr2 then
    if not reaper.ValidatePtr2(0,pending.source,'MediaTrack*')
        or not reaper.ValidatePtr2(0,pending.destination,'MediaTrack*') then return end
  end
  undo.edit('Create track send',function()
    if api.create_send(pending.source,pending.destination)>=0 then
      pending.state.sends=nil
      -- The project change count invalidates the cached send list next frame;
      -- no arrange or track-window refresh is needed here.
    end
  end)
end

local function send_header(ctx,track,available_width)
  local avail=available_width or reaper.ImGui_GetContentRegionAvail(ctx) or 120
  local add_w,gap=23,3
  local body=math.max(1,avail-add_w-gap)
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  local route_hit=reaper.ImGui_InvisibleButton(ctx,'##sendhead',body,22)
  local route_hover=reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx)
  local route_right=reaper.ImGui_IsItemClicked and reaper.ImGui_IsItemClicked(ctx,1)
  tooltip(ctx,'Click to open REAPER routing; right-click for REAPER’s native routing menu')
  reaper.ImGui_DrawList_AddRectFilled(dl,x+1,y+2,x+body,y+24,C.shadow,4)
  reaper.ImGui_DrawList_AddRectFilled(dl,x,y,x+body,y+22,0x2D3236FF,4)
  if route_hover then reaper.ImGui_DrawList_AddRectFilled(dl,x,y,x+body,y+22,0x566069AA,4) end
  reaper.ImGui_DrawList_AddText(dl,x+8,y+5,C.heading or C.violet,'SENDS')
  if route_hit then api.show_routing(track) end
  if route_right then api.show_native_track_menu('track_routing',track) end

  reaper.ImGui_SameLine(ctx,0,gap)
  local ax,ay=reaper.ImGui_GetCursorScreenPos(ctx)
  local add_hit=reaper.ImGui_InvisibleButton(ctx,'##send_add',add_w,22)
  local add_hover=reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx)
  reaper.ImGui_DrawList_AddRectFilled(dl,ax+1,ay+2,ax+add_w,ay+24,C.shadow,4)
  reaper.ImGui_DrawList_AddRectFilled(dl,ax,ay,ax+add_w,ay+22,
    add_hover and 0x4B454AFF or 0x2D3236FF,4)
  reaper.ImGui_DrawList_AddLine(dl,ax+add_w/2-4,ay+11,ax+add_w/2+4,ay+11,C.violet,1.8)
  reaper.ImGui_DrawList_AddLine(dl,ax+add_w/2,ay+7,ax+add_w/2,ay+15,C.violet,1.8)
  tooltip(ctx,'Add a send to another track')
  if add_hit then open_send_picker(ctx,track) end
end

local function send_empty_row(ctx,track,slot)
  local avail=math.max(1,reaper.ImGui_GetContentRegionAvail(ctx) or 120)
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  local initial_add=(slot or 1)==1
  local hit=reaper.ImGui_InvisibleButton(ctx,'##send_empty_add'..tostring(slot or 1),avail,25)
  local hovered=reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx)
  reaper.ImGui_DrawList_AddRectFilled(dl,x+1,y+2,x+avail,y+27,C.shadow,5)
  reaper.ImGui_DrawList_AddRectFilled(dl,x,y,x+avail,y+25,hovered and 0x494146FF or C.well,5)
  reaper.ImGui_DrawList_AddLine(dl,x+1,y+1,x+avail-1,y+1,0xBEB4AF24,1)
  if initial_add then
    reaper.ImGui_DrawList_AddLine(dl,x+13,y+12.5,x+21,y+12.5,C.violet,1.7)
    reaper.ImGui_DrawList_AddLine(dl,x+17,y+8.5,x+17,y+16.5,C.violet,1.7)
    reaper.ImGui_DrawList_AddText(dl,x+29,y+6,C.text,'Add send…')
  end
  tooltip(ctx,initial_add and 'Click to choose a destination' or 'Click to add a send')
  -- This row lives in a nested child, while the popup is drawn in the Sends
  -- parent. Defer opening until the parent scope resumes so popup IDs match.
  if hit then M.pending_send_picker=track end
end

local function send_target_picker(ctx,source,state,sends)
  if not reaper.ImGui_BeginPopup then return end
  local popup=send_popup_id(source)
  if not reaper.ImGui_BeginPopup(ctx,popup) then return end
  if reaper.ImGui_Text then reaper.ImGui_Text(ctx,'Add send to track') end
  if reaper.ImGui_SetNextItemWidth then reaper.ImGui_SetNextItemWidth(ctx,230) end
  local changed,query=reaper.ImGui_InputText(ctx,'Search tracks##send_target_search',M.send_search or '')
  if changed then M.send_search=query or '' end
  if reaper.ImGui_Separator then reaper.ImGui_Separator(ctx) end

  local existing={}
  for _,send in ipairs(sends or {}) do if send.dest then existing[send.dest]='send' end end
  local mainsend=reaper.GetMediaTrackInfo_Value(source,'B_MAINSEND') or 0
  if mainsend>0 then
    local parent=reaper.GetParentTrack and reaper.GetParentTrack(source) or nil
    local master=reaper.GetMasterTrack and reaper.GetMasterTrack(0) or nil
    local parent_destination=parent or master
    if parent_destination and not existing[parent_destination] then existing[parent_destination]='parent' end
  end
  local feedback_targets=api.send_cycle_targets(source)
  local needle=(M.send_search or ''):lower()
  local total=math.max(0,(reaper.CountTracks(0) or 0)-1)
  local shown=0
  local connected_shown=false
  local feedback_shown=false
  child(ctx,'##send_target_results',-1,178,0,function()
    local matched=0
    for i=0,(reaper.CountTracks(0) or 0)-1 do
      local destination=reaper.GetTrack(0,i)
      if destination and destination~=source then
        local name=api.track.name(destination)
        local number=math.floor(reaper.GetMediaTrackInfo_Value(destination,'IP_TRACKNUMBER') or i+1)
        local search=(tostring(number)..' '..name):lower()
        if needle=='' or search:find(needle,1,true) then
          matched=matched+1
          local label=string.format('%02d  %s',number,cut(name~='' and name or 'Track',30))
          if feedback_targets[destination] then
            feedback_shown=true
            if reaper.ImGui_TextDisabled then reaper.ImGui_TextDisabled(ctx,label..'  (feedback loop)')
            elseif reaper.ImGui_Text then reaper.ImGui_Text(ctx,label..'  (feedback loop)') end
          else
            if existing[destination] then
              connected_shown=true
              label=label..(existing[destination]=='parent' and '  (parent send)' or '  (connected)')
            end
            if reaper.ImGui_Selectable and reaper.ImGui_Selectable(ctx,label,false) then
              queue_send_creation(source,destination,state)
              if reaper.ImGui_CloseCurrentPopup then reaper.ImGui_CloseCurrentPopup(ctx) end
            end
          end
        end
      end
    end
    shown=matched
    if matched==0 then
      local message=needle~='' and 'No tracks match that search' or (total==0 and 'No other tracks in this project' or 'No matching destinations')
      if reaper.ImGui_TextDisabled then reaper.ImGui_TextDisabled(ctx,message)
      elseif reaper.ImGui_Text then reaper.ImGui_Text(ctx,message) end
    end
  end)
  if shown>0 and connected_shown and reaper.ImGui_TextDisabled then
    reaper.ImGui_TextDisabled(ctx,'Select a connected track to add another send')
  end
  if shown>0 and feedback_shown and reaper.ImGui_TextDisabled then
    reaper.ImGui_TextDisabled(ctx,'Feedback destinations would route back to this track')
  end
  reaper.ImGui_EndPopup(ctx)
end

local function rack_heights(ctx,height,fx,sends,receives)
  if not M.fx_split_loaded then
    M.fx_split=tonumber(persistence.get('rack_fx_split',nil))
    M.fx_split_loaded=true
  end
  local _,spacing=reaper.ImGui_GetStyleVar(ctx,reaper.ImGui_StyleVar_ItemSpacing())
  spacing=math.max(0,spacing or 4)
  local usable=math.max(2,height-RACK_DIVIDER_HEIGHT-spacing*2)
  -- Both sections keep a header and at least one useful row at normal sizes.
  -- Without a saved split, give longer lists proportionally more space.
  local minimum=math.min(60,usable/2)
  local fx_need=FX_ROW_HEIGHT+math.max(5,#fx+1)*(FX_ROW_HEIGHT+spacing)
  local send_slots=math.max(#receives>0 and 1 or MIN_SEND_SLOTS,#sends+1)
  local send_need=22+(send_slots+#receives)*(25+spacing)+(#receives>0 and 26 or 0)
  local desired=M.fx_split and usable*M.fx_split
    or math.min(fx_need,usable*fx_need/(fx_need+send_need))
  local fx_height=math.floor(clamp(desired,minimum,usable-minimum))
  return fx_height,usable-fx_height,usable,minimum
end

local function rack_divider(ctx,fx_height,usable,minimum)
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  local width=reaper.ImGui_GetContentRegionAvail(ctx) or 100
  reaper.ImGui_InvisibleButton(ctx,'##rack_divider',math.max(1,width),RACK_DIVIDER_HEIGHT)
  local hovered=reaper.ImGui_IsItemHovered(ctx)
  local active=reaper.ImGui_IsItemActive(ctx)
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  local handle=math.min(30,width)
  local left=x+(width-handle)/2
  reaper.ImGui_DrawList_AddRectFilled(dl,x,y+3,x+width,y+4,C.line)
  reaper.ImGui_DrawList_AddRectFilled(dl,left,y+2,left+handle,y+5,
    (hovered or active) and C.violet or C.muted,2)
  tooltip(ctx,'Drag or wheel to resize FX and Sends; right-click for automatic sizing')
  local changed,value=controls.wheel(ctx,fx_height,6,minimum,usable-minimum)
  if controls.right_click(ctx) then
    M.fx_split=nil;M.fx_split_drag=nil
    persistence.set('rack_fx_split','')
  elseif active then
    local _,dy=reaper.ImGui_GetMouseDelta(ctx)
    if dy~=0 then
      M.fx_split=clamp(fx_height+dy,minimum,usable-minimum)/usable
      M.fx_split_drag=true
    end
  elseif changed then
    M.fx_split=value/usable
    persistence.set('rack_fx_split',M.fx_split)
  elseif M.fx_split_drag then
    persistence.set('rack_fx_split',M.fx_split)
    M.fx_split_drag=nil
  end
end

function M.draw(ctx,track,state,height)
  sync_theme()
  local h=math.max(1,height or 350)
  local fx,sends,receives=state.get_fx(),state.get_sends(),state.get_receives()
  local fx_h,send_h,usable,minimum=rack_heights(ctx,h,fx,sends,receives)
  -- A permanent, narrow gutter keeps header and row widths identical before
  -- and after overflow. The native thumb remains draggable; wheel ownership
  -- stays with controls through the shared manual scrolling helpers.
  local gutter=RACK_GUTTER
  local row_flags=reaper.ImGui_WindowFlags_AlwaysVerticalScrollbar()
  local section_flags=reaper.ImGui_WindowFlags_NoScrollbar()
  local fixed_section={fixed=true,padding=0}
  local function rows(id,width,draw)
    local _,remaining=reaper.ImGui_GetContentRegionAvail(ctx)
    -- BeginChild clamps a nonpositive remainder to a small window, which
    -- would overflow a section already too short to show its header.
    if remaining and remaining<4 then return end
    child(ctx,id,width,0,row_flags,draw,{padding=0,scrollbar=gutter})
  end
  child(ctx,'##inserts',-1,fx_h,section_flags,function()
    local width=reaper.ImGui_GetContentRegionAvail(ctx)
    fx_header(ctx,track,state,false,width-gutter)
    rows('##insertrows',width,function()
      for _,item in ipairs(fx) do fx_row(ctx,track,state,item,item.index) end
      for i=#fx,math.max(4,#fx) do fx_row(ctx,track,state,nil,i) end
      local zone_w,zone_h=reaper.ImGui_GetContentRegionAvail(ctx)
      if zone_h and zone_h>6 then
        reaper.ImGui_InvisibleButton(ctx,'##fx_empty_drop_zone',math.max(1,zone_w or 1),zone_h-2)
        tooltip(ctx,'Drop a ReaSpect FX row here to move it to the end of the chain')
        fx_drop(ctx,track,state,reaper.TrackFX_GetCount(track))
      end
    end)
  end,fixed_section)
  rack_divider(ctx,fx_h,usable,minimum)
  child(ctx,'##sends',-1,send_h,section_flags,function()
    local width=reaper.ImGui_GetContentRegionAvail(ctx)
    send_header(ctx,track,width-gutter)
    rows('##sendrows',width,function()
      for _,send in ipairs(sends) do send_row(ctx,track,state,send) end
      -- Keep several destination slots ready, with one empty slot after any
      -- longer send list so adding another route never requires a menu hunt.
      for slot=#sends+1,math.max(#receives>0 and 1 or MIN_SEND_SLOTS,#sends+1) do
        send_empty_row(ctx,track,slot)
      end
      if #receives>0 then
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_TextDisabled(ctx,'Receives ('..#receives..')')
        for _,receive in ipairs(receives) do send_row(ctx,track,state,receive) end
      end
    end)
    if M.pending_send_picker==track then
      M.pending_send_picker=nil
      open_send_picker(ctx,track)
    end
    send_target_picker(ctx,track,state,sends)
  end,fixed_section)
  finish_fx_toggle_drag(ctx)
end

return M
