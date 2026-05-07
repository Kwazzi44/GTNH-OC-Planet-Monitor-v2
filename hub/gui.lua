-- =============================================================================
-- hub/gui.lua — Two-Level GUI Dashboard + Log Viewer
-- =============================================================================

local component = require("component")
local unicode   = require("unicode")
local os        = require("os")

local gui = {}

local _gpu
local W, H = 80, 25

-- ─── Цветовая палитра ─────────────────────────────────────────────────────

local C = {
  bg         = 0x0D0D1A,
  header_bg  = 0x151530,
  header_fg  = 0x7799EE,
  title      = 0xFFFFFF,
  text       = 0xCCCCDD,
  dim        = 0x556677,
  sel_bg     = 0x1E3A6E,
  sel_fg     = 0xFFFFFF,
  ok         = 0x00DD55,
  partial    = 0xFFAA00,
  ring_down  = 0xFF2244,
  unknown    = 0x778899,
  border     = 0x2A3A6A,
  key_bg     = 0x0A0A22,
  key        = 0x4477FF,
  log_bg     = 0x08080F,
  log_ts     = 0x3D5A8A,
  warn       = 0xFF6600,
}

local STATUS_COLOR = {
  OK        = C.ok,
  PARTIAL   = C.partial,
  RING_DOWN = C.ring_down,
  UNKNOWN   = C.unknown,
  MAINTENANCE = C.warn,
}

local STATUS_LABEL = {
  OK        = "OK",
  PARTIAL   = "PARTIAL",
  RING_DOWN = "RING DOWN",
  UNKNOWN   = "UNKNOWN",
  MAINTENANCE = "PROBLEM",
}

-- ─── GPU helpers ──────────────────────────────────────────────────────────

local function g_set(x, y, str, fg, bg)
  _gpu.setForeground(fg or C.text)
  _gpu.setBackground(bg or C.bg)
  _gpu.set(x, y, str)
end

local function g_fill(x, y, w, h, ch, fg, bg)
  _gpu.setForeground(fg or C.text)
  _gpu.setBackground(bg or C.bg)
  _gpu.fill(x, y, w, h, ch or " ")
end

local function pad(s, n)
  s = tostring(s or "")
  local len = unicode.len(s)
  if len >= n then return unicode.sub(s, 1, n) end
  return s .. string.rep(" ", n - len)
end

local function timeAgo(ts)
  if not ts or ts == 0 then return "never   " end
  local d = os.time() - ts
  if d < 5  then return "now     " end
  if d < 60 then return d .. "s ago   " end
  if d < 3600 then return math.floor(d/60) .. "m ago   " end
  return math.floor(d/3600) .. "h ago   "
end

-- ─── Header & Footer ──────────────────────────────────────────────────────

local function drawHeader(line1, line2)
  local len = unicode.len(line1)
  local tx = math.max(1, math.floor((W - len) / 2) + 1)
  local left_pad = string.rep(" ", tx - 1)
  local right_pad = string.rep(" ", W - (tx - 1) - len)
  g_set(1, 1, left_pad .. line1 .. right_pad, C.title, C.header_bg)

  local l2 = " " .. tostring(line2 or "")
  g_set(1, 2, pad(l2, W), C.header_fg, C.header_bg)
  
  g_set(1, 3, string.rep("=", W), C.border, C.bg)
end

local function drawFooter(keys)
  _gpu.setBackground(C.key_bg)
  _gpu.setForeground(C.dim)
  _gpu.set(1, H, " ")
  local x = 2
  for _, k in ipairs(keys) do
    if x >= W - 2 then break end
    _gpu.setForeground(C.key)
    _gpu.set(x, H, "[" .. k[1] .. "]")
    x = x + #k[1] + 2
    _gpu.setForeground(C.dim)
    _gpu.set(x, H, k[2])
    x = x + #k[2]
    _gpu.set(x, H, "  ")
    x = x + 2
  end
  if x <= W then
    g_set(x, H, string.rep(" ", W - x + 1), C.dim, C.key_bg)
  end
