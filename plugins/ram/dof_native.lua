-- DOFLinx Native MAME Lua
print("==================================================")
print("[DOF NATIVE] Lancement du moteur Lua natif...")
print("==================================================")

local MAME_MEM_DIR = "../"
local active_watches = {}
_G["_dof_native_notifier"] = nil

local in_game = false

local function read_mem(cpu, addr, type)
    if not cpu then return 0 end
    local space = cpu.spaces["program"]
    if not space then return 0 end
    
    if type == "u8" then
        return space:read_u8(addr)
    elseif type == "u16be" then
        return space:read_u16(addr)
    elseif type == "u16le" then
        return space:read_u16(addr)
    elseif type == "u32be" then
        return space:read_u32(addr)
    elseif type == "u32le" then
        return space:read_u32(addr)
    end
    return 0
end

local function trigger_event(evt_type, event_name, desc, old_val, new_val)
    print(string.format("\n=================================="))
    
    if evt_type == "POSITIVE" then
        print(string.format("🟢 [EVENT POP] > %s < declenche !", string.upper(event_name)))
    elseif evt_type == "NEGATIVE" then
        print(string.format("🔴 [EVENT POP] > %s < declenche !", string.upper(event_name)))
    elseif evt_type == "CRITICAL" then
        print(string.format("🔥 [EVENT POP] > %s < declenche !", string.upper(event_name)))
    elseif evt_type == "SYSTEM" then
        print(string.format("⚙️ [EVENT POP] > %s < declenche !", string.upper(event_name)))
    else
        print(string.format("🔵 [EVENT POP] > %s < declenche !", string.upper(event_name)))
    end
    
    if desc then
        print(string.format("   Detail: %s est passe de %d a %d", desc, old_val, new_val))
    end
    print(string.format("==================================\n"))
    
    -- ICI ON POURRA AJOUTER LE CODE UDP/TCP VERS RETROBAT/DOFLINX SERVER
end

local function init_dof_native()
    local rom_name = manager.machine.system.name
    print(string.format("[DOF NATIVE] ROM detectee : %s", rom_name))
    
    local mem_file = MAME_MEM_DIR .. rom_name .. ".MEM"
    local f = io.open(mem_file, "r")
    if not f then
        print(string.format("[DOF NATIVE] Aucun fichier %s n a ete trouve.", rom_name .. ".MEM"))
        return
    end
    f:close()
    
    local success, cfg = pcall(dofile, mem_file)
    if not success or type(cfg) ~= "table" or not cfg.events then
        print("[DOF NATIVE] Erreur lors de la lecture des tables dans " .. mem_file)
        return
    end
    
    print("[DOF NATIVE] Fichier MEM pur interprete avec succes !")
    
    local maincpu = nil
    for tag, device in pairs(manager.machine.devices) do
        if device.spaces and device.spaces["program"] then
            maincpu = device
            break
        end
    end
    
    if not maincpu then
        print("[DOF NATIVE] Aucun CPU compatible trouve !")
        return
    end
    
    for evt_name, watchers in pairs(cfg.events) do
        for _, w in ipairs(watchers) do
            local initial_val = read_mem(maincpu, w.address, w.type)
            table.insert(active_watches, {
                event = evt_name,
                address = w.address,
                type = w.type,
                condition = w.condition,
                desc = w.desc,
                last_value = initial_val
            })
            print(string.format("[DOF NATIVE] Ecoute active: [%s] -> %X (Init: %d) - %s", evt_name, w.address, initial_val, w.desc))
        end
    end
    
    if #active_watches == 0 then
        print("[DOF NATIVE] Aucune adresse trouvee, moteur en veille.")
        return
    end

    _G["_dof_native_notifier"] = emu.add_machine_frame_notifier(function()
        for _, w in ipairs(active_watches) do
            local current_val = read_mem(maincpu, w.address, w.type)
            
            if current_val ~= w.last_value then
                
                -- Detecteur systeme : INSERER PIECE ou DEMARRER PARTIE
                if w.event == "coin" then
                    if current_val < w.last_value and w.last_value > 0 then
                        in_game = true
                        trigger_event("SYSTEM", "GAME_STARTED", "Un credit a ete consomme", w.last_value, current_val)
                    elseif current_val > w.last_value then
                        trigger_event("POSITIVE", "COIN_INSERTED", "Credit ajoute", w.last_value, current_val)
                    end
                else
                    -- On ne declenche les actions de gameplay QUE si on est en jeu
                    if in_game then
                        
                        -- Cas 1: L'adresse DECREASE normalement (ex: perte de vie, tir de bombe)
                        if w.condition == "decrease" then
                            if current_val < w.last_value then
                                -- Action normale (degat pris, arme utilisee)
                                trigger_event("NEGATIVE", w.event, w.desc, w.last_value, current_val)
                                
                                -- EVENEMENT DERIVE 1 : La ressource tombe à 0 !
                                if current_val == 0 then
                                    local empty_evt = w.event .. "_empty"
                                    trigger_event("CRITICAL", empty_evt, w.desc .. " EPUISÉ !", w.last_value, current_val)
                                end
                                
                            elseif current_val > w.last_value then
                                -- EVENEMENT DERIVE 2 : Une ressource censee diminuer a AUGMENTÉ ! 
                                -- Cela veut dire que le joueur a ramasse une vie (1UP), une bombe extra, ou du soin !
                                local gain_evt = w.event .. "_gained"
                                trigger_event("POSITIVE", gain_evt, w.desc .. " RAMASSE !", w.last_value, current_val)
                            end
                            
                        -- Cas 2: L'adresse INCREASE normalement (ex: score, niveau d'arme)
                        elseif w.condition == "increase" then
                            if current_val > w.last_value then
                                trigger_event("POSITIVE", w.event, w.desc, w.last_value, current_val)
                            elseif current_val < w.last_value and current_val == 0 then
                                -- Si une chose positive retombe à 0 (perte d'arme ?)
                                local lost_evt = w.event .. "_lost"
                                trigger_event("NEGATIVE", lost_evt, w.desc .. " PERDU !", w.last_value, current_val)
                            end
                            
                        -- Cas 3: Changement "ANY" (changement d'etat)
                        elseif w.condition == "any" then
                            trigger_event("SYSTEM", w.event .. "_changed", w.desc, w.last_value, current_val)
                        end
                        
                    end
                end
                
                w.last_value = current_val
            end
        end
    end)
    
    print(string.format("[DOF NATIVE] Surveillance intelligente active sur %d variables !", #active_watches))
end

if manager.machine then
    init_dof_native()
end
