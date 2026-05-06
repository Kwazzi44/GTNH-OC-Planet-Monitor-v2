-- =============================================================================
-- hub/registry.lua — Planet & Machine Registry (persistent)
-- =============================================================================
-- Структура данных:
-- _data["Ceres"] = {
--   name     = "Ceres",
--   status   = "OK",          -- OK | PARTIAL | RING_DOWN | UNKNOWN
--   last_ok  = <os.time()>,   -- когда последний раз всё было хорошо
--   machines = {
--     {
--       name         = "EBF",
--       adapter_addr = "94c19a39-...",  -- адрес gt_machine компонента
--       rs_addr      = "3f3ae22d-...",  -- адрес redstone компонента (или nil)
--       rs_side      = 2,               -- сторона Redstone I/O
--       rs_color     = nil,             -- nil = прямой, 0-15 = bundled
--       rs_mode      = "pulse",         -- pulse | enable | toggle
--       rs_pulse     = 0.5,
--       -- runtime поля (не сохраняются):
--       active       = false,
--       error        = nil,
--     }
--   }
-- }

local serial = require("serialization")
local config = require("config")

local registry = {}
local _data = {}   -- keyed by planet name

-- ─── Сохранение / загрузка ───────────────────────────────────────────────

local SAVE_KEYS = { "name", "machines" }
local MACHINE_SAVE = {
  "name","adapter_addr","rs_addr","rs_side","rs_color","rs_mode","rs_pulse"
}

local function stripRuntime(planets)
  -- Убираем runtime-поля перед сохранением
  local out = {}
  for pname, p in pairs(planets) do
    local pm = { name = p.name, machines = {} }
    for _, m in ipairs(p.machines or {}) do
      local sm = {}
      for _, k in ipairs(MACHINE_SAVE) do sm[k] = m[k] end
      table.insert(pm.machines, sm)
    end
    out[pname] = pm
  end
  return out
end

function registry.save()
  local f = io.open(config.registry_file, "w")
  if not f then return end
  f:write(serial.serialize(stripRuntime(_data)))
  f:close()
end

function registry.load()
  local f = io.open(config.registry_file, "r")
  if not f then return end
  local raw = f:read("*a"); f:close()
  local ok, result = pcall(serial.unserialize, raw)
  if ok and type(result) == "table" then
    _data = result
    -- Инициализируем runtime-поля
    for _, p in pairs(_data) do
      p.status  = "UNKNOWN"
      p.last_ok = 0
      for _, m in ipairs(p.machines or {}) do
        m.active = false
        m.error  = nil
      end
    end
  end
end

-- ─── CRUD ────────────────────────────────────────────────────────────────

function registry.getAll()  return _data end

function registry.get(planet_name)
  return _data[planet_name]
end

function registry.addPlanet(name)
  if not _data[name] then
    _data[name] = { name = name, status = "UNKNOWN", last_ok = 0, machines = {} }
    registry.save()
  end
  return _data[name]
end

function registry.removePlanet(name)
  _data[name] = nil
  registry.save()
end

function registry.addMachine(planet_name, machine)
  local p = _data[planet_name]
  if not p then return false end
  -- Не добавлять дубликаты по adapter_addr
  for _, m in ipairs(p.machines) do
    if m.adapter_addr == machine.adapter_addr then return false end
  end
  machine.active = false
  machine.error  = nil
  table.insert(p.machines, machine)
  registry.save()
  return true
end

function registry.removeMachine(planet_name, adapter_addr)
  local p = _data[planet_name]
  if not p then return end
  for i, m in ipairs(p.machines) do
    if m.adapter_addr == adapter_addr then
      table.remove(p.machines, i)
      registry.save()
      return
    end
  end
end

--- Отсортированный список планет для GUI
function registry.getPlanetList()
  local list = {}
  for _, p in pairs(_data) do table.insert(list, p) end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

--- Все адреса адаптеров из всех планет (для быстрой проверки)
function registry.getAllAdapterAddrs()
  local addrs = {}
  for _, p in pairs(_data) do
    for _, m in ipairs(p.machines or {}) do
      addrs[m.adapter_addr] = { planet = p.name, machine = m }
    end
  end
  return addrs
end

return registry
