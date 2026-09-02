-- 玩家驱动层。
-- 走路走共用 PathWalker；点击、机关锁定属于玩家，不属于 Graph。

local PathWalker = require "PathWalker"

local PlayerController = {}
PlayerController.__index = PlayerController

function PlayerController.New(pathRuntime, spawnNodeKey, camera)
    local self = setmetatable({}, PlayerController)
    self.walker = PathWalker.New(pathRuntime, spawnNodeKey, camera, {
        name = "player",
    })
    self.mechanismLocked = false
    self.arrivedListeners = {}
    self.walker.onArrived = function(nodeKey)
        if self.arrivedListeners[1] then
            for _, listener in ipairs(self.arrivedListeners) do
                listener(nodeKey)
            end
        end
    end
    return self
end

function PlayerController:Start()
    return self.walker:Start()
end

function PlayerController:Stop()
    self.walker:Stop()
end

function PlayerController:GetTargetKey()
    return self.walker:GetTargetKey()
end

function PlayerController:GetSpeed()
    return self.walker:GetSpeed()
end

function PlayerController:SetSpeed(speed)
    return self.walker:SetSpeed(speed)
end

function PlayerController:TeleportTo(nodeKey)
    if self.mechanismLocked then
        return false, "player is locked to a moving part"
    end
    return self.walker:TeleportTo(nodeKey)
end

function PlayerController:IsWalking()
    return self.walker:IsWalking()
end

function PlayerController:GetCurrentNodeKey()
    return self.walker:GetCurrentNodeKey()
end

function PlayerController:GetPosition()
    return self.walker:GetPosition()
end

function PlayerController:GetRotation()
    return self.walker:GetRotation()
end

function PlayerController:GetViewState()
    return self.walker:GetViewState()
end

function PlayerController:GetCurrentPartId()
    return self.walker:GetCurrentPartId()
end

function PlayerController:SetMechanismLocked(locked)
    self.mechanismLocked = locked == true
    if self.mechanismLocked then
        self.walker:Stop()
    end
end

function PlayerController:FollowCurrentNodeVisual(partRenderer)
    return self.walker:FollowCurrentNodeVisual(partRenderer)
end

function PlayerController:SetOnStarted(listener)
    self.walker.onStarted = listener
end

function PlayerController:SetOnArrived(listener)
    self.arrivedListeners = {}
    if type(listener) == "function" then
        self.arrivedListeners[1] = listener
    end
end

function PlayerController:AddOnArrived(listener)
    if type(listener) == "function" then
        self.arrivedListeners[#self.arrivedListeners + 1] = listener
    end
end

function PlayerController:MoveTo(path, targetKey)
    if self.mechanismLocked then
        return false, "player is locked to a moving part"
    end
    return self.walker:MoveTo(path, targetKey)
end

function PlayerController:Update(timeStep)
    if self.mechanismLocked then
        return
    end
    self.walker:Update(timeStep)
end

return PlayerController
