# GTNH Planet Monitor V2.0

[Русская версия](README.md)

Centralized monitoring system for GregTech multiblocks on remote planets (or within a single base) via **OpenComputers**.
The system works directly with `gt_machine` components over the network, eliminating the need to place separate computers on each planet.

## Features
- Real-time machine status monitoring (OK, STBY, PROB).
- Display of machine activity (ACTIVE/INACTIVE), progress, and problems.
- Remote restart of controllers (Restart (Enter)).
- Remote toggling of machines "(T) Toggle".
- Grouping of machines by planets in a convenient interface.
- Logging of all events (failures, restarts).
- Display of LSC (Lapotronic Supercapacitor) charge and server TPS.

![alt text](image-1.png)
![alt text](image-2.png)
![alt text](image-4.png)

## File Structure
```
/home/
├── hub/
│   ├── main.lua          — Main program loop, interface
│   ├── gui.lua           — Drawing logic (separated into static and dynamic)
│   ├── machines.lua      — Working with GT components (scanning, status, restart)
│   ├── registry.lua      — Database of planets and machines
│   ├── logger.lua        — Buffered logging system
│   ├── stats.lua         — Statistics collection (TPS, LSC)
│   ├── theme.lua         — Color scheme (Solarized Dark) and primitives
│   └── config.lua        — Configuration
├── install_hub.lua       — Installation script
└── update_hub.lua        — Update script
```

## Hardware Requirements
- Server rack with a T3 computer.
  
  ![Rack appearance](image.png)
  
  I use this set of components:<br>
  1: Memory 3.5 - 2 pcs.<br>
  2: CPU T3<br>
  3: Graphics Card T3<br>
  4: Hard Drive T3<br>
  5: Internet Card<br>
  6: Component Bus T3 (If you need to connect more than 16 adapters, use a creative one)
- Monitor T3.
- OpenComputers Adapters connected to multiblock controllers. Adapters are connected using MFU; it is desirable that no other block is adjacent to the faces of the adapter.

## Installation
For the first installation, run in the OpenComputers terminal:
```bash
wget -q https://raw.githubusercontent.com/Kwazzi44/GTNH-OC-Planet-Monitor-v2/main/install_hub.lua 
```
The script will download `install_hub.lua`.
After downloading, run:
```bash
install_hub.lua
```

## Setup
1. Run the setup wizard:
   ```bash
   /home/hub/main.lua
   ```
2. Select **Scan New Machines**. The script will find all disconnected `gt_machine` adapters.
3. For each machine:
   - Enter the planet name (you can choose from the hint list or enter your own).
   - Enter a clear name for the machine. Or leave the name suggested by the program.
4. You can assign one of the adapters as LSC for energy monitoring.
5. Exit the setup using the menu.

## Controls
In the main interface (`lua /home/hub/main.lua`):
- `↑ / ↓` — list navigation.
- `Enter` — open planet details / confirm.
- `B` — back / exit to the list of planets.
- `F4` — open event log.
- `F3` — force poll all machines.
- `A` — restart all stopped machines on the selected planet.
- `T` — toggle machine operation mode (Toggle).
- `Q` or `Esc` — exit the program.

## Update
If a script update is released, press F5 in the script's main menu.
The script will download only the modified files without overwriting your planet database.
