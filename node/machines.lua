-- =============================================================================
-- node/machines.lua — Machine Discovery & Control via GT Adapter
-- =============================================================================

local component = require("component")
local os        = require("os")

local machines = {}

-- Известные типы GT-компонентов, которые мы ищем.
-- В GTNH через OC Adapter GT мультиблоки появляются как компоненты
-- с типом "gt_machine" или именами конкретных машин.
-- Мы сканируем ВСЕ компоненты и фильтруем по наличию GT-методов.
local IGNORED_TYPES = {
  computer     = true,
  screen       = true,
  gpu          = true,
  modem        = true,
  keyboard     = true,
  filesystem   = true,
  eeprom       = true,
  internet     = true,
  redstone     = true,
  ["motion_sensor"] = true,
}

-- GT-методы, которые мы проверяем для идентификации машины
local GT_PROBE_METHODS = {
  "isMachineActive",
  "isActive",
  "getMachineName",
  "hasWork",
}

-- ─── Проверка является ли компонент GT-машиной ───────────────────────────

local function isGTMachine(proxy)
  for _, method in ipairs(GT_PROBE_METHODS) do
    if type(proxy[method]) == "function" then
      return true
    end
  end
  return false
end

-- ─── Получить имя машины через proxy ─────────────────────────────────────

local function getMachineName(proxy, addr, overrides)
  -- Сначала проверяем переопределение
  if overrides and overrides[addr] then
    return overrides[addr]
  end
  -- Пробуем GT-методы
  local methods = { "getMachineName", "getName", "getBlockName" }
  for _, m in ipairs(methods) do
    if type(proxy[m]) == "function" then
      local ok, name = pcall(proxy[m])
      if ok and type(name) == "string" and #name > 0 then
        return name
      end
    end
  end
  return "Unknown (" .. component.type(addr) .. ")"
end

-- ─── Проверить активна ли машина ─────────────────────────────────────────

local function isMachineActive(proxy)
  -- Пробуем разные методы
  local probe = { "isMachineActive", "isActive", "isWorkAllowed" }
  for _, m in ipairs(probe) do
    if type(proxy[m]) == "function" then
      local ok, val = pcall(proxy[m])
      if ok and type(val) == "boolean" then
        return val
      end
    end
  end
  return nil  -- не удалось определить
end

-- ─── Попытка включить машину ──────────────────────────────────────────────

--- Попытка restart через GT Adapter
-- @return ok bool, err string?
local function tryAdapterEnable(proxy)
  local enable_methods = { "setWorkAllowed", "enable", "setEnabled" }
  for _, m in ipairs(enable_methods) do
    if type(proxy[m]) == "function" then
      -- setWorkAllowed принимает bool
      local ok, err = pcall(proxy[m], true)
      if ok then return true end
    end
  end
  return false, "No enable method found on adapter"
end

--- Fallback: Redstone I/O импульс
local function tryRedstoneEnable(rs_side)
  if not component.isAvailable("redstone") then
    return false, "No redstone component"
  end
  local rs = component.redstone
  local ok1 = pcall(rs.setOutput, rs_side, 15)
  os.sleep(0.5)
  local ok2 = pcall(rs.setOutput, rs_side, 0)
  return (ok1 and ok2), (not ok1 or not ok2) and "Redstone error" or nil
end

-- ─── Публичный API ────────────────────────────────────────────────────────

--- Сканировать все локальные GT-адаптеры
-- @param overrides table  config.name_overrides
-- @return table  { { name, addr, active, error } }
function machines.scan(overrides)
  local result = {}
  for addr, compType in component.list() do
    if not IGNORED_TYPES[compType] then
      local ok, proxy = pcall(component.proxy, addr)
      if ok and proxy and isGTMachine(proxy) then
        local name   = getMachineName(proxy, addr, overrides)
        local active = isMachineActive(proxy)
        local err    = nil
        if active == nil then
          active = false
          err    = "Cannot read status"
        end
        table.insert(result, {
          name   = name,
          addr   = addr,
          active = active,
          error  = err,
        })
      end
    end
  end
  -- Стабильная сортировка по имени
  table.sort(result, function(a, b) return a.name < b.name end)
  return result
end

--- Получить текущие статусы уже известных машин (быстрее чем full scan)
-- @param known_list table  Список машин из последнего scan()
-- @return table  Обновлённый список
function machines.updateStatus(known_list)
  local result = {}
  for _, m in ipairs(known_list) do
    local entry = { name = m.name, addr = m.addr, active = false, error = nil }
    local ok, proxy = pcall(component.proxy, m.addr)
    if ok and proxy then
      local active = isMachineActive(proxy)
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

--- Попытаться включить машину по адресу компонента
-- @param addr     string  Адрес GT Adapter компонента
-- @param rs_cfg   table?  { rs_side = N } для redstone fallback
-- @return ok bool, msg string
function machines.restart(addr, rs_cfg)
  local ok_p, proxy = pcall(component.proxy, addr)
  if not ok_p or not proxy then
    return false, "Cannot access adapter"
  end

  -- Пробуем через adapter
  local ok, err = tryAdapterEnable(proxy)
  if ok then
    return true, "Enabled via adapter"
  end

  -- Fallback на Redstone
  if rs_cfg and rs_cfg.rs_side ~= nil then
    ok, err = tryRedstoneEnable(rs_cfg.rs_side)
    if ok then
      return true, "Enabled via redstone pulse"
    end
    return false, "Redstone fallback failed: " .. (err or "?")
  end

  return false, "No restart method available: " .. (err or "?")
end

return machines
