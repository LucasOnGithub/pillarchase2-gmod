-- Clientside backup for headless ragdoll bone hiding. The server
-- scales the bones, and this ensures late-joining clients see the same.
if SERVER then return end

local nextCheck = 0
hook.Add("Think", "PC2_EXEExecutionHeadlessRagdolls", function()
    if CurTime() < nextCheck then return end
    nextCheck = CurTime() + 0.2
    for _, rag in ipairs(ents.FindByClass("prop_ragdoll")) do
        if not rag:GetNWBool("PC2_EXEHeadless", false)
            or rag.PC2EXEHeadHidden then continue end

        local root = rag:LookupBone("ValveBiped.Bip01_Head1")
            or rag:LookupBone("Head") or rag:LookupBone("head")
        if rag:GetBoneCount() == nil then continue end
        for bone = 0, rag:GetBoneCount() - 1 do
            local name = string.lower(rag:GetBoneName(bone) or "")
            local hide = name:find("head", 1, true)
                or name:find("jaw", 1, true)
                or name:find("face", 1, true)
                or name:find("eye", 1, true)
                or name:find("hair", 1, true)
                or name:find("teeth", 1, true)
            local parent = rag:GetBoneParent(bone)
            while parent and parent >= 0 do
                if parent == root then hide = true break end
                parent = rag:GetBoneParent(parent)
            end
            if hide then rag:ManipulateBoneScale(bone, Vector(0, 0, 0)) end
        end
        rag.PC2EXEHeadHidden = true
    end
end)

-- Server SetNoDraw is replicated, but ensure the actual victim model stays
-- invisible even if rendering prediction lags behind the execution state.
hook.Add("PrePlayerDraw", "PC2_EXEExecutionHideVictim", function(ply)
    if ply:GetNWBool("PC2_EXEBeingExecuted", false) then return true end
end)
