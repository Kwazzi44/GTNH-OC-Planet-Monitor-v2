-- =============================================================================
-- node/main.lua — Node Entry Point
-- =============================================================================
-- Запуск: поместите файлы node/ на компьютер планеты, protocol.lua рядом.
-- Затем: lua /path/to/node/main.lua
-- Для автозапуска: создайте /home/autorun.lua с этим содержимым:
--   shell.execute("/path/to/node/main.lua")

local scriptPath = (debug and debug.getinfo and
  debug.getinfo(1,"S").source:match("^@(.+/)")) or ""
package.path = scriptPath .. "?.lua;"
           .. scriptPath .. "../?.lua;"
           .. package.path

local component = require("component")
local event     = require("event")
local os        = require("os")

local ncfg     = require("node_config")
local protocol = require("protocol")
local mch      = require("machines")

-- ─── State ────────────────────────────────────────────────────────────────

local _running      = true
local _modem        = nil
local _hub_addr     = nil      -- modem address Hub'а (узнаём из первого сообщения)
local _known        = {}       -- последний список машин (из scan)
local _last_scan    = 0        -- os.time() последнего полного скана
local _last_status  = {}       -- предыдущий статус для алертов
local SCAN_INTERVAL = 60       -- полный пересмотр раз в 60с

-- ─── Modem ────────────────────────────────────────────────────────────────

local function getModem()
  if _modem then return _modem end
  if component.isAvailable("modem") then
    _modem = component.modem
    _modem.open(ncfg.modem_port)
    return _modem
  end
  return nil
end

local function sendToHub(msg)
  local m = getModem()
  if not m then return end
  if _hub_addr then
    m.send(_hub_addr, ncfg.modem_port, protocol.encode(msg))
  else
    -- Hub-адрес ещё неизвестен — шлём broadcast
    m.broadcast(ncfg.modem_port, protocol.encode(msg))
  end
end

-- ─── Machine helpers ──────────────────────────────────────────────────────

local function doFullScan()
  _known     = mch.scan(ncfg.name_overrides)
  _last_scan = os.time()
  -- Сбрасываем историю статусов для корректного обнаружения изменений
  _last_status = {}
  for _, m in ipairs(_known) do
    _last_status[m.addr] = m.active
  end
  return _known
end

local function doStatusUpdate()
  if #_known == 0 then return _known end
  _known = mch.updateStatus(_known)
  return _known
end

-- ─── Alert: если машина только что упала ─────────────────────────────────

local function checkAlerts(machine_list)
  for _, m in ipairs(machine_list) do
    local prev = _last_status[m.addr]
    if prev ~= nil and prev == true and m.active == false then
      -- Машина только что упала!
      sendToHub(protocol.mkAlert(ncfg.planet_name, m.name,
        "Machine went OFFLINE" .. (m.error and (": " .. m.error) or "")))
    end
    _last_status[m.addr] = m.active
  end
end

-- ─── Register with Hub ────────────────────────────────────────────────────

local function register(machine_list)
  sendToHub(protocol.mkRegister(ncfg.planet_name, machine_list))
end

-- ─── Handle incoming messages ─────────────────────────────────────────────

local function onModem(_, _, sender, port, _, raw)
  if port ~= ncfg.modem_port then return end

  -- Запоминаем адрес Hub'а при первом сообщении
  if not _hub_addr then
    _hub_addr = sender
    io.write("[Node] Hub address learned: " .. sender .. "\n")
  end

  local msg = protocol.decode(raw)
  if not msg then return end

  if msg.type == protocol.PING then
    -- Обновляем статусы и отвечаем
    local list = doStatusUpdate()
    checkAlerts(list)
    sendToHub(protocol.mkPong(ncfg.planet_name, list))

  elseif msg.type == protocol.PING_REGISTER then
    -- Hub перезапустился, нужна повторная регистрация
    local list = doFullScan()
    register(list)

  elseif msg.type == protocol.RESTART then
    -- Включить конкретную машину
    local target_addr = msg.machine
    local ok, info = false, "Machine not found"
    for _, m in ipairs(_known) do
      if m.addr == target_addr then
        local rs_cfg = ncfg.redstone_fallback and ncfg.redstone_fallback[target_addr]
        ok, info = mch.restart(target_addr, rs_cfg)
        break
      end
    end
    sendToHub(protocol.mkAck(ncfg.planet_name, msg.machine, ok, info))

    -- После restart — обновим статус через 2с
    os.sleep(2)
    doStatusUpdate()
    sendToHub(protocol.mkPong(ncfg.planet_name, _known))

  elseif msg.type == protocol.RESTART_ALL then
    -- Включить все выключенные машины
    local any = false
    for _, m in ipairs(_known) do
      if not m.active then
        any = true
        local rs_cfg = ncfg.redstone_fallback and ncfg.redstone_fallback[m.addr]
        local ok, info = mch.restart(m.addr, rs_cfg)
        sendToHub(protocol.mkAck(ncfg.planet_name, m.name, ok, info))
      end
    end
    if not any then
      sendToHub(protocol.mkAck(ncfg.planet_name, "ALL", true, "Nothing to restart"))
    end
    -- Обновить и отправить статус
    os.sleep(2)
    doStatusUpdate()
    sendToHub(protocol.mkPong(ncfg.planet_name, _known))

  elseif msg.type == protocol.SCAN then
    -- Полное пересканирование адаптеров
    local list = doFullScan()
    sendToHub(protocol.mkScanResult(ncfg.planet_name, list))
    -- И сразу зарегистрировать (мог появиться новый мультиблок)
    register(list)
  end
end

-- ─── Init ─────────────────────────────────────────────────────────────────

local function init()
  local m = getModem()
  if not m then
    io.write("[Node] ERROR: No modem found! Check connections.\n")
    return false
  end

  if not ncfg.planet_name or ncfg.planet_name == "MyPlanet" then
    io.write("[Node] WARNING: planet_name not set in node_config.lua!\n")
  end

  io.write("[Node] Starting on planet: " .. (ncfg.planet_name or "?") .. "\n")
  io.write("[Node] Scanning machines...\n")

  local list = doFullScan()
  io.write("[Node] Found " .. #list .. " machine(s).\n")
  for _, m2 in ipairs(list) do
    io.write("  - " .. m2.name .. " [" .. (m2.active and "ACTIVE" or "OFFLINE") .. "]\n")
  end

  -- Регистрируемся на Hub (broadcast, т.к. адрес Hub'а ещё неизвестен)
  register(list)
  io.write("[Node] Registration sent. Listening...\n")

  return true
end

-- ─── Main Loop ────────────────────────────────────────────────────────────

local function mainLoop()
  local modemListener = event.listen("modem_message", onModem)
  local nextScan      = os.time() + SCAN_INTERVAL

  while _running do
    local now = os.time()

    -- Периодический полный скан (новые машины / отключённые адаптеры)
    if now >= nextScan then
      local list = doFullScan()
      -- Если Hub известен, отправляем обновление сами
      if _hub_addr then
        sendToHub(protocol.mkPong(ncfg.planet_name, list))
      end
      nextScan = now + SCAN_INTERVAL
    end

    os.sleep(0.1)
  end

  event.ignore("modem_message", modemListener)
  io.write("[Node] Stopped.\n")
end

-- ─── Entry ────────────────────────────────────────────────────────────────

if init() then
  mainLoop()
else
  io.write("[Node] Initialization failed.\n")
  os.exit(1)
end
