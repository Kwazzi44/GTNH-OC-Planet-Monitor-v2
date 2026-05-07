-- =============================================================================
-- hub/machines.lua — Direct Component Access: Status & Restart
-- =============================================================================

local component = require("component")
local os        = require("os")

local machines = {}

-- ─── GT методы для чтения статуса ────────────────────────────────────────

local STATUS_METHODS = { "isMachineActive", "isActive", "isWorking", "hasWork" }

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
  local GT_NAME_METHODS = { "getMachineName", "getName", "getBlockName", "getInventoryName", "getCustomName" }
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
    if name == "Unknown" and ok and proxy then
      pcall(function()
        local methods = {}
        for k, _ in pairs(proxy) do table.insert(methods, k) end
        require("logger").log("SYSTEM", "DEBUG", "Unknown machine " .. string.sub(addr,1,8) .. " methods: " .. table.concat(methods, ", "))
      end)
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
-- Возвращает: active bool, err string?
-- err == "RING_DOWN" означает что компонент исчез из сети
-- err == другое  означает что компонент есть но что-то не так
function machines.getStatus(m)
  -- Шаг 1: проверить что адрес вообще есть в сети
  local exists = false
  for addr, _ in component.list() do
    if addr == m.adapter_addr then exists = true; break end
  end

  if not exists then
    return false, "RING_DOWN"   -- компонент исчез из OC-сети
  end

  -- Шаг 2: получить proxy и прочитать статус
  local ok, proxy = pcall(component.proxy, m.adapter_addr)
  if not ok or not proxy then
    return false, "Adapter proxy error"
  end

  local active = readActive(proxy)
  local has_problem = false

  -- Проверяем сенсоры на наличие проблем (Maintenance)
  local s_ok, s_data = pcall(proxy.getSensorInformation)
  if s_ok and type(s_data) == "table" then
    for _, line in ipairs(s_data) do
      local clean = line:gsub("§.", "") -- убираем цветовые коды
      
      -- Ищем "Problems: X"
      local prob_count = clean:match("Problems:%s*(%d+)")
      if prob_count and tonumber(prob_count) > 0 then
        has_problem = true
      end

      -- Если active еще не определен (nil), пробуем вытащить его из данных сенсора
      if active == nil then
        if clean:match("Progress:") then
          local p1, p2 = clean:match("Progress:%s*(%d+)%s*s?%s*/%s*(%d+)")
          if p1 and p2 and (tonumber(p1) > 0 or tonumber(p2) > 0) then
            active = true
          end
        elseif clean:match("Efficiency:") then
          local eff = clean:match("Efficiency:%s*(%d+%.?%d*)")
          if eff and tonumber(eff) > 0 then
            active = true
          end
        elseif clean:match("EU/t required:") then
          local eut = clean:match("EU/t required:%s*([%d,]+)")
          if eut then
            eut = eut:gsub(",", "") -- убираем запятые из чисел
            if tonumber(eut) and tonumber(eut) > 0 then active = true end
          end
        elseif clean:match("%d+L/s") or clean:match("%d+%s*L/s") then
          -- Если есть выход в литрах в секунду (например, 1000L/s)
          active = true
        end
      end
    end
  end

  if active == nil then active = false end

  if has_problem then
    return active, "MAINTENANCE" -- Машина работает, но есть проблемы
  end

  return active, nil
end

--- Получить данные сенсоров машины
-- @return table(string) или nil, err
function machines.getSensorData(m)
  if not m.adapter_addr then return nil, "No adapter address" end
  local proxy = component.proxy(m.adapter_addr)
  if not proxy then return nil, "Adapter missing" end
  if not proxy.getSensorInformation then return nil, "No sensor API" end

  local ok, data = pcall(proxy.getSensorInformation)
  if not ok then return nil, tostring(data) end
  return data
end

--- Перезапустить машину через Redstone
-- rs_side = -1 означает "все стороны" (broadcast)
-- @param m  table  Запись машины из registry
-- @return ok bool, msg string
function machines.restart(m)
  local proxy
  if m.adapter_addr then
    proxy = component.proxy(m.adapter_addr)
  end

  -- Software API restart
  if proxy and proxy.setWorkAllowed then
    local ok, err = pcall(function()
      proxy.setWorkAllowed(false)
      os.sleep(0.5)
      proxy.setWorkAllowed(true)
    end)
    if ok then
      return true, "Restarted via API (setWorkAllowed)"
    end
  end

  -- Hardware Redstone restart
  local r = m.redstone
  if not r or not r.addr or r.side == nil then
    return false, "No redstone config and API restart failed/unavailable"
  end
  local rs = rsProxy(r.addr)
  if not rs then
    return false, "Redstone component not found: " .. tostring(r.addr)
  end

  local all_sides = (r.side == -1)
  local sides     = all_sides and {0,1,2,3,4,5} or {r.side}
  local color     = r.color
  local mode      = r.mode  or "pulse"
  local pulse     = r.pulse or 0.5

  local function high() for _, s in ipairs(sides) do rsHigh(rs, s, color) end end
  local function low()  for _, s in ipairs(sides) do rsLow(rs, s, color) end  end

  local sides_str = all_sides and "ALL" or tostring(r.side)

  if mode == "pulse" then
    high(); os.sleep(pulse); low()
    return true, string.format("Pulse sent (sides=%s, %.1fs)", sides_str, pulse)

  elseif mode == "enable" then
    high()
    return true, string.format("RS HIGH set (sides=%s)", sides_str)

  elseif mode == "toggle" then
    low(); os.sleep(0.1); high(); os.sleep(pulse); low()
    return true, string.format("Toggle sent (sides=%s)", sides_str)

  else
    return false, "Unknown mode: " .. tostring(mode)
  end
end

--- Сбросить все редстоун-выходы по всем планетам реестра (при старте)
function machines.resetAllRedstone(planet_list)
  local done = {}
  for _, p in ipairs(planet_list) do
    for _, m in ipairs(p.machines or {}) do
      if m.redstone and m.redstone.addr and m.redstone.side ~= nil then
        local rs = rsProxy(m.redstone.addr)
        if rs then
          if m.redstone.side == -1 then
            for s = 0, 5 do rsLow(rs, s, m.redstone.color) end
          else
            local key = m.redstone.addr .. ":" .. m.redstone.side
            if not done[key] then
              done[key] = true
              rsLow(rs, m.redstone.side, m.redstone.color)
            end
          end
        end
      end
    end
  end
end


return machines
