-- 沿当前有效 Path Graph 走路的共用逻辑。
-- 只消费 PathRuntime；不知道点击、机关或演出。
-- 玩家与阿尔吉侬各自持有一份 Walker，驱动层不同。

local PathWalker = {}
PathWalker.__index = PathWalker

local DEFAULT_SPEED = 2.2
local ARRIVAL_DISTANCE = 0.035

local function CopyVector(vector)
    return Vector3(vector.x, vector.y, vector.z)
end

---@class PathWalker
---@field pathRuntime table
---@field camera Camera|nil
---@field name string
---@field speed number
---@field position Vector3
---@field rotation Quaternion
---@field path string[]|nil
---@field pathIndex number
---@field currentNodeKey string
---@field targetKey string|nil
---@field walking boolean
---@field currentEdgeIsCandidate boolean
---@field onStarted fun(targetKey: string)|nil
---@field onArrived fun(nodeKey: string)|nil

---@param pathRuntime table
---@param spawnNodeKey string
---@param camera Camera|nil
---@param options table|nil
---@return PathWalker
function PathWalker.New(pathRuntime, spawnNodeKey, camera, options)
    options = options or {}
    local self = setmetatable({}, PathWalker)
    self.pathRuntime = pathRuntime
    self.spawnNodeKey = spawnNodeKey
    self.camera = camera
    self.name = type(options.name) == "string" and options.name or "walker"
    self.speed = tonumber(options.speed) or DEFAULT_SPEED
    self.position = Vector3.ZERO
    self.rotation = Quaternion()
    self.path = nil
    self.pathIndex = 1
    self.currentNodeKey = spawnNodeKey
    ---@type string|nil
    self.targetKey = nil
    self.walking = false
    self.currentEdgeIsCandidate = false
    self.started = false
    ---@type fun(targetKey: string)|nil
    self.onStarted = nil
    ---@type fun(nodeKey: string)|nil
    self.onArrived = nil
    return self
end

function PathWalker:Start()
    local spawn = self.pathRuntime:GetNode(self.spawnNodeKey)
    if not spawn or not spawn.worldPoint then
        return false, "出生点节点没有可用世界位置"
    end
    self.position = CopyVector(spawn.worldPoint)
    self:SetNodeOrientation(spawn)
    self.started = true
    print("PathWalker: " .. self.name .. " spawned at " .. self.spawnNodeKey)
    return true
end

function PathWalker:SetMovementOrientation(direction, normal)
    local tangent = direction - normal * direction:DotProduct(normal)
    if tangent:Length() > 0.001 then
        local rotation = Quaternion()
        rotation:FromLookRotation(tangent:Normalized(), normal)
        self.rotation = rotation
    end
end

function PathWalker:SetNodeOrientation(record)
    if not record then
        return
    end
    local normal = record.worldNormal and CopyVector(record.worldNormal) or Vector3.UP
    local direction = self.rotation * Vector3.FORWARD
    self:SetMovementOrientation(direction, normal)
end

function PathWalker:Stop()
    self.path = nil
    self.walking = false
    self.currentEdgeIsCandidate = false
    self.targetKey = nil
end

function PathWalker:GetTargetKey()
    return self.targetKey
end

function PathWalker:GetSpeed()
    return self.speed
end

function PathWalker:SetSpeed(speed)
    local value = tonumber(speed)
    if not value or value <= 0 then
        return false
    end
    self.speed = value * 1.0
    return true
end

function PathWalker:TeleportTo(nodeKey)
    local record = self.pathRuntime:GetNode(nodeKey)
    if not record or not record.worldPoint then
        return false, "node-not-found"
    end
    self:Stop()
    self.currentNodeKey = nodeKey
    self.position = CopyVector(record.worldPoint)
    self:SetNodeOrientation(record)
    return true
end

function PathWalker:IsWalking()
    return self.walking
end

function PathWalker:GetCurrentNodeKey()
    return self.currentNodeKey
end

function PathWalker:GetPosition()
    return CopyVector(self.position)
end

function PathWalker:GetRotation()
    return Quaternion(self.rotation)
end

function PathWalker:GetViewState()
    return self.currentEdgeIsCandidate and "topmost" or "normal"
end

function PathWalker:GetCurrentPartId()
    local record = self.pathRuntime:GetNode(self.currentNodeKey)
    return record and record.partId or nil
end

function PathWalker:GetCurrentEdgeTargetKey()
    if not self.walking or not self.path then
        return nil
    end
    return self.path[self.pathIndex + 1]
end

function PathWalker:FollowCurrentNodeVisual(partRenderer)
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

function PathWalker:MoveTo(path, targetKey)
    if type(path) ~= "table" or #path == 0 then
        return false, "path is empty"
    end
    if self.walking and self.targetKey == targetKey then
        return true
    end
    self.path = {}
    for index, key in ipairs(path) do
        self.path[index] = key
    end
    self.targetKey = targetKey
    local first = self.pathRuntime:GetNode(self.path[1])
    local firstPoint = first and first.worldPoint
    local distanceToFirst = firstPoint and (self.position - firstPoint):Length() or 0.0
    if firstPoint and distanceToFirst > ARRIVAL_DISTANCE then
        self.pathIndex = 0
        self.walking = true
        self.currentEdgeIsCandidate = self.pathRuntime:IsCandidateEdge(
            self.currentNodeKey,
            self.path[1]
        ) or self.pathRuntime:IsConfiguredCandidateEdge(
            self.currentNodeKey,
            self.path[1]
        ) or self.currentEdgeIsCandidate
        if self.onStarted then
            self.onStarted(targetKey)
        end
        return true
    end
    self.pathIndex = 1
    local fromKey = self.path[self.pathIndex]
    local toKey = self.path[self.pathIndex + 1]
    self.currentEdgeIsCandidate = self.pathRuntime:IsCandidateEdge(fromKey, toKey)
        or self.pathRuntime:IsConfiguredCandidateEdge(fromKey, toKey)
    self.walking = #self.path > 1
    if self.walking and self.onStarted then
        self.onStarted(targetKey)
    end
    if not self.walking then
        self.path = nil
        if self.onArrived and type(targetKey) == "string" then
            self.onArrived(targetKey)
        end
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

function PathWalker:GetStepDistance(fromPoint, toPoint, worldDistance, timeStep)
    local worldStep = self.speed * timeStep
    if not self.currentEdgeIsCandidate or not self.camera or worldDistance <= 0.0001 then
        return math.min(worldDistance, worldStep)
    end
    local viewDistance = ViewPlaneDistance(self.camera, fromPoint, toPoint)
    if viewDistance <= 0.0001 then
        return math.min(worldDistance, worldStep)
    end
    local viewStep = worldStep * (worldDistance / viewDistance)
    return math.min(worldDistance, viewStep)
end

function PathWalker:Update(timeStep)
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
            local arrivedKey = self.targetKey
            self.path = nil
            self.walking = false
            self.currentEdgeIsCandidate = false
            print("PathWalker: " .. self.name .. " reached " .. tostring(arrivedKey))
            if self.onArrived and type(arrivedKey) == "string" then
                self.onArrived(arrivedKey)
            end
        else
            self.currentEdgeIsCandidate = self.pathRuntime:IsCandidateEdge(
                self.path[self.pathIndex],
                self.path[self.pathIndex + 1]
            ) or self.pathRuntime:IsConfiguredCandidateEdge(
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
    self:SetMovementOrientation(direction, normal)
end

return PathWalker
