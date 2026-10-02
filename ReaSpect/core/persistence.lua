local M = {}

local SECTION = 'ReaSpect'

function M.get(key, default)
  local v = reaper.GetExtState(SECTION, key)
  if v == nil or v == '' then return default end
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
  reaper.SetExtState(SECTION, key, tostring(value), true)
end

function M.set_bool(key, value) M.set(key, value and '1' or '0') end

return M
