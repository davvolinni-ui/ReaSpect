local M = {}

local SECTION = 'ReaSpect'
local ENCODED = '@ReaSpectText1:'

function M.get(key, default)
  local v = reaper.GetExtState(SECTION, key)
  if v == nil or v == '' then return default end
  if v:sub(1,#ENCODED)==ENCODED then
    return (v:sub(#ENCODED+1):gsub('%%(%x%x)',function(hex) return string.char(tonumber(hex,16)) end))
  end
  return v
end

function M.get_bool(key, default)
  local v = M.get(key, nil)
  if v == nil then return default end
  return v == '1' or v == 'true'
end

function M.get_num(key, default)
  local n = tonumber(M.get(key, nil))
  return n or default
end

function M.set(key, value)
  value=tostring(value)
  -- Persisted ExtState is INI-backed: raw line breaks are truncated on reload.
  if value:find('[\r\n]') or value:sub(1,#ENCODED)==ENCODED then
    value=ENCODED..value:gsub('%%','%%25'):gsub('\r','%%0D'):gsub('\n','%%0A')
  end
  reaper.SetExtState(SECTION, key, value, true)
end

function M.set_bool(key, value) M.set(key, value and '1' or '0') end

return M
