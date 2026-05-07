-- =============================================================================
-- hub/stats.lua — TPS and Energy (LSC) monitoring
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
  _last_realtime = os.time(),
  _last_eu = 0,
  _last_eu_time = computer.uptime()
}

function stats.update(lsc_addr)
  -- 1. Вычисление TPS
  -- os.time() в OC идет со скоростью 72 тика в секунду (игровых), 
  -- но мы можем измерить дрейф uptime (реальные сек)
  local now_uptime = computer.uptime()
  local now_real = os.time()
  
  -- В норме за 1 реальную секунду (uptime) проходит 1000/20 * 72... нет.
  -- Проще: замеряем сколько реальных секунд занимает один игровой тик.
  -- Но в GTNH проще всего замерять через разницу uptime между вызовами.
  -- Мы будем использовать усредненное значение.
  
  -- 2. Опрос Энергии (LSC)
  if lsc_addr then
    local ok, proxy = pcall(component.proxy, lsc_addr)
    if ok and proxy then
      local s = proxy.getStoredEU and proxy.getStoredEU() or 0
      local m = proxy.getEUCapacity and proxy.getEUCapacity() or 1
      
      local dt = now_uptime - stats._last_eu_time
      if dt >= 1.0 then -- замеряем разницу раз в секунду
        stats.energy.diff = (s - stats._last_eu) / dt
        stats._last_eu = s
        stats._last_eu_time = now_uptime
      end
      
      stats.energy.stored = s
      stats.energy.max = m
      stats.energy.percent = (s / m) * 100
    end
  end
  
  -- Оценка TPS (упрощенно)
  -- Если сервер лагает, os.sleep(0.05) длится дольше 0.05 сек.
  -- Но для точного TPS нужен внешний таймер или замер через os.time()
  -- Оставим пока заглушку или простую логику.
  stats.tps = 20.0 -- TODO: Реальный замер через os.clock дрейф
end

return stats
