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
    self.onArrived = nil
    ---@type table|nil
    self.exploration = nil
    self.walker.onArrived = function(nodeKey)
        self:HandleArrived(nodeKey)
    end
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
    self.exploration = nil
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

function AlgernonController:ClearTopmostHold()
    if self.walker.ClearTopmostHold then
        self.walker:ClearTopmostHold()
    end
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
    self.onArrived = listener
end

function AlgernonController:HandleArrived(nodeKey)
    local exploration = self.exploration
    local arrivedCandidate = exploration and exploration.travelWasCandidate == true
    local reverseTargetKey = exploration and exploration.reverseTargetKey or nil
    if self.onArrived then
        self.onArrived(nodeKey)
    end
    exploration = self.exploration
    if exploration and exploration.targetKey == nodeKey then
        self.exploration = nil
        return
    end
    if exploration and arrivedCandidate and exploration.pauseAtEveryCandidate then
        if exploration.suppressCandidatePause then
            exploration.suppressCandidatePause = false
            exploration.travelWasCandidate = false
            exploration.reverseTargetKey = nil
            exploration.pauseReason = nil
            self:ContinueExploration()
            return
        end
        exploration.travelWasCandidate = false
        exploration.paused = true
        exploration.pauseReason = "candidate_arrival"
        exploration.pauseElapsed = 0.0
        exploration.pauseDuration = exploration.minPause
            + (exploration.maxPause - exploration.minPause) * math.random()
        exploration.pauseFromKey = nodeKey
        exploration.pauseToKey = reverseTargetKey
        exploration.reverseTargetKey = reverseTargetKey
        print("AlgernonController: candidate path pause at " .. tostring(nodeKey))
    end
end

function AlgernonController:StartExploration(targetKey, options)
    if not self.enabled then
        return false, "algernon disabled"
    end
    if type(targetKey) ~= "string" or targetKey == "" then
        return false, "empty node key"
    end
    options = options or {}
    self.exploration = {
        targetKey = targetKey,
        minPause = tonumber(options.minPause) or 3.0,
        maxPause = tonumber(options.maxPause) or 5.0,
        candidateProbability = tonumber(options.candidateProbability) or 0.4,
        pauseAtEveryCandidate = options.pauseAtEveryCandidate == true,
        candidateReverseProbability = math.max(0.0, math.min(1.0,
            tonumber(options.candidateReverseProbability) or 0.0)),
        pauseElapsed = 0.0,
        pauseDuration = 0.0,
        paused = false,
        pauseReason = nil,
        skipPause = false,
        pauseFromKey = nil,
        pauseToKey = nil,
        previousCandidate = false,
        nextCandidate = false,
        travelWasCandidate = false,
        reverseTargetKey = nil,
        suppressCandidatePause = false,
        blockedFromKey = nil,
        blockedToKey = nil,
        lastNodeKey = self.walker:GetCurrentNodeKey(),
    }
    return self:ContinueExploration()
end

function AlgernonController:IsExploring()
    return self.exploration ~= nil
end

function AlgernonController:IsExplorationPaused()
    return self.exploration ~= nil and self.exploration.paused == true
end

