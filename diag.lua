local component = require("component")

local file = io.open("/home/diag_output.txt", "w")
local function log(msg)
  print(msg)
  if file then file:write(msg .. "\n") end
end

log("=== GTNH Machine Diagnostic ===")
local count = 0
for addr, _ in component.list("gt_machine") do
  count = count + 1
  log("\n--- Machine #" .. count .. " | Address: " .. string.sub(addr, 1, 12) .. "... ---")
  local proxy = component.proxy(addr)
  
  -- Dump all methods available in the proxy
  local available_methods = {}
  for k, v in pairs(proxy) do
    table.insert(available_methods, k)
  end
  log("Available methods: " .. table.concat(available_methods, ", "))
  
  -- Try to call getName directly
  local ok, val = pcall(proxy.getName)
  log("getName() -> " .. (ok and tostring(val) or ("ERROR: " .. tostring(val))))
  
  -- Try to call getSensorInformation directly
  local sok, sdata = pcall(proxy.getSensorInformation)
  if sok then
    log("Sensor Information (type: " .. type(sdata) .. "):")
    if type(sdata) == "table" then
      for i, v in ipairs(sdata) do
        local clean_str = tostring(v):gsub("§.", "")
        log("  [" .. i .. "] " .. clean_str)
      end
    else
      log("  Data: " .. tostring(sdata))
    end
  else
    log("Sensor Information -> ERROR: " .. tostring(sdata))
  end
end

if file then file:close() end
log("\n=== Diagnostic Complete ===")
log("Output saved to /home/diag_output.txt")
