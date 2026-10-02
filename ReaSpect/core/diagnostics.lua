-- Sparse, read-only diagnostics for native action / main-window lockups.
local M={}
local LIMIT,KEEP=64*1024,32*1024
local path,watch,last_poll,last_state

local function clean(value,limit)
  local kind=type(value)
  if kind~='string' and kind~='number' and kind~='boolean' then value=kind=='nil' and '' or '<'..kind..'>' end
  return (tostring(value):sub(1,limit):gsub('[%c]',' '))
end

local function call(fn,...)
  if type(fn)~='function' then return end
  local ok,value=pcall(fn,...)
  if ok then return value end
end

local function clock()
  local value=call(reaper and reaper.time_precise)
  if type(value)=='number' and value==value and value~=math.huge and value~=-math.huge then return value end
  return os.time()
end

local function append(line)
  local file
  local ok=pcall(function()
    file=assert(io.open(path,'a+b'))
    local size=assert(file:seek('end'))
    if size+#line>LIMIT then
      assert(file:seek('set',math.max(0,size-KEEP)))
      local tail=assert(file:read(KEEP))
      if size>KEEP then tail=tail:match('\n(.*)') or '' end
      assert(file:close());file=nil
      file=assert(io.open(path,'wb'))
      assert(file:write('--- older diagnostics trimmed ---\n',tail,line))
    else
      assert(file:write(line))
    end
  end)
  local closed=true
  if file then
    local success,result=pcall(file.close,file)
    closed=success and result~=nil and result~=false
  end
  -- Do not keep retrying an unwritable log from native action callbacks.
  if not ok or not closed then path=nil;watch=false end
end

function M.event(name,detail)
  if not path then return end
  local ok=pcall(function()
    local stamp=os.date('!%Y-%m-%dT%H:%M:%SZ')
    append(string.format('%s t=%.3f %s %s\n',stamp,clock(),clean(name,80),clean(detail,640)))
  end)
  if not ok then path=nil;watch=false end
end

function M.configure(filename)
  path=type(filename)=='string' and filename~='' and filename or nil
  watch,last_poll,last_state=false,nil,nil
  if not path then return end
  local api=reaper or {}
  local os_name=call(api.GetOS) or 'unknown'
  local missing={}
  for _,name in ipairs({'GetMainHwnd','JS_Window_IsWindow','JS_Window_GetLong'}) do
    if type(api[name])~='function' then missing[#missing+1]=name end
  end
  watch=type(os_name)=='string' and os_name:match('^Win')~=nil and #missing==0
  M.event('session_begin','reaper='..clean(call(api.GetAppVersion) or 'unknown',80)..' os='..clean(os_name,40))
  if watch then
    M.event('window_observer','JS_Window_GetLong STYLE / WS_DISABLED')
  else
    M.event('window_observer_unavailable',#missing>0 and ('missing='..table.concat(missing,',')) or 'Windows STYLE observation only')
  end
end

local function window_state()
  local hwnd=call(reaper.GetMainHwnd)
  if not hwnd or not call(reaper.JS_Window_IsWindow,hwnd) then return 'unknown' end
  -- JS documents GetLong as the numeric form of GetLongPtr, including STYLE:
  -- https://github.com/juliansader/js_ReaScriptAPI/blob/master/js_ReaScriptAPI_def.h
  -- Windows defines WS_DISABLED=0x08000000; no enable/focus APIs are called:
  -- https://learn.microsoft.com/en-us/windows/win32/winmsg/window-styles
  local style=call(reaper.JS_Window_GetLong,hwnd,'STYLE')
  style=type(style)=='number' and math.tointeger(style) or nil
  -- GetLong returns zero on failure; do not mistake a failed read for enabled.
  if not style or style==0 then return 'unknown' end
  return (style&0x08000000)==0 and 'enabled' or 'disabled'
end

function M.poll()
  if not path or not watch then return end
  local ok=pcall(function()
    local now=clock()
    if last_poll and now-last_poll<1 then return end
    last_poll=now
    local state=window_state()
    if state~=last_state then
      M.event('main_window',last_state and (last_state..' -> '..state) or state)
      last_state=state
    end
  end)
  if not ok then watch=false;M.event('window_observer_unavailable','state read failed') end
end

return M