end

-- ─── Init ─────────────────────────────────────────────────────────────────

function gui.init()
  if not component.isAvailable("gpu") then return false end
  _gpu = component.gpu
  _gpu.setDepth(_gpu.maxDepth())
  W, H = _gpu.getResolution()
  g_fill(1, 1, W, H, " ", C.text, C.bg)
  return true
end

function gui.getSize() return W, H end

-- ─── VIEW 1: Planet List ──────────────────────────────────────────────────

--- Нарисовать главный экран со списком планет
-- @param planets  table   Отсортированный список из registry.getPlanetList()
-- @param sel      number  Индекс выбранной строки (1-based)
-- @param scroll   number  Первая видимая строка (1-based)
function gui.drawPlanetList(planets, sel, scroll)
  local count = #planets
  drawHeader(
    "PLANET MULTIBLOCK MONITOR",
    count == 0 and "No planets registered yet. Start a Node on any planet."
              or  ("Monitoring " .. count .. " planet(s)")
  )

  -- Column header row
  local HY = 4
  g_fill(1, HY, W, 1, " ", C.dim, C.header_bg)
  g_set( 2, HY, pad("#",    3),  C.dim, C.header_bg)
  g_set( 5, HY, pad("Planet", 18), C.dim, C.header_bg)
  g_set(24, HY, pad("Status",  10), C.dim, C.header_bg)
  g_set(35, HY, pad("Last Seen", 10), C.dim, C.header_bg)
  g_set(46, HY, pad("Machines", 10), C.dim, C.header_bg)
  g_set(57, HY, "Info", C.dim, C.header_bg)
  g_fill(1, HY+1, W, 1, string.rep("-", W), C.border, C.bg)

  local LIST_Y   = HY + 2
  local LIST_H   = H - LIST_Y - 1   -- строк под список (минус footer)
  scroll = scroll or 1

  for i = 0, LIST_H - 1 do
    local idx = scroll + i
    local ry  = LIST_Y + i
    if idx > count then
      g_set(1, ry, pad(" ", W), C.text, C.bg)
    else
      local p   = planets[idx]
      local isSel  = (idx == sel)
      local bg  = isSel and C.sel_bg or C.bg
      local fg  = isSel and C.sel_fg or C.text
      g_fill(1, ry, W, 1, " ", fg, bg)

      local st   = p.status or "UNKNOWN"
      local scol = STATUS_COLOR[st] or C.unknown

      -- Machines ratio
      local total, active = 0, 0
      for _, m in ipairs(p.machines or {}) do
        total = total + 1
        if m.active then active = active + 1 end
      end
      local mtext = total > 0 and (active .. "/" .. total) or "—"
      local mcol  = (active == total and total > 0) and C.ok
                 or (total > 0 and C.partial or C.unknown)

      local hint, hcol = "", C.bg
      if st == "RING_DOWN" then
        hint, hcol = "[!] Manual needed", C.ring_down
      elseif st == "PARTIAL" then
        hint, hcol = "[*] Can restart", C.partial
      elseif st == "MAINTENANCE" then
        hint, hcol = "[!] Fix machine", C.warn
      end

      -- Draw continuous row to prevent flicker
      g_set(1, ry, " ", C.dim, bg)
      g_set(2, ry, pad(idx, 3), C.dim, bg)
      g_set(5, ry, pad(p.name or "?", 19), fg, bg)
      g_set(24, ry, pad(STATUS_LABEL[st] or st, 11), scol, bg)
      g_set(35, ry, pad(timeAgo(p.last_seen), 11), C.dim, bg)
      g_set(46, ry, pad(mtext, 11), mcol, bg)
      g_set(57, ry, pad(hint, W - 56), hcol, bg)
    end
  end

  -- Scroll arrows
  if scroll > 1 then g_set(W, LIST_Y, "^", C.dim, C.bg) end
  if scroll + LIST_H - 1 < count then g_set(W, LIST_Y + LIST_H - 1, "v", C.dim, C.bg) end

  drawFooter({
    {"Up/Dn", "Navigate"},
    {"Enter", "Details"},
    {"A",     "RestartAll"},
    {"R",     "Refresh"},
    {"L",     "Log"},
    {"S",     "Setup"},
    {"Q",     "Quit"},
  })