function AlgernonController:ContinueExploration()
    local exploration = self.exploration
    if not exploration then
        return false, "exploration-not-started"
    end
    local currentKey = self.walker:GetCurrentNodeKey()
    if currentKey == exploration.targetKey then
        self.exploration = nil
        return true
    end
    local path, errorMessage = self.pathRuntime:FindPathIncludingCandidates(
        currentKey,
        exploration.targetKey,
        exploration.blockedFromKey,
        exploration.blockedToKey
    )
    if not path then
        self.exploration = nil
        return false, errorMessage
    end
    local nextKey = path[2]
    if not nextKey then
        self.exploration = nil
        return false, "exploration path has no next node"
    end
    local function IsCandidate(fromKey, toKey)
        return self.pathRuntime:IsConfiguredCandidateEdge(fromKey, toKey)
            or self.pathRuntime:IsCandidateEdge(fromKey, toKey)
    end
    local nextCandidate = IsCandidate(currentKey, nextKey)
    local shouldPause = not exploration.skipPause
        and exploration.lastNodeKey ~= nil
        and exploration.previousCandidate ~= nextCandidate
    exploration.skipPause = false
    if shouldPause then
        exploration.paused = true
        exploration.pauseReason = "edge_transition"
        exploration.pauseElapsed = 0.0
        exploration.pauseDuration = exploration.minPause
            + (exploration.maxPause - exploration.minPause) * math.random()
        exploration.pauseFromKey = currentKey
        exploration.pauseToKey = nextKey
        exploration.nextCandidate = nextCandidate
        return true
    end
    local run = { currentKey, nextKey }
    if not exploration.pauseAtEveryCandidate then
        for index = 3, #path do
            local fromKey = path[index - 1]
            local toKey = path[index]
            if IsCandidate(fromKey, toKey) ~= nextCandidate then
                break
            end
            run[#run + 1] = toKey
        end
    end
    local runTarget = run[#run]
    exploration.paused = false
    exploration.pauseReason = nil
    exploration.lastNodeKey = currentKey
    exploration.previousCandidate = nextCandidate
    exploration.travelWasCandidate = nextCandidate
    exploration.reverseTargetKey = nextCandidate and currentKey or nil
    local moved, moveError = self.walker:MoveTo(run, runTarget)
    if not moved then
        exploration.travelWasCandidate = false
        exploration.reverseTargetKey = nil
        self.exploration = nil
        return false, moveError
    end
    return true
end

function AlgernonController:UpdateExploration(timeStep)
    local exploration = self.exploration
    if not exploration then
        return
    end
    if exploration.paused then
        exploration.pauseElapsed = exploration.pauseElapsed + timeStep
        if exploration.pauseElapsed < exploration.pauseDuration then
            return
        end
        if exploration.pauseReason == "candidate_arrival"
            and exploration.pauseToKey
            and math.random() < exploration.candidateReverseProbability then
            local reverseFromKey = exploration.pauseFromKey
            local reverseToKey = exploration.pauseToKey
            exploration.pauseReason = "candidate_reverse"
            exploration.pauseElapsed = 0.0
            exploration.pauseDuration = 0.0
            exploration.paused = false
            exploration.blockedFromKey = nil
            exploration.blockedToKey = nil
            exploration.suppressCandidatePause = true
            exploration.travelWasCandidate = true
            exploration.reverseTargetKey = reverseFromKey
            local moved, moveError = self.walker:MoveTo(
                { reverseFromKey, reverseToKey },
                reverseToKey
            )
            if not moved then
                exploration.suppressCandidatePause = false
                exploration.travelWasCandidate = false
                exploration.reverseTargetKey = nil
                print("AlgernonController: candidate reverse failed " .. tostring(moveError))
                self:ContinueExploration()
            else
                print(string.format(
                    "AlgernonController: candidate path reverses %s -> %s",
                    tostring(reverseFromKey),
                    tostring(reverseToKey)
                ))
            end
            return
        end
        local continueOriginal = math.random() >= exploration.candidateProbability
        if continueOriginal then
            exploration.blockedFromKey = nil
            exploration.blockedToKey = nil
        else
            exploration.blockedFromKey = exploration.pauseFromKey
            exploration.blockedToKey = exploration.pauseToKey
        end
        exploration.paused = false
        exploration.pauseReason = nil
        exploration.skipPause = true
        local continued, continueError = self:ContinueExploration()
        if not continued then
            print("AlgernonController: alternate exploration path unavailable " .. tostring(continueError))
            if not self.exploration then
                self.exploration = exploration
            end
            exploration.blockedFromKey = nil
            exploration.blockedToKey = nil
            exploration.skipPause = true
            self:ContinueExploration()
        end
        return
    end
    if not self.walker:IsWalking() then
        self:ContinueExploration()
    end
end

function AlgernonController:Stop()
    if not self.enabled then
        return false
    end
    self.walker:Stop()
    self.exploration = nil
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

---@param nodeKey string
---@return boolean, string|nil
function AlgernonController:MoveToIncludingCandidates(nodeKey)
    if not self.enabled then
        return false, "algernon disabled"
    end
    if type(nodeKey) ~= "string" or nodeKey == "" then
        return false, "empty node key"
    end
    local path, errorMessage = self.pathRuntime:FindPathIncludingCandidates(
        self.walker:GetCurrentNodeKey(),
        nodeKey
    )
    if not path then
        return false, errorMessage
    end
    return self.walker:MoveTo(path, nodeKey)
end

function AlgernonController:MoveToIncludingCandidatesExcept(nodeKey, blockedFromKey, blockedToKey)
    if not self.enabled then
        return false, "algernon disabled"
    end
    local path, errorMessage = self.pathRuntime:FindPathIncludingCandidates(
        self.walker:GetCurrentNodeKey(),
        nodeKey,
        blockedFromKey,
        blockedToKey
    )
    if not path then
        return false, errorMessage
    end
    return self.walker:MoveTo(path, nodeKey)
end

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
    self:UpdateExploration(timeStep)
    self.walker:Update(timeStep)
end

return AlgernonController
