-- =============================================================================
-- hub/main.lua — Hub Entry Point & Main Loop
-- =============================================================================
-- Запуск: поместите файлы hub/ на компьютер Hub, protocol.lua рядом или в /lib/
-- Затем: lua /path/to/hub/main.lua

local scriptPath = (debug and debug.getinfo and
  debug.getinfo(1,"S").source:match("^@(.+/)")) or ""
-- Добавляем директорию hub/ и корень проекта в путь
package.path = scriptPath .. "?.lua;"
           .. scriptPath .. "../?.lua;"
           .. package.path

local component = require("component")
local event     = require("event")
local os        = require("os")
local keyboard  = require("keyboard")

local config   = require("config")
local protocol = require("protocol")
local registry = require("registry")
local monitor  = require("monitor")
local logger   = require("logger")
local gui      = require("gui")

-- ─── UI State ─────────────────────────────────────────────────────────────

local VIEW = { PLANETS = "planets", DETAIL = "detail", LOG = "log" }

local uiState = {
  view         = VIEW.PLANETS,
  planet_sel   = 1,
  planet_scroll= 1,
  machine_sel  = 1,
  machine_scroll= 1,
  log_scroll   = nil,   -- nil = auto-bottom
  detail_addr  = nil,   -- modem address of planet in detail view
  dirty        = true,
  notify       = nil,   -- { msg, color, until_clock }
  last_draw    = 0,
}

local _running = true

-- ─── Helper: navigate list ────────────────────────────────────────────────

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function navigate(sel, scroll, delta, count, visible)
  sel = clamp(sel + delta, 1, math.max(1, count))
  if sel < scroll then scroll = sel end
  if sel >= scroll + visible then scroll = sel - visible + 1 end
  return sel, scroll
end

-- ─── Notify helper ────────────────────────────────────────────────────────

local function setNotify(msg, color)
  uiState.notify = { msg = msg, color = color, until_t = os.clock() + 3 }
  uiState.dirty  = true
end

-- ─── View transitions ─────────────────────────────────────────────────────

local function openDetail(planets)
  if #planets == 0 then return end
  local p = planets[uiState.planet_sel]
  if not p then return end
  uiState.detail_addr   = p.address
  uiState.machine_sel   = 1
  uiState.machine_scroll= 1
  uiState.view          = VIEW.DETAIL
  uiState.dirty         = true
end

local function openLog()
  uiState.log_scroll = nil  -- auto-bottom
  uiState.view       = VIEW.LOG
  uiState.dirty      = true
end

local function goBack()
  uiState.view  = VIEW.PLANETS
  uiState.dirty = true
end

-- ─── Actions ──────────────────────────────────────────────────────────────

local function doRestartMachine()
  if uiState.view ~= VIEW.DETAIL then return end
  local p = registry.get(uiState.detail_addr)
  if not p then return end
  if p.status == "RING_DOWN" then
    setNotify("Ring is offline! Cannot restart remotely.", 0xFF2244)
    return
  end
  local machines = p.machines or {}
  local m = machines[uiState.machine_sel]
  if not m then return end
  if m.active then
    setNotify(m.name .. " is already ACTIVE.", 0x00DD55)
    return
  end
  monitor.restartMachine(p.address, m.addr)
  setNotify("Restart sent for: " .. m.name, 0xFFAA00)
end

local function doRestartAll()
  local planets = registry.getPlanetList()
  if uiState.view == VIEW.DETAIL then
    local p = registry.get(uiState.detail_addr)
    if p and p.status ~= "RING_DOWN" then
      monitor.restartAll(p.address)
      setNotify("Restart ALL sent to " .. p.planet, 0xFFAA00)
    else
      setNotify("Ring is offline! Cannot restart remotely.", 0xFF2244)
    end
  elseif uiState.view == VIEW.PLANETS then
    local p = planets[uiState.planet_sel]
    if p and p.status ~= "RING_DOWN" then
      monitor.restartAll(p.address)
      setNotify("Restart ALL sent to " .. p.planet, 0xFFAA00)
    end
  end
end

local function doScan()
  if uiState.view ~= VIEW.DETAIL then return end
  local p = registry.get(uiState.detail_addr)
  if p then
    monitor.scanPlanet(p.address)
    setNotify("Scan request sent to " .. p.planet, 0x4477FF)
  end
end

local function doRefresh()
  monitor.pingAll()
  setNotify("Refresh: pinged all planets", 0x4477FF)
end

-- ─── Keyboard handler ─────────────────────────────────────────────────────

