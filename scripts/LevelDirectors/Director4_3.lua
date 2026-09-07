-- 第四章第三关演出：查理在旧训练房间与研究员正面交锋，确认自己看不见研究员。
-- 旋转由玩家完成；导演只负责角色状态、已有路径事件与剧情生命周期。

local LevelDirector = require "LevelDirector"
local Story = require "Story.Chapter4"

local Director4_3 = LevelDirector.Extend()

local MOUSE_NODE_KEY = "part_part:mouse_node"
local ROTATEABLE_PART_ID = "part_mainpart_1_2"
local ROTATEABLE_START_KEY = "part_mainpart_1_2:rotateable_node_start"
local ROTATEABLE_END_KEY = "part_mainpart_1_2:rotateable_node_end"
local FINISH_NODE_KEY = "part_part:finish_node"

function Director4_3:OnStart()
    self.stage = "intro"
    self.observationPlayed = false
    self.pauseStoryPlayed = false
    self.algernonStarted = false
    self.algernonArrived = false
    self.algernonArrivalPending = false
    self.finishStoryPlayed = false
    self.finishPayload = nil

    self:SetInputLocked(true)
    self:SetPlayerLocked(true)

    local enabled, enableError = self:SetAlgernonEnabled(true, MOUSE_NODE_KEY)
    if not enabled then
        print("Director4_3: algernon enable failed " .. tostring(enableError))
    else
        self:SetAlgernonVisible(true)
        self:SetAlgernonSpeed(0.82)
        print("Director4_3: algernon waiting at " .. MOUSE_NODE_KEY)
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

    self:PlayStory(Story.ch4_3_intro, {
        onComplete = function()
            self.stage = "playable"
            self:SetPlayerLocked(false)
            self:SetInputLocked(false)
            self:StartAlgernonExploration()
            print("Director4_3: contact room playable")
        end,
    })
end

function Director4_3:StartAlgernonExploration()
    if self.algernonStarted then
        return
    end
    self.algernonStarted = true
    local started, startError = self:StartAlgernonExplorationCommand(FINISH_NODE_KEY)
    if not started then
        print("Director4_3: exploration start failed " .. tostring(startError))
        return
    end
    print("Director4_3: algernon started slow exploration")
end

function Director4_3:StartAlgernonExplorationCommand(nodeKey)
    local algernon = self:GetAlgernon()
    if not algernon then
        return false, "no algernon"
    end
    return algernon:StartExploration(nodeKey, {
        minPause = 1.2,
        maxPause = 1.8,
        candidateProbability = 0.0,
    })
end

function Director4_3:BeginObservation()
    if self.stage ~= "playable" or self.observationPlayed then
        return false
    end
    self.observationPlayed = true
    self.stage = "observation"
    self:SetPlayerLocked(true)
    self:SetInputLocked(true)
    self:PlayStory(Story.ch4_3_observation, {
        onComplete = function()
            self.stage = "playable"
            self:SetPlayerLocked(false)
            self:SetInputLocked(false)
        end,
    })
    print("Director4_3: Charlie entered the contact test")
    return true
end

function Director4_3:ObserveRotateableEntry()
    if self.stage ~= "playable" or self.observationPlayed then
        return false
    end
    local player = self:GetPlayer()
    if not player then
        return false
    end
    local currentNodeKey = player:GetCurrentNodeKey()
    local edgeTargetKey = player.GetCurrentEdgeTargetKey
        and player:GetCurrentEdgeTargetKey()
        or nil
    local enteringRotateable = currentNodeKey == ROTATEABLE_START_KEY
        or edgeTargetKey == ROTATEABLE_START_KEY
        or player:GetCurrentPartId() == ROTATEABLE_PART_ID
    if enteringRotateable then
        return self:BeginObservation()
    end
    return false
end

function Director4_3:OnPlayerArrived(nodeKey)
    self:ObserveRotateableEntry()
end

function Director4_3:ObservePlayerProgress()
    local player = self:GetPlayer()
    if not player then
        return
    end
    local currentNodeKey = player:GetCurrentNodeKey()
    local edgeTargetKey = player.GetCurrentEdgeTargetKey
        and player:GetCurrentEdgeTargetKey()
        or nil
    if self.stage == "playable"
        and currentNodeKey == ROTATEABLE_END_KEY
        and not self.pauseStoryPlayed then
        self.pauseStoryPlayed = true
        self:SetPlayerLocked(true)
        self:SetInputLocked(true)
        self:PlayStory(Story.ch4_3_pause, {
            onComplete = function()
                self.stage = "playable"
                self:SetPlayerLocked(false)
                self:SetInputLocked(false)
            end,
        })
        print("Director4_3: pause observation at rotateable end")
    end
end

function Director4_3:OnAlgernonArrived(nodeKey)
    if nodeKey ~= FINISH_NODE_KEY or self.algernonArrived then
        return
    end
    self.algernonArrived = true
    self.algernonArrivalPending = true
    print("Director4_3: algernon reached finish")
end

function Director4_3:OnFinish(payload)
    if self.finishStoryPlayed then
        return
    end
    self.finishStoryPlayed = true
    self.finishPayload = payload
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    self:StopAlgernon()
    self:PlayStory(Story.ch4_3_finish, {
        onComplete = function()
            local session = self.session
            if session and session.onFinish then
                session.onFinish(session, self.finishPayload)
            end
        end,
    })
end

function Director4_3:OnUpdate(timeStep)
    if self.stage == "playable" then
        self:ObserveRotateableEntry()
        if self.algernonArrivalPending and not self:IsStoryPlaying() then
            self.algernonArrivalPending = false
            self:PlayStory(Story.ch4_3_algernon_finish)
        end
        self:ObservePlayerProgress()
    end
end

function Director4_3:OnDispose()
    self:StopAlgernon()
    self:SetAlgernonVisible(false)
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
end

return Director4_3
