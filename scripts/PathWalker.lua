-- 沿当前有效 Path Graph 走路的共用逻辑。
-- 只消费 PathRuntime；不知道点击、机关或演出。
-- 玩家与阿尔吉侬各自持有一份 Walker，驱动层不同。

local PathWalker = {}
PathWalker.__index = PathWalker

local DEFAULT_SPEED = 2.2
local ARRIVAL_DISTANCE = 0.035
local DEFAULT_CORNER_RADIUS = 0.16
local DEFAULT_ACCEL_TIME = 0.28
local DEFAULT_DECEL_TIME = 0.34
local DEFAULT_TURN_RATE = 9.0

local function CopyVector(vector)
    return Vector3(vector.x, vector.y, vector.z)
end

---@class PathWalker
---@field pathRuntime table
---@field camera Camera|nil
---@field name string
---@field speed number
---@field smooth boolean
---@field cornerRadius number
---@field accelTime number
---@field decelTime number
---@field turnRate number
---@field currentSpeed number
---@field lastTimeStep number
---@field position Vector3
---@field rotation Quaternion
---@field path string[]|nil
---@field pathIndex number
---@field currentNodeKey string
---@field targetKey string|nil
---@field walking boolean
---@field settledAtNode boolean
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
    self.smooth = options.smooth == true
    self.cornerRadius = tonumber(options.cornerRadius) or DEFAULT_CORNER_RADIUS
    self.accelTime = tonumber(options.accelTime) or DEFAULT_ACCEL_TIME
    self.decelTime = tonumber(options.decelTime) or DEFAULT_DECEL_TIME
    self.turnRate = tonumber(options.turnRate) or DEFAULT_TURN_RATE
    self.currentSpeed = 0.0
    self.lastTimeStep = 0.016
    ---@type table[]|nil
    self.travel = nil
    self.travelIndex = 1
    self.position = Vector3.ZERO
    self.rotation = Quaternion()
    self.path = nil
    self.pathIndex = 1
    self.currentNodeKey = spawnNodeKey
    ---@type string|nil
    self.targetKey = nil
    self.walking = false
    self.settledAtNode = false
    self.currentEdgeIsCandidate = false
    ---@type string|nil
    self.candidateHoldKey = nil
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
    self.settledAtNode = true
    self.started = true
    print("PathWalker: " .. self.name .. " spawned at " .. self.spawnNodeKey)
    return true
end

function PathWalker:SetMovementOrientation(direction, normal)
    local tangent = direction - normal * direction:DotProduct(normal)
    if tangent:Length() <= 0.001 then
        return
    end
    local rotation = Quaternion()
    rotation:FromLookRotation(tangent:Normalized(), normal)
    if self.smooth then
        local dt = self.lastTimeStep
        if dt < 0.0001 then
            dt = 0.0001
        end
        local t = 1.0 - math.exp(-self.turnRate * dt)
        local current = self.rotation
        self.rotation = current:Slerp(rotation, t)
        return
    end
    self.rotation = rotation
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
    self.currentSpeed = 0.0
    self.travel = nil
    self.travelIndex = 1
    self.settledAtNode = true
    self:RefreshCandidateHold()
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
    self.settledAtNode = true
    self.currentSpeed = 0.0
    self.candidateHoldKey = nil
    return true
end

function PathWalker:IsWalking()
    return self.walking
end

function PathWalker:IsSettledAtNode()
    return self.settledAtNode == true and not self.walking
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

function PathWalker:RefreshCandidateHold()
    if self.currentEdgeIsCandidate then
        return
    end
    if not self.candidateHoldKey then
        return
    end
    if not self.pathRuntime:IsPointOnNodeFace(self.candidateHoldKey, self.position) then
        self.candidateHoldKey = nil
    end
end

