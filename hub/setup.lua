-- =============================================================================
-- hub/setup.lua — Setup Wizard (Pair: Adapter <-> Redstone side)
-- =============================================================================
-- Запуск: lua /hub/setup.lua
-- Показывает ТОЛЬКО незарегистрированные адаптеры.
-- Каждый адаптер привязывается к планете + redstone-стороне.

local component = require("component")
local event     = require("event")
local unicode   = require("unicode")
local os        = require("os")
local registry  = require("registry")
local mch       = require("machines")

local gpu = component.isAvailable("gpu") and component.gpu or nil
if not gpu then
  io.write("GPU not found!\n")
  return
end

local W, H = gpu.getResolution()
local LEFT_W = 25

local C = {
  bg       = 0x0A0A1A,
  fg       = 0xDDDDDD,
  sel_bg   = 0x224488,
  sel_fg   = 0xFFFFFF,
  dim      = 0x556677,
  border   = 0x1E3A6E,
  title    = 0xFFFFFF,
  warn     = 0xFF5555,
  ok       = 0x55FF55,
}

local config = {}
local function load_config()
  if require("filesystem").exists("/home/hub/config.lua") then
    config = dofile("/home/hub/config.lua")
  end
end

local function save_config()
  local f = io.open("/home/hub/config.lua", "w")
  if f then
    f:write("-- GTNH Planet Monitor Config\n")
    f:write("local config = {}\n\n")
    f:write("config.poll_interval = " .. tostring(config.poll_interval or 10) .. "\n")
    f:write("config.lsc_address   = " .. (config.lsc_address and ("\"" .. config.lsc_address .. "\"") or "nil") .. "\n")
    f:write("config.gui_refresh   = 0.5\n")
    f:write("config.registry_file = \"/home/planet_registry.json\"\n")
    f:write("config.log_file      = \"/home/planet_log.txt\"\n\n")
    f:write("return config\n")
    f:close()
  end
end

local function clear()
  gpu.setBackground(C.bg)
  gpu.setForeground(C.fg)
  gpu.fill(1, 1, W, H, " ")
  -- Draw border
  gpu.setBackground(C.border)
  gpu.fill(LEFT_W + 1, 1, 1, H, " ")
  gpu.setBackground(C.bg)
end

local function header(txt)
  drawText(LEFT_W + 3, 2, txt, C.title)
end

local function drawText(x, y, text, fg, bg)
  gpu.setForeground(fg or C.fg)
  gpu.setBackground(bg or C.bg)
  gpu.set(x, y, text)
end

local function clearRight()
  gpu.setBackground(C.bg)
  gpu.fill(LEFT_W + 2, 1, W - LEFT_W - 1, H, " ")
end

-- =============================================================================
-- Simple Input Field
-- =============================================================================

local function readInput(x, y, prompt, default)
  gpu.setBackground(C.bg)
  gpu.setForeground(C.fg)
  gpu.set(x, y, prompt)
  local px = x + unicode.len(prompt)
  local input = default or ""
  
  while true do
    gpu.fill(px, y, W - px, 1, " ")
    gpu.setForeground(C.title)
    gpu.set(px, y, input .. "_")
    
    local e, _, char, code = event.pull("key_down")
    if char > 31 then
      input = input .. unicode.char(char)
    elseif code == 14 then -- Backspace
      if unicode.len(input) > 0 then
        input = unicode.sub(input, 1, -2)
      end
    elseif code == 28 then -- Enter
      gpu.fill(px, y, W - px, 1, " ")
      gpu.setForeground(C.ok)
      gpu.set(px, y, input)
      return input
    end
  end
end

-- =============================================================================
-- VIEWS
-- =============================================================================

local function buildTaken()
  local ta, tr = {}, {}
  for _, p in pairs(registry.getAll()) do
    for _, m in ipairs(p.machines or {}) do
      ta[m.adapter_addr] = p.name .. " / " .. m.name
      if m.redstone and m.redstone.addr then tr[m.redstone.addr] = p.name .. " / " .. m.name end
    end
  end
  return ta, tr
end

