-- Preview 角色逻辑模型。
-- 不创建 Scene Node、材质或 Overlay；表现层可通过公开状态接口在后续独立实现。

local PlayerController = {}
PlayerController.__index = PlayerController

local WALK_SPEED = 2.2
local ARRIVAL_DISTANCE = 0.035

local function CopyVector(vector)
    return Vector3(vector.x, vector.y, vector.z)
end

function PlayerController.New(pathRuntime, spawnNodeKey, camera)
    local self = setmetatable({}, PlayerController)
    self.pathRuntime = pathRuntime
    self.spawnNodeKey = spawnNodeKey
    self.camera = camera
    self.position = Vector3.ZERO
    self.rotation = Quaternion()
    self.path = nil
    self.pathIndex = 1
    self.currentNodeKey = spawnNodeKey
    self.targetKey = nil
    self.walking = false
    self.currentEdgeIsCandidate = false
    self.mechanismLocked = false
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

function PlayerController:GetCurrentPartId()
    local record = self.pathRuntime:GetNode(self.currentNodeKey)
    return record and record.partId or nil
end

function PlayerController:SetMechanismLocked(locked)
    self.mechanismLocked = locked == true
    if self.mechanismLocked then
        self.path = nil
        self.walking = false
        self.currentEdgeIsCandidate = false
    end
end

function PlayerController:FollowCurrentNodeVisual(partRenderer)
    if self.walking then
        return false
    end
    local record = self.pathRuntime:GetNode(self.currentNodeKey)
    if not record or not record.node or not partRenderer then
        return false
    end
    local localPoint, localNormal = record.node:GetLocalAnchor(partRenderer.grid, 0.035)
    if not localPoint then
        return false
    end
    local worldPoint = partRenderer:GetPartWorldPoint(record.partId, localPoint)
    local worldNormal = localNormal and partRenderer:GetPartWorldNormal(record.partId, localNormal) or nil
    if not worldPoint then
        return false
    end
    self.position = CopyVector(worldPoint)
    self:SetNodeOrientation({ worldNormal = worldNormal })
    return true
end

function PlayerController:MoveTo(path, targetKey)
    if type(path) ~= "table" or #path == 0 then
        return false, "path is empty"
    end
    if self.walking then
        return false, "player is already walking"
    end
    if self.mechanismLocked then
        return false, "player is locked to a moving part"
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

local function ViewPlaneDistance(camera, fromPoint, toPoint)
    if not camera then
        return (toPoint - fromPoint):Length()
    end
    local view = camera.view
    if not view then
        return (toPoint - fromPoint):Length()
    end
    local fromView = view * fromPoint
    local toView = view * toPoint
    local dx = toView.x - fromView.x
    local dy = toView.y - fromView.y
    return math.sqrt(dx * dx + dy * dy)
end

function PlayerController:GetStepDistance(fromPoint, toPoint, worldDistance, timeStep)
    local worldStep = self.speed * timeStep
    if not self.currentEdgeIsCandidate or not self.camera or worldDistance <= 0.0001 then
        return math.min(worldDistance, worldStep)
    end
    -- 候选边按视平面长度映射速度：屏幕速度对齐普通边，世界步长随深度边拉长。
    local viewDistance = ViewPlaneDistance(self.camera, fromPoint, toPoint)
    if viewDistance <= 0.0001 then
        return math.min(worldDistance, worldStep)
    end
    local viewStep = worldStep * (worldDistance / viewDistance)
    return math.min(worldDistance, viewStep)
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

    local step = self:GetStepDistance(self.position, target.worldPoint, distance, timeStep)
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
