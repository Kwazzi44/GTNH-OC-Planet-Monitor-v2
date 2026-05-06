-- =============================================================================
-- hub/machines.lua — Direct Component Access: Status & Restart
-- =============================================================================

local component = require("component")
local os        = require("os")

local machines = {}

-- ─── GT методы для чтения статуса ────────────────────────────────────────

local STATUS_METHODS = { "isMachineActive", "isActive" }

local function readActive(proxy)
  for _, m in ipairs(STATUS_METHODS) do
    if type(proxy[m]) == "function" then
      local ok, val = pcall(proxy[m])
      if ok and type(val) == "boolean" then return val end
    end
  end
  return nil
end

-- ─── Redstone helpers ─────────────────────────────────────────────────────

local function rsProxy(rs_addr)
  if not rs_addr then return nil end
  local ok, p = pcall(component.proxy, rs_addr)
  return (ok and p) or nil
end

local function rsHigh(rs, side, color)
  if color then
    pcall(function()
      local out = rs.getBundledOutput(side)
      out[color] = 15
      rs.setBundledOutput(side, out)
    end)
  else
    pcall(rs.setOutput, side, 15)
  end
end

local function rsLow(rs, side, color)
  if color then
    pcall(function()
      local out = rs.getBundledOutput(side)
      out[color] = 0
      rs.setBundledOutput(side, out)
    end)
  else
    pcall(rs.setOutput, side, 0)
  end
end

-- ─── Публичный API ────────────────────────────────────────────────────────

--- Сканировать все gt_machine компоненты в сети
-- Возвращает список { addr, name, active }
function machines.scanNetwork()
  local GT_NAME_METHODS = { "getMachineName", "getName", "getBlockName" }
  local result = {}
  for addr, compType in component.list("gt_machine") do
    local ok, proxy = pcall(component.proxy, addr)
    local name = "Unknown"
    if ok and proxy then
      for _, m in ipairs(GT_NAME_METHODS) do
        if type(proxy[m]) == "function" then
          local ok2, n = pcall(proxy[m])
          if ok2 and type(n) == "string" and #n > 0 then
            name = n; break
          end
        end
      end
    end
    local active = (ok and proxy) and readActive(proxy) or false
    table.insert(result, { addr = addr, name = name, active = active or false })
  end
  table.sort(result, function(a, b) return a.name < b.name end)
  return result
end

--- Сканировать все redstone компоненты в сети
function machines.scanRedstone()
  local result = {}
  for addr, _ in component.list("redstone") do
    table.insert(result, addr)
  end
  return result
end

--- Обновить статус одной машины
-- @param m  table  Запись машины из registry (содержит adapter_addr)
-- @return active bool, err string?
function machines.getStatus(m)
  local ok, proxy = pcall(component.proxy, m.adapter_addr)
  if not ok or not proxy then
    return false, "Adapter not found (Ring Down?)"
  end
  local active = readActive(proxy)
  if active == nil then
    return false, "Cannot read status"
  end
  return active, nil
end

--- Перезапустить машину через Redstone
-- @param m  table  Запись машины из registry (содержит rs_addr, rs_side и т.д.)
-- @return ok bool, msg string
function machines.restart(m)
  if not m.rs_addr or m.rs_side == nil then
    return false, "No redstone configured for this machine"
  end
  local rs = rsProxy(m.rs_addr)
  if not rs then
    return false, "Redstone component not found: " .. tostring(m.rs_addr)
  end

  local side  = m.rs_side
  local color = m.rs_color
  local mode  = m.rs_mode  or "pulse"
  local pulse = m.rs_pulse or 0.5

  if mode == "pulse" then
    rsHigh(rs, side, color)
    os.sleep(pulse)
    rsLow(rs, side, color)
    return true, string.format("Pulse sent (side=%d, %.1fs)", side, pulse)

  elseif mode == "enable" then
    rsHigh(rs, side, color)
    return true, string.format("RS HIGH set (side=%d)", side)

  elseif mode == "toggle" then
    rsLow(rs, side, color)
    os.sleep(0.1)
    rsHigh(rs, side, color)
    os.sleep(pulse)
    rsLow(rs, side, color)
    return true, string.format("Toggle sent (side=%d)", side)

  else
    return false, "Unknown mode: " .. tostring(mode)
  end
end

--- Сбросить все редстоун-выходы по всем планетам реестра (при старте)
function machines.resetAllRedstone(planet_list)
  local done = {}
  for _, p in ipairs(planet_list) do
    for _, m in ipairs(p.machines or {}) do
      if m.rs_addr and m.rs_side ~= nil then
        local key = m.rs_addr .. ":" .. m.rs_side .. ":" .. tostring(m.rs_color)
        if not done[key] then
          done[key] = true
          local rs = rsProxy(m.rs_addr)
          if rs then rsLow(rs, m.rs_side, m.rs_color) end
        end
      end
    end
  end
end

return machines
