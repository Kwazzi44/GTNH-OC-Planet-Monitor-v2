-- =============================================================================
-- hub/logger.lua — Event Logger
-- =============================================================================
-- Пишет события в файл и хранит последние N строк в памяти для GUI

local config = require("config")

local logger  = {}
local _lines  = {}   -- Строки в памяти

-- ─── Timestamp ───────────────────────────────────────────────────────────

local function ts()
  local t = os.date("*t")
  return string.format("[%04d-%02d-%02d %02d:%02d:%02d]",
    t.year, t.month, t.day, t.hour, t.min, t.sec)
end

-- ─── Запись строки ───────────────────────────────────────────────────────

local function writeLine(line)
  table.insert(_lines, line)
  while #_lines > config.log_max_lines do
    table.remove(_lines, 1)
  end
  local f = io.open(config.log_file, "a")
  if f then
    f:write(line .. "\n")
    f:close()
  end
end

-- ─── Публичный API ───────────────────────────────────────────────────────

--- Записать событие
-- @param planet  string   Название планеты
-- @param machine string?  Название машины (nil если событие уровня планеты)
-- @param msg     string   Описание события
function logger.log(planet, machine, msg)
  local line
  if machine then
    line = string.format("%s %-15s :: %-25s → %s",
      ts(), planet, machine, msg)
  else
    line = string.format("%s %-15s :: %s",
      ts(), planet, msg)
  end
  writeLine(line)
end

--- Получить все строки лога (для GUI)
function logger.getLines()
  return _lines
end

--- Загрузить лог из файла при старте
function logger.load()
  local f = io.open(config.log_file, "r")
  if not f then return end
  for line in f:lines() do
    table.insert(_lines, line)
  end
  f:close()
  while #_lines > config.log_max_lines do
    table.remove(_lines, 1)
  end
end

return logger