function PathWalker:GetViewState()
    self:RefreshCandidateHold()
    if self.currentEdgeIsCandidate or self.candidateHoldKey then
        return "topmost"
    end
    return "normal"
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
        self.settledAtNode = false
        self.currentEdgeIsCandidate = self.pathRuntime:IsCandidateEdge(
            self.currentNodeKey,
            self.path[1]
        ) or self.pathRuntime:IsConfiguredCandidateEdge(
            self.currentNodeKey,
            self.path[1]
        ) or self.currentEdgeIsCandidate
        self:BeginTravel()
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
    self.settledAtNode = not self.walking
    if self.walking and self.onStarted then
        self.onStarted(targetKey)
    end
    if not self.walking then
        self.path = nil
        self.settledAtNode = true
        self.travel = nil
        self.travelIndex = 1
        if self.onArrived and type(targetKey) == "string" then
            self.onArrived(targetKey)
        end
    else
        self:BeginTravel()
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

function PathWalker:GetStepDistance(fromPoint, toPoint, worldDistance, timeStep, speed)
    local travelSpeed = speed or self.speed
    local worldStep = travelSpeed * timeStep
    if not self.currentEdgeIsCandidate or not self.camera or worldDistance <= 0.0001 then
        return math.min(worldDistance, worldStep)
    end
    local viewDistance = ViewPlaneDistance(self.camera, fromPoint, toPoint)
    if viewDistance <= 0.0001 then
        return worldDistance
    end
    local viewStep = worldStep * (worldDistance / viewDistance)
    return math.min(worldDistance, viewStep)
end

function PathWalker:IsCandidatePair(fromKey, toKey)
    return self.pathRuntime:IsCandidateEdge(fromKey, toKey)
        or self.pathRuntime:IsConfiguredCandidateEdge(fromKey, toKey)
end

function PathWalker:GetNodePoint(nodeKey)
    local record = nodeKey and self.pathRuntime:GetNode(nodeKey) or nil
    if not record or not record.worldPoint then
        return nil, nil
    end
    return CopyVector(record.worldPoint), record
end

function PathWalker:FinishPath()
    local arrivedKey = self.targetKey
    if self.currentEdgeIsCandidate then
        self.candidateHoldKey = arrivedKey or self.currentNodeKey
    end
    self.path = nil
    self.walking = false
    self.settledAtNode = true
    self.currentEdgeIsCandidate = false
    self.currentSpeed = 0.0
    self.travel = nil
    self.travelIndex = 1
    self:RefreshCandidateHold()
    print("PathWalker: " .. self.name .. " reached " .. tostring(arrivedKey))
    if self.onArrived and type(arrivedKey) == "string" then
        self.onArrived(arrivedKey)
    end
end

local function QuadraticBezier(p0, p1, p2, t)
    local u = 1.0 - t
    return p0 * (u * u) + p1 * (2.0 * u * t) + p2 * (t * t)
end

local function ScreenLength(from, to)
    local dx = to.x - from.x
    local dy = to.y - from.y
    return math.sqrt(dx * dx + dy * dy)
end

local function ScreenBezier(p0, p1, p2, t)
    local u = 1.0 - t
    return Vector2(
        p0.x * (u * u) + p1.x * (2.0 * u * t) + p2.x * (t * t),
        p0.y * (u * u) + p1.y * (2.0 * u * t) + p2.y * (t * t)
    )
end

