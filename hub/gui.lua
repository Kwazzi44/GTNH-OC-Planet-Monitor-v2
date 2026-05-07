-- =============================================================================
-- hub/gui.lua — Premium Solarized UI
-- =============================================================================

local component = require("component")
local computer  = require("computer")

local gui = {}

local _gpu = nil
local W, H = 80, 25

-- ─── Color Palette (Solarized Dark) ─────────────────────────────────────────

local C = {
  bg        = 0x002B36, -- Base03
  header_bg = 0x073642, -- Base02
  sel_bg    = 0x073642, -- Base02
  sel_fg    = 0x268BD2, -- Blue
  text      = 0x839496, -- Base0
  dim       = 0x586E75, -- Base01
  border    = 0x073642, -- Base02
  title     = 0x268BD2, -- Blue (Bright)
  key       = 0xB58900, -- Yellow
  key_bg    = 0x002B36,
  
  ok        = 0x859900, -- Green
  warn      = 0xB58900, -- Yellow
  ring_down = 0xDC322F, -- Red
  unknown   = 0x586E75, -- Base01
  partial   = 0x2AA198  -- Cyan
}

local STATUS_COLOR = {
  OK          = C.ok,
  PARTIAL     = C.partial,
  MAINTENANCE = C.warn,
  RING_DOWN   = C.ring_down,
  UNKNOWN     = C.unknown
}

