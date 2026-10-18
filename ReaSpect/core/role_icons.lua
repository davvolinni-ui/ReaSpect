-- Resolve only files actually installed in REAPER's track-icon library.
local M={}
local cached_root,catalog
local candidates={
  drums={'drums','drumbox','beats'},kick={'kick'},snare={'snare_top','snare_bottom'},toms={'tom'},
  hats={'hihat'},cymbals={'cymbal_large','cymbal_small','ride_bell'},overheads={'overheads'},room={'room_medium','room_small'},
  percussion={'congas','bongos','tamborine','maracas'},bass={'bass','bass_full'},synth_bass={'synthbass','bass'},sub={'synthbass','beats'},
  electric={'guitar','guitar_full'},acoustic={'ac_guitar','ac_guitar_full'},lead_guitar={'guitar2','guitar'},
  keys={'synth','piano'},piano={'piano'},ep={'piano','synth'},organ={'organ'},synth={'synth','synth2'},pads={'pads','synth2'},
  strings={'violin','cello'},brass={'trumpet','trombone'},woodwinds={'sax','harmonica'},
  lead_vocal={'mic_condenser_1','mic','mic_dynamic_1'},backing={'mic_dynamic_1','mic'},doubles={'mic_dynamic_2','mic'},
  harmonies={'mic_condenser_2','mic'},adlibs={'mic_dynamic_2','mic'},choir={'mic','speech'},
  returns={'reverb','fx'},fx={'fx'},buses={'mixer','group','folder'},reference={'phones','tape'},
}
function M.root()
  return reaper.GetResourcePath and reaper.GetResourcePath():gsub('\\','/')..'/Data/track_icons' or nil
end
local function scan(root)
  local files={}
  if not root or not reaper.EnumerateFiles or not reaper.EnumerateSubdirectories then return files end
  local folders={{path=root,depth=0}};local index,count,examined=1,0,0
  while index<=#folders and index<=256 and count<4096 and examined<16384 do
    local folder=folders[index];index=index+1
    reaper.EnumerateFiles(folder.path,-1)
    for i=0,4095 do
      local name=reaper.EnumerateFiles(folder.path,i);if not name then break end
      examined=examined+1
      if not name:find('[/\\]') and (name:lower():match('%.png$') or name:lower():match('%.jpe?g$')) then
        local key=name:lower():gsub('%.[^.]+$','')
        if not files[key] then files[key]=folder.path..'/'..name end
        count=count+1
      end
      if count>=4096 or examined>=16384 then break end
    end
    if folder.depth<6 then
      reaper.EnumerateSubdirectories(folder.path,-1)
      for i=0,255 do
        local name=reaper.EnumerateSubdirectories(folder.path,i);if not name then break end
        if #folders<256 and name~='.' and name~='..' and not name:find('[/\\]') then folders[#folders+1]={path=folder.path..'/'..name,depth=folder.depth+1} end
      end
    end
  end
  return files
end
function M.resolve(role)
  if not role or role.icon=='' then return '' end
  if role.icon~='@auto' then return role.icon end
  local root=M.root()
  if root~=cached_root or not catalog then cached_root=root;catalog=scan(root) end
  for _,name in ipairs(candidates[role.id] or {}) do if catalog[name] then return catalog[name] end end
  return ''
end
function M.reload() catalog=nil end
return M
