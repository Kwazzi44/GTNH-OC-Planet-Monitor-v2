-- =============================================================================
-- hub/logger.lua
-- =============================================================================
local config = require("config")

local logger = {}
local _lines = {}

local function ts()
  local t = math.floor(os.time())
  local d = math.floor(t / 86400)
  local h = math.floor((t % 86400) / 3600)
  local m = math.floor((t % 3600) / 60)
  local s = t % 60
  return string.format("[D%04d %02d:%02d:%02d]", d, h, m, s)
end

local function writeLine(line)
  table.insert(_lines, line)
  local max = config.log_max_lines or 100
  while #_lines > max do table.remove(_lines, 1) end
  local f = io.open(config.log_file, "a")
  if f then f:write(line .. "\n"); f:close() end
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
  for line in f:lines() do table.insert(_lines, line) end
  f:close()
  while #_lines > max do table.remove(_lines, 1) end
end

return logger
