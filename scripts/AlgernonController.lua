-- 阿尔吉侬驱动层。
-- 走路走同一份 PathRuntime / PathWalker；只接受演出指令，不响应点击。
-- 默认关闭：没启用时不出现、不走路，现有关卡观感不变。

local PathWalker = require "PathWalker"

local AlgernonController = {}
AlgernonController.__index = AlgernonController

local DEFAULT_SPEED = 2.4

---@class AlgernonController
---@field walker table
---@field pathRuntime table
---@field enabled boolean
---@field visible boolean

function AlgernonController.New(pathRuntime, spawnNodeKey, camera)
    local self = setmetatable({}, AlgernonController)
    self.pathRuntime = pathRuntime
    self.spawnNodeKey = spawnNodeKey
    self.walker = PathWalker.New(pathRuntime, spawnNodeKey, camera, {
        name = "algernon",
        speed = DEFAULT_SPEED,
    })
    self.enabled = false
    self.visible = false
    return self
end

function AlgernonController:IsEnabled()
    return self.enabled == true
end

function AlgernonController:IsVisible()
    return self.enabled and self.visible
end

function AlgernonController:SetVisible(visible)
    if not self.enabled then
        return false
    end
    self.visible = visible ~= false
    return true
end

---@param enabled boolean
---@param nodeKey string|nil
---@return boolean, string|nil
function AlgernonController:SetEnabled(enabled, nodeKey)
    if enabled then
        local spawnKey = nodeKey
        if type(spawnKey) ~= "string" or spawnKey == "" then
            spawnKey = self.walker:GetCurrentNodeKey() or self.spawnNodeKey
        end
        if not self.walker.started then
            local started, startError = self.walker:Start()
            if not started then
                return false, startError
            end
        end
        local teleported, teleportError = self.walker:TeleportTo(spawnKey)
        if not teleported then
            return false, teleportError
        end
        self.enabled = true
        self.visible = true
        print("AlgernonController: enabled at " .. tostring(spawnKey))
        return true
    end
    self.walker:Stop()
    self.enabled = false
    self.visible = false
    print("AlgernonController: disabled")
    return true
end

function AlgernonController:GetWalker()
    return self.walker
end

function AlgernonController:GetCurrentNodeKey()
    return self.walker:GetCurrentNodeKey()
end

function AlgernonController:GetPosition()
    return self.walker:GetPosition()
end

function AlgernonController:GetRotation()
    return self.walker:GetRotation()
end

function AlgernonController:GetViewState()
    return self.walker:GetViewState()
end

function AlgernonController:GetCurrentPartId()
    return self.walker:GetCurrentPartId()
end

function AlgernonController:IsWalking()
    return self.enabled and self.walker:IsWalking()
end

function AlgernonController:GetTargetKey()
    return self.walker:GetTargetKey()
end

function AlgernonController:SetSpeed(speed)
    return self.walker:SetSpeed(speed)
end

function AlgernonController:GetSpeed()
    return self.walker:GetSpeed()
end

function AlgernonController:SetOnArrived(listener)
    self.walker.onArrived = listener
end

function AlgernonController:Stop()
    if not self.enabled then
        return false
    end
    self.walker:Stop()
    return true
end

function AlgernonController:TeleportTo(nodeKey)
    if not self.enabled then
        return false, "algernon disabled"
    end
    return self.walker:TeleportTo(nodeKey)
end

---@param nodeKey string
---@return boolean, string|nil
function AlgernonController:MoveTo(nodeKey)
    if not self.enabled then
        return false, "algernon disabled"
    end
    if type(nodeKey) ~= "string" or nodeKey == "" then
        return false, "empty node key"
    end
    local path, errorMessage = self.pathRuntime:FindPath(
        self.walker:GetCurrentNodeKey(),
        nodeKey
    )
    if not path then
        return false, errorMessage
    end
    return self.walker:MoveTo(path, nodeKey)
end

---@param worldPoint Vector3
---@return boolean, string|nil
function AlgernonController:MoveToWorld(worldPoint)
    if not self.enabled then
        return false, "algernon disabled"
    end
    local record = self.pathRuntime:FindNearestWalkableNode(worldPoint)
    if not record then
        return false, "no-walkable-node"
    end
    return self:MoveTo(record.key)
end

function AlgernonController:FollowCurrentNodeVisual(partRenderer)
    if not self.enabled then
        return false
    end
    return self.walker:FollowCurrentNodeVisual(partRenderer)
end

function AlgernonController:Update(timeStep)
    if not self.enabled then
        return
    end
    self.walker:Update(timeStep)
end

return AlgernonController