end

-- ─── VIEW 2: Planet Detail ────────────────────────────────────────────────

--- Нарисовать экран деталей одной планеты
-- @param planet   table   Запись планеты из registry
-- @param sel      number  Индекс выбранной машины
-- @param scroll   number  Первая видимая машина
function gui.drawPlanetDetail(planet, sel, scroll, sensor_data)
  local st    = planet.status or "UNKNOWN"
  local scol  = STATUS_COLOR[st] or C.unknown

  local h1 = tostring(planet.name or "?") .. "  [" .. tostring(STATUS_LABEL[st] or st) .. "]"
  local h2 = "Last seen: " .. timeAgo(planet.last_ok)
  drawHeader(h1, h2)

  -- Column header
  local HY = 4
  g_fill(1, HY, 45, 1, " ", C.dim, C.header_bg)
  g_set( 2, HY, pad("#",    3),  C.dim, C.header_bg)
  g_set( 5, HY, pad("Machine",  24), C.dim, C.header_bg)
  g_set(30, HY, pad("Status",   15), C.dim, C.header_bg)
  g_fill(1, HY+1, 45, 1, string.rep("-", 45), C.border, C.bg)

  -- Right panel header
  g_fill(47, HY, W-46, 1, " ", C.title, C.header_bg)
  g_set(48, HY, "SENSOR DATA", C.title, C.header_bg)
  g_fill(47, HY+1, W-46, 1, string.rep("-", W-46), C.border, C.bg)

  local LIST_Y = HY + 2
  local LIST_H = H - LIST_Y - 1
  local machines = planet.machines or {}
  local count = #machines
  scroll = scroll or 1

  for i = 0, LIST_H - 1 do
    local idx = scroll + i
    local ry  = LIST_Y + i
    if idx > count then
      g_set(1, ry, pad(" ", 45), C.text, C.bg)
    else
      local m     = machines[idx]
      local isSel = (idx == sel)
      local bg    = isSel and C.sel_bg or C.bg
      local fg    = isSel and C.sel_fg or C.text

      local mcol  = m.active and C.ok or C.ring_down
      local micon = m.active and ">" or "X"
      local mst   = m.active and "ACTIVE" or (m.error or "OFFLINE")

      if m.error == "MAINTENANCE" then
        mcol = C.warn
        micon = "!"
        mst = "PROBLEM"
      end

      g_set(1, ry, " ", C.dim, bg)
      g_set(2, ry, pad(idx, 3), C.dim, bg)
      g_set(5, ry, micon .. " " .. pad(m.name or "Unknown", 23), mcol, bg)
      g_set(30, ry, pad(mst, 16), mcol, bg)
    end
    -- Draw vertical separator
    g_set(46, ry, "|", C.border, C.bg)
  end

  -- SENSOR PANEL RENDER
  local SX = 48
  local SY = LIST_Y
  local sel_m = machines[sel]
  if sel_m then
    g_set(SX, SY, pad(sel_m.name, W - SX), C.title, C.bg)
    SY = SY + 2
    if st == "RING_DOWN" then
      g_set(SX, SY, "Ring is offline.", C.ring_down, C.bg)
    else
      if not sel_m.active then
        g_set(SX, SY, "Status: OFFLINE", C.warn, C.bg)
        g_set(SX, SY+1, "[Enter] to restart", C.dim, C.bg)
        SY = SY + 3
      end
      if sensor_data then
        if type(sensor_data) == "table" then
          for _, line in ipairs(sensor_data) do
            if SY < H - 1 then
              -- Очищаем майнкрафтовские коды форматирования (§a, §r и т.д.)
              local clean_line = line:gsub("§.", "")
              local col = C.text
              if clean_line:match("^Problems:") and not clean_line:match(" 0$") then col = C.warn end
              if clean_line:match("^Progress: ") then col = C.ok end
              g_set(SX, SY, pad(clean_line, W - SX), col, C.bg)
              SY = SY + 1
            end
          end
        else
          g_set(SX, SY, "Error reading sensors:", C.warn, C.bg)
          g_set(SX, SY+1, pad(tostring(sensor_data), W - SX), C.dim, C.bg)
        end
      else
        g_set(SX, SY, "Fetching data...", C.dim, C.bg)
        SY = SY + 1
      end
    end
  end

  -- Clear remaining lines in the right panel
  for y = SY, H - 1 do
    g_fill(47, y, W - 46, 1, " ", C.text, C.bg)
  end

  -- RING DOWN warning banner
  if st == "RING_DOWN" then
    local wy = H - 2
    g_fill(1, wy, 45, 1, " ", C.ring_down, C.bg)
    g_set(2, wy, pad("! RING OFFLINE !", 43), C.ring_down, C.bg)
  end

  -- Scroll arrows
  if scroll > 1 then g_set(W, LIST_Y, "^", C.dim, C.bg) end
  if scroll + LIST_H - 1 < count then g_set(W, LIST_Y + LIST_H - 1, "v", C.dim, C.bg) end

  drawFooter({
    {"Up/Dn", "Navigate"},
    {"Enter", "Restart"},
    {"A",     "RestartAll"},
    {"B",     "Back"},
    {"Q",     "Quit"},
  })
