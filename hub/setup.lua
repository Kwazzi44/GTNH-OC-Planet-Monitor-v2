-- =============================================================================
-- hub/setup.lua — Setup Wizard (Pair: Adapter <-> Redstone side)
-- =============================================================================
-- Запуск: lua /hub/setup.lua
-- Показывает ТОЛЬКО незарегистрированные адаптеры.
-- Каждый адаптер привязывается к планете + redstone-стороне.

package.path = "/home/hub/?.lua;" .. package.path

local component = require("component")
local os        = require("os")
local registry  = require("registry")
local mch       = require("machines")

-- ─── Утилиты ──────────────────────────────────────────────────────────────

local function ln(s)  io.write((s or "") .. "\n") end
local function hr()   ln(string.rep("-", 62)) end

local function ask(prompt)
  io.write(prompt)
  return io.read() or ""
end

local function askYN(prompt)
  local a = ask(prompt .. " [y/n]: ")
  return (a:lower() == "y" or a:lower() == "yes")
end

local SIDES = {
  [0]="DOWN(0)", [1]="UP(1)", [2]="NORTH(2)",
  [3]="SOUTH(3)", [4]="WEST(4)", [5]="EAST(5)"
}

-- ─── Построить карту занятых слотов ──────────────────────────────────────

local function buildUsedSlots()
  local taken_adapters = {}  -- adapter_addr -> "Planet / Machine"
  local taken_redstone = {}  -- rs_addr -> "Planet / Machine"
  for _, planet in pairs(registry.getAll()) do
    for _, m in ipairs(planet.machines or {}) do
      taken_adapters[m.adapter_addr] = planet.name .. " / " .. m.name
      if m.rs_addr then
        taken_redstone[m.rs_addr] = planet.name .. " / " .. m.name
      end
    end
  end
  return taken_adapters, taken_redstone
end

-- ─── Выбор redstone (1:1 — один блок на одну машину) ────────────────────

