-- =============================================================================
-- hub/registry.lua — Planet Registry (persistent)
-- =============================================================================
-- Хранит список всех известных планет и их машин.
-- Сохраняется в JSON-файл на диске OC для переживания перезапусков Hub.

local serial = require("serialization")
local config = require("config")

local registry = {}
local _planets = {}   -- [ modem_address ] = planet_record

-- ─── Структура записи планеты ─────────────────────────────────────────────
-- {
--   address   = "abc-123",          -- modem address Node-компьютера
--   planet    = "Ceres",            -- имя планеты из node_config
--   status    = "UNKNOWN",          -- OK | PARTIAL | RING_DOWN | UNKNOWN
--   last_seen = 0,                  -- os.time() последнего PONG
--   machines  = {                   -- список машин
--     { name="EBF", addr="comp-addr", active=true, error=nil }
--   }
-- }

-- ─── Персистентность ─────────────────────────────────────────────────────

function registry.load()
  local f = io.open(config.registry_file, "r")
  if not f then return end
  local data = f:read("*a")
  f:close()
  local ok, result = pcall(serial.unserialize, data)
  if ok and type(result) == "table" then
    _planets = result
  end
end

function registry.save()
  local f = io.open(config.registry_file, "w")
  if not f then return end
  f:write(serial.serialize(_planets))
  f:close()
end

-- ─── CRUD ────────────────────────────────────────────────────────────────

--- Получить запись планеты по адресу modem
function registry.get(addr)
  return _planets[addr]
end

--- Получить все планеты (сырая таблица)
function registry.getAll()
  return _planets
end

--- Добавить или обновить планету
function registry.upsert(addr, planet_name, machines)
  if not _planets[addr] then
    _planets[addr] = {
      address   = addr,
      planet    = planet_name,
      status    = "UNKNOWN",
      last_seen = 0,
      machines  = machines or {},
    }
  else
    _planets[addr].planet   = planet_name
    if machines then
      _planets[addr].machines = machines
    end
  end
  registry.save()
end

--- Обновить статус и машины после PONG
function registry.updateStatus(addr, status, machines, timestamp)
  local p = _planets[addr]
  if not p then return end
  p.status    = status
  p.last_seen = timestamp or os.time()
  if machines then
    p.machines = machines
  end
  -- Не сохраняем на каждый PONG (часто) — только при структурных изменениях
end

--- Сохранить статусы на диск (вызывать периодически)
function registry.flush()
  registry.save()
end

--- Удалить планету (например, если её больше нет)
function registry.remove(addr)
  _planets[addr] = nil
  registry.save()
end

--- Отсортированный список планет для GUI
function registry.getPlanetList()
  local list = {}
  for _, p in pairs(_planets) do
    table.insert(list, p)
  end
  table.sort(list, function(a, b)
    return (a.planet or "") < (b.planet or "")
  end)
  return list
end

--- Найти планету по имени (возвращает addr, record)
function registry.findByName(name)
  for addr, p in pairs(_planets) do
    if p.planet == name then
      return addr, p
    end
  end
  return nil, nil
end

return registry
