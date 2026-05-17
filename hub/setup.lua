



local component = require("component")
local event     = require("event")
local unicode   = require("unicode")
local os        = require("os")
local registry  = require("registry")
local mch       = require("machines")

local gpu = component.isAvailable("gpu") and component.gpu or nil
if not gpu then io.write("GPU not found!\n"); return end

local W, H = gpu.getResolution()



local theme = require("theme")
local C = theme.C

local config = {}
local config_path = "/home/hub/config.lua"



local function load_config()
  local fs = require("filesystem")
  local pwd = os.getenv("PWD") or ""
  if fs.exists(pwd .. "/config.lua") then
    config_path = pwd .. "/config.lua"
  elseif fs.exists("/home/hub/config.lua") then
    config_path = "/home/hub/config.lua"
  end
  if fs.exists(config_path) then
    local ok, cfg = pcall(dofile, config_path)
    if ok and type(cfg) == "table" then config = cfg end
  end
end

local function save_config()
  local f = io.open(config_path, "w")
  if not f then return end
  f:write("-- hub/config.lua\nlocal config = {}\n\n")
  f:write("config.poll_interval = " .. tostring(config.poll_interval or 10) .. "\n")
  f:write("config.lsc_address   = " .. (config.lsc_address and ('"' .. config.lsc_address .. '"') or "nil") .. "\n")
  f:write("config.gui_refresh   = " .. tostring(config.gui_refresh or 0.5) .. "\n")
  f:write("config.log_max_lines = " .. tostring(config.log_max_lines or 500) .. "\n")
  f:write('config.registry_file = "' .. (config.registry_file or "/home/planet_registry.json") .. '"\n')
  f:write('config.log_file      = "' .. (config.log_file or "/home/planet_log.txt") .. '"\n\n')
  f:write("return config\n")
  f:close()
end



local function gset(x, y, text, fg, bg) theme.gset(x, y, text, fg, bg) end
local function gfill(x, y, w, h, ch, fg, bg) theme.gfill(x, y, w, h, ch, fg, bg) end
local function pad(s, n) return theme.pad(s, n) end



local LEFT_W = 22

