local actions=require('ReaSpect.core.track_actions')
local controls=require('ReaSpect.widgets.controls')
local theme=require('ReaSpect.core.theme')
local M={}
local POPUP='##track_icon_browser'
local catalog,request
local images,owners={},{}
local MAX_FILES,MAX_DIRECTORIES,MAX_DEPTH=4096,256,6

local function normalize(path) return ((path or ''):gsub('\\','/'):gsub('/+$','')) end
local function root_path()
  return reaper.GetResourcePath and normalize(reaper.GetResourcePath())..'/Data/track_icons' or nil
end

local function leaf(name)
  return type(name)=='string' and name~='' and name~='.' and name~='..' and not name:find('[/\\]')
end

local function scan(root)
  local result={root=root,entries={},limited=false}
  if not root or not (reaper.EnumerateFiles and reaper.EnumerateSubdirectories) then return result end
  local folders={{path=root,relative='',depth=0}}
  local cursor,examined=1,0
  while cursor<=#folders and examined<MAX_FILES*4 and #result.entries<MAX_FILES do
    local folder=folders[cursor];cursor=cursor+1
    reaper.EnumerateFiles(folder.path,-1)
    for index=0,MAX_FILES*4-1 do
      local name=reaper.EnumerateFiles(folder.path,index)
      if not name then break end
      examined=examined+1
      local extension=name:lower():match('%.([^.]+)$')
      if leaf(name) and (extension=='png' or extension=='jpg' or extension=='jpeg') then
        local relative=folder.relative..name
        result.entries[#result.entries+1]={path=folder.path..'/'..name,name=name,relative=relative,search=relative:lower()}
      end
      if examined>=MAX_FILES*4 or #result.entries>=MAX_FILES then result.limited=true;break end
    end
    reaper.EnumerateSubdirectories(folder.path,-1)
    for index=0,MAX_DIRECTORIES do
      local name=reaper.EnumerateSubdirectories(folder.path,index)
      if not name then break end
      if leaf(name) then
        if #folders>=MAX_DIRECTORIES or folder.depth>=MAX_DEPTH then result.limited=true;break end
        folders[#folders+1]={path=folder.path..'/'..name,relative=folder.relative..name..'/',depth=folder.depth+1}
      end
    end
  end
  if cursor<=#folders then result.limited=true end
  table.sort(result.entries,function(a,b) return a.search<b.search end)
  return result
end

local function current_project() return reaper.EnumProjects and reaper.EnumProjects(-1,'') end
local function identity(track) return reaper.GetTrackGUID and reaper.GetTrackGUID(track) or tostring(track) end
local function valid(track)
  return request and request.track==track and current_project()==request.project
    and reaper.ValidatePtr2 and reaper.ValidatePtr2(request.project,track,'MediaTrack*')
    and identity(track)==request.guid
end

local function safe_images()
  return reaper.ImGui_CreateImage and reaper.ImGui_ImageFlags_NoErrors and reaper.ImGui_ValidatePtr
    and reaper.ImGui_Image_GetSize and reaper.ImGui_DrawList_AddImage
end

local function thumbnail(path)
  if not safe_images() then return end
  local entry=images[path]
  if not entry then entry={};images[path]=entry end
  if entry.failed then return end
  if not entry.image or not reaper.ImGui_ValidatePtr(entry.image,'ImGui_Image*') then
    if entry.image then owners[entry.image]=nil end
    entry.image=reaper.ImGui_CreateImage(path,reaper.ImGui_ImageFlags_NoErrors())
    if not entry.image then entry.failed=true;return end
    if owners[entry.image] and owners[entry.image]~=entry then owners[entry.image].image=nil end
    owners[entry.image]=entry
  end
  local width,height=reaper.ImGui_Image_GetSize(entry.image)
  if width<=0 or height<=0 then entry.failed=true;return end
  return entry.image,width,height
end

local function fit(ctx,text,width)
  if reaper.ImGui_CalcTextSize(ctx,text)<=width then return text end
  while #text>0 and reaper.ImGui_CalcTextSize(ctx,text..'…')>width do
    local last=utf8.offset(text,-1)
    text=text:sub(1,(last or #text)-1)
  end
  return text..'…'
end

local function tooltip(ctx,text)
  if reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx,text) end
end

local function queue(ctx,name,path)
  if not valid(request and request.track) then return false end
  if actions.queue(name,{request.track},path) then
    reaper.ImGui_CloseCurrentPopup(ctx)
    return true
  end
  return false
end

function M.open(ctx,track)
  local project=current_project()
  if not project or not track or not reaper.ValidatePtr2 or not reaper.ValidatePtr2(project,track,'MediaTrack*')
    or (reaper.GetMasterTrack and track==reaper.GetMasterTrack(project)) then return false end
  request={ctx=ctx,track=track,project=project,guid=identity(track),search='',focus=true,reset_scroll=true}
  reaper.ImGui_OpenPopup(ctx,POPUP)
  return true
end

local function draw_tile(ctx,entry,width,height,selected)
  local x,y=reaper.ImGui_GetCursorScreenPos(ctx)
  local hit=reaper.ImGui_InvisibleButton(ctx,'##icon_'..entry.relative,width,height)
  local hovered=reaper.ImGui_IsItemHovered(ctx)
  local visible=not reaper.ImGui_IsItemVisible or reaper.ImGui_IsItemVisible(ctx)
  if visible then
    local dl=reaper.ImGui_GetWindowDrawList(ctx)
    local colors=theme.colors
    local background=selected and colors.accent or (hovered and colors.border or colors.frame)
    local ink,outline=colors.text,colors.border
    if theme.tile_colors then background,ink,outline=theme.tile_colors(selected,hovered) end
    reaper.ImGui_DrawList_AddRectFilled(dl,x,y,x+width,y+height,background or 0x30343AFF,4)
    if reaper.ImGui_DrawList_AddRect and (selected or hovered) then
      reaper.ImGui_DrawList_AddRect(dl,x+1,y+1,x+width-1,y+height-1,outline or 0xC6A4F3FF,4,0,selected and 2 or 1)
    end
    local image,iw,ih=thumbnail(entry.path)
    local image_height=height-25
    if image then
      local scale=math.min((width-12)/iw,(image_height-8)/ih)
      local left,top=x+(width-iw*scale)/2,y+4+(image_height-8-ih*scale)/2
      reaper.ImGui_DrawList_AddImage(dl,image,left,top,left+iw*scale,top+ih*scale)
    else
      local label='No preview'
      local tw=reaper.ImGui_CalcTextSize(ctx,label)
      reaper.ImGui_DrawList_AddText(dl,x+(width-tw)/2,y+image_height/2-7,ink or 0xFFFFFFFF,label)
    end
    local label=fit(ctx,entry.name:gsub('%.[^.]+$',''),width-10)
    local tw=reaper.ImGui_CalcTextSize(ctx,label)
    reaper.ImGui_DrawList_AddText(dl,x+(width-tw)/2,y+height-20,ink or 0xFFFFFFFF,label)
  end
  tooltip(ctx,entry.relative..(selected and '\nCurrent track icon' or '\nClick to use this icon'))
  -- A thumbnail is a browsing target: its wheel scrolls the grid and never
  -- assigns an icon. Assignment is only an explicit click.
  return hit and queue(ctx,'icon_set',entry.path)
end

function M.draw(ctx,track)
  if not request or request.ctx~=ctx then return end
  -- BeginPopup normally auto-sizes. An unconditional size prevents fill-width
  -- controls and a remaining-height grid from shrinking that popup each frame.
  reaper.ImGui_SetNextWindowSize(ctx,340,360)
  local flags=controls.scroll_flags(reaper.ImGui_WindowFlags_NoScrollbar())
  if not reaper.ImGui_BeginPopup(ctx,POPUP,flags) then request=nil;return end
  if not valid(track) then
    reaper.ImGui_CloseCurrentPopup(ctx)
    reaper.ImGui_EndPopup(ctx)
    request=nil
    return
  end
  local root=root_path()
  if not catalog or catalog.root~=root then catalog=scan(root) end
  if request.focus then reaper.ImGui_SetKeyboardFocusHere(ctx);request.focus=false end
  reaper.ImGui_SetNextItemWidth(ctx,-1)
  local changed,text=reaper.ImGui_InputTextWithHint(ctx,'##icon_search','Search track icons',request.search)
  controls.wheel_delta(ctx)
  if changed then request.search=text;request.reset_scroll=true end
  local closed=false
  if reaper.ImGui_Button(ctx,'None##icon_none') then closed=queue(ctx,'icon_remove') end
  tooltip(ctx,'Remove the focused track\'s custom icon.')
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx,'Browse files...##icon_browse') then closed=queue(ctx,'icon_choose') or closed end
  tooltip(ctx,'Open REAPER\'s icon browser for files outside this library.')
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx,'Reload##icon_reload') then
    catalog=scan(root);images,owners={},{};request.reset_scroll=true
  end
  if not closed then
    if not safe_images() then
      reaper.ImGui_TextWrapped(ctx,'Thumbnail previews need a newer ReaImGui. Use Browse files... to choose an icon.')
    elseif #catalog.entries==0 then
      reaper.ImGui_TextWrapped(ctx,'No PNG or JPEG icons found in REAPER\'s track icon folder. Use Browse files... to choose a file.')
    else
      local needle=request.search:lower()
      local matches={}
      for _,entry in ipairs(catalog.entries) do
        if needle=='' or entry.search:find(needle,1,true) then matches[#matches+1]=entry end
      end
      reaper.ImGui_TextDisabled(ctx,#matches..' icon'..(#matches==1 and '' or 's')..(catalog.limited and ' · library limit reached' or ''))
      local _,height=reaper.ImGui_GetContentRegionAvail(ctx)
      if height>0 and reaper.ImGui_BeginChild(ctx,'##icon_grid',-1,height,0,controls.scroll_flags()) then
        if request.reset_scroll then reaper.ImGui_SetScrollY(ctx,0);request.reset_scroll=false end
        local width=reaper.ImGui_GetContentRegionAvail(ctx)
        local columns=math.max(1,math.floor((width+4)/92))
        local tile_width=(width-(columns-1)*4)/columns
        local assigned=''
        if reaper.GetSetMediaTrackInfo_String then
          local ok,path=reaper.GetSetMediaTrackInfo_String(track,'P_ICON','',false)
          if ok then assigned=normalize(path) end
        end
        for index,entry in ipairs(matches) do
          if (index-1)%columns~=0 then reaper.ImGui_SameLine(ctx,0,4) end
          if draw_tile(ctx,entry,tile_width,82,assigned==entry.path or assigned==entry.relative) then closed=true;break end
        end
        if #matches==0 then reaper.ImGui_TextDisabled(ctx,'No matching icons') end
        controls.scroll_end(ctx)
        reaper.ImGui_EndChild(ctx)
      end
    end
    controls.scroll_end(ctx)
  end
  reaper.ImGui_EndPopup(ctx)
  if closed then request=nil end
end

return M
