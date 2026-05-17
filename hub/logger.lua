-- =============================================================================
-- hub/logger.lua
-- =============================================================================
local config = require("config")

local logger = {}
local _lines = {}
local _buffer = {}
local _timer_id = nil

local function ts()
  local t = math.floor(os.time())
  local d = math.floor(t / 86400)
  local h = math.floor((t % 86400) / 3600)
  local m = math.floor((t % 3600) / 60)
  local s = t % 60
  return string.format("[D%04d %02d:%02d:%02d]", d, h, m, s)
end

local function flush()
  if #_buffer == 0 then return end
  
  local max = config.log_max_lines or 100
  local trimmed = false
  while #_lines > max do 
    table.remove(_lines, 1)
    trimmed = true
  end
  
  if trimmed then
    -- Перезаписываем файл целиком, чтобы он не рос бесконечно
    local f = io.open(config.log_file, "w")
    if f then 
      for _, l in ipairs(_lines) do f:write(l .. "\n") end
      f:close() 
    end
  else
    -- Просто дописываем в конец
    local f = io.open(config.log_file, "a")
    if f then 
      for _, l in ipairs(_buffer) do f:write(l .. "\n") end
      f:close() 
    end
  end
  _buffer = {}
end

local function writeLine(line)
  table.insert(_lines, line)
  table.insert(_buffer, line)
  
  if #_buffer >= 10 then
    flush()
  elseif not _timer_id then
    local event = require("event")
    _timer_id = event.timer(3, function()
      flush()
      _timer_id = nil
    end)
  end
end

function logger.log(planet, machine, msg)
  local line
  if machine then
    line = string.format("%s %-14s :: %-24s -> %s", ts(), planet, machine, msg)
  else
    line = string.format("%s %-14s :: %s", ts(), planet, msg)
  end
  writeLine(line)
end

function logger.getLines() return _lines end

function logger.load()
  local f = io.open(config.log_file, "r")
  if not f then return end
  local max = config.log_max_lines or 100
  local count = 0
  for line in f:lines() do 
    table.insert(_lines, line)
    count = count + 1
    if count % 1000 == 0 then require("os").sleep(0) end -- предотвращаем тайм-аут на больших логах
  end
  f:close()
  
  local trimmed = false
  while #_lines > max do 
    table.remove(_lines, 1)
    trimmed = true
  end
  
  if trimmed then
    local fw = io.open(config.log_file, "w")
    if fw then 
      for _, l in ipairs(_lines) do fw:write(l .. "\n") end
      fw:close()
    end
  end
end

return logger