local function drawFrame()
  gfill(1, 1, W, H, " ", C.text, C.bg)


  gset(1, 1, "+" .. string.rep("-", W-2) .. "+", C.border, C.bg)

  gset(1, 2, "|", C.border, C.bg)
  local tag = "==[ GTNH PLANET MONITOR - SETUP ]"
  local fill = string.rep("=", math.max(0, W-2 - #tag))
  gset(2, 2, tag .. fill, C.title, C.bg)
  gset(W, 2, "|", C.border, C.bg)

  gset(1, 3, "|", C.border, C.bg)
  gfill(2, 3, W-2, 1, " ", C.dim, C.bg)
  gset(3, 3, "STATUS: Setup Wizard", C.dim, C.bg)
  gset(W, 3, "|", C.border, C.bg)

  gset(1, 4, "+" .. string.rep("-", W-2) .. "+", C.border, C.bg)


  for row = 5, H-3 do
    gset(1, row, "|", C.border, C.bg)
    gset(W, row, "|", C.border, C.bg)
  end


  for row = 4, H-3 do
    gset(LEFT_W + 1, row, "|", C.border, C.bg)
  end


  gset(2, 5, "MENU", C.dim, C.bg)
end

local function drawFooter(keys)
  gset(1, H-2, "+" .. string.rep("-", W-2) .. "+", C.border, C.bg)
  gfill(2, H-1, W-2, 1, " ", C.text, C.bg)
  gset(1, H-1, "|", C.border, C.bg)
  local x = 3
  for _, k in ipairs(keys) do
    if x >= W - 4 then break end
    gset(x, H-1, "[" .. k[1] .. "]", C.key, C.bg)
    x = x + #k[1] + 3
    gset(x, H-1, k[2], C.text, C.bg)
    x = x + #k[2] + 2
  end
  gset(W, H-1, "|", C.border, C.bg)
  gset(1, H, "+" .. string.rep("-", W-2) .. "+", C.border, C.bg)
end

local function clearRight()
  gfill(LEFT_W+2, 5, W-LEFT_W-2, H-7, " ", C.text, C.bg)

  for row = 5, H-3 do
    gset(W, row, "|", C.border, C.bg)
  end
end

local function drawMenu(items, sel)
  for i, item in ipairs(items) do
    local y = 5 + i
    if i == sel then
      gfill(2, y, LEFT_W-1, 1, " ", C.sel_fg, C.sel_bg)
      gset(3, y, item.label, C.sel_fg, C.sel_bg)
    else
      gfill(2, y, LEFT_W-1, 1, " ", C.text, C.bg)
      gset(3, y, item.label, C.text, C.bg)
    end
  end
end

local function rightHeader(txt)
  gset(LEFT_W+3, 5, txt, C.title, C.bg)
  gset(LEFT_W+3, 6, string.rep("-", W-LEFT_W-4), C.border, C.bg)
end



local function readInput(x, y, prompt, default)
  gset(x, y, prompt, C.dim, C.bg)
  local px = x + #prompt
  local input = default or ""
  local dirty = true
  while true do
    if dirty then
      gfill(px, y, W-px-1, 1, " ", C.text, C.bg)
      gset(px, y, input .. "_", C.title, C.bg)
      dirty = false
    end
    local ev = table.pack(event.pull())
    if ev[1] == "key_down" then
      local char, code = ev[3], ev[4]
      if code == 28 then
        gfill(px, y, W-px-1, 1, " ", C.text, C.bg)
        gset(px, y, input, C.ok, C.bg)
        return input
      elseif code == 14 and unicode.len(input) > 0 then
        input = unicode.sub(input, 1, -2)
        dirty = true
      elseif char > 31 then
        input = input .. unicode.char(char)
        dirty = true
      end
    elseif ev[1] == "clipboard" and ev[3] then
      input = input .. ev[3]
      dirty = true
    end
  end
end



local PLANET_LIST = {
  "[T0] Overworld", "[T1] Moon", "[T2] Mars", "[T2] Phobos", "[T2] Deimos",
  "[T3] Asteroids", "[T3] Ceres", "[T3] Europa", "[T3] Ganymede", "[T3] Callisto", "[T3] Ross 128 B",
  "[T4] Venus", "[T4] Mercury", "[T4] Io",
  "[T3] Jupiter", "[T5] Saturn", "[T5] Titan", "[T5] Enceladus", 
  "[T5] Uranus", "[T5] Miranda", "[T5] Oberon", "[T5] Ross128ba",
  "[T6] Neptune", "[T6] Triton", "[T6] Proteus",
  "[T7] Pluto", "[T7] Kuiper Belt", "[T7] Haumea", "[T7] Makemake", "[T7] Eris",
  "[T8] Proxima B", "[T8] Barnarda C", "[T8] Barnarda E", "[T8] Barnarda F",
  "[T8] Ross 128 C", "[T8] Tau Ceti F", "[T8] Tau Ceti B", "[T8] Tau Ceti C", "[T8] Tau Ceti D", "[T8] Tau Ceti E", "[T8] Tau Ceti G",
  "[T8] Kepler 22b", "[T8] Kepler 47c", "[T8] Kepler 62e", "[T8] Kepler 62f",
  "[T8] Sirius B", "[T8] Sirius C", "[T8] Centauri A", "[T8] Vega B", "[T8] Arcturus",
  "[T8] Antares", "[T8] Betelgeuse", "[T8] Rigel", "[T8] Aldebaran", "[T8] Polaris", 
  "[T9] Neper", "[T9] Horus", "[T9] Maahes", "[T9] Anubis", "[T9] Seth", "[T9] Mehen Belt"
}

local function pickPlanet(x, y, prompt)
  gset(x, y, prompt, C.dim, C.bg)
  local px = x + #prompt
  local input = ""
  local sel = 1
  local max_show = 5
  local dirty = true
  
  while true do
    local matches = {}
    local raw_map = {}
    
    if input ~= "" then
      local disp = input .. " [Custom]"
      table.insert(matches, disp)
      raw_map[disp] = input
    end
    
    local lower_input = input:lower()
    for _, name in ipairs(PLANET_LIST) do
      if input == "" or name:lower():find(lower_input, 1, true) then
        if name ~= input then
          table.insert(matches, name)
          raw_map[name] = name
        end
      end
    end
    
    if sel > #matches then sel = math.max(1, #matches) end
    if #matches == 0 then sel = 1 end
    
    if dirty then

      gfill(px, y, W-px-1, 1, " ", C.text, C.bg)
      gset(px, y, input .. "_", C.title, C.bg)
      

      for i = 1, max_show do
        local my = y + 1 + i
        gfill(x, my, W-x-1, 1, " ", C.text, C.bg)
        if i <= #matches then
          local name = matches[i]
          local label = "  " .. name
          if i == sel then
            label = "> " .. name
            gset(x, my, label, C.sel_fg, C.sel_bg)
          else
            gset(x, my, label, C.text, C.bg)
          end
        end
      end
      dirty = false
    end
    
    local ev = table.pack(event.pull())
    if ev[1] == "key_down" then
      local char, code = ev[3], ev[4]
      if code == 28 then
        local res = input
        if #matches > 0 and sel <= #matches then
          local selected = matches[sel]
          res = raw_map[selected] or input
        end

        for i = 1, max_show do
          gfill(x, y + 1 + i, W-x-1, 1, " ", C.text, C.bg)
        end
        gfill(px, y, W-px-1, 1, " ", C.text, C.bg)
        gset(px, y, res, C.ok, C.bg)
        return res
      elseif code == 14 and unicode.len(input) > 0 then
        input = unicode.sub(input, 1, -2)
        sel = 1
        dirty = true
      elseif code == 200 then
        if sel > 1 then sel = sel - 1; dirty = true end
      elseif code == 208 then
        if sel < #matches and sel < max_show then sel = sel + 1; dirty = true end
      elseif char > 31 then
        input = input .. unicode.char(char)
        sel = 1
        dirty = true
      end
    elseif ev[1] == "clipboard" and ev[3] then
      input = input .. ev[3]
      sel = 1
      dirty = true
    end
  end
end



local function buildTaken()
  local ta = {}
  for _, p in pairs(registry.getAll()) do
    for _, m in ipairs(p.machines or {}) do
      ta[m.adapter_addr] = p.name .. "/" .. m.name
    end
  end
  return ta
end

local function viewScan()
  local rx = LEFT_W + 3
  clearRight()
  rightHeader("--- SCANNING NETWORK ---")
  gset(rx, 8, "Scanning...", C.dim, C.bg)

  local adapters = mch.scanNetwork()
  local taken_a  = buildTaken()

  local free_a = {}
  for _, gm in ipairs(adapters) do
    if not taken_a[gm.addr] and not registry.isIgnored(gm.addr)
       and gm.addr ~= registry.getLSC() then
      table.insert(free_a, gm)
    end
  end

  clearRight()
  rightHeader("--- SCAN RESULTS ---")

  if #free_a == 0 then
    gset(rx, 8, "No unregistered GT machines found.", C.warn, C.bg)
    gset(rx, 10, "Press Enter to return...", C.dim, C.bg)
    drawFooter({{"Enter", "Back"}})
    while true do
      local _, _, _, code = event.pull("key_down")
      if code == 28 or code == 1 then return end
    end
  end

  gset(rx, 8, "Found " .. #free_a .. " unregistered machine(s)", C.ok, C.bg)

  for i, gm in ipairs(free_a) do
    clearRight()
    rightHeader("--- MACHINE " .. i .. "/" .. #free_a .. " ---")
    gset(rx, 8,  "Type:    " .. pad(gm.name, 40), C.text, C.bg)
    gset(rx, 9,  "Address: " .. string.sub(gm.addr, 1, 20) .. "...", C.dim, C.bg)
    gset(rx, 11, "(y) Register   (n) Skip   (i) Ignore   (l) Set as LSC", C.dim, C.bg)
    drawFooter({{"Y", "Register"}, {"N", "Skip"}, {"I", "Ignore"}, {"L", "LSC"}, {"Esc", "Cancel"}})

    local ans = readInput(rx, 12, "> ", "")
    local la  = ans:lower()

    if la == "y" then
      local pname = pickPlanet(rx, 14, "Planet name: ")
      local mname = readInput(rx, 15, "Machine name: ", gm.name)
      registry.addPlanet(pname)
      registry.addMachine(pname, { name = mname, adapter_addr = gm.addr })
      gset(rx, 17, "[OK] Registered!", C.ok, C.bg)
      os.sleep(1)
    elseif la == "i" then
      registry.ignoreAdapter(gm.addr)
      gset(rx, 14, "[OK] Ignored.", C.dim, C.bg)
      os.sleep(1)
    elseif la == "l" then
      registry.setLSC(gm.addr)
      gset(rx, 14, "[OK] Set as LSC.", C.ok, C.bg)
      os.sleep(1.5)
    elseif la == "n" then

    else

      return
    end
  end
end



local function viewDatabase()
  local rx     = LEFT_W + 3
  local sel_p  = 1
  local in_db  = true
  local scroll_p = 1
  local list_h = H - 12

  while in_db do
    local planets = registry.getPlanetList()
    clearRight()
    rightHeader("--- DATABASE ---")

    if #planets == 0 then
      gset(rx, 8, "Registry is empty.", C.dim, C.bg)
      gset(rx, 10, "Press Enter to return...", C.dim, C.bg)
      drawFooter({{"Enter", "Back"}})
      while true do
        local _, _, _, code = event.pull("key_down")
        if code == 28 or code == 1 then return end
      end
    end

    for i = 0, list_h - 1 do
      local idx = scroll_p + i
      local y = 8 + i
      if idx <= #planets then
        local p = planets[idx]
        local label = pad(string.format("%02d  %s  (%d machines)", idx, p.name, #(p.machines or {})), W-LEFT_W-4)
        if idx == sel_p then
          gfill(rx, y, W-LEFT_W-3, 1, " ", C.sel_fg, C.sel_bg)
          gset(rx, y, label, C.sel_fg, C.sel_bg)
        else
          gfill(rx, y, W-LEFT_W-3, 1, " ", C.text, C.bg)
          gset(rx, y, label, C.text, C.bg)
        end
      else
        gfill(rx, y, W-LEFT_W-3, 1, " ", C.text, C.bg)
      end
    end

    drawFooter({{"Up/Dn", "Move"}, {"Enter", "Machines"}, {"Del", "Delete"}, {"B", "Back"}})

    local ev = table.pack(event.pull())
    if ev[1] == "key_down" then
      local code = ev[4]
      if code == 200 then
        if sel_p > 1 then
          sel_p = sel_p - 1
          if sel_p < scroll_p then scroll_p = sel_p end
        end
      elseif code == 208 then
        if sel_p < #planets then
          sel_p = sel_p + 1
          if sel_p >= scroll_p + list_h then scroll_p = sel_p - list_h + 1 end
        end
      elseif code == 14 or code == 1 or code == 48 then in_db = false
      elseif code == 211 then
        local p = planets[sel_p]
        clearRight()
        rightHeader("--- DELETE PLANET? ---")
        gset(rx, 8, "Delete planet: " .. p.name .. "?", C.warn, C.bg)
        local ans = readInput(rx, 10, "Confirm (y/n): ", "")
        if ans:lower() == "y" then
          registry.removePlanet(p.name)
          if sel_p > #registry.getPlanetList() then sel_p = math.max(1, #registry.getPlanetList()) end
        end
      elseif code == 28 then
        local p  = planets[sel_p]
        local sm = 1
        local scroll_m = 1
        local in_machines = true
        while in_machines do
          clearRight()
          rightHeader("--- " .. p.name:upper() .. " ---")
          local mlist = p.machines or {}
          
          for j = 0, list_h - 1 do
            local idx = scroll_m + j
            local y = 8 + j
            if idx <= #mlist then
              local m = mlist[idx]
              local ml = pad(string.format("%02d  %s  [%s]", idx, m.name, m.adapter_addr:sub(1,8)), W-LEFT_W-4)
              if idx == sm then
                gfill(rx, y, W-LEFT_W-3, 1, " ", C.sel_fg, C.sel_bg)
                gset(rx, y, ml, C.sel_fg, C.sel_bg)
              else
                gfill(rx, y, W-LEFT_W-3, 1, " ", C.text, C.bg)
                gset(rx, y, ml, C.text, C.bg)
              end
            else
              gfill(rx, y, W-LEFT_W-3, 1, " ", C.text, C.bg)
            end
          end
          
          if #mlist == 0 then gset(rx, 8, "No machines.", C.dim, C.bg) end
          drawFooter({{"Up/Dn", "Move"}, {"R", "Rename"}, {"Del", "Delete"}, {"B", "Back"}})

          local mev = table.pack(event.pull())
          if mev[1] == "key_down" then
            local mc = mev[4]
            if mc == 200 then
              if sm > 1 then
                sm = sm - 1
                if sm < scroll_m then scroll_m = sm end
              end
            elseif mc == 208 then
              if sm < #mlist then
                sm = sm + 1
                if sm >= scroll_m + list_h then scroll_m = sm - list_h + 1 end
              end
            elseif mc == 1 or mc == 14 or mc == 48 then in_machines = false
            elseif mc == 19 and mlist[sm] then
              local m = mlist[sm]
              local nn = readInput(rx, H-4, "New name: ", m.name)
              if nn ~= "" then m.name = nn; registry.save() end
            elseif mc == 211 and mlist[sm] then
              local m = mlist[sm]
              local ans = readInput(rx, H-4, "Delete " .. m.name .. "? (y/n): ", "")
              if ans:lower() == "y" then
                registry.removeMachine(p.name, m.adapter_addr)
                if sm > #(p.machines or {}) then sm = math.max(1, #(p.machines or {})) end
              end
            end
          end
        end
      end
    end
  end
end



local MENU_ITEMS = {
  { label = "Scan New Machines", fn = viewScan     },
  { label = "Manage Database",   fn = viewDatabase },
  { label = "Exit Setup",        fn = function() return "exit" end },
}

local function run()
  load_config()
  registry.load()
  drawFrame()
  drawMenu(MENU_ITEMS, 1)
  drawFooter({{"Up/Dn", "Move"}, {"Enter", "Select"}, {"Esc", "Exit"}})

  local sel = 1
  while true do
    drawMenu(MENU_ITEMS, sel)
    local ev = table.pack(event.pull())
    if ev[1] == "key_down" then
      local code = ev[4]
      if code == 200 and sel > 1 then sel = sel - 1
      elseif code == 208 and sel < #MENU_ITEMS then sel = sel + 1
      elseif code == 1 then break
      elseif code == 28 or code == 205 then
        local res = MENU_ITEMS[sel].fn()
        if res == "exit" then break end

        drawFrame()
        drawMenu(MENU_ITEMS, sel)
        drawFooter({{"Up/Dn", "Move"}, {"Enter", "Select"}, {"Esc", "Exit"}})
      end
    elseif ev[1] == "touch" then
      local tx, ty = ev[3], ev[4]
      if tx <= LEFT_W then
        for i, _ in ipairs(MENU_ITEMS) do
          if ty == 5 + i then
            sel = i
            local res = MENU_ITEMS[sel].fn()
            if res == "exit" then goto done end
            drawFrame()
            drawMenu(MENU_ITEMS, sel)
            drawFooter({{"Up/Dn", "Move"}, {"Enter", "Select"}, {"Esc", "Exit"}})
            break
          end
        end
      end
    end
  end
  ::done::

  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, W, H, " ")
end

local ok, err = pcall(run)
if not ok then
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFF2244)
  gpu.fill(1, 1, W, H, " ")
  gpu.set(1, 1, "SETUP ERROR:")
  gpu.set(1, 3, tostring(err))
  gpu.set(1, H, "Press any key...")
  event.pull("key_down")
end
