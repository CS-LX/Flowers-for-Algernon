-- 沿当前有效 Path Graph 走路的共用逻辑。
-- 只消费 PathRuntime；不知道点击、机关或演出。
-- 玩家与阿尔吉侬各自持有一份 Walker，驱动层不同。

local PathWalker = {}
PathWalker.__index = PathWalker

local DEFAULT_SPEED = 2.2
local ARRIVAL_DISTANCE = 0.035
-- 屏幕几乎重叠的沿 Y 候选边：按视平面速度走；世界距离再大，也按屏幕位移计时。

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
---@field settledAtNode boolean
---@field currentEdgeIsCandidate boolean
---@field candidateHoldKey string|nil
---@field travel table[]|nil
---@field travelIndex number
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
    self.travel = nil
    self.travelIndex = 1
    self.settledAtNode = true
    self:RefreshCandidateHold()
end

-- 演出截停：先停在当前 hop 的目标节点，不瞬移、不中途冻住。
-- 已在节点上则直接停。正在走路则把路径裁到即将到达的那个节点。
-- 第二个返回值 settled：true 表示已经站在节点上，false 表示还在走到停点。
function PathWalker:StopAtCurrentNode()
    if not self.walking or not self.path then
        self:Stop()
        return true, true
    end
    local stopKey = self.path[self.pathIndex]
    if type(stopKey) ~= "string" or stopKey == "" then
        stopKey = self.currentNodeKey
    end
    local nextKey = self.path[self.pathIndex + 1]
    if type(nextKey) == "string" and nextKey ~= "" then
        stopKey = nextKey
    end
    if type(stopKey) ~= "string" or stopKey == "" then
        self:Stop()
        return true, true
    end
    if self.targetKey == stopKey then
        return true, false
    end
    local fromKey = self.currentNodeKey
    if self.pathIndex > 0 then
        local pathFrom = self.path[self.pathIndex]
        if type(pathFrom) == "string" and pathFrom ~= "" then
            fromKey = pathFrom
        end
    end
    if type(fromKey) == "string" and fromKey ~= "" and fromKey ~= stopKey then
        self.path = { fromKey, stopKey }
        self.pathIndex = 1
    else
        self.path = { stopKey }
        self.pathIndex = 0
    end
    self.targetKey = stopKey
    self.walking = true
    self.settledAtNode = false
    self:BeginTravel()
    print("PathWalker: " .. self.name .. " stopping at " .. stopKey)
    return true, false
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
    if self.walking and self.travel then
        local current = self.travel[self.travelIndex]
        local nextSample = self.travel[self.travelIndex + 1]
        if (current and current.topmost) or (nextSample and nextSample.topmost) then
            return "topmost"
        end
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
    self.travel = nil
    self.travelIndex = 1
    self:RefreshCandidateHold()
    print("PathWalker: " .. self.name .. " reached " .. tostring(arrivedKey))
    if self.onArrived and type(arrivedKey) == "string" then
        self.onArrived(arrivedKey)
    end
end

