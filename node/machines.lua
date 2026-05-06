-- =============================================================================
-- node/machines.lua — Machine Discovery (GT Adapter) & Restart (Redstone)
-- =============================================================================

local component = require("component")
local os        = require("os")

local machines = {}

-- ─── Типы компонентов, которые точно НЕ являются GT-машинами ─────────────

local IGNORED_TYPES = {
  computer       = true,
  screen         = true,
  gpu            = true,
  modem          = true,
  keyboard       = true,
  filesystem     = true,
  eeprom         = true,
  internet       = true,
  redstone       = true,
  motion_sensor  = true,
  experience     = true,
  tractor_beam   = true,
  geolyzer       = true,
  chunkloader    = true,
  data           = true,
  debug          = true,
  ["3d_printer"] = true,
}

-- GT-методы — признак того, что компонент является GT-машиной
local GT_PROBE = { "isMachineActive", "isActive", "getMachineName", "hasWork" }

-- ─── Helpers ──────────────────────────────────────────────────────────────

local function isGTMachine(proxy)
  for _, m in ipairs(GT_PROBE) do
    if type(proxy[m]) == "function" then return true end
  end
  return false
end

local function getMachineName(proxy, addr, overrides)
  if overrides and overrides[addr] then
    return overrides[addr]
  end
  for _, m in ipairs({ "getMachineName", "getName", "getBlockName" }) do
    if type(proxy[m]) == "function" then
      local ok, name = pcall(proxy[m])
      if ok and type(name) == "string" and #name > 0 then
        return name
      end
    end
  end
  return "Unknown (" .. component.type(addr) .. ")"
end

local function readActive(proxy)
  for _, m in ipairs({ "isMachineActive", "isActive" }) do
    if type(proxy[m]) == "function" then
      local ok, val = pcall(proxy[m])
      if ok and type(val) == "boolean" then return val end
    end
  end
  return nil
end

-- ─── Redstone helpers ─────────────────────────────────────────────────────

--- Получить Redstone-компонент (первый доступный)
local function getRS()
  if component.isAvailable("redstone") then
    return component.redstone
  end
  return nil
end

--- Выдать HIGH на сторону (прямой редстоун или bundled)
local function rsHigh(rs, side, color)
  if color then
    -- Bundled cable
    local ok = pcall(function()
      local outputs = rs.getBundledOutput(side)
      outputs[color] = 15
      rs.setBundledOutput(side, outputs)
    end)
    return ok
  else
    return pcall(rs.setOutput, side, 15)
  end
end

--- Выдать LOW на сторону
local function rsLow(rs, side, color)
  if color then
    local ok = pcall(function()
      local outputs = rs.getBundledOutput(side)
      outputs[color] = 0
      rs.setBundledOutput(side, outputs)
    end)
    return ok
  else
    return pcall(rs.setOutput, side, 0)
  end
end

-- ─── Публичный API ────────────────────────────────────────────────────────

--- Полное сканирование всех GT-адаптеров
-- @param overrides table  Переопределения имён из node_config
-- @return table  { {name, addr, active, error} }
function machines.scan(overrides)
  local result = {}
  for addr, compType in component.list() do
    if not IGNORED_TYPES[compType] then
      local ok, proxy = pcall(component.proxy, addr)
      if ok and proxy and isGTMachine(proxy) then
        local name   = getMachineName(proxy, addr, overrides)
        local active = readActive(proxy)
        local err    = nil
        if active == nil then
          active = false
          err    = "Cannot read status"
        end
        table.insert(result, { name = name, addr = addr, active = active, error = err })
      end
    end
  end
  table.sort(result, function(a, b) return a.name < b.name end)
  return result
end

--- Быстрое обновление статусов уже известных машин (без повторного поиска)
-- @param known_list table  Последний результат scan()
-- @return table  Обновлённый список
function machines.updateStatus(known_list)
  local result = {}
  for _, m in ipairs(known_list) do
    local entry = { name = m.name, addr = m.addr, active = false, error = nil }
    local ok, proxy = pcall(component.proxy, m.addr)
    if ok and proxy then
      local active = readActive(proxy)
      if active == nil then
        entry.active = false
        entry.error  = "Cannot read status"
      else
        entry.active = active
      end
    else
      entry.error = "Adapter disconnected"
    end
    table.insert(result, entry)
  end
  return result
end

--- Перезапустить машину через Redstone I/O сигнал
-- @param machine_name  string  Название машины (для поиска в redstone_restart)
-- @param rs_config     table?  { side, color?, mode?, pulse? } из node_config.redstone_restart
-- @return ok bool, msg string
function machines.restart(machine_name, rs_config)
  if not rs_config then
    return false, "No redstone config for: " .. tostring(machine_name)
  end

  local rs = getRS()
  if not rs then
    return false, "No Redstone I/O component found on this computer"
  end

  local side   = rs_config.side
  local color  = rs_config.color    -- nil = прямой редстоун, число = bundled цвет
  local mode   = rs_config.mode or "pulse"
  local pulse  = rs_config.pulse or 0.5

  if side == nil then
    return false, "rs_config.side not specified for: " .. tostring(machine_name)
  end

  -- ── Режим "pulse": кратковременный HIGH → LOW ─────────────────────────
  if mode == "pulse" then
    rsHigh(rs, side, color)
    os.sleep(pulse)
    rsLow(rs, side, color)
    return true, string.format("Redstone pulse sent (side=%d, %.1fs)", side, pulse)

  -- ── Режим "enable": выставить HIGH и оставить ────────────────────────
  elseif mode == "enable" then
    rsHigh(rs, side, color)
    return true, string.format("Redstone HIGH set (side=%d)", side)

  -- ── Режим "toggle": убедиться что LOW, затем HIGH→LOW ────────────────
  elseif mode == "toggle" then
    rsLow(rs, side, color)
    os.sleep(0.1)
    rsHigh(rs, side, color)
    os.sleep(pulse)
    rsLow(rs, side, color)
    return true, string.format("Redstone toggle sent (side=%d)", side)

  else
    return false, "Unknown redstone mode: " .. tostring(mode)
  end
end

--- Сбросить все редстоун-выходы в LOW (безопасное состояние при запуске)
-- Вызывается при инициализации Node, чтобы убедиться что сигналы чистые
-- @param redstone_restart table  Карта из node_config
function machines.resetAllOutputs(redstone_restart)
  local rs = getRS()
  if not rs then return end
  local cleared = {}
  for _, cfg in pairs(redstone_restart) do
    local key = tostring(cfg.side) .. ":" .. tostring(cfg.color)
    if not cleared[key] then
      rsLow(rs, cfg.side, cfg.color)
      cleared[key] = true
    end
  end
end

return machines