local function viewScan()
  clearRight()
  local rx = LEFT_W + 3
  drawText(rx, 2, "--- SCANNING NETWORK ---", C.title)
  
  local adapters = mch.scanNetwork()
  local taken_a, taken_r = buildTaken()
  
  local free_a = {}
  for _, gm in ipairs(adapters) do
    if not taken_a[gm.addr] then table.insert(free_a, gm) end
  end
  
  if #free_a == 0 then
    drawText(rx, 4, "No unregistered GT machines found.", C.warn)
    drawText(rx, 5, "Press Enter to return...")
    while true do
      local _, _, _, code = event.pull("key_down")
      if code == 28 then return end
    end
  end
  
  drawText(rx, 4, "Found " .. #free_a .. " unregistered machines:", C.ok)
  
  for i, gm in ipairs(free_a) do
    clearRight()
    drawText(rx, 2, "--- ADDING MACHINE (" .. i .. "/" .. #free_a .. ") ---", C.title)
    drawText(rx, 4, "Type:    " .. gm.name)
    drawText(rx, 5, "Address: " .. string.sub(gm.addr, 1, 16) .. "...")
    
    drawText(rx, 7, "Do you want to register this machine? (y/n)")
    local ans = readInput(rx, 8, "> ", "")
    if ans:lower() == "y" then
      local pname = readInput(rx, 10, "Planet name: ", "Earth")
      local mname = readInput(rx, 11, "Machine name: ", gm.name)
      
      registry.addPlanet(pname)
      registry.addMachine(pname, {
        name = mname,
        adapter_addr = gm.addr,
      })
      drawText(rx, 13, "Registered! (Redstone can be configured later)", C.ok)
      os.sleep(1)
    end
  end
end

local function setup_lsc()
  clearRight()
  header("CONFIGURE ENERGY MONITOR (LSC)")
  local rx = LEFT_W + 3
  
  local candidates = {}
  for addr, name in component.list() do
    local is_reg = false
    for _, p in ipairs(registry.getPlanetList()) do
      for _, m in ipairs(p.machines or {}) do
        if m.adapter_addr == addr then is_reg = true; break end
      end
    end
    
    if not is_reg and addr ~= component.gpu.address and addr ~= component.screen.address then
      table.insert(candidates, {addr = addr, name = name})
    end
  end

  if #candidates == 0 then
    drawText(rx, 4, "No available adapters found.", C.warn)
    drawText(rx, 5, "Press Enter to return...")
    while true do local _,_,_,c = event.pull("key_down") if c == 28 then break end end
    return
  end

  drawText(rx, 4, "Select the adapter for LSC:", C.title)
  for i, c in ipairs(candidates) do
    drawText(rx, 5+i, string.format("%d. %s", i, string.sub(c.addr, 1, 8)))
  end
  
  local ans = readInput(rx, 6+#candidates, "Selection (0 to cancel) > ", "")
  local idx = tonumber(ans)
  
  if idx and idx > 0 and idx <= #candidates then
    config.lsc_address = candidates[idx].addr
    save_config()
    drawText(rx, 8+#candidates, "[OK] LSC bound!", C.ok)
    os.sleep(1)
  end
end

local function viewDatabase()
  local rx = LEFT_W + 3
  local planets = registry.getPlanetList()
  
  local sel_p = 1
  
  while true do
    clearRight()
    drawText(rx, 2, "--- DATABASE MANAGEMENT ---", C.title)
    
    if #planets == 0 then
      drawText(rx, 4, "Registry is empty.", C.dim)
      drawText(rx, 6, "Press Enter to return...")
      while true do
        local _, _, _, code = event.pull("key_down")
        if code == 28 then return end
      end
    end
    
    -- Draw planets
    for i, p in ipairs(planets) do
      local y = 3 + i
      if i == sel_p then
        gpu.setBackground(C.sel_bg)
        gpu.setForeground(C.sel_fg)
        gpu.fill(rx, y, W - rx, 1, " ")
      else
        gpu.setBackground(C.bg)
        gpu.setForeground(C.fg)
      end
      gpu.set(rx, y, p.name .. " (" .. #(p.machines or {}) .. " machines)")
    end
    gpu.setBackground(C.bg)
    
    drawText(rx, H-2, "[Enter] Select  [Del] Delete  [B] Back", C.dim)
    
    local action = nil
    local ev = table.pack(event.pull())
    local e = ev[1]
    
    if e == "key_down" then
      local code = ev[4]
      if code == 200 then action = "up"
      elseif code == 208 then action = "down"
      elseif code == 14 or code == 1 or code == 48 then action = "back"
      elseif code == 211 then action = "delete"
      elseif code == 28 then action = "enter"
      end
    end
    
    if action == "up" and sel_p > 1 then sel_p = sel_p - 1
    elseif action == "down" and sel_p < #planets then sel_p = sel_p + 1
    elseif action == "back" then return
    elseif action == "delete" then
      local p = planets[sel_p]
      drawText(rx, H-4, "Delete " .. p.name .. "? (y/n)", C.warn)
      local ans = readInput(rx, H-3, "> ", "")
      if ans:lower() == "y" then
        registry.removePlanet(p.name)
        planets = registry.getPlanetList()
        if sel_p > #planets then sel_p = math.max(1, #planets) end
      end
    elseif action == "enter" then
      local p = planets[sel_p]
      local sel_m = 1
      local in_machines = true
      
      while in_machines do
        clearRight()
        drawText(rx, 2, "--- PLANET: " .. p.name .. " ---", C.title)
        
        if #(p.machines or {}) == 0 then
          drawText(rx, 4, "No machines.", C.dim)
        else
          for j, m in ipairs(p.machines) do
            local my = 3 + j
            if j == sel_m then
              gpu.setBackground(C.sel_bg); gpu.setForeground(C.sel_fg)
              gpu.fill(rx, my, W - rx, 1, " ")
            else
              gpu.setBackground(C.bg); gpu.setForeground(C.fg)
            end
            gpu.set(rx, my, m.name .. " (" .. string.sub(m.adapter_addr, 1, 8) .. ")")
          end
        end
        gpu.setBackground(C.bg)
        drawText(rx, H-2, "[R]ename  [Del] Delete  [B] Back", C.dim)
        
        local maction = nil
        local mev = table.pack(event.pull())
        local me = mev[1]
        
        if me == "key_down" then
          local mcode = mev[4]
          if mcode == 200 then maction = "up"
          elseif mcode == 208 then maction = "down"
          elseif mcode == 1 or mcode == 14 or mcode == 48 then maction = "back"
          elseif mcode == 19 then maction = "rename"
          elseif mcode == 211 then maction = "delete"
          end
        end
        
        if maction == "up" and sel_m > 1 then sel_m = sel_m - 1
        elseif maction == "down" and sel_m < #(p.machines or {}) then sel_m = sel_m + 1
        elseif maction == "back" then in_machines = false
        elseif maction == "rename" then
          local m = p.machines[sel_m]
          local newName = readInput(rx, H-4, "New name: ", m.name)
          if newName ~= "" then m.name = newName; registry.save() end
        elseif maction == "delete" then
          local m = p.machines[sel_m]
          drawText(rx, H-4, "Delete " .. m.name .. "? (y/n)", C.warn)
          local ans = readInput(rx, H-3, "> ", "")
          if ans:lower() == "y" then
            registry.removeMachine(p.name, m.adapter_addr)
            if sel_m > #(p.machines or {}) then sel_m = math.max(1, #(p.machines or {})) end
          end
        end
      end
    end
  end
end

-- =============================================================================
-- MAIN MENU
-- =============================================================================

local MENU_ITEMS = {
  { label = "Scan New Machines",  fn = viewScan },
  { label = "Configure LSC",      fn = setup_lsc },
  { label = "Manage Database",    fn = viewDatabase },
  { label = "Exit Setup Wizard",  fn = function() return "exit" end },
}

local function drawMainMenu(sel)
  for i, item in ipairs(MENU_ITEMS) do
    local y = 3 + (i * 2)
    if i == sel then
      gpu.setBackground(C.sel_bg)
      gpu.setForeground(C.sel_fg)
      gpu.fill(2, y, LEFT_W - 2, 1, " ")
    else
      gpu.setBackground(C.bg)
      gpu.setForeground(C.title)
    end
    gpu.set(4, y, item.label)
  end
  gpu.setBackground(C.bg)
end

local function run()
  registry.load()
  clear()
  
  drawText(2, 2, "GTNH Planet Monitor", C.ok)
  drawText(2, 3, "Setup Wizard", C.dim)
  
  local sel = 1
  drawMainMenu(sel)
  
  while true do
    local ev = table.pack(event.pull())
    local e = ev[1]
    
    if e == "key_down" then
      local code = ev[4]
      if code == 200 then -- Up
        if sel > 1 then sel = sel - 1; drawMainMenu(sel) end
      elseif code == 208 then -- Down
        if sel < #MENU_ITEMS then sel = sel + 1; drawMainMenu(sel) end
      elseif code == 28 or code == 205 then -- Enter or Right Arrow
        local res = MENU_ITEMS[sel].fn()
        if res == "exit" then break end
        -- Redraw full screen after returning
        clear()
        drawText(2, 2, "GTNH Planet Monitor", C.ok)
        drawText(2, 3, "Setup Wizard", C.dim)
        drawMainMenu(sel)
      end
    elseif e == "touch" then
      local tx, ty, tbtn = ev[3], ev[4], ev[5]
      if tbtn == 0 and tx <= LEFT_W then
        for i, _ in ipairs(MENU_ITEMS) do
          if ty == 3 + (i * 2) then
            sel = i
            drawMainMenu(sel)
            local res = MENU_ITEMS[sel].fn()
            if res == "exit" then return end
            clear()
            drawText(2, 2, "GTNH Planet Monitor", C.ok)
            drawText(2, 3, "Setup Wizard", C.dim)
            drawMainMenu(sel)
            break
          end
        end
      end
    end
  end
  
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, W, H, " ")
end

run()
