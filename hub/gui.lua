-- =============================================================================
-- hub/gui.lua — Premium GUI with Two-Column Layout and Stats Panel
-- =============================================================================

local component = require("component")
local computer  = require("computer")

local gui = {}

local _gpu = nil
local W, H = 80, 25

-- ─── Color Palette ─────────────────────────────────────────────────────────

local C = {
  bg        = 0x000000,
  header_bg = 0x111111,
  sel_bg    = 0x333333,
  sel_fg    = 0xFFFFFF,
  text      = 0xCCCCCC,
  dim       = 0x666666,
  border    = 0x444444,
  title     = 0xFFFFFF,
  key       = 0xFFAA00,
  key_bg    = 0x111111,
  
  ok        = 0x00FF88,
  warn      = 0xFFAA00,
  ring_down = 0xFF4422,
  unknown   = 0x888888,
  partial   = 0x44AAFF
}

local STATUS_COLOR = {
  OK          = C.ok,
  PARTIAL     = C.partial,
  MAINTENANCE = C.warn,
  RING_DOWN   = C.ring_down,
  UNKNOWN     = C.unknown
}

local STATUS_LABEL = {
  OK          = "OK",
  PARTIAL     = "OFFLINE",
  MAINTENANCE = "PROBLEM",
  RING_DOWN   = "RING DOWN",
  UNKNOWN     = "UNKNOWN"
}

-- ─── Internal Helpers ──────────────────────────────────────────────────────

local function g_set(x, y, text, fg, bg)
  if fg then _gpu.setForeground(fg) end
  if bg then _gpu.setBackground(bg) end
  _gpu.set(x, y, text)
end

local function g_fill(x, y, w, h, char, fg, bg)
  if fg then _gpu.setForeground(fg) end
  if bg then _gpu.setBackground(bg) end
  _gpu.fill(x, y, w, h, char)
end