function PathWalker:AppendTravelSample(point, nodeKey, record, candidate, pathIndex, topmost)
    if not point then
        return
    end
    local isTopmost = topmost == true or candidate == true
    local last = self.travel[#self.travel]
    if last and (last.point - point):Length() < 0.001 then
        if nodeKey then
            last.nodeKey = nodeKey
            last.record = record
            last.pathIndex = pathIndex
        end
        if candidate ~= nil then
            last.candidate = candidate == true
        end
        if isTopmost then
            last.topmost = true
        end
        return
    end
    self.travel[#self.travel + 1] = {
        point = CopyVector(point),
        nodeKey = nodeKey,
        record = record,
        candidate = candidate == true,
        topmost = isTopmost,
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

function PathWalker:GetCandidateSeams(fromKey, toKey, fallbackFrom, fallbackTo)
    local fromSeam = nil
    local toSeam = nil
    local seam = fromKey and toKey and self.pathRuntime:GetProjectedSeamMid(fromKey, toKey) or nil
    if seam then
        fromSeam = self.pathRuntime:UnprojectToNode(fromKey, seam)
        toSeam = self.pathRuntime:UnprojectToNode(toKey, seam)
    end
    if (not fromSeam or not toSeam) and self.camera and fallbackFrom and fallbackTo then
        local fromScreen = self.camera:WorldToScreenPoint(fallbackFrom)
        local toScreen = self.camera:WorldToScreenPoint(fallbackTo)
        local mid = Vector2(
            (fromScreen.x + toScreen.x) * 0.5,
            (fromScreen.y + toScreen.y) * 0.5
        )
        fromSeam = fromSeam or self.pathRuntime:UnprojectToNode(fromKey, mid)
        toSeam = toSeam or self.pathRuntime:UnprojectToNode(toKey, mid)
    end
    return fromSeam or fallbackFrom, toSeam or fallbackTo
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
            if self:IsCandidatePair(from.key, toKey) then
                print(string.format(
                    "PathWalker: %s candidate hop %s -> %s",
                    self.name,
                    tostring(from.key),
                    tostring(toKey)
                ))
                local fromSeam, toSeam = self:GetCandidateSeams(from.key, toKey, from.point, toPoint)
                if fromSeam and (fromSeam - from.point):Length() > ARRIVAL_DISTANCE then
                    waypoints[#waypoints + 1] = {
                        key = from.key,
                        point = CopyVector(fromSeam),
                        record = from.record,
                        pathIndex = from.pathIndex,
                        candidate = false,
                        topmost = true,
                    }
                end
                waypoints[#waypoints + 1] = {
                    key = toKey,
                    point = CopyVector(toSeam or toPoint),
                    record = toRecord,
                    pathIndex = index,
                    candidate = true,
                    topmost = true,
                }
            else
                local portal = self:GetPortalWaypoint(from.key, toKey, from.point, toPoint)
                if portal then
                    waypoints[#waypoints + 1] = {
                        key = toKey,
                        point = CopyVector(portal),
                        record = toRecord,
                        pathIndex = index,
                        candidate = false,
                        topmost = false,
                    }
                end
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
                topmost = false,
            }
        end
    end
    if #waypoints < 2 then
        return
    end
    for index = 2, #waypoints do
        local curr = waypoints[index]
        local candidate = curr.candidate == true
        local topmost = curr.topmost == true or candidate
        self:AppendTravelSample(curr.point, curr.key, curr.record, candidate, curr.pathIndex, topmost)
    end
end



function PathWalker:ConsumeTravelSample(sample)
    if sample.candidate ~= nil then
        self.currentEdgeIsCandidate = sample.candidate == true
        if self.currentEdgeIsCandidate then
            self.candidateHoldKey = sample.nodeKey or self.currentNodeKey
        end
    end
    if sample.topmost then
        self.candidateHoldKey = sample.nodeKey or self.currentNodeKey
    end
    if type(sample.pathIndex) == "number" and sample.pathIndex > self.pathIndex then
        self.pathIndex = sample.pathIndex
    end
    if sample.nodeKey then
        self.currentNodeKey = sample.nodeKey
        if self.currentEdgeIsCandidate or sample.topmost then
            self.candidateHoldKey = sample.nodeKey
        end
    end
    self:RefreshCandidateHold()
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

    local budget = self.speed * timeStep
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
            if self.currentEdgeIsCandidate or nextSample.topmost then
                self.candidateHoldKey = nextSample.nodeKey or self.currentNodeKey
            end
            local step = self:GetStepDistance(
                self.position,
                nextSample.point,
                distance,
                timeStep,
                budget / math.max(timeStep, 0.0001)
            )
            local consumed = step
            if nextSample.candidate and self.camera then
                local viewDistance = ViewPlaneDistance(self.camera, self.position, nextSample.point)
                if viewDistance > 0.0001 then
                    consumed = step * (viewDistance / distance)
                else
                    consumed = budget
                end
            end
            if step >= distance - 0.0001 then
                self.position = CopyVector(nextSample.point)
                budget = budget - consumed
                if budget < 0.0 then
                    budget = 0.0
                end
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
    self:UpdateSmooth(timeStep)
end

return PathWalker
