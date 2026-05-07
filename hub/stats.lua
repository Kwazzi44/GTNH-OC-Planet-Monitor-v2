-- =============================================================================
-- hub/stats.lua — Real-time TPS and LSC Monitoring
-- =============================================================================

local component = require("component")
local computer  = require("computer")

local stats = {
  tps = 20.0,
  energy = {
    stored = 0,
    max = 0,
    diff = 0,
    percent = 0
  },
  _last_uptime = computer.uptime(),
  _last_os_time = os.time(),
  _last_eu = 0,
  _last_eu_time = computer.uptime(),
  _tps_buffer = {20, 20, 20, 20, 20} -- для плавности
}

function stats.update(lsc_addr)
  local now_uptime = computer.uptime()
  local now_os     = os.time()
  
  -- 1. Вычисление TPS
  local dt_real = now_uptime - stats._last_uptime
  if dt_real >= 1.0 then -- обновляем TPS раз в секунду
    -- В Minecraft 1 час игрового времени = 1000 тиков.
    -- Функция os.time() возвращает игровое время в часах (от 0 до 24).
    local dt_os = now_os - stats._last_os_time
    if dt_os < 0 then dt_os = dt_os + 24 end -- переход через полночь
    
    -- Вычисляем TPS: (прошедшие тики / прошедшее реальное время)
    -- dt_os * 1000 — это количество тиков
    local current_tps = (dt_os * 1000) / dt_real
    if current_tps > 20 then current_tps = 20 end
    
    -- Сглаживание (среднее по буферу)
    table.remove(stats._tps_buffer, 1)
    table.insert(stats._tps_buffer, current_tps)
    local sum = 0
    for _, v in ipairs(stats._tps_buffer) do sum = sum + v end
    stats.tps = sum / #stats._tps_buffer
    
    stats._last_uptime = now_uptime
    stats._last_os_time = now_os
  end

  -- 2. Опрос Энергии (LSC)
  if lsc_addr then
    local ok, proxy = pcall(component.proxy, lsc_addr)
    if ok and proxy then
      local getS = proxy.getStoredEU or proxy.getEUStored
      local getM = proxy.getEUCapacity or proxy.getEUMax
      
      local s = getS and getS() or 0
      local m = getM and getM() or 1
      
      local dt_eu = now_uptime - stats._last_eu_time
      if dt_eu >= 1.0 then
        stats.energy.diff = (s - stats._last_eu) / dt_eu
        stats._last_eu = s
        stats._last_eu_time = now_uptime
      end
      
      stats.energy.stored = s
      stats.energy.max = m
      stats.energy.percent = (s / m) * 100
    end
  end
end

return stats
