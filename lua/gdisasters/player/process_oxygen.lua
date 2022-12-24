if (SERVER) then
    
    function gDisasters_ProcessOxygen()
        if GetConVar("gdisasters_hud_oxygen_enable"):GetInt() == 0 then return end 
        
        for k, v in pairs(player.GetAll()) do 
        
            v:SetNWFloat("BodyOxygen", v.gDisasters.Body.Oxygen)
            
            if ( bit.band( util.PointContents(v:GetPos()), CONTENTS_WATER ) == CONTENTS_WATER ) or v:WaterLevel() >= 3 or v.IsInWater or v.IsInlava then 
                v.gDisasters.Body.Oxygen = math.Clamp(v.gDisasters.Body.Oxygen - engine.TickInterval(), 0,10) 
            
                if v.gDisasters.Body.Oxygen <= 0 then
                
                    if GetConVar("gdisasters_hud_oxygen_damage"):GetInt() == 0 then return end
                
    				if math.random(1, 50)==1 then
    				    local dmg = DamageInfo()
    				    dmg:SetDamage( math.random(1,25) )
    				    dmg:SetAttacker( v )
    				    dmg:SetDamageType( DMG_DROWN  )
                    
    				    v:TakeDamageInfo(  dmg)
                    end
    		    end
            else
                v.gDisasters.Body.Oxygen = math.Clamp(v.gDisasters.Body.Oxygen + 0.1, 0,10)
            end
        end
    end
    for k, v in pairs(ents.FindByClass("npc_*")) do           
        if ( bit.band( util.PointContents(v:GetPos()), CONTENTS_WATER ) == CONTENTS_WATER ) or v:WaterLevel() >= 3 or v.IsInWater or v.IsInlava then 
            timer.Simple(5, function()
                if GetConVar("gdisasters_hud_oxygen_damage"):GetInt() == 0 then return end
                
                if math.random(1, 50)==1 then
                    local dmg = DamageInfo()
                    dmg:SetDamage( math.random(1,25) )
                    dmg:SetAttacker( v )
                    dmg:SetDamageType( DMG_DROWN  )
            
                    v:TakeDamageInfo(  dmg)
                end
            end)

        end

    end

    
end