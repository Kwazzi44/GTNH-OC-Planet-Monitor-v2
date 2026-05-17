local fs = require("filesystem")

local function del(path)
  if fs.exists(path) then
    fs.remove(path)
    print("Deleted: " .. path)
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
  print("Deleted dir: " .. path)
end

print("GTNH Planet Monitor -- UNINSTALLER")
print("This will delete ALL files including data!")
io.write("Are you sure? [y/n]: ")
local a = io.read()
if a and a:lower() == "y" then
  delDir("/home/hub/")
  del("/home/planet_registry.json")
  del("/home/planet_log.txt")
  del("/home/autorun.lua")
  del("/home/update_hub.lua")
  del("/home/cleanup_old.lua")
  del("/home/diag.lua")
  del("/home/1")
  
  fs.remove("/home/uninstall_hub.lua")
  print("Uninstallation complete!")
else
  print("Cancelled.")
end