local STATUS_LABEL = {
  OK          = "[  OK  ]",
  PARTIAL     = "[ STBY ]",
  MAINTENANCE = "[ PROB ]",
  RING_DOWN   = "[ DOWN ]",
  UNKNOWN     = "[ ???? ]"
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

local function format_energy(v)
  local abs_v = math.abs(v)
  if abs_v >= 1e12 then return string.format("%.1fT", v / 1e12) end
  if abs_v >= 1e9  then return string.format("%.1fG", v / 1e9) end
  if abs_v >= 1e6  then return string.format("%.1fM", v / 1e6) end
  if abs_v >= 1e3  then return string.format("%.1fk", v / 1e3) end
  return string.format("%d", v)
end

local function format_full(v)
  local s = string.format("%.0f", v)
  local formatted = s
  while true do  
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
    if (k==0) then break end
  end
  return formatted
end

local function timeAgo(t)
  if not t then return "never" end
  local sec = computer.uptime() - t
  if sec < 0 then return "active" end
  if sec < 60 then return math.floor(sec) .. "s" end
  return math.floor(sec/60) .. "m"
end

local function drawHeader(title, subtitle)
  -- Массивная шапка
  g_fill(1, 1, W, 2, " ", C.title, C.header_bg)
  local deco = "══[ " .. title .. " ]" .. string.rep("═", W - #title - 8)
  g_set(1, 1, deco, C.title, C.header_bg)
  
  if subtitle then
    g_set(2, 2, "STATUS: " .. subtitle, C.dim, C.header_bg)
  end
  
  -- Разделительная линия
  g_fill(1, 3, W, 1, " ", C.bg, C.bg)
  g_set(1, 3, string.rep("─", W), C.border, C.bg)
end

local function drawFooter(keys)
  g_fill(1, H, W, 1, " ", C.dim, C.header_bg)
  local x = 2
  for _, k in ipairs(keys) do
    if x >= W - 5 then break end
    g_set(x, H, "[" .. k[1] .. "]", C.key, C.header_bg)
    x = x + #k[1] + 2
    g_set(x, H, k[2], C.text, C.header_bg)
    x = x + #k[2] + 2
  end
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

function gui.clear()
  g_fill(1, 1, W, H, " ", C.text, C.bg)
end

function gui.drawPlanetList(planets, sel, scroll, stats)
  g_fill(1, 4, W, H-4, " ", C.text, C.bg)

  local count = #planets
  drawHeader(
    "GTNH PLANET MONITOR V2.0",
    count == 0 and "SYSTEM OFFLINE" or ("ONLINE - " .. count .. " NODES")
  )

  local HY = 4
  -- Заголовки колонок
  g_fill(1, HY, W, 1, " ", C.dim, C.header_bg)
  g_set( 2, HY, "#",  C.dim, C.header_bg)
  g_set( 6, HY, "PLANET NAME", C.dim, C.header_bg)
  g_set(24, HY, "STATUS", C.dim, C.header_bg)
  g_set(34, HY, "ACTIVITY", C.dim, C.header_bg) -- Новая колонка
  g_set(46, HY, "SEEN", C.dim, C.header_bg)
  g_set(56, HY, "MACHINES", C.dim, C.header_bg)

  local LIST_Y = HY + 1
  local LIST_H = H - 6
  scroll = scroll or 1

  for i = 0, LIST_H - 1 do
    local idx = scroll + i
    local ry = LIST_Y + i
    if idx <= count then
      local p = planets[idx]
      local isSel = (idx == sel)
      local bg = isSel and C.sel_bg or C.bg
      local fg = isSel and C.sel_fg or C.text
      
      local st = p.status or "UNKNOWN"
      local scol = STATUS_COLOR[st] or C.unknown
      
      local total, active = 0, 0
      for _, m in ipairs(p.machines or {}) do
        total = total + 1
        if m.active then active = active + 1 end
      end

      g_fill(1, ry, W, 1, " ", fg, bg)
      g_set(2, ry, string.format("%02d", idx), C.dim, bg)
      g_set(6, ry, pad(p.name or "?", 16), fg, bg)
      g_set(24, ry, STATUS_LABEL[st] or st, scol, bg)
      
      -- Индикатор активности
      if active > 0 then
        g_set(34, ry, "● ACTIVE", C.ok, bg)
      else
        g_set(34, ry, "○ idle", C.dim, bg)
      end
      
      g_set(46, ry, pad(timeAgo(p.last_ok), 8), C.dim, bg)
      g_set(56, ry, string.format("%d/%d", active, total), (active > 0 and C.ok or C.text), bg)
    end
  end

  -- Stats Panel
  local STAT_Y = H - 4
  g_fill(1, STAT_Y, W, 1, " ", C.border, C.border)
  
  -- Server Stats
  g_set(2, STAT_Y + 1, "SERVER ", C.dim, C.bg)
  if stats and stats.tps then
    local tps_c = (stats.tps > 18) and C.ok or (stats.tps > 15 and C.warn or C.ring_down)
    g_set(10, STAT_Y + 1, string.format("TPS %.1f", stats.tps), tps_c, C.bg)
  end

  -- Energy Stats
  local col2 = 30
  g_set(col2, STAT_Y + 1, "ENERGY ", C.dim, C.bg)
  if stats and stats.energy and stats.energy.max > 0 then
    local e = stats.energy
    local e_color = e.percent > 50 and C.ok or (e.percent > 20 and C.warn or C.ring_down)
    g_set(col2 + 8, STAT_Y + 1, format_full(e.stored) .. " EU (" .. math.floor(e.percent) .. "%)", e_color, C.bg)
    
    local diff_c = e.diff >= 0 and C.ok or C.ring_down
    g_set(col2 + 8, STAT_Y + 2, (e.diff >= 0 and "+" or "") .. format_energy(e.diff / 20) .. " EU/t", diff_c, C.bg)
  else
    g_set(col2 + 8, STAT_Y + 1, "LSC not configured", C.dim, C.bg)
  end

  drawFooter({
    {"Up/Dn", "Select"},
    {"Enter", "Details"},
    {"A", "RestartAll"},
    {"F3", "Scan"},
    {"F1", "Setup"},
    {"Q", "Quit"},
  })
end

function gui.drawPlanetDetail(planet, sel, scroll, sensor_data)
  g_fill(1, 4, W, H-4, " ", C.text, C.bg)

  local st    = planet.status or "UNKNOWN"
  local scol  = STATUS_COLOR[st] or C.unknown

  drawHeader(tostring(planet.name or "?") .. " STATUS", STATUS_LABEL[st] or st)

  local HY = 4
  g_fill(1, HY, 45, 1, " ", C.dim, C.header_bg)
  g_set( 2, HY, "#",  C.dim, C.header_bg)
  g_set( 5, HY, "MACHINE",  24, C.dim, C.header_bg)
  g_set(30, HY, "STATE",   15, C.dim, C.header_bg)

  g_fill(47, HY, W-46, 1, " ", C.title, C.header_bg)
  g_set(48, HY, "TELEMETRY", C.title, C.header_bg)

  local LIST_Y = HY + 1
  local LIST_H = H - LIST_Y - 1
  local machines = planet.machines or {}
  scroll = scroll or 1

  for i = 0, LIST_H - 1 do
    local idx = scroll + i
    local ry  = LIST_Y + i
    if idx <= #machines then
      local m = machines[idx]
      local isSel = (idx == sel)
      local bg = isSel and C.sel_bg or C.bg
      local fg = isSel and C.sel_fg or C.text
      local mcol = m.active and C.ok or C.ring_down
      local mst = m.active and ">> ACTIVE" or (m.error or "-- IDLE")

      g_fill(1, ry, 46, 1, " ", fg, bg)
      g_set(2, ry, string.format("%02d", idx), C.dim, bg)
      g_set(5, ry, pad(m.name or "?", 24), fg, bg)
      g_set(30, ry, mst, mcol, bg)
    end
    g_set(46, ry, "│", C.border, C.bg)
  end

  if sensor_data then
    for i = 1, LIST_H do
      local line = sensor_data[i]
      if line then
        g_set(48, LIST_Y + i - 1, pad(line:gsub("§.", ""), W - 49), C.text, C.bg)
      end
    end
  end

  drawFooter({{"Backspace", "Back"}, {"Enter", "Restart"}, {"A", "Restart All"}})
end

function gui.drawLog(lines, scroll)
  g_fill(1, 4, W, H-4, " ", C.text, C.bg)
  drawHeader("DIAGNOSTIC LOG", "RECORDS")
  local LIST_Y = 4
  local LIST_H = H - LIST_Y - 1
  local count = #lines
  scroll = scroll or math.max(1, count - LIST_H + 1)

  for i = 0, LIST_H - 1 do
    local idx = scroll + i
    local ry = LIST_Y + i
    if idx <= count then
      g_set(2, ry, pad(lines[idx] or "", W - 3), C.text, C.bg)
    end
  end
  drawFooter({{"Backspace", "Back"}})
end

function gui.notify(msg, color)
  local len = #msg + 4
  local x = math.floor((W - len) / 2)
  local y = math.floor(H / 2)
  g_fill(x, y-1, len, 3, " ", color, C.header_bg)
  g_set(x + 2, y, msg, 0xFFFFFF, C.header_bg)
end

return gui
