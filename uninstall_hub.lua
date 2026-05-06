-- =============================================================================
-- uninstall_hub.lua — Cleanup script for Hub computer
-- =============================================================================
-- Удаляет все файлы Hub'а. Реестр и лог — по выбору.
-- Запуск: lua /uninstall_hub.lua

local filesystem = require("filesystem")

local function ln(s) io.write((s or "") .. "\n") end
local function hr() ln(string.rep("-", 50)) end
local function ask(p) io.write(p); return io.read() or "" end
local function askYN(p)
  local a = ask(p .. " [y/n]: ")
  return (a:lower() == "y" or a:lower() == "yes")
end

local function del(path)
  if filesystem.exists(path) then
    local ok, err = filesystem.remove(path)
    if ok then
      ln("  [DEL] " .. path)
    else
      ln("  [ERR] " .. path .. " — " .. tostring(err))
    end
  else
    ln("  [--]  " .. path .. " (not found)")
  end
end

local function delDir(path)
  if filesystem.exists(path) then
    -- Удаляем все файлы в директории
    for file in filesystem.list(path) do
      local full = path .. file
      if filesystem.isDirectory(full) then
        delDir(full .. "/")
      else
        del(full)
      end
    end
    -- Удаляем саму директорию
    local ok, err = filesystem.remove(path)
    if ok then
      ln("  [DEL] " .. path .. "  (dir)")
    else
      -- Директория могла не удалиться если не пуста — не критично
      ln("  [~]   " .. path .. " (dir, may not be empty)")
    end
  else
    ln("  [--]  " .. path .. " (not found)")
  end
end

-- ─── Файлы Hub'а ──────────────────────────────────────────────────────────

local HUB_FILES = {
  "/hub/config.lua",
  "/hub/logger.lua",
  "/hub/registry.lua",
  "/hub/machines.lua",
  "/hub/gui.lua",
  "/hub/setup.lua",
  "/hub/main.lua",
}

local DATA_FILES = {
  { path = "/planet_registry.json", desc = "Planet registry (your configuration!)" },
  { path = "/planet_log.txt",       desc = "Event log" },
}

local MISC_FILES = {
  "/home/autorun.lua",
  "/uninstall_hub.lua",
}

-- ─── Запуск ───────────────────────────────────────────────────────────────

hr()
ln("  GTNH Planet Monitor — HUB UNINSTALLER")
hr()
ln()
ln("This will delete all Hub script files.")
ln()

if not askYN("Continue?") then
  ln("Cancelled."); return
end

-- Спросить про данные
local keep_registry = false
local keep_log      = false

ln()
for _, df in ipairs(DATA_FILES) do
  if filesystem.exists(df.path) then
    local keep = askYN("Keep " .. df.desc .. " (" .. df.path .. ")?")
    if df.path == DATA_FILES[1].path then keep_registry = keep end
    if df.path == DATA_FILES[2].path then keep_log = keep end
  end
end

ln()
hr()
ln("Deleting hub scripts...")

-- Удалить скрипты
for _, f in ipairs(HUB_FILES) do del(f) end

-- Попробовать удалить папку /hub/ если пуста
if filesystem.exists("/hub") then
  local empty = true
  for _ in filesystem.list("/hub") do empty = false; break end
  if empty then
    filesystem.remove("/hub")
    ln("  [DEL] /hub/ (dir)")
  else
    ln("  [~]   /hub/ (not empty — some files remain)")
  end
end

-- Данные — по выбору
ln()
ln("Data files:")
if not keep_registry then del(DATA_FILES[1].path)
else ln("  [OK]  " .. DATA_FILES[1].path .. " kept") end

if not keep_log then del(DATA_FILES[2].path)
else ln("  [OK]  " .. DATA_FILES[2].path .. " kept") end

-- autorun
ln()
ln("Misc:")
if filesystem.exists("/home/autorun.lua") then
  if askYN("Remove /home/autorun.lua?") then
    del("/home/autorun.lua")
  else
    ln("  [OK]  /home/autorun.lua kept")
  end
end

-- Самоудаление
ln()
if askYN("Delete this uninstall script too?") then
  -- Удаляем после завершения через небольшой трюк
  local self_path = "/uninstall_hub.lua"
  if filesystem.exists(self_path) then
    filesystem.remove(self_path)
    ln("  [DEL] " .. self_path)
  end
end

hr()
ln("Cleanup complete!")
ln()
ln("To reinstall:")
ln("  wget -q <URL>/install_hub.lua /tmp/ih.lua && lua /tmp/ih.lua")
ln()
