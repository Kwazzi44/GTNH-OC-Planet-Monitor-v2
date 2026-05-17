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
  border    = 0x1D6680, -- Teal (видимый, но не резкий)
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
  OK          = "[ OK ]",
  PARTIAL     = "[STBY]",
  MAINTENANCE = "[PROB]",
  RING_DOWN   = "[DOWN]",
  UNKNOWN     = "[????]"
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
  -- Верхняя рамка
  g_set(1, 1, "+" .. string.rep("-", W - 2) .. "+", C.border, C.bg)

  -- Строка заголовка: "| ==[ TITLE ]========...= |"
  g_set(1, 2, "|", C.border, C.bg)
  local inner = W - 2  -- ширина внутри рамки
  local tag = "==[ " .. title .. " ]"
  local fill = string.rep("=", math.max(0, inner - #tag))
  g_set(2, 2, tag .. fill, C.title, C.bg)
  g_set(W, 2, "|", C.border, C.bg)

  -- Строка подзаголовка
  g_set(1, 3, "|", C.border, C.bg)
  g_fill(2, 3, W - 2, 1, " ", C.dim, C.bg)
  if subtitle then
    g_set(3, 3, "STATUS: " .. subtitle, C.dim, C.bg)
  end
  g_set(W, 3, "|", C.border, C.bg)
end

local function drawFooter(keys)
  -- Разделитель
  g_set(1, H - 2, "+" .. string.rep("-", W - 2) .. "+", C.border, C.bg)

  -- Кнопки
  g_fill(2, H - 1, W - 2, 1, " ", C.text, C.bg)
  g_set(1, H - 1, "|", C.border, C.bg)
  local x = 3
  for _, k in ipairs(keys) do
    if x >= W - 4 then break end
    g_set(x, H - 1, "[" .. k[1] .. "]", C.key, C.bg)
    -- [  ] = 2 символа + сам ключ, +1 пробел перед описанием
    x = x + #k[1] + 3
    g_set(x, H - 1, k[2], C.text, C.bg)
    x = x + #k[2] + 2
  end
  g_set(W, H - 1, "|", C.border, C.bg)

  -- Нижняя рамка
  g_set(1, H, "+" .. string.rep("-", W - 2) .. "+", C.border, C.bg)
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
  -- Удален g_fill для предотвращения мерцания
  
  local total_nodes = 0
  for _, p in ipairs(planets) do
    total_nodes = total_nodes + #(p.machines or {})
  end

  drawHeader("GTNH PLANET MONITOR V2.0", string.format("ONLINE - %d NODES", total_nodes))

  -- Заголовки колонок на строке 4
  local HY = 4
  
  -- Динамическое распределение колонок (сдвинуто на 1 вправо для красоты)
  local c1 = 3                 -- #
  local c2 = 7                 -- PLANET NAME
  local c3 = math.floor(W * 0.3) -- STATUS
  local c4 = math.floor(W * 0.45) -- ACTIVITY
  local c5 = math.floor(W * 0.65) -- SEEN
  local c6 = math.floor(W * 0.8)  -- MACHINES
  
  -- Рисуем боковые рамки для строки заголовков
  g_set(1, HY, "|", C.border, C.bg)
  g_set(W, HY, "|", C.border, C.bg)
  
  g_set(c1, HY, "#",  C.dim, C.bg)
  g_set(c2, HY, "PLANET NAME", C.dim, C.bg)
  g_set(c3, HY, "STATUS", C.dim, C.bg)
  g_set(c4, HY, "ACTIVITY", C.dim, C.bg)
  g_set(c5, HY, "SEEN", C.dim, C.bg)
  g_set(c6, HY, "MACHINES", C.dim, C.bg)

  -- Разделитель на строке 5
  g_set(1, 5, "+" .. string.rep("=", W - 2) .. "+", C.border, C.bg)

  local LIST_Y = 6
  local LIST_H = H - LIST_Y - 5 -- 5 строк зарезервировано под подвал и статусы
  scroll = scroll or 1

  for i = 0, LIST_H - 1 do
    local idx = scroll + i
    local ry  = LIST_Y + i
    
    -- Рисуем боковые рамки для всех строк списка
    g_set(1, ry, "|", C.border, C.bg)
    g_set(W, ry, "|", C.border, C.bg)
    
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

      -- Заполняем только внутреннюю часть, не затирая рамку
      g_fill(2, ry, W - 2, 1, " ", fg, bg)
      g_set(c1, ry, string.format("%02d", idx), C.dim, bg)
      g_set(c2, ry, pad(p.name or "?", c3 - c2 - 2), fg, bg)
      g_set(c3, ry, STATUS_LABEL[st] or st, scol, bg)
      
      -- Индикатор активности
      if active > 0 then
        g_set(c4, ry, "● ACTIVE", C.ok, bg)
      else
        g_set(c4, ry, "○ idle", C.dim, bg)
      end
      
      g_set(c5, ry, pad(timeAgo(p.last_ok), c6 - c5 - 2), C.dim, bg)
      g_set(c6, ry, string.format("%d/%d", active, total), (active > 0 and C.ok or C.text), bg)
    else
      -- Заполняем пустоту
      g_fill(2, ry, W - 2, 1, " ", C.text, C.bg)
    end
  end

  -- Панель статистики
  local STAT_Y = H - 5
  -- Разделитель над статистикой
  g_set(1, STAT_Y, "+" .. string.rep("=", W - 2) .. "+", C.border, C.bg)
  
  -- Боковые рамки для строк статистики
  g_set(1, STAT_Y + 1, "|", C.border, C.bg)
  g_set(W, STAT_Y + 1, "|", C.border, C.bg)
  g_set(1, STAT_Y + 2, "|", C.border, C.bg)
  g_set(W, STAT_Y + 2, "|", C.border, C.bg)
  
  -- Server Stats
  g_set(c2, STAT_Y + 1, "SERVER ", C.dim, C.bg)
  if stats and stats.tps then
    local tps_c = (stats.tps > 18) and C.ok or (stats.tps > 15 and C.warn or C.ring_down)
    g_set(c2 + 8, STAT_Y + 1, string.format("TPS %.1f", stats.tps), tps_c, C.bg)
  end

  -- Energy Stats
  g_set(c4, STAT_Y + 1, "ENERGY ", C.dim, C.bg)
  if stats and stats.energy and stats.energy.max > 0 then
    local e = stats.energy
    local e_color = e.percent > 50 and C.ok or (e.percent > 20 and C.warn or C.ring_down)
    g_set(c4 + 8, STAT_Y + 1, format_full(e.stored) .. " EU (" .. math.floor(e.percent) .. "%)", e_color, C.bg)
    
    local diff_c = e.diff >= 0 and C.ok or C.ring_down
    g_set(c4 + 8, STAT_Y + 2, (e.diff >= 0 and "+" or "") .. format_energy(e.diff / 20) .. " EU/t", diff_c, C.bg)
  else
    g_set(c4 + 8, STAT_Y + 1, "LSC not configured", C.dim, C.bg)
  end

  drawFooter({
    {"Enter", "Details"},
    {"A",     "Restart"},
    {"F3",    "Refresh"},
    {"F4",    "Log"},
    {"F5",    "Update"},
    {"F1",    "Setup"},
  })
end

function gui.drawPlanetDetail(planet, sel, scroll, sensor_data)
  -- Удален g_fill для предотвращения мерцания

  local st    = planet.status or "UNKNOWN"
  local scol  = STATUS_COLOR[st] or C.unknown

  drawHeader(tostring(planet.name or "?") .. " STATUS", STATUS_LABEL[st] or st)

  -- Заголовки колонок на строке 4
  local HY = 4
  
  -- Динамическое распределение для деталей
  local c1 = 3
  local c2 = 6
  local c3 = math.floor(W * 0.4)
  local c4 = math.floor(W * 0.55)
  
  -- Рисуем боковые рамки для строки заголовков
  g_set(1, HY, "|", C.border, C.bg)
  g_set(W, HY, "|", C.border, C.bg)
  
  g_set( c1, HY, "#",  C.dim, C.bg)
  g_set( c2, HY, "MACHINE",  C.dim, C.bg)
  g_set( c3, HY, "STATE",   C.dim, C.bg)

  g_set(c4 + 1, HY, "TELEMETRY", C.title, C.bg)

  -- Разделитель на строке 5
  g_set(1, 5, "+" .. string.rep("=", W - 2) .. "+", C.border, C.bg)

  local LIST_Y = 6
  local LIST_H = H - LIST_Y - 2 -- 2 строки под подвал (separator + keys)
  local machines = planet.machines or {}
  scroll = scroll or 1

  for i = 0, LIST_H - 1 do
    local idx = scroll + i
    local ry  = LIST_Y + i
    
    -- Рисуем боковые рамки
    g_set(1, ry, "|", C.border, C.bg)
    g_set(W, ry, "|", C.border, C.bg)
    
    if idx <= #machines then
      local m = machines[idx]
      local isSel = (idx == sel)
      local bg = isSel and C.sel_bg or C.bg
      local fg = isSel and C.sel_fg or C.text
      local mcol = m.active and C.ok or C.ring_down
      local mst = m.active and ">> ACTIVE" or (m.error or "-- IDLE")

      g_fill(2, ry, c4 - 3, 1, " ", fg, bg)
      g_set(c1, ry, string.format("%02d", idx), C.dim, bg)
      g_set(c2, ry, pad(m.name or "?", c3 - c2 - 2), fg, bg)
      g_set(c3, ry, mst, mcol, bg)
    else
      -- Заполняем пустоту
      g_fill(2, ry, c4 - 3, 1, " ", C.text, C.bg)
    end
    g_set(c4 - 1, ry, "│", C.border, C.bg)
  end

  -- Обновление телеметрии с очисткой старых строк
  for i = 1, LIST_H do
    local line = sensor_data and sensor_data[i]
    if line then
      g_set(c4 + 1, LIST_Y + i - 1, pad(line:gsub("§.", ""), W - c4), C.text, C.bg)
    else
      g_fill(c4 + 1, LIST_Y + i - 1, W - c4, 1, " ", C.text, C.bg)
    end
  end

  drawFooter({{"B", "Back"}, {"Enter", "Restart"}, {"T", "Toggle"}, {"A", "Restart All"}})
end

function gui.drawLog(lines, scroll)
  -- Без g_fill чтобы не мигало — перезаписываем строки
  drawHeader("DIAGNOSTIC LOG", "RECORDS")
  local LIST_Y = 4
  local LIST_H = H - LIST_Y - 3  -- -3 под footer (separator + keys + bottom)
  local count = #lines
  scroll = scroll or math.max(1, count - LIST_H + 1)

  for i = 0, LIST_H - 1 do
    local idx = scroll + i
    local ry = LIST_Y + i
    -- Боковые рамки
    g_set(1, ry, "|", C.border, C.bg)
    g_set(W, ry, "|", C.border, C.bg)
    if idx <= count then
      g_set(2, ry, pad(lines[idx] or "", W - 3), C.text, C.bg)
    else
      g_fill(2, ry, W - 2, 1, " ", C.text, C.bg)
    end
  end
  drawFooter({{"Home", "Top"}, {"End", "Bottom"}, {"B", "Back"}})
end

function gui.notify(msg, color)
  local len = math.min(#msg + 4, W - 2)
  local x   = math.max(1, math.floor((W - len) / 2))
  local y    = math.floor(H / 2)
  g_fill(x, y-1, len, 3, " ", color, C.header_bg)
  g_set(x + 2, y, msg:sub(1, len - 4), 0xFFFFFF, C.header_bg)
end

return gui