local function pickRedstone(rs_list, taken_redstone)
  -- Показываем только свободные Redstone I/O блоки
  local free_rs = {}
  for _, rs_addr in ipairs(rs_list) do
    if not taken_redstone[rs_addr] then
      table.insert(free_rs, rs_addr)
    end
  end

  if #free_rs == 0 then
    ln("[!] No free Redstone I/O blocks available.")
    ln("    All redstone blocks are already paired with machines.")
    ln("    Add more Redstone I/O blocks to the network and re-run setup.")
    return nil, nil, nil, nil, nil
  end

  ln("\nFree Redstone I/O blocks:")
  for i, rs_addr in ipairs(free_rs) do
    ln(string.format("  %d. %s", i, rs_addr))
  end
  if #taken_redstone > 0 then
    local n = 0
    for _ in pairs(taken_redstone) do n = n + 1 end
    ln(string.format("  (%d already paired, not shown)", n))
  end

  -- Выбираем блок
  local rs_addr
  if #free_rs == 1 then
    rs_addr = free_rs[1]
    ln("Using only free Redstone I/O: " .. rs_addr)
  else
    local a = ask("Redstone block number (0 = skip): ")
    local n = tonumber(a)
    if not n or n < 1 or n > #free_rs then
      ln("Skipped — no redstone configured.")
      return nil, nil, nil, nil, nil
    end
    rs_addr = free_rs[n]
  end

  -- Сторона
  ln("\nSides: 0=DOWN 1=UP 2=NORTH 3=SOUTH 4=WEST 5=EAST")
  ln("  Enter -1 to broadcast on ALL sides (safe if no other blocks around)")
  local a = ask("Side (-1 or 0-5): ")
  local rs_side = tonumber(a)
  if not rs_side or rs_side < -1 or rs_side > 5 then
    ln("[!] Invalid side. Redstone not configured.")
    return nil, nil, nil, nil, nil
  end

  -- Режим
  ln("\nModes:")
  ln("  pulse  — кратковременный HIGH→LOW (по умолчанию)")
  ln("  enable — выставить HIGH и держать")
  ln("  toggle — LOW→HIGH→LOW")
  local mode_in = ask("Mode [pulse]: ")
  local rs_mode = (mode_in and #mode_in > 0) and mode_in or "pulse"

  local dur = ask("Pulse duration sec [0.5]: ")
  local rs_pulse = tonumber(dur) or 0.5

  return rs_addr, rs_side, nil, rs_mode, rs_pulse
end


-- ─── Выбор/создание планеты ───────────────────────────────────────────────

local function pickOrCreatePlanet()
  local planets = registry.getPlanetList()
  if #planets > 0 then
    ln("\nExisting planets:")
    for i, p in ipairs(planets) do
      ln(string.format("  %d. %-20s (%d machines)", i, p.name, #(p.machines or {})))
    end
    ln("  0. + Create new planet")
    local a = ask("Planet number: ")
    local n = tonumber(a)
    if n and n >= 1 and n <= #planets then
      return planets[n].name
    end
  end
  -- Создать новую
  local name = ask("New planet name: ")
  if not name or #name == 0 then return nil end
  registry.addPlanet(name)
  ln("[OK] Planet created: " .. name)
  return name
end

-- ─── Главная процедура ────────────────────────────────────────────────────

local function setup()
  registry.load()

  hr()
  ln("  GTNH Planet Monitor — Setup Wizard")
  hr()
  ln("Scanning OC network...")
  ln()

  -- Сканировать все компоненты
  local all_adapters = mch.scanNetwork()  -- { addr, name, active }
  local rs_list      = mch.scanRedstone() -- { addr, ... }

  ln(string.format("GT machines found:    %d", #all_adapters))
  ln(string.format("Redstone I/O found:   %d", #rs_list))
  ln()

  -- Построить список занятых адаптеров
  local taken_adapters, taken_redstone = buildUsedSlots()

  -- Отфильтровать незарегистрированные адаптеры
  local free_adapters = {}
  local registered = {}
  for _, gm in ipairs(all_adapters) do
    if taken_adapters[gm.addr] then
      table.insert(registered, gm)
    else
      table.insert(free_adapters, gm)
    end
  end

  -- Показать уже зарегистрированные
  if #registered > 0 then
    ln(string.format("Already registered (%d):", #registered))
    for _, gm in ipairs(registered) do
      ln(string.format("  [=] %-35s %s", gm.name, taken_adapters[gm.addr]))
    end
    ln()
  end

  -- Показать незарегистрированные
  if #free_adapters == 0 then
    ln("All discovered machines are already registered!")
    ln("To add a new machine, connect a new GT Adapter and re-run setup.")
    hr()
    return
  end

  ln(string.format("Unregistered machines (%d) — need configuration:", #free_adapters))
  for i, gm in ipairs(free_adapters) do
    ln(string.format("  %2d. %-35s [%s]", i,
      gm.name, gm.active and "ACTIVE" or "OFFLINE"))
    ln("      " .. gm.addr)
  end
  ln()

  -- Настраиваем каждый незарегистрированный адаптер
  local added = 0
  for _, gm in ipairs(free_adapters) do
    hr()
    ln("CONFIGURE: " .. gm.name)
    ln("  Adapter: " .. gm.addr)
    ln("  Status:  " .. (gm.active and "ACTIVE" or "OFFLINE"))
    ln()

    if not askYN("Add this machine to monitoring?") then
      ln("Skipped.")
    else
      -- Планета
      local pname = pickOrCreatePlanet()
      if not pname then ln("Skipped (no planet)."); goto continue end

      -- Имя машины
      local mname = ask("Machine name [" .. gm.name .. "]: ")
      if not mname or #mname == 0 then mname = gm.name end

      -- Redstone пара
      local rs_addr, rs_side, rs_color, rs_mode, rs_pulse

      if #rs_list > 0 then
        ln("\n-- Redstone configuration for restart --")
        if askYN("Configure redstone restart?") then
          rs_addr, rs_side, rs_color, rs_mode, rs_pulse =
            pickRedstone(rs_list, taken_redstone)
          -- Помечаем redstone как занятый (1:1 — убираем из пула)
          if rs_addr then
            taken_redstone[rs_addr] = pname .. " / " .. mname
          end
        end
      else
        ln("[--] No Redstone I/O in network. Skipping redstone config.")
      end

      -- Сохранить пару
      local ok = registry.addMachine(pname, {
        name         = mname,
        adapter_addr = gm.addr,
        rs_addr      = rs_addr,
        rs_side      = rs_side,
        rs_color     = rs_color,
        rs_mode      = rs_mode,
        rs_pulse     = rs_pulse,
      })

      if ok then
        local rs_info = rs_addr
          and string.format("RS: side=%d %s", rs_side, SIDES[rs_side] or "")
          or  "RS: not configured"
        ln(string.format("[OK] Added: %s -> %s (%s)", mname, pname, rs_info))
        added = added + 1
      else
        ln("[!] Failed to add (duplicate adapter address?)")
      end
    end
    ::continue::
  end

  -- Итоговый реестр
  hr()
  ln(string.format("Done. Added %d machine(s) this session.", added))
  ln()

  local planets = registry.getPlanetList()
  ln(string.format("Current registry (%d planet(s)):", #planets))
  for _, p in ipairs(planets) do
    ln(string.format("  [%s] %d machine(s):", p.name, #(p.machines or {})))
    for _, m in ipairs(p.machines or {}) do
      local rs_info = m.rs_addr
        and string.format("side=%d %s", m.rs_side, SIDES[m.rs_side] or "")
        or  "no RS"
      ln(string.format("    %-30s [%s] %s",
        m.name, m.active and "ACTIVE" or "OFFLINE", rs_info))
    end
  end
  hr()
  ln("Run: lua /hub/main.lua")
  ln()
end

setup()
