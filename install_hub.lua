-- =============================================================================
-- install_hub.lua — Hub Installer
-- =============================================================================
-- Запуск на Hub-компьютере:
--   wget -q https://raw.githubusercontent.com/ТВОЙ_НИК/GTNH-OC-Planet-Monitor/main/install_hub.lua /tmp/install_hub.lua
--   lua /tmp/install_hub.lua
--
-- Требует: Internet Card в компьютере

-- ─── НАСТРОЙКА ────────────────────────────────────────────────────────────
-- Замени на свой GitHub username и название репозитория:
local REPO = "https://raw.githubusercontent.com/Kwazzi44/GTNH-OC-Planet-Monitor/main"

-- Куда устанавливать файлы (корень файловой системы OC):
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
-- { url_path, local_path }

local FILES = {
  { "/protocol.lua",      "/protocol.lua"      },
  { "/hub/config.lua",    "/hub/config.lua"    },
  { "/hub/logger.lua",    "/hub/logger.lua"    },
  { "/hub/registry.lua",  "/hub/registry.lua"  },
  { "/hub/monitor.lua",   "/hub/monitor.lua"   },
  { "/hub/gui.lua",       "/hub/gui.lua"       },
  { "/hub/main.lua",      "/hub/main.lua"      },
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
io.write("  GTNH Planet Monitor — HUB INSTALLER     \n")
io.write("===========================================\n")
io.write("Repository: " .. REPO .. "\n\n")

local success = 0
local failed  = 0

for _, entry in ipairs(FILES) do
  local url_path, dest = entry[1], entry[2]
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

io.write("\n")
io.write("-------------------------------------------\n")
io.write(string.format("  Done: %d OK, %d FAILED\n", success, failed))
io.write("-------------------------------------------\n")

if failed == 0 then
  -- Создать autorun для Hub
  io.write("\nCreate /home/autorun.lua to auto-start on boot? [y/n]: ")
  local ans = io.read()
  if ans and (ans:lower() == "y" or ans:lower() == "yes") then
    local f = io.open("/home/autorun.lua", "w")
    if f then
      f:write('-- Hub auto-start\n')
      f:write('shell.execute("/hub/main.lua")\n')
      f:close()
      io.write("[OK] /home/autorun.lua created.\n")
    end
  end

  io.write("\nInstallation complete!\n")
  io.write("Run:  lua /hub/main.lua\n\n")
else
  io.write("\n[WARN] Some files failed. Check your internet connection and REPO URL.\n\n")
end
