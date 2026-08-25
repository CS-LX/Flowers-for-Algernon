-- Preview 角色逻辑模型。
-- 不创建 Scene Node、材质或 Overlay；表现层可通过公开状态接口在后续独立实现。

local PlayerController = {}
PlayerController.__index = PlayerController

local WALK_SPEED = 2.2
local ARRIVAL_DISTANCE = 0.035

local function CopyVector(vector)
    return Vector3(vector.x, vector.y, vector.z)
end

function PlayerController.New(pathRuntime, spawnNodeKey)
    local self = setmetatable({}, PlayerController)
    self.pathRuntime = pathRuntime
    self.spawnNodeKey = spawnNodeKey
    self.position = Vector3.ZERO
    self.rotation = Quaternion()
    self.path = nil
    self.pathIndex = 1
    self.currentNodeKey = spawnNodeKey
    self.targetKey = nil
    self.walking = false
    self.currentEdgeIsCandidate = false
    self.speed = WALK_SPEED
    return self
end

function PlayerController:Start()
    local spawn = self.pathRuntime:GetNode(self.spawnNodeKey)
    if not spawn or not spawn.worldPoint then
        return false, "出生点节点没有可用世界位置"
    end
    self.position = CopyVector(spawn.worldPoint)
    self:SetNodeOrientation(spawn)
    print("Preview Player Model: spawned at " .. self.spawnNodeKey)
    return true
end

function PlayerController:SetNodeOrientation(record)
    if not record then
        return
    end
    local normal = record.worldNormal and CopyVector(record.worldNormal) or Vector3.UP
    local direction = self.rotation * Vector3.FORWARD
    local tangent = direction - normal * direction:DotProduct(normal)
    if tangent:Length() < 0.001 then
        tangent = Vector3.FORWARD - normal * Vector3.FORWARD:DotProduct(normal)
    end
    if tangent:Length() > 0.001 then
        local rotation = Quaternion()
        rotation:FromLookRotation(tangent:Normalized(), normal)
        self.rotation = rotation
    end
end

function PlayerController:Stop()
    self.path = nil
    self.walking = false
    self.currentEdgeIsCandidate = false
end

function PlayerController:IsWalking()
    return self.walking
end

function PlayerController:GetCurrentNodeKey()
    return self.currentNodeKey
end

function PlayerController:GetPosition()
    return CopyVector(self.position)
end

function PlayerController:GetRotation()
    return Quaternion(self.rotation)
end

function PlayerController:GetViewState()
    return self.currentEdgeIsCandidate and "topmost" or "normal"
end

function PlayerController:MoveTo(path, targetKey)
    if type(path) ~= "table" or #path == 0 then
        return false, "path is empty"
    end
    if self.walking then
        return false, "player is already walking"
    end
    self.path = {}
    for index, key in ipairs(path) do
        self.path[index] = key
    end
    self.pathIndex = 1
    self.targetKey = targetKey
    self.currentEdgeIsCandidate = #self.path > 1
        and self.pathRuntime:IsCandidateEdge(self.path[1], self.path[2])
        or false
    self.walking = #self.path > 1
    if not self.walking then
        self.path = nil
    end
    return true
end

function PlayerController:Update(timeStep)
    if not self.walking or not self.path then
        return
    end
    local targetKey = self.path[self.pathIndex + 1]
    local target = self.pathRuntime:GetNode(targetKey)
    if not target or not target.worldPoint then
        self.path = nil
        self.walking = false
        self.currentEdgeIsCandidate = false
        return
    end

    local delta = target.worldPoint - self.position
    local distance = delta:Length()
    if distance <= ARRIVAL_DISTANCE then
        self.position = CopyVector(target.worldPoint)
        self:SetNodeOrientation(target)
        self.currentNodeKey = targetKey
        self.pathIndex = self.pathIndex + 1
        if self.pathIndex >= #self.path then
            self.path = nil
            self.walking = false
            self.currentEdgeIsCandidate = false
            print("Preview Player Model: reached " .. tostring(self.targetKey))
        else
            self.currentEdgeIsCandidate = self.pathRuntime:IsCandidateEdge(
                self.path[self.pathIndex],
                self.path[self.pathIndex + 1]
            )
        end
        return
    end

    local step = math.min(distance, self.speed * timeStep)
    local direction = delta / distance
    self.position = self.position + direction * step
    local normal = target.worldNormal and CopyVector(target.worldNormal) or Vector3.UP
    local tangent = direction - normal * direction:DotProduct(normal)
    if tangent:Length() > 0.001 then
        local rotation = Quaternion()
        rotation:FromLookRotation(tangent:Normalized(), normal)
        self.rotation = rotation
    end
end

return PlayerController
