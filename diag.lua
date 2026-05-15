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
  
  -- Проверяем все стандартные методы имён
  local methods = { "getName", "getMachineName", "getBlockName", "getInventoryName", "getCustomName" }
  for _, m in ipairs(methods) do
    if type(proxy[m]) == "function" then
      local ok, val = pcall(proxy[m])
      log("Method " .. m .. "() -> " .. (ok and tostring(val) or ("ERROR: " .. tostring(val))))
    end
  end
  
  -- Выгружаем весь сенсор
  if type(proxy.getSensorInformation) == "function" then
    local ok, data = pcall(proxy.getSensorInformation)
    if ok then
      log("Sensor Information (type: " .. type(data) .. "):")
      if type(data) == "table" then
        for i, v in ipairs(data) do
          -- Заменяем параграфы (цветовые коды) на что-то читаемое в txt
          local clean_str = tostring(v):gsub("§.", "")
          log("  [" .. i .. "] " .. clean_str)
        end
      else
        log("  Data: " .. tostring(data))
      end
    else
      log("Sensor Information -> ERROR: " .. tostring(data))
    end
  else
    log("Sensor Information -> NOT FOUND")
  end
end

if file then file:close() end
log("\n=== Diagnostic Complete ===")
log("Output saved to /home/diag_output.txt")
