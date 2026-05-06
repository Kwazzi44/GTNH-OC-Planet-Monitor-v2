-- =============================================================================
-- install_node.lua — Node Installer
-- =============================================================================
-- Запуск на Node-компьютере (каждая планета):
--   wget -q https://raw.githubusercontent.com/ТВОЙ_НИК/GTNH-OC-Planet-Monitor/main/install_node.lua /tmp/install_node.lua
--   lua /tmp/install_node.lua
--
-- После установки: отредактируй /node/node_config.lua — впиши имя планеты.
-- Требует: Internet Card в компьютере

-- ─── НАСТРОЙКА ────────────────────────────────────────────────────────────
local REPO = "https://raw.githubusercontent.com/ТВОЙ_НИК/GTNH-OC-Planet-Monitor/main"
local INSTALL_DIR = "/"
-- ──────────────────────────────────────────────────────────────────────────

local component  = require("component")
local filesystem = require("filesystem")
local internet   = require("internet")

-- ─── Проверки ─────────────────────────────────────────────────────────────

if not component.isAvailable("internet") then
  io.write("[ERROR] Internet Card not found! Insert it and try again.\n")
  os.exit(1)
end

-- ─── Файлы для скачивания ─────────────────────────────────────────────────

local FILES = {
  { "/protocol.lua",           "/protocol.lua"           },
  { "/node/machines.lua",      "/node/machines.lua"      },
  { "/node/main.lua",          "/node/main.lua"          },
  -- node_config.lua скачивается только если его ещё нет (чтобы не затереть настройки)
  { "/node/node_config.lua",   "/node/node_config.lua", true },
}

-- ─── Утилиты ──────────────────────────────────────────────────────────────

local function mkdirs(path)
  local dir = filesystem.path(path)
  if dir and dir ~= "/" and not filesystem.exists(dir) then
    filesystem.makeDirectory(dir)
  end
end

local function download(url, dest)
  mkdirs(INSTALL_DIR .. dest)
  local full_dest = INSTALL_DIR .. dest:gsub("^/", "")
  local ok, err = pcall(function()
    local response = internet.request(url)
    local f = io.open(full_dest, "w")
    if not f then error("Cannot open file: " .. full_dest) end
    for chunk in response do
      f:write(chunk)
    end
    f:close()
  end)
  return ok, err
end

-- ─── Установка ────────────────────────────────────────────────────────────

io.write("\n")
io.write("===========================================\n")
io.write("  GTNH Planet Monitor — NODE INSTALLER    \n")
io.write("===========================================\n")
io.write("Repository: " .. REPO .. "\n\n")

local success = 0
local failed  = 0
local skipped = 0

for _, entry in ipairs(FILES) do
  local url_path, dest, skip_if_exists = entry[1], entry[2], entry[3]
  local full_dest = INSTALL_DIR .. dest:gsub("^/", "")

  -- Пропускаем node_config.lua если уже настроен
  if skip_if_exists and filesystem.exists(full_dest) then
    io.write(string.format("  [--] %-35s (skipped, already exists)\n", dest))
    skipped = skipped + 1
  else
    local url = REPO .. url_path
    io.write(string.format("  [..] %-35s", dest))
    local ok, err = download(url, dest)
    if ok then
      io.write("\r  [OK] " .. dest .. "\n")
      success = success + 1
    else
      io.write("\r  [!!] " .. dest .. " — FAILED\n")
      io.write("       " .. tostring(err) .. "\n")
      failed = failed + 1
    end
  end
end

io.write("\n")
io.write("-------------------------------------------\n")
io.write(string.format("  Done: %d OK, %d skipped, %d FAILED\n", success, skipped, failed))
io.write("-------------------------------------------\n")

if failed == 0 then

  -- Запросить имя планеты прямо сейчас
  io.write("\nEnter planet name for this node: ")
  local planet = io.read()
  if planet and #planet > 0 then
    -- Патчим node_config.lua — меняем planet_name
    local cfg_path = INSTALL_DIR .. "node/node_config.lua"
    local f = io.open(cfg_path, "r")
    if f then
      local content = f:read("*a")
      f:close()
      content = content:gsub(
        'config%.planet_name%s*=%s*"[^"]*"',
        'config.planet_name = "' .. planet .. '"'
      )
      local fw = io.open(cfg_path, "w")
      if fw then
        fw:write(content)
        fw:close()
        io.write("[OK] Planet name set to: " .. planet .. "\n")
      end
    end
  else
    io.write("[WARN] Planet name not set. Edit /node/node_config.lua manually.\n")
  end

  -- Autorun
  io.write("\nCreate /home/autorun.lua to auto-start on boot? [y/n]: ")
  local ans = io.read()
  if ans and (ans:lower() == "y" or ans:lower() == "yes") then
    local f = io.open("/home/autorun.lua", "w")
    if f then
      f:write('-- Node auto-start\n')
      f:write('shell.execute("/node/main.lua")\n')
      f:close()
      io.write("[OK] /home/autorun.lua created.\n")
    end
  end

  io.write("\nInstallation complete!\n")
  io.write("Run:  lua /node/main.lua\n\n")
else
  io.write("\n[WARN] Some files failed. Check your internet connection and REPO URL.\n\n")
end
