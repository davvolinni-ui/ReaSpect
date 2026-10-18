local auto=require('ReaSpect.core.auto_colors')
local undo=require('ReaSpect.core.undo')
local controls=require('ReaSpect.widgets.controls')
local M={}
local draft,draft_project,error_text
local window_open,editor_section=false,'roles'
local window_project,project_changed
local results_open=false
local folder_labels={smart='Group related roles',shades='Shades of folder',uniform='Match folder',independent='Automatic',parent='Follow parent folder rule',inherit='Saved inheritance',gradient='Saved gradient'}
local folder_choices={{'Group related roles','smart'},{'Match folder','uniform'},{'Shades of folder','shades'},{'Use own colors','independent'}}
local function folder_choice(rule,config)
  if rule=='gradient' and config.child_priority=='smart' then return 'smart' end
  return rule
end
function M.preview_sample(rows,limit)
  local selected,used,groups={},{},{}
  local function add(i)
    if #selected>=limit or used[i] then return end
    selected[#selected+1]=rows[i];used[i]=true;groups[rows[i].group or rows[i].reason]=true
  end
  -- Prefer changes across families, then include unchanged/protected context.
  for i,row in ipairs(rows) do if row.changed and not groups[row.group or row.reason] then add(i) end end
  for i,row in ipairs(rows) do if not groups[row.group or row.reason] then add(i) end end
  for i,row in ipairs(rows) do if row.changed then add(i) end end
  for i in ipairs(rows) do add(i) end
  return selected
end
local function edit(label,fn,wheel)
  undo.wheel_source(wheel==true)
  undo.edit(label,fn)
end
local function item(ctx,label,selected,fn)
  if reaper.ImGui_MenuItem(ctx,label,nil,selected) then edit('Auto track colors: '..label,fn) end
end
local function set(ctx,label,key,value,selected)
  item(ctx,label,selected,function() auto.set_config(key,value) end)
end
local function folder_options(ctx,rule,apply)
  for _,choice in ipairs({{'Automatic','independent'},{'Match folder','uniform'},{'Shades of folder','shades'}}) do
    item(ctx,choice[1],rule==choice[2],function() apply(choice[2]) end)
  end
end
local function folder_scope(ctx,folders)
  local include=auto.track_get(folders[1],'children_scope')=='all'
  local mixed=false
  for _,folder in ipairs(folders) do if (auto.track_get(folder,'children_scope')=='all')~=include then mixed=true end end
  if mixed then reaper.ImGui_TextDisabled(ctx,'Include subfolders: Mixed') end
  local changed,value=reaper.ImGui_Checkbox(ctx,'Include subfolders',not mixed and include)
  if changed then edit('Set folder color scope',function() auto.set_children_scope(folders,value) end) end
end
local function swatches(ctx,colors)
  for i=1,math.min(#colors,16) do
    if i>1 then reaper.ImGui_SameLine(ctx) end
    reaper.ImGui_ColorButton(ctx,'##auto_preview'..i,(colors[i]<<8)|255,reaper.ImGui_ColorEditFlags_NoTooltip(),12,12)
  end
end
local function palette_combo(ctx,id,current,extra,on_pick,preview)
  local names={}
  for _,p in ipairs(auto.presets) do names[#names+1]=p.name end
  names[#names+1]=extra
  local flags=reaper.ImGui_ComboFlags_HeightLarge and reaper.ImGui_ComboFlags_HeightLarge() or 0
  if reaper.ImGui_BeginCombo(ctx,id,preview or current,flags) then
    -- A bounded list owns its wheel and cannot forward scrolling to a menu
    -- or inspector beneath it, including when the list reaches either end.
    local height=reaper.ImGui_GetTextLineHeightWithSpacing(ctx)*10
    if reaper.ImGui_BeginChild(ctx,'##palette_choices',-1,height,0,controls.scroll_flags()) then
      for i,name in ipairs(names) do
        if reaper.ImGui_Selectable(ctx,name,name==current) then on_pick(name,false) end
        if name==current then reaper.ImGui_SetItemDefaultFocus(ctx) end
        if auto.presets[i] and reaper.ImGui_IsItemHovered(ctx) then
          reaper.ImGui_BeginTooltip(ctx);swatches(ctx,auto.presets[i].colors);reaper.ImGui_EndTooltip(ctx)
        end
      end
      controls.popup_scroll_end(ctx)
      reaper.ImGui_EndChild(ctx)
    end
    controls.capture_popup_wheel(ctx)
    reaper.ImGui_EndCombo(ctx)
  else
    local changed,name=controls.choice(ctx,current,names)
    if changed then
      if reaper.ImGui_SetWindowFocus then reaper.ImGui_SetWindowFocus(ctx) end
      on_pick(name,true)
    end
  end
end
local function serialize(colors)
  local hex={}
  for i,rgb in ipairs(colors) do hex[i]=string.format('%06X',rgb) end
  return table.concat(hex,' ')
end
local function seed(colors,source)
  draft={colors={},selected=1,hex=serialize(colors),source=source}
  for i,rgb in ipairs(colors) do draft.colors[i]=rgb end
  error_text=nil
end
local function action(ctx,label,enabled,fn)
  reaper.ImGui_BeginDisabled(ctx,not enabled)
  if reaper.ImGui_Button(ctx,label) and enabled then fn();draft.hex=serialize(draft.colors) end
  reaper.ImGui_EndDisabled(ctx)
end
local function custom_editor(ctx,config)
  local proj=reaper.EnumProjects(-1,'')
  if draft_project~=proj or not draft then draft_project=proj;seed(auto.palette(config),config.palette=='Custom' and 'Saved custom palette' or config.palette) end
  palette_combo(ctx,'Start from preset',draft.source,'Saved custom palette',function(name)
    if name=='Saved custom palette' then
      seed(auto.parse_custom(config.custom) or auto.presets[1].colors,name)
    else
      for _,p in ipairs(auto.presets) do if p.name==name then seed(p.colors,name);break end end
    end
  end,'Choose a palette to copy')
  reaper.ImGui_Text(ctx,'Click a color to edit. Changes apply only when saved.')
  for i,rgb in ipairs(draft.colors) do
    if i>1 and (i-1)%8~=0 then reaper.ImGui_SameLine(ctx) end
    if reaper.ImGui_ColorButton(ctx,'##custom_swatch'..i,(rgb<<8)|255,0,26,26) then
      draft.selected=i
      reaper.ImGui_OpenPopup(ctx,'##custom_color_picker')
    end
    if reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx,'Color '..i..' · #'..string.format('%06X',rgb)) end
  end
  if reaper.ImGui_BeginPopup(ctx,'##custom_color_picker') then
    reaper.ImGui_Text(ctx,'Color '..draft.selected)
    local changed,rgb=reaper.ImGui_ColorPicker3(ctx,'##custom_picker',draft.colors[draft.selected])
    if changed then draft.colors[draft.selected]=rgb&0xFFFFFF;draft.hex=serialize(draft.colors) end
    reaper.ImGui_EndPopup(ctx)
  end
  reaper.ImGui_Text(ctx,'Selected color '..draft.selected..' of '..#draft.colors)
  local changed,rgb=reaper.ImGui_ColorEdit3(ctx,'Selected color',draft.colors[draft.selected])
  if changed then draft.colors[draft.selected]=rgb&0xFFFFFF;draft.hex=serialize(draft.colors) end
  action(ctx,'Move left',draft.selected>1,function()
    local i=draft.selected;draft.colors[i-1],draft.colors[i]=draft.colors[i],draft.colors[i-1];draft.selected=i-1
  end)
  reaper.ImGui_SameLine(ctx)
  action(ctx,'Move right',draft.selected<#draft.colors,function()
    local i=draft.selected;draft.colors[i+1],draft.colors[i]=draft.colors[i],draft.colors[i+1];draft.selected=i+1
  end)
  reaper.ImGui_SameLine(ctx)
  action(ctx,'Remove',#draft.colors>2,function()
    table.remove(draft.colors,draft.selected);draft.selected=math.min(draft.selected,#draft.colors)
  end)
  reaper.ImGui_SameLine(ctx)
  action(ctx,'Add color',#draft.colors<64,function()
    table.insert(draft.colors,draft.selected+1,draft.colors[draft.selected]);draft.selected=draft.selected+1
  end)
  if reaper.ImGui_BeginMenu(ctx,'Hex / paste palette...') then
    reaper.ImGui_Text(ctx,'2–64 RGB hex colors, separated by spaces or commas')
    reaper.ImGui_SetNextItemWidth(ctx,340)
    local hex_changed,value=reaper.ImGui_InputText(ctx,'##custom_auto_palette',draft.hex)
    if hex_changed then draft.hex=value;error_text=nil end
    if reaper.ImGui_Button(ctx,'Import into preview') then
      local colors,message=auto.parse_custom(draft.hex)
      if colors then seed(colors) else error_text=message end
    end
    if error_text then reaper.ImGui_TextWrapped(ctx,error_text) end
    controls.capture_popup_wheel(ctx)
    reaper.ImGui_EndMenu(ctx)
  end
  reaper.ImGui_Separator(ctx)
  if reaper.ImGui_Button(ctx,'Save and use custom palette') then
    local hex=serialize(draft.colors)
    edit('Set custom track palette',function() auto.set_custom(hex) end)
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx,'Discard edits') then seed(auto.palette(config)) end
  controls.capture_popup_wheel(ctx)
end
M.draw_editor=custom_editor
local approval_project,replace_existing
local function apply_preview(ctx)
  local proj=reaper.EnumProjects(-1,'')
  if approval_project~=proj then
    approval_project=proj
    replace_existing=require('ReaSpect.core.persistence').get('auto_colors_replace_existing','1')=='1'
  end
  local changed,value=reaper.ImGui_Checkbox(ctx,'Recolor imported track colors',replace_existing)
  if changed then replace_existing=value end
  reaper.ImGui_TextWrapped(ctx,replace_existing and 'Recolor imported tracks. Manual overrides stay protected; managed tracks continue following automation.'
    or 'Preserve imported colors. Already-managed tracks keep following automation; new tracks join automatically.')
  local rows=auto.preview(auto.smart_config(),replace_existing)
  local color=require('ReaSpect.widgets.color')
  local colors,icons=0,0
  for _,row in ipairs(rows) do if row.changed then colors=colors+1 end;if row.icon_changed then icons=icons+1 end end
  reaper.ImGui_Text(ctx,colors..' color changes · '..icons..' icon changes')
  if reaper.ImGui_BeginChild(ctx,'##approval_preview',450,240,0,controls.scroll_flags()) then
    for i,row in ipairs(rows) do
      reaper.ImGui_ColorButton(ctx,'##approval_color'..i,color.native_to_rgba(row.color),reaper.ImGui_ColorEditFlags_NoTooltip(),12,12)
      reaper.ImGui_SameLine(ctx)
      require('ReaSpect.widgets.icon_browser').preview_icon(ctx,row.icon,18)
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_Text(ctx,(row.name~='' and row.name or ('Track '..i))..' · '..row.reason)
    end
    controls.popup_scroll_end(ctx);reaper.ImGui_EndChild(ctx)
  end
  item(ctx,'Apply to this project',false,function() auto.apply_project(replace_existing) end)
  controls.capture_popup_wheel(ctx)
end
local function appearance(ctx,config,targets)
  if reaper.ImGui_BeginMenu(ctx,'Palettes') then
    if reaper.ImGui_BeginMenu(ctx,'Role palette') then
      for _,preset in ipairs(auto.role_palettes.presets) do
        local current=auto.role_palettes.find(config.role_palette)
        set(ctx,preset.name,'role_palette',preset.id,current and current.id==preset.id)
      end
      reaper.ImGui_Separator(ctx)
      item(ctx,'Reset role colors',false,auto.reset_role_colors)
      reaper.ImGui_EndMenu(ctx)
    end
    palette_combo(ctx,'Track palette',config.palette,'Custom',function(name,wheel)
      edit('Choose track palette',function()
        auto.set_config('palette',name);auto.set_config('unmatched','separate')
      end,wheel)
    end)
    swatches(ctx,auto.palette(config))
    if reaper.ImGui_MenuItem(ctx,'Edit custom palette...') then M.open_editor('palette') end
    controls.capture_popup_wheel(ctx);reaper.ImGui_EndMenu(ctx)
  end
  local folders={}
  for _,target in ipairs(targets or {}) do
    if reaper.GetMediaTrackInfo_Value(target,'I_FOLDERDEPTH')>0 then folders[#folders+1]=target end
  end
  if #folders>0 and reaper.ImGui_BeginMenu(ctx,'Folder colors') then
    local rule=auto.track_get(folders[1],'children')
    for _,folder in ipairs(folders) do if auto.track_get(folder,'children')~=rule then rule=nil;break end end
    if rule==nil then reaper.ImGui_TextDisabled(ctx,'Mixed') end
    local function apply(value) for _,folder in ipairs(folders) do auto.set_children(folder,value) end end
    item(ctx,'Default',rule=='',function() apply('') end)
    folder_options(ctx,rule,apply)
    folder_scope(ctx,folders)
    reaper.ImGui_EndMenu(ctx)
  end
end
local function setup(ctx,targets)
  local config=auto.config()
  local changed,enabled=reaper.ImGui_Checkbox(ctx,'Auto Color',config.enabled)
  if changed then
    edit('Auto Color',function()
      if enabled then auto.enable_smart() else auto.set_config('enabled','0') end
    end)
  end
  if not auto.project_allowed() then
    if reaper.ImGui_MenuItem(ctx,'Apply to this project...') then M.open_editor('apply') end
  end
  appearance(ctx,config,targets)
end
M.draw_setup=setup
M.draw_apply_preview=apply_preview
function M.open_editor(section) window_open=true;editor_section=section or 'roles' end
function M.close_editor() window_open=false end
function M.folder_control(ctx,track)
  local config=auto.config()
  local raw=auto.track_get(track,'children')
  local rule=folder_choice(raw,config)
  local default=auto.folder_default(track)
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  local clicked=reaper.ImGui_InvisibleButton(ctx,'##folder_colors_'..tostring(track),20,22)
  local hovered=reaper.ImGui_IsItemHovered(ctx)
  local include=auto.track_get(track,'children_scope')=='all'
  if clicked then
    include=not include
    edit('Toggle include subfolders',function() auto.set_children_scope({track},include) end)
  end
  local choices={'','independent','uniform','shades'}
  local wheel=controls.wheel_delta(ctx)
  local value=rule
  if controls.right_click(ctx) then value=''
  elseif wheel~=0 then
    local index=1
    for i,choice in ipairs(choices) do if choice==rule then index=i;break end end
    value=choices[(index-1+(wheel>0 and 1 or -1))%#choices+1]
  end
  local changed=value~=rule
  if changed then undo.edit('Change folder child colors',function() auto.set_children(track,value) end);rule=value end
  if hovered then
    reaper.ImGui_SetTooltip(ctx,'Include subfolders: '..(include and 'On' or 'Off')..' · Click to toggle\n'..(rule=='' and ('Use default — '..(folder_labels[default] or default)) or (folder_labels[rule] or rule))
      )
  end
  local dl=reaper.ImGui_GetWindowDrawList(ctx)
  local tint=hovered and 0xE5D4A6FF or include and 0xE5C46AFF or 0xB8AC8CFF
  reaper.ImGui_DrawList_AddRectFilled(dl,x+2,y+5,x+9,y+9,tint,1)
  reaper.ImGui_DrawList_AddRectFilled(dl,x+2,y+8,x+18,y+18,tint,2)
end
function M.source_control(ctx,track)
  local source=auto.color_source(track)
  if reaper.ImGui_Selectable(ctx,'Color: '..source.label..'##track_color_source',false) then
    reaper.ImGui_OpenPopup(ctx,'##edit_track_color_source')
  end
  if reaper.ImGui_BeginPopup(ctx,'##edit_track_color_source') then
    reaper.ImGui_TextWrapped(ctx,'Color comes from: '..source.label)
    if source.kind=='palette' then
      if reaper.ImGui_Button(ctx,'Edit track palette') then M.open_editor('palette');reaper.ImGui_CloseCurrentPopup(ctx) end
    else
      local value=source.kind=='role' and source.role.color
        or (require('ReaSpect.widgets.color').native_to_rgba(reaper.GetTrackColor(source.track))>>8)
      reaper.ImGui_TextWrapped(ctx,source.kind=='role' and 'Changes this role on all following tracks.'
        or source.kind=='folder' and 'Changes the folder color and its following children.' or 'Changes this track only.')
      local changed,rgb=reaper.ImGui_ColorEdit3(ctx,'Color',value)
      if changed then edit('Edit '..source.label,function()
        if source.kind=='role' then auto.set_role_color(source.role.id,rgb)
        else
          auto.protect(source.track)
          reaper.SetTrackColor(source.track,reaper.ColorToNative((rgb>>16)&255,(rgb>>8)&255,rgb&255)|0x1000000)
          auto.tick(true);reaper.UpdateArrange()
        end
      end) end
    end
    if source.kind=='track' then
      item(ctx,'Resume automatic colors',false,function() auto.set_modes({track},'') end)
    elseif source.kind=='folder' then
      item(ctx,"Use this track's role color",false,function() auto.set_modes({track},'role') end)
    end
    controls.capture_popup_wheel(ctx)
    reaper.ImGui_EndPopup(ctx)
  end
end
function M.draw_window(ctx)
  if results_open then
    reaper.ImGui_SetNextWindowSize(ctx,650,440,reaper.ImGui_Cond_FirstUseEver())
    local visible,open=reaper.ImGui_Begin(ctx,'Auto Color · Results',true)
    results_open=open
    if visible then
      reaper.ImGui_TextDisabled(ctx,'Current colors · all tracks in the active project')
      if not auto.config().enabled then reaper.ImGui_Text(ctx,'Auto Color is off')
      elseif not auto.project_allowed() then
        reaper.ImGui_Text(ctx,'Auto Color is awaiting project approval')
        if reaper.ImGui_Button(ctx,'Apply to this project...') then window_open=true;editor_section='apply' end
      end
      if reaper.ImGui_BeginTable(ctx,'##color_results',3) then
        for _,label in ipairs({'Track','Role','Color source'}) do reaper.ImGui_TableSetupColumn(ctx,label) end
        reaper.ImGui_TableHeadersRow(ctx)
        for i=0,reaper.CountTracks(0)-1 do
          local track=reaper.GetTrack(0,i)
          local _,name=reaper.GetTrackName(track)
          reaper.ImGui_TableNextRow(ctx);reaper.ImGui_TableSetColumnIndex(ctx,0)
          reaper.ImGui_ColorButton(ctx,'##result_'..i,require('ReaSpect.widgets.color').native_to_rgba(reaper.GetTrackColor(track)),reaper.ImGui_ColorEditFlags_NoTooltip(),12,12)
          reaper.ImGui_SameLine(ctx);reaper.ImGui_Text(ctx,name~='' and name or ('Track '..(i+1)))
          local role_label=auto.role_label(track):gsub('^Role: ','')
          reaper.ImGui_TableSetColumnIndex(ctx,1);reaper.ImGui_Text(ctx,role_label)
          reaper.ImGui_TableSetColumnIndex(ctx,2);reaper.ImGui_Text(ctx,auto.color_source(track).label)
        end
        reaper.ImGui_EndTable(ctx)
      end
    end
    reaper.ImGui_End(ctx)
  end
  if not window_open then return end
  local active,filename=reaper.EnumProjects(-1,'')
  local project_key=tostring(active)..'\31'..(filename or '')..'\31'..(reaper.GetProjectGUID and reaper.GetProjectGUID(active) or '')
  if window_project and project_key~=window_project then project_changed=true end
  window_project=project_key
  reaper.ImGui_SetNextWindowSize(ctx,580,650,reaper.ImGui_Cond_FirstUseEver())
  local visible,open=reaper.ImGui_Begin(ctx,'Auto Color · Customize',true)
  window_open=open
  if visible then
    local label=filename
    if not label or label=='' then
      label='Unsaved project'
      for i=0,1023 do local candidate=reaper.EnumProjects(i,'');if not candidate then break end
        if candidate==active then label=label..' (tab '..(i+1)..')';break end
      end
    end
    reaper.ImGui_TextWrapped(ctx,'Project: '..label)
    if project_changed then
      reaper.ImGui_TextWrapped(ctx,'Project changed. Edits now apply to the project shown above.')
      if reaper.ImGui_Button(ctx,'Dismiss project notice') then project_changed=false end
    end
    reaper.ImGui_TextDisabled(ctx,'Preferences are also remembered for future projects.')
    if reaper.ImGui_Selectable(ctx,'Roles##auto_page_roles',editor_section=='roles',0,100,0) then editor_section='roles' end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Selectable(ctx,'Custom unmatched palette##auto_page_palette',editor_section=='palette',0,240,0) then editor_section='palette' end
    reaper.ImGui_Separator(ctx)
    if editor_section=='apply' then apply_preview(ctx)
    elseif editor_section=='palette' then custom_editor(ctx,auto.config())
    else
      local targets={}
      if reaper.CountSelectedTracks and reaper.GetSelectedTrack then
        for i=0,reaper.CountSelectedTracks(0)-1 do targets[#targets+1]=reaper.GetSelectedTrack(0,i) end
      end
      local config=auto.smart_config()
      local current=auto.role_palettes and auto.role_palettes.find(config.role_palette)
      reaper.ImGui_Text(ctx,'Role palette')
      if reaper.ImGui_BeginCombo(ctx,'##customize_role_palette',current and current.name or 'Legacy palette') then
        for _,preset in ipairs(auto.role_palettes.presets) do
          if reaper.ImGui_Selectable(ctx,preset.name,current and current.id==preset.id) then
            edit('Choose role palette',function() auto.set_config('role_palette',preset.id) end)
          end
          reaper.ImGui_SameLine(ctx)
          local colors={}
          for _,group in ipairs({'Drums','Bass','Guitars','Keys','Orchestral','Vocals','Utility'}) do colors[#colors+1]=preset.colors[group] end
          swatches(ctx,colors)
        end
        controls.capture_popup_wheel(ctx);reaper.ImGui_EndCombo(ctx)
      end
      if current then
        local colors={}
        for _,group in ipairs({'Drums','Bass','Guitars','Keys','Orchestral','Vocals','Utility'}) do colors[#colors+1]=current.colors[group] end
        swatches(ctx,colors)
      end
      reaper.ImGui_Separator(ctx)
      require('ReaSpect.widgets.track_roles').draw(ctx)
    end
    reaper.ImGui_End(ctx)
  end
end
function M.menu(ctx,track,on_default,selected_tracks)
  local targets=selected_tracks and #selected_tracks>0 and selected_tracks or {track}
  local function common(key,normalize)
    local first
    for i,target in ipairs(targets) do
      local value=auto.track_get(target,key)
      if normalize then value=normalize(value,target) end
      if i==1 then first=value elseif value~=first then return nil end
    end
    return first
  end
  setup(ctx,targets)
  reaper.ImGui_Separator(ctx)
  local role_id=common('role')
  if reaper.ImGui_BeginMenu(ctx,'Assign role') then
    local targets=selected_tracks and #selected_tracks>0 and selected_tracks or {track}
    local roles,groups,seen=auto.roles(),{},{}
    item(ctx,'Detect from track name',common('role')=='',function() auto.detect_roles(targets) end)
    if reaper.ImGui_MenuItem(ctx,'Edit roles...') then M.open_editor('roles') end
    for _,role in ipairs(roles) do if not seen[role.group] then groups[#groups+1]=role.group;seen[role.group]=true end end
    for _,group in ipairs(groups) do
      local assigned_group=false
      for _,role in ipairs(roles) do if role.group==group and role.id==role_id then assigned_group=true end end
      if reaper.ImGui_BeginMenu(ctx,group..(assigned_group and ' ✓' or '')) then
        for _,role in ipairs(roles) do if role.group==group then
          item(ctx,role.name..'##assign_'..role.id,common('role')==role.id,function() auto.assign_role(targets,role.id) end)
        end end
        controls.capture_popup_wheel(ctx);reaper.ImGui_EndMenu(ctx)
      end
    end
    controls.capture_popup_wheel(ctx)
    reaper.ImGui_EndMenu(ctx)
  end
  local mode=common('mode',function(value,target)
    if value=='auto' then value='' end
    return value
  end)
  if reaper.ImGui_BeginMenu(ctx,'Track color') then
  if mode==nil then reaper.ImGui_TextDisabled(ctx,'Mixed color behaviors') end
  local can_inherit=true
  for _,target in ipairs(targets) do if not reaper.GetParentTrack(target) then can_inherit=false end end
  for _,entry in ipairs({{'Follow automatic colors',''}, {'Keep current color','keep'},
      {'Same color as parent folder','inherit'}, {'Use role color','role'}, {'Use track palette','independent'}}) do
    if entry[2]=='inherit' then reaper.ImGui_BeginDisabled(ctx,not can_inherit) end
    item(ctx,entry[1],mode==entry[2],function()
      local targets=selected_tracks and #selected_tracks>0 and selected_tracks or {track}
      auto.set_modes(targets,entry[2])
    end)
    if entry[2]=='inherit' then reaper.ImGui_EndDisabled(ctx) end
  end
  if reaper.ImGui_MenuItem(ctx,"Reset this track's color to default") then on_default() end
  reaper.ImGui_EndMenu(ctx)
  end
  reaper.ImGui_Separator(ctx)
  if reaper.ImGui_BeginMenu(ctx,'Settings') then
    if reaper.ImGui_BeginMenu(ctx,'Default folder colors') then
      folder_options(ctx,auto.config().children,function(value) auto.set_config('children',value) end)
      reaper.ImGui_EndMenu(ctx)
    end
    local config=auto.config()
    set(ctx,'Role colors','roles',config.roles and '0' or '1',config.roles)
    set(ctx,'Role icons','role_icons',config.role_icons and '0' or '1',config.role_icons)
    if reaper.ImGui_MenuItem(ctx,'Color results...') then results_open=true end
    item(ctx,'Reset color rules',false,auto.use_name_defaults)
    if reaper.ImGui_BeginMenu(ctx,'Restore original colors...') then
      item(ctx,'Restore originals',false,auto.restore)
      reaper.ImGui_EndMenu(ctx)
    end
    reaper.ImGui_EndMenu(ctx)
  end
  controls.capture_popup_wheel(ctx)
end
return M
