-- =============================================================================
-- protocol.lua — Shared message protocol for Hub <-> Node communication
-- =============================================================================
-- Используется и на Hub, и на Node (одинаковый файл)
-- Все сообщения: Lua-таблицы, сериализованные через serialization API

local serial  = require("serialization")

local protocol = {}

protocol.PORT = 42   -- Единый порт для всех OC-сообщений

-- ─── Типы сообщений ───────────────────────────────────────────────────────

-- Node → Hub
protocol.REGISTER    = "REGISTER"     -- Node регистрируется при старте
protocol.PONG        = "PONG"         -- Ответ на PING (полный статус)
protocol.ALERT       = "ALERT"        -- Асинхронный алерт (машина упала)
protocol.ACK         = "ACK"          -- Результат RESTART
protocol.SCAN_RESULT = "SCAN_RESULT"  -- Результат SCAN (новые машины)

-- Hub → Node
protocol.PING          = "PING"          -- Запрос статуса
protocol.PING_REGISTER = "PING_REGISTER" -- Hub перезапущен, нужна регистрация
protocol.RESTART       = "RESTART"       -- Включить конкретную машину
protocol.RESTART_ALL   = "RESTART_ALL"   -- Включить все выключенные
protocol.SCAN          = "SCAN"          -- Пересканировать адаптеры

-- ─── Encode / Decode ──────────────────────────────────────────────────────

function protocol.encode(msg)
  return serial.serialize(msg)
end

function protocol.decode(raw)
  if type(raw) ~= "string" then return nil end
  local ok, result = pcall(serial.unserialize, raw)
  if ok and type(result) == "table" then
    return result
  end
  return nil
end

-- ─── Конструкторы сообщений (Node → Hub) ──────────────────────────────────

function protocol.mkRegister(planet_name, machines)
  return { type = protocol.REGISTER, planet = planet_name, machines = machines }
end

function protocol.mkPong(planet_name, machines)
  return { type = protocol.PONG, planet = planet_name, machines = machines }
end

function protocol.mkAlert(planet_name, machine_name, msg)
  return { type = protocol.ALERT, planet = planet_name, machine = machine_name, msg = msg }
end

function protocol.mkAck(planet_name, machine_name, ok, msg)
  return { type = protocol.ACK, planet = planet_name, machine = machine_name, ok = ok, msg = msg }
end

function protocol.mkScanResult(planet_name, machines)
  return { type = protocol.SCAN_RESULT, planet = planet_name, machines = machines }
end

-- ─── Конструкторы сообщений (Hub → Node) ──────────────────────────────────

function protocol.mkPing()
  return { type = protocol.PING }
end

function protocol.mkPingRegister()
  return { type = protocol.PING_REGISTER }
end

function protocol.mkRestart(machine_addr)
  return { type = protocol.RESTART, machine = machine_addr }
end

function protocol.mkRestartAll()
  return { type = protocol.RESTART_ALL }
end

function protocol.mkScan()
  return { type = protocol.SCAN }
end

return protocol
