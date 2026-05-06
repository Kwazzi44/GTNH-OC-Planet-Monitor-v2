-- =============================================================================
-- uninstall_hub.lua — Cleanup Hub files
-- =============================================================================
-- Запуск: lua /home/uninstall_hub.lua

local fs = require("filesystem")

local function ln(s) io.write((s or "") .. "\n") end
local function ask(p) io.write(p); return io.read() or "" end
local function askYN(p)
  local a = ask(p .. " [y/n]: ")
  return (a:lower() == "y" or a:lower() == "yes")
end

local function del(path)
  if fs.exists(path) then
    fs.remove(path)
    ln("  [DEL] " .. path)
  else
    ln("  [--]  " .. path)
  end
end

local HUB_FILES = {
  "/home/hub/config.lua",
  "/home/hub/logger.lua",
  "/home/hub/registry.lua",
  "/home/hub/machines.lua",
  "/home/hub/gui.lua",
  "/home/hub/setup.lua",
  "/home/hub/main.lua",
}

local DATA_FILES = {
  { path = "/home/planet_registry.json", desc = "Planet registry (your config!)" },
  { path = "/home/planet_log.txt",       desc = "Event log" },
}

ln("\n" .. string.rep("-", 50))
ln("  GTNH Planet Monitor — UNINSTALLER")
ln(string.rep("-", 50))

if not askYN("Delete all Hub scripts?") then ln("Cancelled."); return end

-- Данные
ln()
local keep = {}
for _, df in ipairs(DATA_FILES) do
  if fs.exists(df.path) then
    keep[df.path] = askYN("Keep " .. df.desc .. "?")
  end
end

-- Удалить скрипты
ln("\nDeleting scripts...")
for _, f in ipairs(HUB_FILES) do del(f) end

-- Папка /home/hub/
if fs.exists("/home/hub") then
  local empty = true
  for _ in fs.list("/home/hub") do empty = false; break end
  if empty then fs.remove("/home/hub"); ln("  [DEL] /home/hub/") end
end

-- Данные
ln("\nData:")
for _, df in ipairs(DATA_FILES) do
  if keep[df.path] then
    ln("  [OK]  " .. df.path .. " (kept)")
  else
    del(df.path)
  end
end

-- Misc
ln("\nMisc:")
if fs.exists("/home/autorun.lua") then
  if askYN("Remove /home/autorun.lua?") then del("/home/autorun.lua") end
end
if askYN("Remove update/uninstall scripts?") then
  del("/home/update_hub.lua")
  del("/home/cleanup_old.lua")
  fs.remove("/home/uninstall_hub.lua")
  ln("  [DEL] /home/uninstall_hub.lua")
end

ln("\n" .. string.rep("-", 50))
ln("Done! To reinstall:")
ln("  wget -q <REPO>/install_hub.lua /tmp/ih.lua && lua /tmp/ih.lua")
ln()