function PathWalker:AppendTravelSample(point, nodeKey, record, candidate, pathIndex)
    if not point then
        return
    end
    local last = self.travel[#self.travel]
    if last and (last.point - point):Length() < 0.001 then
        if nodeKey then
            last.nodeKey = nodeKey
            last.record = record
            last.pathIndex = pathIndex
        end
        if candidate ~= nil then
            last.candidate = candidate
        end
        return
    end
    self.travel[#self.travel + 1] = {
        point = CopyVector(point),
        nodeKey = nodeKey,
        record = record,
        candidate = candidate == true,
        pathIndex = pathIndex,
    }
end

function PathWalker:GetPortalWaypoint(fromKey, toKey, fallbackFrom, fallbackTo)
    if fromKey and toKey and self:IsCandidatePair(fromKey, toKey) then
        local seam = self.pathRuntime:GetProjectedSeamMid(fromKey, toKey)
        if seam then
            return self.pathRuntime:UnprojectToNode(toKey, seam)
                or self.pathRuntime:UnprojectToNode(fromKey, seam)
        end
        if self.camera and fallbackFrom and fallbackTo then
            local fromScreen = self.camera:WorldToScreenPoint(fallbackFrom)
            local toScreen = self.camera:WorldToScreenPoint(fallbackTo)
            local mid = Vector2(
                (fromScreen.x + toScreen.x) * 0.5,
                (fromScreen.y + toScreen.y) * 0.5
            )
            return self.pathRuntime:UnprojectToNode(toKey, mid)
                or self.pathRuntime:UnprojectToNode(fromKey, mid)
        end
        return fallbackTo
    end
    local portal = fromKey and toKey and self.pathRuntime:GetPortalPoint(fromKey, toKey) or nil
    if portal then
        return portal
    end
    if fallbackFrom and fallbackTo then
        return (fallbackFrom + fallbackTo) * 0.5
    end
    return fallbackTo
end

function PathWalker:BeginTravel()
    self.travel = {}
    self.travelIndex = 1
    if not self.path then
        return
    end
    local currentRecord = self.pathRuntime:GetNode(self.currentNodeKey)
    self:AppendTravelSample(
        self.position,
        nil,
        currentRecord,
        self.currentEdgeIsCandidate,
        self.pathIndex
    )
    local waypoints = {
        {
            key = self.currentNodeKey,
            point = CopyVector(self.position),
            record = currentRecord,
            pathIndex = self.pathIndex,
            candidate = self.currentEdgeIsCandidate,
        },
    }
    local startIndex = self.pathIndex + 1
    if startIndex < 1 then
        startIndex = 1
    end
    for index = startIndex, #self.path do
        local toKey = self.path[index]
        local toRecord = self.pathRuntime:GetNode(toKey)
        local toPoint = toRecord and toRecord.worldPoint or nil
        if toRecord and toPoint then
            local from = waypoints[#waypoints]
            local portal = self:GetPortalWaypoint(from.key, toKey, from.point, toPoint)
            if portal then
                waypoints[#waypoints + 1] = {
                    key = toKey,
                    point = CopyVector(portal),
                    record = toRecord,
                    pathIndex = index,
                    candidate = self:IsCandidatePair(from.key, toKey),
                }
            end
        end
    end
    local lastKey = self.path[#self.path]
    local lastPoint, lastRecord = self:GetNodePoint(lastKey)
    if lastPoint then
        local lastWp = waypoints[#waypoints]
        if not lastWp or (lastWp.point - lastPoint):Length() > ARRIVAL_DISTANCE then
            waypoints[#waypoints + 1] = {
                key = lastKey,
                point = lastPoint,
                record = lastRecord,
                pathIndex = #self.path,
                candidate = false,
            }
        end
    end
    if #waypoints < 2 then
        return
    end
    for index = 2, #waypoints do
        local prev = waypoints[index - 1]
        local curr = waypoints[index]
        local nextWp = waypoints[index + 1]
        local candidate = curr.candidate == true
        if nextWp and candidate and self.camera then
            local prevScreen = self.camera:WorldToScreenPoint(prev.point)
            local currScreen = self.camera:WorldToScreenPoint(curr.point)
            local nextScreen = self.camera:WorldToScreenPoint(nextWp.point)
            local incoming = ScreenLength(prevScreen, currScreen)
            local outgoing = ScreenLength(currScreen, nextScreen)
            local turnDot = 1.0
            local radius = 0.0
            if incoming > 0.0001 and outgoing > 0.0001 then
                local ix = (currScreen.x - prevScreen.x) / incoming
                local iy = (currScreen.y - prevScreen.y) / incoming
                local ox = (nextScreen.x - currScreen.x) / outgoing
                local oy = (nextScreen.y - currScreen.y) / outgoing
                turnDot = ix * ox + iy * oy
                radius = math.min(0.04, incoming * 0.45, outgoing * 0.45)
            end
            if radius >= 0.004 and turnDot < 0.94 then
                local ix = (currScreen.x - prevScreen.x) / incoming
                local iy = (currScreen.y - prevScreen.y) / incoming
                local ox = (nextScreen.x - currScreen.x) / outgoing
                local oy = (nextScreen.y - currScreen.y) / outgoing
                local p0 = Vector2(currScreen.x - ix * radius, currScreen.y - iy * radius)
                local p1 = Vector2(currScreen.x, currScreen.y)
                local p2 = Vector2(currScreen.x + ox * radius, currScreen.y + oy * radius)
                local function AppendScreen(screen, nodeKey)
                    local world = self.pathRuntime:UnprojectToNode(curr.key, screen)
                        or self.pathRuntime:UnprojectToNode(prev.key, screen)
                    if world then
                        self:AppendTravelSample(world, nodeKey, curr.record, true, curr.pathIndex)
                    end
                end
                AppendScreen(p0, nil)
                for sample = 1, 6 do
                    AppendScreen(ScreenBezier(p0, p1, p2, sample / 6.0), sample == 3 and curr.key or nil)
                end
                AppendScreen(p2, curr.key)
            else
                self:AppendTravelSample(curr.point, curr.key, curr.record, true, curr.pathIndex)
            end
        elseif nextWp then
            local incoming = curr.point - prev.point
            local outgoing = nextWp.point - curr.point
            local incomingLength = incoming:Length()
            local outgoingLength = outgoing:Length()
            local radius = 0.0
            local turnDot = 1.0
            if incomingLength > 0.0001 and outgoingLength > 0.0001 then
                turnDot = (incoming / incomingLength):DotProduct(outgoing / outgoingLength)
                radius = math.min(self.cornerRadius, incomingLength * 0.45, outgoingLength * 0.45)
            end
            if radius >= 0.04 and turnDot < 0.94 then
                local incomingDir = incoming / incomingLength
                local outgoingDir = outgoing / outgoingLength
                local p0 = curr.point - incomingDir * radius
                local p1 = curr.point
                local p2 = curr.point + outgoingDir * radius
                self:AppendTravelSample(p0, nil, curr.record, false, curr.pathIndex)
                for sample = 1, 6 do
                    local t = sample / 6.0
                    self:AppendTravelSample(
                        QuadraticBezier(p0, p1, p2, t),
                        sample == 3 and curr.key or nil,
                        curr.record,
                        false,
                        curr.pathIndex
                    )
                end
                self:AppendTravelSample(p2, curr.key, curr.record, false, curr.pathIndex)
            else
                self:AppendTravelSample(curr.point, curr.key, curr.record, false, curr.pathIndex)
            end
        else
            self:AppendTravelSample(curr.point, curr.key, curr.record, candidate, curr.pathIndex)
        end
    end
end

function PathWalker:GetTravelRemaining()
    if not self.travel or self.travelIndex >= #self.travel then
        return 0.0
    end
    local remaining = 0.0
    local from = self.position
    for index = self.travelIndex + 1, #self.travel do
        local sample = self.travel[index]
        if sample.candidate and self.camera then
            remaining = remaining + ViewPlaneDistance(self.camera, from, sample.point)
        else
            remaining = remaining + (sample.point - from):Length()
        end
        from = sample.point
    end
    return remaining
end

function PathWalker:ConsumeTravelSample(sample)
    if sample.candidate ~= nil then
        self.currentEdgeIsCandidate = sample.candidate
        if sample.candidate then
            self.candidateHoldKey = sample.nodeKey or self.currentNodeKey
        end
    end
    if type(sample.pathIndex) == "number" and sample.pathIndex > self.pathIndex then
        self.pathIndex = sample.pathIndex
    end
    if sample.nodeKey then
        self.currentNodeKey = sample.nodeKey
        if self.currentEdgeIsCandidate then
            self.candidateHoldKey = sample.nodeKey
        end
    end
    self:RefreshCandidateHold()
end

function PathWalker:UpdateDesiredSpeed(remaining)
    local maxSpeed = self.speed
    local desired = maxSpeed
    local decelDistance = maxSpeed * self.decelTime
    if remaining < decelDistance and decelDistance > 0.0001 then
        desired = maxSpeed * (remaining / decelDistance)
        if desired < maxSpeed * 0.12 then
            desired = maxSpeed * 0.12
        end
    end
    return desired
end

function PathWalker:TickSpeed(desired, timeStep)
    local maxSpeed = self.speed
    local accel = maxSpeed / math.max(self.accelTime, 0.05)
    local decel = maxSpeed / math.max(self.decelTime, 0.05)
    if self.currentSpeed < desired then
        self.currentSpeed = math.min(desired, self.currentSpeed + accel * timeStep)
    else
        self.currentSpeed = math.max(desired, self.currentSpeed - decel * timeStep)
    end
end

function PathWalker:UpdateSmooth(timeStep)
    if not self.travel or #self.travel < 2 then
        self:BeginTravel()
    end
    if not self.travel or #self.travel < 2 then
        self:FinishPath()
        return
    end
    if self.travelIndex >= #self.travel then
        local last = self.travel[#self.travel]
        if last and last.point then
            self.position = CopyVector(last.point)
        end
        self:FinishPath()
        return
    end

    local remaining = self:GetTravelRemaining()
    local desired = self:UpdateDesiredSpeed(remaining)
    if remaining < ARRIVAL_DISTANCE * 4.0 then
        desired = math.min(desired, self.speed * 0.18)
    end
    self:TickSpeed(desired, timeStep)

    local budget = self.currentSpeed * timeStep
    local guard = 0
    while budget > 0.00001 and self.travelIndex < #self.travel and guard < 32 do
        guard = guard + 1
        local nextSample = self.travel[self.travelIndex + 1]
        if not nextSample then
            break
        end
        local delta = nextSample.point - self.position
        local distance = delta:Length()
        if distance <= 0.0001 then
            self.travelIndex = self.travelIndex + 1
            self:ConsumeTravelSample(nextSample)
        else
            self.currentEdgeIsCandidate = nextSample.candidate == true
            if self.currentEdgeIsCandidate then
                self.candidateHoldKey = nextSample.nodeKey or self.currentNodeKey
            end
            local step = self:GetStepDistance(
                self.position,
                nextSample.point,
                distance,
                timeStep,
                budget / math.max(timeStep, 0.0001)
            )
            if step >= distance - 0.0001 then
                self.position = CopyVector(nextSample.point)
                budget = budget - distance
                self.travelIndex = self.travelIndex + 1
                self:ConsumeTravelSample(nextSample)
            else
                local direction = delta / distance
                self.position = self.position + direction * step
                local normal = nextSample.record and nextSample.record.worldNormal
                    and CopyVector(nextSample.record.worldNormal)
                    or Vector3.UP
                self:SetMovementOrientation(direction, normal)
                budget = 0.0
            end
        end
    end

    if self.travelIndex >= #self.travel then
        local last = self.travel[#self.travel]
        if last and last.point then
            self.position = CopyVector(last.point)
        end
        self:FinishPath()
    end
end

function PathWalker:Update(timeStep)
    if not self.walking or not self.path then
        return
    end
    if timeStep < 0.0001 then
        timeStep = 0.0001
    end
    self.lastTimeStep = timeStep
    self:UpdateSmooth(timeStep)
end

return PathWalker