local function pad(str, len)
  str = tostring(str)
  if #str > len then return str:sub(1, len-1) .. "…" end
  return str .. string.rep(" ", len - #str)
end

local function drawHeader(title, subtitle)
  g_fill(1, 1, W, 1, " ", C.title, C.header_bg)
  g_set(math.floor((W - #title)/2), 1, title, C.title, C.header_bg)
  
  g_fill(1, 2, W, 2, " ", C.dim, C.bg)
  if subtitle then
    g_set(2, 2, subtitle, C.dim, C.bg)
  end
  g_set(1, 3, string.rep("═", W), C.border, C.bg)
end

local function drawFooter(keys)
  g_fill(1, H, W, 1, " ", C.dim, C.key_bg)
  local x = 2
  for _, k in ipairs(keys) do
    if x >= W - 5 then break end
    g_set(x, H, "[" .. k[1] .. "]", C.key, C.key_bg)
    x = x + #k[1] + 2
    g_set(x, H, k[2], C.dim, C.key_bg)
    x = x + #k[2] + 2
  end
end

local function format_energy(v)
  local abs_v = math.abs(v)
  if abs_v >= 1e12 then return string.format("%.1fT", v / 1e12) end
  if abs_v >= 1e9  then return string.format("%.1fG", v / 1e9) end
  if abs_v >= 1e6  then return string.format("%.1fM", v / 1e6) end
  if abs_v >= 1e3  then return string.format("%.1fk", v / 1e3) end
  return string.format("%d", v)
end

local function timeAgo(t)
  if not t then return "never" end
  local diff = (computer.uptime() - (t / 72)) -- очень грубо, если t это os.time
  -- В данном скрипте мы используем computer.uptime() для last_ok в некоторых местах
  -- Если t > uptime, значит это os.time.
  if t > computer.uptime() then
     return "active"
  end
  local sec = computer.uptime() - t
  if sec < 60 then return math.floor(sec) .. "s" end
  return math.floor(sec/60) .. "m"
end

-- ─── API ───────────────────────────────────────────────────────────────────

function gui.init()
  if not component.isAvailable("gpu") then return false end
  _gpu = component.gpu
  _gpu.setDepth(_gpu.maxDepth())
  W, H = _gpu.getResolution()
  g_fill(1, 1, W, H, " ", C.text, C.bg)
  return true
end

function gui.getSize() return W, H end

function gui.drawPlanetList(planets, sel, scroll, stats)
  local count = #planets
  drawHeader(
    "PLANET MULTIBLOCK MONITOR",
    count == 0 and "No planets registered yet." or ("Monitoring " .. count .. " planet(s)")
  )

  local HY = 4
  local list_h = 10 
  local col_w = math.floor(W / 2) - 1

  -- Headers
  g_fill(1, HY, W, 1, " ", C.dim, C.header_bg)
  g_set( 2, HY, "# Planet      Status", C.dim, C.header_bg)
  g_set(col_w + 4, HY, "# Planet      Status", C.dim, C.header_bg)
  g_fill(1, HY+1, W, 1, string.rep("-", W), C.border, C.bg)

  local LIST_Y = HY + 2
  scroll = scroll or 1

  for i = 0, list_h - 1 do
    local ry = LIST_Y + i
    
    -- Left Col
    local idx1 = scroll + i
    if idx1 <= count then
      local p = planets[idx1]
      local isSel = (idx1 == sel)
      local bg = isSel and C.sel_bg or C.bg
      local fg = isSel and C.sel_fg or C.text
      local st = p.status or "UNKNOWN"
      local scol = STATUS_COLOR[st] or C.unknown
      
      g_set(2, ry, string.format("%2d ", idx1), C.dim, bg)
      g_set(5, ry, pad(p.name or "?", 11), fg, bg)
      g_set(17, ry, pad(STATUS_LABEL[st] or st, 10), scol, bg)
      if isSel then g_fill(1, ry, 1, 1, " ", fg, bg); g_fill(col_w+1, ry, 1, 1, " ", fg, bg) end
    else
      g_fill(1, ry, col_w, 1, " ", C.text, C.bg)
    end

    g_set(col_w + 2, ry, "│", C.border, C.bg)

    -- Right Col
    local idx2 = scroll + i + list_h
    if idx2 <= count then
      local p = planets[idx2]
      local isSel = (idx2 == sel)
      local bg = isSel and C.sel_bg or C.bg
      local fg = isSel and C.sel_fg or C.text
      local st = p.status or "UNKNOWN"
      local scol = STATUS_COLOR[st] or C.unknown
      
      g_set(col_w + 4, ry, string.format("%2d ", idx2), C.dim, bg)
      g_set(col_w + 7, ry, pad(p.name or "?", 11), fg, bg)
      g_set(col_w + 19, ry, pad(STATUS_LABEL[st] or st, 10), scol, bg)
    else
      g_fill(col_w + 3, ry, W - col_w - 2, 1, " ", C.text, C.bg)
    end
  end

  -- Stats Panel
  local STAT_Y = LIST_Y + list_h + 1
  g_fill(1, STAT_Y - 1, W, 1, string.rep("═", W), C.border, C.bg)
  
  -- Left: Server
  g_set(2, STAT_Y, "SERVER STATUS", C.title, C.bg)
  g_set(2, STAT_Y + 1, "TPS: ", C.dim, C.bg)
  if stats and stats.tps then
    local tps_c = (stats.tps > 18) and C.ok or (stats.tps > 15 and C.partial or C.ring_down)
    g_set(7, STAT_Y + 1, string.format("%.1f", stats.tps), tps_c, C.bg)
  else
    g_set(7, STAT_Y + 1, "20.0", C.ok, C.bg) -- default
  end

  -- Right: Energy
  g_set(col_w + 4, STAT_Y, "ENERGY STORAGE (LSC)", C.title, C.bg)
  if stats and stats.energy and stats.energy.max > 0 then
    local e = stats.energy
    local e_color = e.percent > 50 and C.ok or (e.percent > 20 and C.partial or C.ring_down)
    g_set(col_w + 4, STAT_Y + 1, "Stored: ", C.dim, C.bg)
    g_set(col_w + 12, STAT_Y + 1, format_energy(e.stored) .. " EU (" .. math.floor(e.percent) .. "%)", e_color, C.bg)
    g_set(col_w + 4, STAT_Y + 2, "Flow:   ", C.dim, C.bg)
    local diff_c = e.diff >= 0 and C.ok or C.ring_down
    g_set(col_w + 12, STAT_Y + 2, (e.diff >= 0 and "+" or "") .. format_energy(e.diff * 20) .. " EU/sec", diff_c, C.bg)
  else
    g_set(col_w + 4, STAT_Y + 1, "LSC not configured", C.dim, C.bg)
  end

  drawFooter({
    {"Up/Dn", "Navigate"},
    {"Enter", "Details"},
    {"F3",    "Refresh"},
    {"F4",    "Log"},
    {"F1",    "Setup"},
    {"Q",     "Quit"},
  })
end

function gui.drawPlanetDetail(planet, sel, scroll, sensor_data)
  local st    = planet.status or "UNKNOWN"
  local scol  = STATUS_COLOR[st] or C.unknown

  drawHeader(tostring(planet.name or "?") .. " [" .. (STATUS_LABEL[st] or st) .. "]")

  local HY = 4
  g_fill(1, HY, 45, 1, " ", C.dim, C.header_bg)
  g_set( 2, HY, "# Machine            Status", C.dim, C.header_bg)
  g_fill(1, HY+1, 45, 1, string.rep("-", 45), C.border, C.bg)

  g_fill(47, HY, W-46, 1, " ", C.title, C.header_bg)
  g_set(48, HY, "SENSOR DATA", C.title, C.header_bg)
  g_fill(47, HY+1, W-46, 1, string.rep("-", W-46), C.border, C.bg)

  local LIST_Y = HY + 2
  local LIST_H = H - LIST_Y - 1
  local machines = planet.machines or {}
  scroll = scroll or 1

  for i = 0, LIST_H - 1 do
    local idx = scroll + i
    local ry  = LIST_Y + i
    if idx > #machines then
      g_fill(1, ry, 45, 1, " ", C.text, C.bg)
    else
      local m = machines[idx]
      local isSel = (idx == sel)
      local bg = isSel and C.sel_bg or C.bg
      local fg = isSel and C.sel_fg or C.text
      local mcol = m.active and C.ok or C.ring_down
      local mst = m.active and "ACTIVE" or (m.error or "OFFLINE")

      g_set(1, ry, isSel and ">" or " ", fg, bg)
      g_set(2, ry, string.format("%2d ", idx), C.dim, bg)
      g_set(5, ry, pad(m.name or "?", 24), fg, bg)
      g_set(30, ry, pad(mst, 15), mcol, bg)
    end
    g_set(46, ry, "│", C.border, C.bg)
  end

  -- Sensor data
  if sensor_data then
    for i = 1, LIST_H do
      local line = sensor_data[i]
      if line then
        g_set(48, LIST_Y + i - 1, pad(line:gsub("§.", ""), W - 49), C.text, C.bg)
      else
        g_fill(48, LIST_Y + i - 1, W - 49, 1, " ", C.text, C.bg)
      end
    end
  end

  drawFooter({
    {"Backspace", "Back"},
    {"Enter", "Restart"},
    {"A", "Restart All"},
    {"Q", "Quit"}
  })
end

function gui.drawLog(lines, scroll)
  drawHeader("SYSTEM LOG")
  local LIST_Y = 4
  local LIST_H = H - LIST_Y - 1
  local count = #lines
  scroll = scroll or math.max(1, count - LIST_H + 1)

  for i = 0, LIST_H - 1 do
    local idx = scroll + i
    local ry = LIST_Y + i
    if idx <= count then
      g_set(2, ry, pad(lines[idx] or "", W - 3), C.text, C.bg)
    else
      g_fill(1, ry, W, 1, " ", C.text, C.bg)
    end
  end
  drawFooter({{"Backspace", "Back"}, {"Q", "Quit"}})
end

function gui.notify(msg, color)
  local len = #msg + 4
  local x = math.floor((W - len) / 2)
  local y = math.floor(H / 2)
  g_fill(x, y-1, len, 3, " ", color, C.header_bg)
  g_set(x + 2, y, msg, 0xFFFFFF, C.header_bg)
end

return gui
