-- =============================================================================
-- hub/main.lua — Entry Point: Polling Loop + GUI
-- =============================================================================

package.path = "/home/hub/?.lua;" .. package.path

local component = require("component")
local event     = require("event")
local os        = require("os")
local computer  = require("computer")

local config   = require("config")
local registry = require("registry")
local mch      = require("machines")
local logger   = require("logger")
local gui      = require("gui")
local stats    = require("stats")

-- ─── UI State ─────────────────────────────────────────────────────────────

local VIEW = { PLANETS = 1, DETAIL = 2, LOG = 3 }

local ui = {
  view          = VIEW.PLANETS,
  planet_sel    = 1,
  planet_scroll = 1,
  machine_sel   = 1,
  machine_scroll= 1,
  log_scroll    = nil,
  detail_planet = nil,   -- имя планеты в detail-view
  dirty         = true,
  notify        = nil,   -- { msg, color, until_t }
  last_draw     = 0,
  sensor_data       = nil,
  last_sensor_poll  = 0,
  last_sensor_maddr = nil,
  lsc_addr          = nil, -- адрес лапотронника
}

local _running    = true
local _last_poll  = 0

-- Предварительное объявление для разрешения кольцевых зависимостей
local runSetup, runUpdate, safeOnKey, safeOnTouch

-- ─── Polling ──────────────────────────────────────────────────────────────

