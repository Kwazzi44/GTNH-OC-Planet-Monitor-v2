






local REPO = "https://raw.githubusercontent.com/Kwazzi44/GTNH-OC-Planet-Monitor-v2/main"

local component  = require("component")
local filesystem = require("filesystem")
local internet   = require("internet")

if not component.isAvailable("internet") then
  io.write("[ERROR] Internet Card not found!\n"); os.exit(1)
end

local FILES = {
  { "/hub/config.lua",      "/home/hub/config.lua"    },
  { "/hub/logger.lua",      "/home/hub/logger.lua"    },
  { "/hub/registry.lua",    "/home/hub/registry.lua"  },
  { "/hub/machines.lua",    "/home/hub/machines.lua"  },
  { "/hub/stats.lua",       "/home/hub/stats.lua"     },
  { "/hub/theme.lua",       "/home/hub/theme.lua"     },
  { "/hub/gui.lua",         "/home/hub/gui.lua"       },
  { "/hub/setup.lua",       "/home/hub/setup.lua"     },
  { "/hub/main.lua",        "/home/hub/main.lua"      },
  { "/update_hub.lua",      "/home/update_hub.lua"    },
  { "/uninstall_hub.lua",   "/home/uninstall_hub.lua" },
  { "/autorun.lua",         "/home/autorun.lua"       },
}

local function mkdirs(dest)
  local dir = filesystem.path(dest)
  if dir and dir ~= "/" and not filesystem.exists(dir) then
    filesystem.makeDirectory(dir)
  end
end

local function download(url, dest)
  mkdirs(dest)
  local bust = "?v=" .. tostring(math.floor(os.time()))
  local ok, err = pcall(function()
    local resp = internet.request(url .. bust)
    local f = assert(io.open(dest, "w"))
    for chunk in resp do f:write(chunk) end
    f:close()
  end)
  return ok, err
end

io.write("\n==========================================\n")
io.write("  GTNH Planet Monitor — HUB INSTALLER    \n")
io.write("==========================================\n\n")

local ok_n, fail_n = 0, 0
for _, e in ipairs(FILES) do
  io.write(string.format("  [..] %-35s", e[2]))
  local ok, err = download(REPO .. e[1], e[2])
  if ok then
    io.write("\r  [OK] " .. e[2] .. "\n"); ok_n = ok_n + 1
  else
    io.write("\r  [!!] " .. e[2] .. "\n")
    io.write("       " .. tostring(err) .. "\n"); fail_n = fail_n + 1
  end
end

io.write(string.format("\nDone: %d OK, %d FAILED\n", ok_n, fail_n))

if fail_n == 0 then

  -- autorun.lua is now downloaded automatically
  io.write("\nInstallation complete!\n")
  io.write("Step 1:  lua /home/hub/setup.lua   (first time only)\n")
  io.write("Step 2:  lua /home/hub/main.lua\n\n")
end
