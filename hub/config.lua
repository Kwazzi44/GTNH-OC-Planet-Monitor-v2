-- =============================================================================
-- hub/config.lua
-- =============================================================================
local config = {}

config.poll_interval = 10    -- Секунды между опросами машин
config.gui_refresh   = 0.5   -- Частота перерисовки GUI
config.registry_file = "/home/planet_registry.json"
config.log_file      = "/home/planet_log.txt"
config.log_max_lines = 500

return config
