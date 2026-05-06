-- =============================================================================
-- cleanup_old.lua — Разовая очистка файлов старой архитектуры
-- =============================================================================
-- Удаляет файлы от node/modem версии + старые файлы из корня ФС.
-- Запуск: lua /home/cleanup_old.lua  или  lua /cleanup_old.lua

local fs = require("filesystem")

local function del(path)
  if fs.exists(path) then
    fs.remove(path)
    io.write("  [DEL] " .. path .. "\n")
  end
end

local function delDir(path)
  if not fs.exists(path) then return end
  local function rmAll(p)
    for name in fs.list(p) do
      local full = p .. name
      if fs.isDirectory(full) then rmAll(full .. "/") end
      fs.remove(full)
    end
    fs.remove(p)
  end
  rmAll(path)
  io.write("  [DEL] " .. path .. " (dir)\n")
end

io.write("Cleaning up old/misplaced files...\n")
io.write(string.rep("-", 40) .. "\n")

-- Старая архитектура (node + modem)
delDir("/node/")
del("/protocol.lua")
del("/hub/monitor.lua")
del("/install_node.lua")

-- Файлы которые раньше ставились в корень вместо /home/
del("/hub/config.lua")
del("/hub/logger.lua")
del("/hub/registry.lua")
del("/hub/machines.lua")
del("/hub/gui.lua")
del("/hub/setup.lua")
del("/hub/main.lua")
del("/planet_registry.json")
del("/planet_log.txt")

-- Старая папка /hub/ в корне
if fs.exists("/hub") then
  local empty = true
  for _ in fs.list("/hub") do empty = false; break end
  if empty then fs.remove("/hub"); io.write("  [DEL] /hub/ (dir)\n") end
end

-- Самоудаление
fs.remove("/home/cleanup_old.lua")
fs.remove("/cleanup_old.lua")

io.write(string.rep("-", 40) .. "\n")
io.write("Done. Files are now in /home/hub/\n")
