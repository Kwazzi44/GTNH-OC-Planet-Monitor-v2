-- =============================================================================
-- hub/monitor.lua — Monitoring Logic (ping/pong, timeouts, commands)
-- =============================================================================

local component = require("component")
local os        = require("os")

local config   = require("config")
local protocol = require("protocol")
local registry = require("registry")
local logger   = require("logger")

local monitor = {}

local _modem          = nil
local _pending_pings  = {}   -- [addr] = deadline (os.time)
local _last_ping_all  = 0

-- ─── Modem helper ─────────────────────────────────────────────────────────

local function getModem()
  if _modem then return _modem end
  if component.isAvailable("modem") then
    _modem = component.modem
    _modem.open(config.modem_port)
    return _modem
  end
  return nil
end

local function send(addr, msg)
  local m = getModem()
  if not m then return false end
  m.send(addr, config.modem_port, protocol.encode(msg))
  return true
end

-- ─── Status calculation ───────────────────────────────────────────────────

local function calcStatus(machines)
  if not machines or #machines == 0 then return "UNKNOWN" end
  for _, m in ipairs(machines) do
    if not m.active then return "PARTIAL" end
  end
  return "OK"
end

-- ─── Diff helper (for logging changes) ───────────────────────────────────

local function buildMachineMap(machines)
  local map = {}
  if not machines then return map end
  for _, m in ipairs(machines) do
    map[m.addr] = m
  end
  return map
end

-- ─── Incoming message handler ─────────────────────────────────────────────

--- Вызывается из main.lua при получении modem_message
-- @param sender  string  Адрес отправителя (Node modem address)
-- @param raw     string  Сырое сообщение
function monitor.handleMessage(sender, raw)
  local msg = protocol.decode(raw)
  if not msg then return end

  if msg.type == protocol.REGISTER then
    local existed = registry.get(sender)
    registry.upsert(sender, msg.planet, msg.machines)
    registry.updateStatus(sender, "UNKNOWN", msg.machines, os.time())
    if not existed then
      logger.log(msg.planet, nil,
        string.format("REGISTERED (%d machine(s))", #(msg.machines or {})))
    else
      logger.log(msg.planet, nil,
        string.format("RE-REGISTERED (%d machine(s))", #(msg.machines or {})))
    end

  elseif msg.type == protocol.PONG then
    _pending_pings[sender] = nil
    local prev    = registry.get(sender)
    local prevSt  = prev and prev.status or "UNKNOWN"
    local prevMap = prev and buildMachineMap(prev.machines) or {}

    local newStatus = calcStatus(msg.machines)
    registry.updateStatus(sender, newStatus, msg.machines, os.time())

    -- Лог изменения статуса планеты
    if prevSt ~= newStatus then
      logger.log(msg.planet, nil, prevSt .. " → " .. newStatus)
    end

    -- Лог изменений статуса отдельных машин
    for _, m in ipairs(msg.machines or {}) do
      local pm = prevMap[m.addr]
      if pm and (pm.active ~= m.active) then
        logger.log(msg.planet, m.name, m.active and "ACTIVE" or "OFFLINE")
      end
    end

  elseif msg.type == protocol.ALERT then
    local p = registry.get(sender)
    local pname = p and p.planet or ("node:" .. sender:sub(1,8))
    logger.log(pname, msg.machine, "ALERT: " .. (msg.msg or ""))

  elseif msg.type == protocol.ACK then
    local p = registry.get(sender)
    local pname = p and p.planet or ("node:" .. sender:sub(1,8))
    local result = msg.ok and "OK" or ("FAILED: " .. (msg.msg or "?"))
    logger.log(pname, msg.machine, "RESTART → " .. result)

  elseif msg.type == protocol.SCAN_RESULT then
    local p = registry.get(sender)
    if p then
      registry.upsert(sender, p.planet, msg.machines)
      logger.log(p.planet, nil,
        string.format("SCAN COMPLETE: %d machine(s) found", #(msg.machines or {})))
    end
  end
end

-- ─── Timeout checker ──────────────────────────────────────────────────────

--- Вызывается из главного цикла для проверки просроченных PING'ов
function monitor.checkTimeouts()
  local now = os.time()
  for addr, deadline in pairs(_pending_pings) do
    if now >= deadline then
      _pending_pings[addr] = nil
      local p = registry.get(addr)
      if p and p.status ~= "RING_DOWN" then
        registry.updateStatus(addr, "RING_DOWN", nil, p.last_seen)
        logger.log(p.planet, nil, "RING DOWN")
      end
    end
  end
end

-- ─── Outgoing commands ────────────────────────────────────────────────────

--- Пинговать все известные планеты
function monitor.pingAll()
  local m = getModem()
  if not m then return end
  local now = os.time()
  for addr, _ in pairs(registry.getAll()) do
    send(addr, protocol.mkPing())
    _pending_pings[addr] = now + config.ping_timeout
  end
  _last_ping_all = now
end

--- Пинговать одну планету
function monitor.pingOne(addr)
  send(addr, protocol.mkPing())
  _pending_pings[addr] = os.time() + config.ping_timeout
end

--- Отправить команду restart конкретной машины
function monitor.restartMachine(planet_addr, machine_addr)
  send(planet_addr, protocol.mkRestart(machine_addr))
end

--- Отправить команду restart всех машин на планете
function monitor.restartAll(planet_addr)
  send(planet_addr, protocol.mkRestartAll())
end

--- Отправить команду пересканировать адаптеры
function monitor.scanPlanet(planet_addr)
  send(planet_addr, protocol.mkScan())
end

--- Запросить регистрацию у всех (например, после перезапуска Hub)
function monitor.broadcastRegister()
  local m = getModem()
  if not m then return end
  m.broadcast(config.modem_port, protocol.encode(protocol.mkPingRegister()))
end

--- Надо ли запускать автопинг прямо сейчас?
function monitor.shouldAutoPing()
  return (os.time() - _last_ping_all) >= config.ping_interval
end

-- ─── Init ────────────────────────────────────────────────────────────────

function monitor.init()
  local m = getModem()
  if not m then return false, "Modem component not found!" end
  return true
end

return monitor
