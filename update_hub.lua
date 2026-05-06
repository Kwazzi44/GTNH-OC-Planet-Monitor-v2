-- =============================================================================
-- update_hub.lua — Обновление файлов Hub с GitHub
-- =============================================================================
-- Скачивает свежие версии всех скриптов, НЕ трогает реестр и лог.
-- Запуск: lua /update_hub.lua
-- Или через wget:
--   wget -q <REPO>/update_hub.lua /tmp/upd.lua && lua /tmp/upd.lua

local REPO = "https://raw.githubusercontent.com/ТВОЙ_НИК/GTNH-OC-Planet-Monitor/main"

local component  = require("component")
local filesystem = require("filesystem")
local internet   = require("internet")

if not component.isAvailable("internet") then
  io.write("[ERROR] Internet Card not found!\n"); os.exit(1)
end

-- Только скрипты — данные не трогаем
local FILES = {
  { "/hub/config.lua",      "/hub/config.lua"      },
  { "/hub/logger.lua",      "/hub/logger.lua"       },
  { "/hub/registry.lua",    "/hub/registry.lua"     },
  { "/hub/machines.lua",    "/hub/machines.lua"     },
  { "/hub/gui.lua",         "/hub/gui.lua"          },
  { "/hub/setup.lua",       "/hub/setup.lua"        },
  { "/hub/main.lua",        "/hub/main.lua"         },
  { "/install_hub.lua",     "/install_hub.lua"      },
  { "/update_hub.lua",      "/update_hub.lua"       },
  { "/uninstall_hub.lua",   "/uninstall_hub.lua"    },
}

local function mkdirs(dest)
  local dir = filesystem.path(dest)
  if dir and dir ~= "/" and not filesystem.exists(dir) then
    filesystem.makeDirectory(dir)
  end
end

local function download(url, dest)
  mkdirs(dest)
  local ok, err = pcall(function()
    local resp = internet.request(url)
    local f = assert(io.open(dest, "w"))
    for chunk in resp do f:write(chunk) end
    f:close()
  end)
  return ok, err
end

io.write("\n")
io.write("==========================================\n")
io.write("  GTNH Planet Monitor — UPDATER          \n")
io.write("==========================================\n")
io.write("Repository: " .. REPO .. "\n")
io.write("[NOTE] Registry and log are NOT touched.\n\n")

local ok_n, fail_n = 0, 0

for _, e in ipairs(FILES) do
  io.write(string.format("  [..] %-30s", e[2]))
  local ok, err = download(REPO .. e[1], e[2])
  if ok then
    io.write("\r  [OK] " .. e[2] .. "\n"); ok_n = ok_n + 1
  else
    io.write("\r  [!!] " .. e[2] .. "\n")
    io.write("       " .. tostring(err) .. "\n"); fail_n = fail_n + 1
  end
end

io.write("\n")
io.write(string.format("Done: %d updated, %d failed\n", ok_n, fail_n))

if fail_n == 0 then
  io.write("\nUpdate complete! Run: lua /hub/main.lua\n\n")
else
  io.write("\n[WARN] Some files failed. Check REPO URL and internet connection.\n\n")
end
