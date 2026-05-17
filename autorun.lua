-- =============================================================================
-- autorun.lua — Autorun script for GTNH Planet Monitor
-- Place this file in the root directory (/) of your OpenComputers computer.
-- =============================================================================

local shell = require("shell")

-- Ждем полной загрузки системы
os.sleep(1)

-- Запускаем основной скрипт монитора
shell.execute("/home/hub/main.lua")
