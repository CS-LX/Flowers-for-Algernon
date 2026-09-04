-- 第二章第二关演出：查理学会操控“不存在的路径”。
-- 旋转由玩家通过 Preview 机关交互完成；导演只负责教学、节点时序和角色演出。

local LevelDirector = require "LevelDirector"
local Story = require "Story.Chapter2"

local Director2_2 = LevelDirector.Extend()

local MOUSE_NODE_KEY = "part_part:mouse_node"
local ROTATEABLE_PART_ID = "part_mainpart_1_2"
local ROTATEABLE_START_KEY = "part_mainpart_1_2:rotateable_node_start"
local ROTATEABLE_END_KEY = "part_mainpart_1_2:rotateable_node_end"
local FINISH_NODE_KEY = "part_part:finish_node"
local ALGERNON_EXIT_DURATION = 1.0
local ALGERNON_SCALE = 1.05

local function Clamp01(value)
    return math.max(0.0, math.min(1.0, value))
end

function Director2_2:OnStart()
    self.stage = "control_intro"
    self.stageElapsed = 0.0
    self.controlBannerPlayed = false
    self.algernonStarted = false
    self.finishStoryPlayed = false
    self.narrativeFinished = false
    self.finishPayload = nil
    self.algernonExitElapsed = 0.0

    self:SetInputLocked(true)
    self:SetPlayerLocked(true)

    local enabled, enableError = self:SetAlgernonEnabled(true, MOUSE_NODE_KEY)
    if not enabled then
        print("Director2_2: algernon enable failed " .. tostring(enableError))
    else
        self:SetAlgernonVisible(true)
        self:SetAlgernonLocalTransform({ scale = ALGERNON_SCALE })
        print("Director2_2: algernon waiting at " .. MOUSE_NODE_KEY)
    end

    self:SetAlgernonOnArrived(function(nodeKey)
        self:OnAlgernonArrived(nodeKey)
    end)

    local player = self:GetPlayer()
    if player and player.AddOnArrived then
        player:AddOnArrived(function(nodeKey)
            self:OnPlayerArrived(nodeKey)
        end)
    end

    self:PlayStory(Story.control_intro, {
        onComplete = function()
            self.stage = "await_rotateable_start"
            self.stageElapsed = 0.0
            self:SetPlayerLocked(false)
            self:SetInputLocked(false)
            print("Director2_2: waiting for Charlie to enter the rotateable path")
        end,
    })
end

function Director2_2:OnPlayerArrived(nodeKey)
    self:ObservePlayerProgress(nodeKey)
end

function Director2_2:ObservePlayerProgress(nodeKey)
    local player = self:GetPlayer()
    if not player then
        return
    end

    local currentNodeKey = player:GetCurrentNodeKey()
    local edgeTargetKey = player.GetCurrentEdgeTargetKey
        and player:GetCurrentEdgeTargetKey()
        or nil
    local enteringRotateable = currentNodeKey == ROTATEABLE_START_KEY
        or edgeTargetKey == ROTATEABLE_START_KEY
        or player:GetCurrentPartId() == ROTATEABLE_PART_ID

    if self.stage == "await_rotateable_start"
        and enteringRotateable
        and not self.controlBannerPlayed then
        self.controlBannerPlayed = true
        self.stage = "control_path"
        self.stageElapsed = 0.0
        self:PlayStory(Story.control_start)
        print("Director2_2: Charlie entered rotateable path at " .. tostring(nodeKey))
        return
    end

    if (self.stage == "control_path" or self.stage == "await_rotateable_end")
        and player:GetCurrentNodeKey() == ROTATEABLE_END_KEY
        and not self.algernonStarted then
        self.stage = "await_algernon_start"
        self.stageElapsed = 0.0
        self:StartAlgernonMotion()
    end
end

function Director2_2:StartAlgernonMotion()
    if self.algernonStarted then
        return
    end
    self.algernonStarted = true
    self.stage = "algernon_motion"
    self.stageElapsed = 0.0
    local moved, errorMessage = self:MoveAlgernonToIncludingCandidates(FINISH_NODE_KEY)
    if not moved then
        print("Director2_2: algernon path rejected " .. tostring(errorMessage))
        self.stage = "await_finish"
        self.stageElapsed = 0.0
        return
    end
    print("Director2_2: algernon moving from mouse to " .. FINISH_NODE_KEY)
end

function Director2_2:OnAlgernonArrived(nodeKey)
    if self.stage ~= "algernon_motion" then
        return
    end
    self.stage = "algernon_exit"
    self.stageElapsed = 0.0
    self.algernonExitElapsed = 0.0
    print("Director2_2: algernon reached " .. tostring(nodeKey))
end

function Director2_2:FinishAlgernonExit()
    self:SetAlgernonVisible(false)
    self.stage = "await_finish"
    self.stageElapsed = 0.0
    print("Director2_2: algernon disappeared, Charlie remains playable")
end

function Director2_2:FinishNarrative()
    if self.narrativeFinished then
        return
    end
    self.narrativeFinished = true
    local session = self.session
    if session and session.onFinish then
        session.onFinish(session, self.finishPayload)
    end
end

function Director2_2:OnFinish(payload)
    if self.finishStoryPlayed then
        return
    end
    self.finishStoryPlayed = true
    self.finishPayload = payload
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    self:PlayStory(Story.clear, {
        onComplete = function()
            self:FinishNarrative()
        end,
    })
end

function Director2_2:OnUpdate(timeStep)
    self.stageElapsed = self.stageElapsed + timeStep

    if self.stage == "await_rotateable_start" or self.stage == "control_path" then
        local player = self:GetPlayer()
        if player then
            self:ObservePlayerProgress(player:GetCurrentNodeKey())
        end
        return
    end

    if self.stage == "algernon_exit" then
        self.algernonExitElapsed = self.algernonExitElapsed + timeStep
        local progress = Clamp01(self.algernonExitElapsed / ALGERNON_EXIT_DURATION)
        self:SetAlgernonLocalTransform({
            scale = ALGERNON_SCALE * (1.0 - progress),
        })
        if progress >= 1.0 then
            self:FinishAlgernonExit()
        end
    end
end

function Director2_2:OnDispose()
    self:SetAlgernonVisible(false)
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
end

return Director2_2