end

-- ─── VIEW 3: Log Viewer ───────────────────────────────────────────────────

--- Нарисовать экран лога событий
-- @param lines   table   Строки лога из logger.getLines()
-- @param scroll  number  Первая видимая строка (nil = прилипание к низу)
function gui.drawLog(lines, scroll)
  drawHeader("EVENT LOG", #lines .. " entries total")

  local LIST_Y = 4
  local LIST_H = H - LIST_Y - 1
  local count  = #lines

  -- Auto-scroll to bottom
  if not scroll or scroll < 1 then
    scroll = math.max(1, count - LIST_H + 1)
  end

  for i = 0, LIST_H - 1 do
    local idx = scroll + i
    local ry  = LIST_Y + i
    if idx <= count then
      local line = lines[idx]
      local ts_part, rest = line:match("^(%b[]) (.+)$")
      if ts_part then
        g_set(1, ry, ts_part, C.log_ts, C.log_bg)
        g_set(#ts_part + 1, ry, " " .. pad(unicode.sub(rest, 1, W - #ts_part - 1), W - #ts_part), C.text, C.log_bg)
      else
        g_set(1, ry, pad(unicode.sub(line, 1, W), W), C.text, C.log_bg)
      end
    else
      g_set(1, ry, pad(" ", W), C.text, C.log_bg)
    end
  end

  -- Scroll arrows
  if scroll > 1 then g_set(W, LIST_Y, "^", C.dim, C.log_bg) end
  if scroll + LIST_H - 1 < count then
    g_set(W, LIST_Y + LIST_H - 1, "v", C.dim, C.log_bg)
  end

  drawFooter({
    {"Up/Dn", "Scroll"},
    {"Home",  "Top"},
    {"End",   "Bottom"},
    {"B",     "Back"},
  })
end

-- ─── Overlay: Notification ────────────────────────────────────────────────

--- Показать временное уведомление по центру экрана
function gui.notify(msg, color)
  color = color or C.warn
  local mw  = math.min(#msg + 4, W - 4)
  local nx  = math.floor((W - mw) / 2) + 1
  local ny  = math.floor(H / 2)
  g_fill(nx, ny-1, mw, 3, " ", color, C.header_bg)
  g_set(nx + 2, ny, pad(msg, mw - 4), color, C.header_bg)
end

--- Восстановить экран (убрать overlay — просто пометить dirty)
function gui.clearScreen()
  g_fill(1, 1, W, H, " ", C.text, C.bg)
end

return gui