local function onKey(_, _, char, code)
  local _, W_gui = gui.getSize and gui.getSize() or (80, 25)
  local _, H_gui = gui.getSize()
  -- Visible rows для списков (приблизительно)
  local LIST_VISIBLE = H_gui - 7

  -- Q / ESC → quit
  if char == string.byte("q") or char == string.byte("Q") or code == 1 then
    _running = false
    return
  end

  -- B → back
  if char == string.byte("b") or char == string.byte("B") then
    if uiState.view ~= VIEW.PLANETS then goBack() end
    return
  end

  -- L → log view
  if char == string.byte("l") or char == string.byte("L") then
    if uiState.view ~= VIEW.LOG then openLog() end
    return
  end

  -- R → refresh all
  if char == string.byte("r") or char == string.byte("R") then
    doRefresh()
    uiState.dirty = true
    return
  end

  -- A → restart all
  if char == string.byte("a") or char == string.byte("A") then
    doRestartAll()
    return
  end

  -- S → scan (detail view)
  if char == string.byte("s") or char == string.byte("S") then
    doScan()
    return
  end

  -- ENTER
  if code == 28 then
    if uiState.view == VIEW.PLANETS then
      openDetail(registry.getPlanetList())
    elseif uiState.view == VIEW.DETAIL then
      doRestartMachine()
    elseif uiState.view == VIEW.LOG then
      -- nothing
    end
    return
  end

  -- Navigation
  local UP   = (code == 200)  -- arrow up
  local DOWN = (code == 208)  -- arrow down
  local HOME = (code == 199)
  local ENDK = (code == 207)

  if uiState.view == VIEW.PLANETS then
    if UP or DOWN then
      local planets = registry.getPlanetList()
      uiState.planet_sel, uiState.planet_scroll =
        navigate(uiState.planet_sel, uiState.planet_scroll,
                 UP and -1 or 1, #planets, LIST_VISIBLE)
      uiState.dirty = true
    end

  elseif uiState.view == VIEW.DETAIL then
    if UP or DOWN then
      local p = registry.get(uiState.detail_addr)
      local count = p and #(p.machines or {}) or 0
      uiState.machine_sel, uiState.machine_scroll =
        navigate(uiState.machine_sel, uiState.machine_scroll,
                 UP and -1 or 1, count, LIST_VISIBLE)
      uiState.dirty = true
    end

  elseif uiState.view == VIEW.LOG then
    local lines = logger.getLines()
    local count = #lines
    local _, H2 = gui.getSize()
    local lh = H2 - 5
    if UP   then uiState.log_scroll = math.max(1, (uiState.log_scroll or count) - 1) end
    if DOWN then uiState.log_scroll = math.min(count, (uiState.log_scroll or count) + 1) end
    if HOME then uiState.log_scroll = 1 end
    if ENDK then uiState.log_scroll = nil end
    uiState.dirty = true
  end
end

-- ─── Modem message handler ────────────────────────────────────────────────

local function onModem(_, _, sender, port, _, raw)
  if port ~= config.modem_port then return end
  monitor.handleMessage(sender, raw)
  uiState.dirty = true
end

-- ─── Draw frame ───────────────────────────────────────────────────────────

local function draw()
  local planets = registry.getPlanetList()

  if uiState.view == VIEW.PLANETS then
    gui.drawPlanetList(planets, uiState.planet_sel, uiState.planet_scroll)

  elseif uiState.view == VIEW.DETAIL then
    local p = registry.get(uiState.detail_addr)
    if p then
      gui.drawPlanetDetail(p, uiState.machine_sel, uiState.machine_scroll)
    else
      goBack()
    end

  elseif uiState.view == VIEW.LOG then
    gui.drawLog(logger.getLines(), uiState.log_scroll)
  end

  -- Notify overlay
  if uiState.notify then
    if os.clock() < uiState.notify.until_t then
      gui.notify(uiState.notify.msg, uiState.notify.color)
    else
      uiState.notify = nil
      uiState.dirty  = true
    end
  end

  uiState.dirty    = false
  uiState.last_draw = os.clock()
end

-- ─── Init ────────────────────────────────────────────────────────────────

local function init()
  if not gui.init() then
    io.write("[ERROR] No GPU/Screen found.\n")
    return false
  end

  local ok, err = monitor.init()
  if not ok then
    io.write("[ERROR] " .. (err or "Monitor init failed") .. "\n")
    return false
  end

  registry.load()
  logger.load()

  -- Запросить регистрацию у всех уже запущенных Node'ов
  monitor.broadcastRegister()

  return true
end

-- ─── Main Loop ────────────────────────────────────────────────────────────

local function mainLoop()
  local keyListener   = event.listen("key_down",      onKey)
  local modemListener = event.listen("modem_message",  onModem)

  while _running do
    local now = os.clock()

    -- Авто-пинг
    if monitor.shouldAutoPing() then
      monitor.pingAll()
    end

    -- Проверка таймаутов (Ring Down)
    monitor.checkTimeouts()

    -- Перерисовка
    if uiState.dirty or (now - uiState.last_draw >= config.gui_refresh) then
      draw()
    end

    -- Периодическое сохранение реестра
    registry.flush()

    os.sleep(0.05)
  end

  event.ignore("key_down",     keyListener)
  event.ignore("modem_message", modemListener)

  -- Восстановить экран
  if component.isAvailable("gpu") then
    local gpu = component.gpu
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
    local gw, gh = gpu.getResolution()
    gpu.fill(1, 1, gw, gh, " ")
    gpu.set(1, 1, "Planet Monitor stopped.")
  end
end

-- ─── Entry Point ──────────────────────────────────────────────────────────

if init() then
  mainLoop()
else
  print("Initialization failed.")
  os.exit(1)
end
