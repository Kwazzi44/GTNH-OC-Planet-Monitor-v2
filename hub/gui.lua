-- =============================================================================
-- hub/gui.lua — Premium Solarized UI
-- =============================================================================

local component = require("component")
local computer  = require("computer")

local gui = {}

local _gpu = nil
local W, H = 80, 25

local theme = require("theme")
local C = theme.C

local STATUS_COLOR = {
  OK          = C.ok,
  PARTIAL     = C.partial,
  MAINTENANCE = C.warn,
  RING_DOWN   = C.ring_down,
  UNKNOWN     = C.unknown
}

local STATUS_LABEL = {
  OK          = "[ OK ]",
  PARTIAL     = "[STBY]",
  MAINTENANCE = "[PROB]",
  RING_DOWN   = "[DOWN]",
  UNKNOWN     = "[????]"
}

-- ─── Internal Helpers ──────────────────────────────────────────────────────

local function g_set(x, y, text, fg, bg) theme.gset(x, y, text, fg, bg) end
local function g_fill(x, y, w, h, char, fg, bg) theme.gfill(x, y, w, h, char, fg, bg) end
local function pad(str, len) return theme.pad(str, len) end

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
  local k
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

-- Helpers removed, now in theme.lua


function gui.init()
  if not component.isAvailable("gpu") then return false end
  _gpu = component.gpu
  _gpu.setDepth(_gpu.maxDepth())
  W, H = _gpu.getResolution()
  theme.init(_gpu)
  gui.clear()
  return true
end

function gui.clear()
  theme.gfill(1, 1, W, H, " ", C.text, C.bg)
end

function gui.drawStatic(view, data)
  if view == "LIST" then
    local total_nodes = 0
    for _, p in ipairs(data.planets or {}) do
      total_nodes = total_nodes + #(p.machines or {})
    end
    theme.drawHeader("GTNH PLANET MONITOR V2.0", string.format("ONLINE - %d NODES", total_nodes))

    local HY = 4
    theme.gset(1, HY, "|", C.border, C.bg)
    theme.gset(W, HY, "|", C.border, C.bg)
    
    local c1 = 3
    local c2 = 7
    local c3 = math.floor(W * 0.3)
    local c4 = math.floor(W * 0.45)
    local c5 = math.floor(W * 0.65)
    local c6 = math.floor(W * 0.8)

    theme.gset(c1, HY, "#",  C.dim, C.bg)
    theme.gset(c2, HY, "PLANET NAME", C.dim, C.bg)
    theme.gset(c3, HY, "STATUS", C.dim, C.bg)
    theme.gset(c4, HY, "ACTIVITY", C.dim, C.bg)
    theme.gset(c5, HY, "SEEN", C.dim, C.bg)
    theme.gset(c6, HY, "MACHINES", C.dim, C.bg)

    theme.gset(1, 5, "+" .. string.rep("=", W - 2) .. "+", C.border, C.bg)

    local STAT_Y = H - 5
    theme.gset(1, STAT_Y, "+" .. string.rep("=", W - 2) .. "+", C.border, C.bg)
    theme.gset(1, STAT_Y + 1, "|", C.border, C.bg)
    theme.gset(W, STAT_Y + 1, "|", C.border, C.bg)
    theme.gset(1, STAT_Y + 2, "|", C.border, C.bg)
    theme.gset(W, STAT_Y + 2, "|", C.border, C.bg)
    
    theme.gset(c2, STAT_Y + 1, "SERVER ", C.dim, C.bg)
    theme.gset(c4, STAT_Y + 1, "ENERGY ", C.dim, C.bg)

    theme.drawFooter({
      {"Enter", "Details"},
      {"A",     "Restart"},
      {"F3",    "Refresh"},
      {"F4",    "Log"},
      {"F5",    "Update"},
      {"F1",    "Setup"},
    })

  elseif view == "DETAIL" then
    local planet = data.planet
    local st = planet.status or "UNKNOWN"
    theme.drawHeader(tostring(planet.name or "?") .. " STATUS", STATUS_LABEL[st] or st)

    local HY = 4
    local c1 = 3
    local c2 = 6
    local c3 = math.floor(W * 0.4)
    local c4 = math.floor(W * 0.55)

    theme.gset(1, HY, "|", C.border, C.bg)
    theme.gset(W, HY, "|", C.border, C.bg)
    
    theme.gset( c1, HY, "#",  C.dim, C.bg)
    theme.gset( c2, HY, "MACHINE",  C.dim, C.bg)
    theme.gset( c3, HY, "STATE",   C.dim, C.bg)
    theme.gset(c4 + 1, HY, "TELEMETRY", C.title, C.bg)

    theme.gset(1, 5, "+" .. string.rep("=", W - 2) .. "+", C.border, C.bg)

    theme.drawFooter({{"B", "Back"}, {"Enter", "Restart"}, {"T", "Toggle"}, {"A", "Restart All"}})

  elseif view == "LOG" then
    theme.drawHeader("DIAGNOSTIC LOG", "RECORDS")
    theme.drawFooter({{"Home", "Top"}, {"End", "Bottom"}, {"B", "Back"}})
  end
end

