local auto=require('ReaSpect.core.auto_colors')
local controls=require('ReaSpect.widgets.controls')
local undo=require('ReaSpect.core.undo')
local color=require('ReaSpect.widgets.color')
local icons=require('ReaSpect.core.role_icons')
local M={}
local draft,project,preview,revision
local project_key
local inspect_open,result_revision
local custom_sequence=0
local function current_project() return reaper.EnumProjects(-1,'') end
local function current_project_key()
  local proj,path=reaper.EnumProjects(-1,'')
  return tostring(proj)..'\31'..(path or '')..'\31'..(reaper.GetProjectGUID and reaper.GetProjectGUID(proj) or '')
end
local function config_revision()
  local config=auto.config()
  return table.concat({tostring(config.roles_data),tostring(config.roles),tostring(config.role_icons),tostring(config.role_palette),tostring(config.palette),tostring(config.custom),tostring(config.family_gradients),tostring(config.family_bases),tostring(config.role_behaviors),tostring(config.role_children),tostring(config.unmatched)},'\31')
end
local function details_signature()
  local values={}
  for _,r in ipairs(draft.roles) do values[#values+1]=table.concat({r.id,tostring(r.enabled),r.name,r.group,r.keywords,r.icon or ''},'\31') end
  return table.concat(values,'\30')
end
local function save_details()
  undo.wheel_source(false)
  undo.edit('Edit track roles',function() auto.save_roles(draft.roles,draft.enabled,draft.icons) end)
  revision=config_revision();preview=nil
end
local function reset()
  local config=auto.smart_config()
  if project_key~=current_project_key() then inspect_open=false end
  project=current_project()
  project_key=current_project_key()
  draft={roles=auto.roles(config),enabled=config.roles,icons=config.role_icons}
  revision=config_revision()
  preview=nil
end
local function browse(ctx,role)
  local captured=draft
  local captured_project=project_key
  require('ReaSpect.widgets.icon_browser').open_picker(ctx,{
    current=icons.resolve(role),
    is_valid=function() return captured==draft and captured_project==current_project_key() end,
    on_pick=function(path) role.icon=path;save_details() end,
  })
end
local function config_for_preview()
  local config=auto.config()
  config.roles=draft.enabled;config.role_icons=draft.icons
  config.roles_data=auto.roles_model.encode(draft.roles)
  return config
end
local function refresh_group(group)
  for _,saved in ipairs(auto.roles()) do
    for _,r in ipairs(draft.roles) do
      if r.group==group and r.id==saved.id then r.color=saved.color;r.color_custom=saved.color_custom end
    end
  end
end
-- Keep unsaved drafts through popup dismissal/native file dialogs. They are
-- discarded explicitly or when the user switches projects.
function M.close() preview=nil end
function M.draw(ctx)
  if not draft or project_key~=current_project_key() or revision~=config_revision() then reset() end
  local before_details=details_signature()
  reaper.ImGui_Text(ctx,'Track Roles')
  reaper.ImGui_TextDisabled(ctx,'All edits save automatically. Use REAPER Undo to revert changes.')
  reaper.ImGui_TextWrapped(ctx,'In an enabled, approved project, editing a role or family color also resumes matching tracks preserved only as imported colors. Deliberate manual track colors stay protected; folder treatment still applies.')
  if not auto.project_allowed() then
    reaper.ImGui_TextWrapped(ctx,'Colors are saved for the roles, but this existing project stays unchanged until Preview and apply.')
    if reaper.ImGui_Button(ctx,'Apply to this project...') then require('ReaSpect.widgets.auto_colors').open_editor('apply') end
  elseif not auto.config().enabled then
    reaper.ImGui_TextWrapped(ctx,'Auto Color is off. Colors are saved; enable Auto Color to update tracks.')
  end
  reaper.ImGui_TextDisabled(ctx,'Name colors and automatic icons are enabled in Auto Track Colors.')
  local changed,value
  reaper.ImGui_TextDisabled(ctx,'Only checked categories participate in name detection.')
  if reaper.ImGui_Button(ctx,'Enable common') then
    local defaults=auto.roles_model.defaults()
    for _,r in ipairs(draft.roles) do local d=auto.roles_model.by_id(defaults,r.id);r.enabled=d and d.enabled or false end;preview=nil
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx,'Enable all') then for _,r in ipairs(draft.roles) do r.enabled=true end;preview=nil end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx,'Disable all') then for _,r in ipairs(draft.roles) do r.enabled=false end;preview=nil end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx,'Add role') then
    custom_sequence=custom_sequence+1
    local index=os.time()*100000+custom_sequence
    while auto.roles_model.by_id(draft.roles,'custom_'..index) do index=index+1 end
    local role={id='custom_'..index,name='Custom role',group='Custom',keywords='',
      color=0,color_custom=false,enabled=true,priority=0,icon=''}
    role.color=auto.role_palette_color(auto.config(),role)
    draft.roles[#draft.roles+1]=role
    preview=nil
  end
  local removed
  if reaper.ImGui_Button(ctx,'Reset all to role palette') then
    local palette=auto.palette(auto.config())
    for _,r in ipairs(draft.roles) do r.color=auto.role_palette_color(auto.config(),r);r.color_custom=false end
    undo.wheel_source(false);undo.edit('Use current palette for all roles',auto.reset_role_colors)
    preview=nil
  end
  if reaper.ImGui_BeginChild(ctx,'##track_roles_categories',500,350,0,controls.scroll_flags()) then
    local last_group,group_open
    for _,r in ipairs(draft.roles) do
      if last_group~=r.group then
        if group_open then reaper.ImGui_TreePop(ctx) end
        last_group=r.group
        local count,enabled,mixed=0,0,false
        for _,member in ipairs(draft.roles) do
          if member.group==r.group then count=count+1;if member.enabled then enabled=enabled+1 end;if member.color~=r.color then mixed=true end end
        end
        local group_changed,group_color=reaper.ImGui_ColorEdit3(ctx,'##family_color_'..r.group,auto.family_color and auto.family_color(r.group) or r.color,reaper.ImGui_ColorEditFlags_NoInputs())
        if group_changed then
          group_color=group_color&0xFFFFFF
          preview=nil;mixed=false
        end
        undo.gesture(ctx,'family_color_'..r.group,'Change '..r.group..' family color',group_changed,function()
          auto.set_role_group_color(r.group,group_color)
          refresh_group(r.group)
        end)
        reaper.ImGui_SameLine(ctx)
        local gradient_changed,gradient=reaper.ImGui_Checkbox(ctx,'Subrole shades##family_'..r.group,auto.group_gradient(r.group))
        if gradient_changed then
          undo.wheel_source(false)
          undo.edit('Set '..r.group..' gradient',function() auto.set_group_gradient(r.group,gradient) end)
          refresh_group(r.group);preview=nil
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx,'Reset##family_'..r.group) then
          undo.wheel_source(false)
          undo.edit('Reset '..r.group..' role colors',function() auto.reset_role_group(r.group) end)
          refresh_group(r.group);preview=nil
        end
        reaper.ImGui_SameLine(ctx)
        group_open=reaper.ImGui_TreeNode(ctx,r.group..' ('..enabled..'/'..count..')'..'###family_'..r.group)
      end
      if group_open then
      changed,value=reaper.ImGui_Checkbox(ctx,'##enable_role_'..r.id,r.enabled)
      if changed then r.enabled=value;preview=nil end
      reaper.ImGui_SameLine(ctx)
      require('ReaSpect.widgets.icon_browser').preview_icon(ctx,icons.resolve(r),20)
      reaper.ImGui_SameLine(ctx)
      local flags=reaper.ImGui_ColorEditFlags_NoInputs()
      changed,value=reaper.ImGui_ColorEdit3(ctx,r.name..'##role_color_'..r.id,r.color,flags)
      if changed then r.color=value&0xFFFFFF;r.color_custom=true;preview=nil end
      undo.gesture(ctx,'role_color_'..r.id,'Change '..r.name..' role color',changed,function()
        auto.set_role_color(r.id,r.color)
      end)
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_BeginMenu(ctx,'Details##role_'..r.id) then
        reaper.ImGui_TextDisabled(ctx,r.color_custom and 'Custom color override' or 'Following family palette')
        reaper.ImGui_SetNextItemWidth(ctx,380)
        changed,value=reaper.ImGui_InputText(ctx,'Name##'..r.id,r.name)
        if changed and value~='' then r.name=value;preview=nil end
        if reaper.ImGui_Button(ctx,'Reset to role palette##'..r.id) then
          r.color=auto.role_palette_color(auto.config(),r);r.color_custom=false;preview=nil
          undo.wheel_source(false)
          undo.edit('Use palette color for '..r.name,function() auto.set_role_color(r.id,r.color,true) end)
        end
        reaper.ImGui_Text(ctx,'Match whole words or phrases, separated by commas')
        reaper.ImGui_SetNextItemWidth(ctx,380)
        changed,value=reaper.ImGui_InputText(ctx,'Keywords##'..r.id,r.keywords)
        if changed then r.keywords=value;preview=nil end
        reaper.ImGui_Text(ctx,'Icon: '..(r.icon=='@auto' and 'Automatic from REAPER library' or (r.icon=='' and 'None' or (r.icon:match('[^/\\]+$') or r.icon))))
        if reaper.ImGui_Button(ctx,'Choose icon...##'..r.id) then browse(ctx,r) end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx,'Automatic##'..r.id) then r.icon='@auto';preview=nil end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx,'None##'..r.id) then r.icon='';preview=nil end
        require('ReaSpect.widgets.icon_browser').draw_picker(ctx)
        if r.id:match('^custom_') and reaper.ImGui_Button(ctx,'Remove role##'..r.id) then removed=r.id;preview=nil end
        controls.capture_popup_wheel(ctx)
        reaper.ImGui_EndMenu(ctx)
      end
      end
    end
    if group_open then reaper.ImGui_TreePop(ctx) end
    controls.popup_scroll_end(ctx)
    reaper.ImGui_EndChild(ctx)
  end
  if removed then for i,r in ipairs(draft.roles) do if r.id==removed then table.remove(draft.roles,i);break end end end
  if details_signature()~=before_details then save_details() end
  if reaper.ImGui_Button(ctx,'Inspect track color results') then inspect_open=not inspect_open;preview=nil end
  if inspect_open then
    local key=config_revision()..':'..tostring(reaper.GetProjectStateChangeCount(project))
    if not preview or key~=result_revision then preview=auto.preview(config_for_preview());result_revision=key end
  end
  reaper.ImGui_TextDisabled(ctx,'Preferences are remembered automatically for future projects.')
  reaper.ImGui_TextDisabled(ctx,'Manual colors and icons stay protected. Explicit track overrides win.')
  if inspect_open and preview and reaper.ImGui_BeginChild(ctx,'##role_preview',500,160,0,controls.scroll_flags()) then
    local changes=0;for _,row in ipairs(preview) do if row.changed then changes=changes+1 end end
    local active=auto.config().enabled and auto.project_allowed()
    reaper.ImGui_Text(ctx,changes..(active and ' differences from current track colors · live results' or ' potential color changes · automation paused'))
    for i,row in ipairs(preview) do
      reaper.ImGui_ColorButton(ctx,'##role_preview_'..i,color.native_to_rgba(row.color),reaper.ImGui_ColorEditFlags_NoTooltip(),12,12)
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_Text(ctx,(row.name~='' and row.name or ('Track '..i))..' · '..row.reason)
    end
    controls.popup_scroll_end(ctx);reaper.ImGui_EndChild(ctx)
  end
  controls.capture_popup_wheel(ctx)
end
return M