local function pollAll()
  for pname, planet in pairs(registry.getAll()) do
    if pname ~= "__ignored__" and pname ~= "__system__" then
      local all_missing = (#planet.machines > 0)
      local any_offline = false
      local any_problem = false
      local prev_status = planet.status

      for _, m in ipairs(planet.machines) do
        local prev_active = m.active
        local active, err = mch.getStatus(m)
        m.active = active
        m.error  = err

        if err == "RING_DOWN" then
          -- компонент полностью исчез из OC-сети, all_missing остаётся true
        else
          all_missing = false   -- компонент виден в сети, значит кольцо цело
        end

        if err == "MAINTENANCE" then
          any_problem = true
        end

        if not active then
          any_offline = true
        end

        -- Лог изменений статуса машины
        if prev_active ~= active then
          logger.log(pname, m.name, active and "ACTIVE" or "OFFLINE")
        end
      end

      -- Вычислить статус планеты
      local new_status
      if #planet.machines == 0 then
        new_status = "UNKNOWN"
      elseif all_missing then
        new_status = "RING_DOWN"
      elseif any_offline then
        new_status = "PARTIAL"
      elseif any_problem then
        new_status = "MAINTENANCE"
      else
        new_status = "OK"
        planet.last_ok = os.time()
      end

      if prev_status ~= new_status then
        planet.status = new_status
        logger.log(pname, nil, prev_status .. " -> " .. new_status)
      end
    end
  end

  registry.save()
  ui.dirty = true
end

-- ─── Helpers ──────────────────────────────────────────────────────────────

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function navigate(sel, scroll, delta, count, visible)
  sel = clamp(sel + delta, 1, math.max(1, count))
  if sel < scroll then scroll = sel end
  if sel >= scroll + visible then scroll = sel - visible + 1 end
  return sel, scroll
end

local function setNotify(msg, color)
  ui.notify = { msg = msg, color = color or 0xFFAA00, until_t = computer.uptime() + 3 }
  ui.dirty  = true
end

local LIST_H = 15  -- приблизительно, gui.lua уточняет

-- ─── Actions ──────────────────────────────────────────────────────────────

local function doRestartMachine()
  local p = registry.get(ui.detail_planet)
  if not p then return end
  if p.status == "RING_DOWN" then
    setNotify("Ring DOWN! Cannot restart.", 0xFF2244); return
  end
  local m = (p.machines or {})[ui.machine_sel]
  if not m then return end
  local ok, msg = mch.restart(m)
  logger.log(p.name, m.name, "RESTART -> " .. (ok and "OK: " or "FAIL: ") .. msg)
  setNotify((ok and "[OK] " or "[FAIL] ") .. msg, ok and 0x00DD55 or 0xFF2244)
end

local function doToggleMachine()
  local p = registry.get(ui.detail_planet)
  if not p then return end
  if p.status == "RING_DOWN" then
    setNotify("Ring DOWN! Cannot toggle.", 0xFF2244); return
  end
  local m = (p.machines or {})[ui.machine_sel]
  if not m then return end
  local ok, msg = mch.toggle(m)
  -- Полный момент идёт в лог (F4 → Log)
  logger.log(p.name, m.name, "TOGGLE -> " .. (ok and "OK: " or "FAIL: ") .. msg)
  -- В уведомлении — короткая версия (макс 40 симв)
  local short = msg:len() > 40 and (msg:sub(1, 38) .. "...") or msg
  setNotify((ok and "[OK] " or "[ERR] ") .. short, ok and 0x00DD55 or 0xFF2244)
  if ok then
    local active, err = mch.getStatus(m)
    m.active = active
    m.error  = err
    ui.dirty = true
  end
end

local function doRestartAll()
  local pname = (ui.view == VIEW.DETAIL) and ui.detail_planet
    or (registry.getPlanetList()[ui.planet_sel] or {}).name
  if not pname then return end
  local p = registry.get(pname)
  if not p then return end
  if p.status == "RING_DOWN" then setNotify("Ring DOWN!", 0xFF2244); return end
  local count = 0
  for _, m in ipairs(p.machines or {}) do
    if not m.active then
      local ok, msg = mch.restart(m)
      logger.log(pname, m.name, "RESTART -> " .. (ok and "OK" or "FAIL: "..msg))
      if ok then count = count + 1 end
    end
  end
  setNotify(string.format("Restart ALL: %d sent", count))
end

local function openDetail()
  local planets = registry.getPlanetList()
  local p = planets[ui.planet_sel]
  if not p then return end
  ui.detail_planet  = p.name
  ui.machine_sel    = 1
  ui.machine_scroll = 1
  ui.view           = VIEW.DETAIL
  ui.dirty          = true
end

-- ─── Keyboard & Mouse Handlers ──────────────────────────────────────────

local function onKey(_, _, char, code)
  -- Q → выход (code 16 или Esc = 1)
  if code == 16 or code == 1 then
    _running = false; return
  end
  -- B → назад (code 48 или Backspace = 14)
  if code == 48 or code == 14 then
    ui.view = VIEW.PLANETS; ui.dirty = true; return
  end
  -- F4 → лог (code 62)
  if code == 62 then
    ui.log_scroll = nil; ui.view = VIEW.LOG; ui.dirty = true; return
  end
  -- F3 → poll сейчас (code 61)
  if code == 61 then
    pollAll(); setNotify("Refreshed", 0x4477FF); return
  end
  -- A → restart all (code 30) - оставим A, но только в VIEW.PLANETS/DETAIL
  if code == 30 then
    doRestartAll(); return
  end
  -- T → toggle (скан-код 20, char 116=t 84=T)
  if (code == 20 or char == 116 or char == 84) and ui.view == VIEW.DETAIL then
    doToggleMachine(); return
  end
  -- F2 → update + reboot (code 60)
  if code == 60 and ui.view == VIEW.PLANETS then
    runUpdate(); return
  end
  -- F1 → setup (code 59)
  if code == 59 and ui.view == VIEW.PLANETS then
    runSetup(); return
  end
  -- ENTER
  if code == 28 then
    if ui.view == VIEW.PLANETS then openDetail()
    elseif ui.view == VIEW.DETAIL then doRestartMachine()
    end
    return
  end

  -- Навигация
  local UP   = (code == 200)
  local DOWN = (code == 208)
  local HOME = (code == 199)
  local ENDK = (code == 207)

  if ui.view == VIEW.PLANETS and (UP or DOWN) then
    local planets = registry.getPlanetList()
    ui.planet_sel, ui.planet_scroll =
      navigate(ui.planet_sel, ui.planet_scroll, UP and -1 or 1, #planets, LIST_H)
    ui.dirty = true

  elseif ui.view == VIEW.DETAIL and (UP or DOWN) then
    local p = registry.get(ui.detail_planet)
    local cnt = p and #(p.machines or {}) or 0
    ui.machine_sel, ui.machine_scroll =
      navigate(ui.machine_sel, ui.machine_scroll, UP and -1 or 1, cnt, LIST_H)
    ui.dirty = true

  elseif ui.view == VIEW.LOG then
    local lines = logger.getLines()
    local cnt   = #lines
    if UP   then ui.log_scroll = math.max(1, (ui.log_scroll or cnt) - 1) end
    if DOWN then ui.log_scroll = math.min(cnt, (ui.log_scroll or cnt) + 1) end
    if HOME then ui.log_scroll = 1 end
    if ENDK then ui.log_scroll = nil end
    ui.dirty = true
  end
end

local function onTouch(_, _, x, y, button, playerName)
  if ui.notify then
    ui.notify = nil
    ui.dirty = true
    return
  end
  if button ~= 0 then return end -- Only left click
  
  -- Footer click (y == H)
  if y == H then
    if ui.view == VIEW.PLANETS then
      if x >= 19 and x <= 34 then onKey(nil, nil, nil, 28) -- Enter (Details)
      elseif x >= 35 and x <= 49 then onKey(nil, nil, string.byte("a"), nil) -- A (RestartAll)
      elseif x >= 50 and x <= 61 then onKey(nil, nil, string.byte("r"), nil) -- R (Refresh)
      elseif x >= 62 and x <= 69 then onKey(nil, nil, string.byte("l"), nil) -- L (Log)
      elseif x >= 70 then onKey(nil, nil, string.byte("s"), nil) -- S (Setup)
      end
    elseif ui.view == VIEW.DETAIL then
      if x >= 11 and x <= 26 then onKey(nil, nil, nil, 28) -- Enter (Restart)
      elseif x >= 27 and x <= 37 then onKey(nil, nil, string.byte("t"), nil) -- T (Toggle)
      elseif x >= 38 and x <= 53 then onKey(nil, nil, string.byte("a"), nil) -- A (RestartAll)
      elseif x >= 2 and x <= 10 then onKey(nil, nil, string.byte("b"), nil) -- B (Back)
      end
    elseif ui.view == VIEW.LOG then
      if x >= 15 and x <= 22 then onKey(nil, nil, nil, 199) -- Home
      elseif x >= 23 and x <= 33 then onKey(nil, nil, nil, 207) -- End
      elseif x >= 34 then onKey(nil, nil, string.byte("b"), nil) -- B (Back)
      end
    end
    return
  end

  -- List click (y >= 6 and y < H-1)
  if y >= 6 and y < H - 1 then
    local list_idx = y - 6
    if ui.view == VIEW.PLANETS then
      local planets = registry.getPlanetList()
      local target = ui.planet_scroll + list_idx
      if target > 0 and target <= #planets then
        ui.planet_sel = target
        openDetail()
      end
    elseif ui.view == VIEW.DETAIL then
      local p = registry.get(ui.detail_planet)
      if p then
        local cnt = #(p.machines or {})
        local target = ui.machine_scroll + list_idx
        if target > 0 and target <= cnt then
          ui.machine_sel = target
          doRestartMachine()
        end
      end
    end
  end
end

safeOnTouch = function(...)
  local ok, err = pcall(onTouch, ...)
  if not ok then logger.log("SYSTEM", "ERROR", "Touch error: " .. tostring(err)) end
end

safeOnKey = function(...)
  local ok, err = pcall(onKey, ...)
  if not ok then logger.log("SYSTEM", "ERROR", "Key error: " .. tostring(err)) end
end

runSetup = function()
  if component.isAvailable("gpu") then
    local gpu = component.gpu
    gpu.setBackground(0x000000); gpu.setForeground(0xFFFFFF)
    local w,h = gpu.getResolution()
    gpu.fill(1,1,w,h," ")
  end
  -- Отключаем слушатели на время работы другого скрипта
  event.ignore("key_down", safeOnKey)
  event.ignore("touch", safeOnTouch)

  local shell = require("shell")
  local ok, err = pcall(shell.execute, "/home/hub/setup.lua")
  if not ok then
    io.write("[ERROR] Setup failed: " .. tostring(err) .. "\n")
  end

  -- Возвращаем слушатели
  event.listen("key_down", safeOnKey)
  event.listen("touch", safeOnTouch)

  package.loaded["config"] = nil
  config = require("config")
  
  -- Сбросить закешированный lsc_addr
  ui.lsc_addr = config.lsc_address
  
  registry.load()
  ui.dirty = true
end

runUpdate = function()
  setNotify("Updating... please wait", 0x4477FF)
  event.ignore("key_down", safeOnKey)
  event.ignore("touch",    safeOnTouch)

  if component.isAvailable("gpu") then
    local gpu = component.gpu
    gpu.setBackground(0x000000); gpu.setForeground(0xFFFFFF)
    local w, h = gpu.getResolution()
    gpu.fill(1, 1, w, h, " ")
    gpu.set(2, 2, "GTNH Planet Monitor -- Updating...")
    gpu.set(2, 3, "Downloading latest files from GitHub...")
  end

  local shell = require("shell")
  local ok, err = pcall(shell.execute, "/home/update_hub.lua")

  if component.isAvailable("gpu") then
    local gpu = component.gpu
    if ok then
      gpu.set(2, 5, "[OK] Update complete! Rebooting in 3s...")
    else
      gpu.set(2, 5, "[FAIL] " .. tostring(err))
      gpu.set(2, 6, "Rebooting anyway in 3 seconds...")
    end
  end

  os.sleep(3)
  computer.shutdown(true)  -- true = reboot
end

-- ─── Keyboard ─────────────────────────────────────────────────────────────


-- ─── Draw ─────────────────────────────────────────────────────────────────

local function draw()
  local planets = registry.getPlanetList()

  if ui.view == VIEW.PLANETS then
    gui.drawPlanetList(planets, ui.planet_sel, ui.planet_scroll, stats)
  elseif ui.view == VIEW.DETAIL then
    local p = registry.get(ui.detail_planet)
    if p then
      gui.drawPlanetDetail(p, ui.machine_sel, ui.machine_scroll, ui.sensor_data)
    else
      ui.view = VIEW.PLANETS
    end
  elseif ui.view == VIEW.LOG then
    gui.drawLog(logger.getLines(), ui.log_scroll)
  end

  if ui.notify then
    if computer.uptime() < ui.notify.until_t then
      gui.notify(ui.notify.msg, ui.notify.color)
    else
      ui.notify = nil; ui.dirty = true
    end
  end

  ui.dirty    = false
  ui.last_draw = computer.uptime()
end

-- ─── Init ────────────────────────────────────────────────────────────────

local function init()
  if not gui.init() then
    io.write("[ERROR] No GPU/Screen.\n"); return false
  end
  registry.load()
  logger.load()
  
  if config.lsc_address then
    logger.log("SYSTEM", nil, "LSC Address Loaded: " .. string.sub(config.lsc_address, 1, 8))
  else
    logger.log("SYSTEM", nil, "LSC Address: NOT CONFIGURED")
  end

  local planets = registry.getPlanetList()
  if #planets == 0 then
    -- Нет планет — запустить setup
    io.write("[INFO] No planets configured. Running setup...\n")
    os.sleep(1)
    runSetup()
    planets = registry.getPlanetList()
    if #planets == 0 then
      io.write("[WARN] Still no planets. Add machines via setup.\n")
    end
  end

  -- Сбросить все редстоун-выходы
  mch.resetAllRedstone(planets)

  -- Первый опрос
  pollAll()

  return true
end

-- ─── Main Loop ────────────────────────────────────────────────────────────

local function mainLoop()
  local keyListen = event.listen("key_down", safeOnKey)
  local touchListen = event.listen("touch", safeOnTouch)

  while _running do
    local now = computer.uptime()

    local ok, err = pcall(function()
      -- Обновление статистики (TPS, LSC)
      if ui.view == VIEW.PLANETS then
        local lsc_addr = registry.getLSC()
        if lsc_addr then
          ui.lsc_addr = lsc_addr
        else
          ui.lsc_addr = nil
          -- Авто-поиск если не настроено точечно
          local function check(addr)
            local p = component.proxy(addr)
            if p then
              local getS = p.getStoredEU or p.getEUStored
              local getM = p.getEUCapacity or p.getEUMax
              if getS and getM then return true end
            end
            return false
          end
          for addr, name in component.list("gt_machine") do
            if check(addr) then ui.lsc_addr = addr; break end
          end
        end
        stats.update(ui.lsc_addr)
      end

      -- Автополлинг сети
      if (now - _last_poll) >= config.poll_interval then
        pollAll()
        _last_poll = now
      end

      -- Асинхронный поллинг сенсоров для выделенной машины (раз в 1 сек)
      if ui.view == VIEW.DETAIL and ui.detail_planet then
        local p = registry.get(ui.detail_planet)
        if p and p.machines then
          local m = p.machines[ui.machine_sel]
          if m then
            if m.adapter_addr ~= ui.last_sensor_maddr or (now - ui.last_sensor_poll) >= 1.0 then
              ui.sensor_data = mch.getSensorData(m)
              ui.last_sensor_maddr = m.adapter_addr
              ui.last_sensor_poll = now
              ui.dirty = true
            end
          end
        end
      end

      -- Перерисовка
      if ui.dirty or (now - ui.last_draw) >= config.gui_refresh then
        draw()
      end
    end)
    
    if not ok then
      logger.log("SYSTEM", "ERROR", "Main loop error: " .. tostring(err))
      ui.dirty = true
    end

    os.sleep(0.05)
  end

  event.ignore("key_down", safeOnKey)
  event.ignore("touch", safeOnTouch)

  -- Восстановить терминал
  if component.isAvailable("gpu") then
    local gpu = component.gpu
    gpu.setBackground(0x000000); gpu.setForeground(0xFFFFFF)
    local w, h = gpu.getResolution()
    gpu.fill(1, 1, w, h, " ")
    gpu.set(1, 1, "Planet Monitor stopped.")
  end
end

-- ─── Entry ────────────────────────────────────────────────────────────────

if init() then
  mainLoop()
else
  io.write("Init failed.\n")
  os.exit(1)
end