function gui.drawPlanetList(planets, sel, scroll, stats)
  local LIST_Y = 6
  local LIST_H = H - LIST_Y - 5
  scroll = scroll or 1

  local c1 = 3
  local c2 = 7
  local c3 = math.floor(W * 0.3)
  local c4 = math.floor(W * 0.45)
  local c5 = math.floor(W * 0.65)
  local c6 = math.floor(W * 0.8)

  for i = 0, LIST_H - 1 do
    local idx = scroll + i
    local ry  = LIST_Y + i
    
    theme.gset(1, ry, "|", C.border, C.bg)
    theme.gset(W, ry, "|", C.border, C.bg)
    
    if idx <= #planets then
      local p = planets[idx]
      local isSel = (idx == sel)
      local bg = isSel and C.sel_bg or C.bg
      local fg = isSel and C.sel_fg or C.text
      local st = p.status or "UNKNOWN"
      local scol = STATUS_COLOR[st] or C.unknown

      local total = #(p.machines or {})
      local active = 0
      for _, m in ipairs(p.machines or {}) do
        if m.active then active = active + 1 end
      end

      theme.gfill(2, ry, W - 2, 1, " ", fg, bg)
      theme.gset(c1, ry, string.format("%02d", idx), C.dim, bg)
      theme.gset(c2, ry, pad(p.name or "?", c3 - c2 - 2), fg, bg)
      theme.gset(c3, ry, STATUS_LABEL[st] or st, scol, bg)
      
      if active > 0 then
        theme.gset(c4, ry, "● ACTIVE", C.ok, bg)
      else
        theme.gset(c4, ry, "○ idle", C.dim, bg)
      end
      
      theme.gset(c5, ry, pad(timeAgo(p.last_ok), c6 - c5 - 2), C.dim, bg)
      theme.gset(c6, ry, string.format("%d/%d", active, total), (active > 0 and C.ok or C.text), bg)
    else
      theme.gfill(2, ry, W - 2, 1, " ", C.text, C.bg)
    end
  end

  gui.drawStats(stats)
end

function gui.drawStats(stats)
  local STAT_Y = H - 5
  local c2 = 7
  local c4 = math.floor(W * 0.45)
  
  if stats and stats.tps then
    local tps_c = (stats.tps > 18) and C.ok or (stats.tps > 15 and C.warn or C.ring_down)
    theme.gset(c2 + 8, STAT_Y + 1, string.format("TPS %.1f", stats.tps), tps_c, C.bg)
  end

  if stats and stats.energy and stats.energy.max > 0 then
    local e = stats.energy
    local e_color = e.percent > 50 and C.ok or (e.percent > 20 and C.warn or C.ring_down)
    theme.gset(c4 + 8, STAT_Y + 1, format_full(e.stored) .. " EU (" .. math.floor(e.percent) .. "%)", e_color, C.bg)
    
    local diff_c = e.diff >= 0 and C.ok or C.ring_down
    theme.gset(c4 + 8, STAT_Y + 2, (e.diff >= 0 and "+" or "") .. format_energy(e.diff / 20) .. " EU/t", diff_c, C.bg)
  else
    theme.gset(c4 + 8, STAT_Y + 1, "LSC not configured", C.dim, C.bg)
  end
end

function gui.drawPlanetDetail(planet, sel, scroll, sensor_data)
  local LIST_Y = 6
  local LIST_H = H - LIST_Y - 2
  local machines = planet.machines or {}
  scroll = scroll or 1

  local c1 = 3
  local c2 = 6
  local c3 = math.floor(W * 0.4)
  local c4 = math.floor(W * 0.55)

  for i = 0, LIST_H - 1 do
    local idx = scroll + i
    local ry  = LIST_Y + i
    
    theme.gset(1, ry, "|", C.border, C.bg)
    theme.gset(W, ry, "|", C.border, C.bg)
    
    if idx <= #machines then
      local m = machines[idx]
      local isSel = (idx == sel)
      local bg = isSel and C.sel_bg or C.bg
      local fg = isSel and C.sel_fg or C.text
      local mcol = m.active and C.ok or C.ring_down
      local mst = m.active and ">> ACTIVE" or (m.error or "-- IDLE")

      theme.gfill(2, ry, c4 - 3, 1, " ", fg, bg)
      theme.gset(c1, ry, string.format("%02d", idx), C.dim, bg)
      theme.gset(c2, ry, pad(m.name or "?", c3 - c2 - 2), fg, bg)
      theme.gset(c3, ry, mst, mcol, bg)
    else
      theme.gfill(2, ry, c4 - 3, 1, " ", C.text, C.bg)
    end
    theme.gset(c4 - 1, ry, "│", C.border, C.bg)
  end

  for i = 1, LIST_H do
    local line = sensor_data and sensor_data[i]
    if line then
      theme.gset(c4 + 1, LIST_Y + i - 1, pad(tostring(line):gsub("§.", ""), W - c4), C.text, C.bg)
    else
      theme.gfill(c4 + 1, LIST_Y + i - 1, W - c4, 1, " ", C.text, C.bg)
    end
  end
end

function gui.drawLog(lines, scroll)
  local LIST_Y = 4
  local LIST_H = H - LIST_Y - 3
  local count = #lines
  scroll = scroll or math.max(1, count - LIST_H + 1)

  for i = 0, LIST_H - 1 do
    local idx = scroll + i
    local ry = LIST_Y + i
    theme.gset(1, ry, "|", C.border, C.bg)
    theme.gset(W, ry, "|", C.border, C.bg)
    if idx <= count then
      theme.gset(2, ry, pad(lines[idx] or "", W - 3), C.text, C.bg)
    else
      theme.gfill(2, ry, W - 2, 1, " ", C.text, C.bg)
    end
  end
end

function gui.notify(msg, color)
  local len = math.min(#msg + 4, W - 2)
  local x   = math.max(1, math.floor((W - len) / 2))
  local y    = math.floor(H / 2)
  theme.gfill(x, y-1, len, 3, " ", color, C.header_bg)
  theme.gset(x + 2, y, msg:sub(1, len - 4), 0xFFFFFF, C.header_bg)
end

return gui
