-- 第四章第二关演出：查理返回寻路测试房间，目击阿尔吉侬的迟缓。
-- 阿尔吉侬仍走当前有效 Path Graph；本导演只调整探索速度、观察停滞并播放剧情。

local LevelDirector = require "LevelDirector"
local Story = require "Story.Chapter4"

local Director4_2 = LevelDirector.Extend()

local MOUSE_NODE_KEY = "part_staticpart_1_1:mouse_node"
local ROTATOR_PART_ID = "part_mainpart_1_3"
local FINISH_NODE_KEY = "part_rotateablepart_1_2:finish_node"
local ALGERNON_SPEED = 0.82
local ALGERNON_PAUSE_MIN = 1.4
local ALGERNON_PAUSE_MAX = 2.0
local ROTATOR_FAULT = {
    stallChance = 0.10,
    slipChance = 0.16,
    slowSnapChance = 0.22,
    slipDelay = 0.50,
}

function Director4_2:OnStart()
    self.stage = "intro"
    self.pauseCount = 0
    self.pendingPauseStory = nil
    self.algernonWasPaused = false
    self.algernonStarted = false
    self.algernonArrived = false
    self.finishStoryPlayed = false
    self.finishPayload = nil

    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    self:SetRotatorFault(ROTATOR_PART_ID, ROTATOR_FAULT)

    local enabled, enableError = self:SetAlgernonEnabled(true, MOUSE_NODE_KEY)
    if not enabled then
        print("Director4_2: algernon enable failed " .. tostring(enableError))
    else
        self:SetAlgernonVisible(true)
        self:SetAlgernonSpeed(ALGERNON_SPEED)
        print("Director4_2: algernon waiting at " .. MOUSE_NODE_KEY)
    end

    self:SetAlgernonOnArrived(function(nodeKey)
        self:OnAlgernonArrived(nodeKey)
    end)

    self:PlayStory(Story.ch4_2_intro, {
        onComplete = function()
            self.stage = "exploration"
            self:SetPlayerLocked(false)
            self:SetInputLocked(false)
            self:BeginAlgernonExploration()
        end,
    })
end

function Director4_2:BeginAlgernonExploration()
    if self.algernonStarted then
        return
    end
    self.algernonStarted = true
    local started, startError = self:StartAlgernonExploration(FINISH_NODE_KEY, {
        minPause = ALGERNON_PAUSE_MIN,
        maxPause = ALGERNON_PAUSE_MAX,
        candidateProbability = 0.0,
    })
    if not started then
        print("Director4_2: exploration start failed " .. tostring(startError))
        return
    end
    print("Director4_2: algernon started slow exploration to " .. FINISH_NODE_KEY)
end

function Director4_2:OnAlgernonArrived(nodeKey)
    if nodeKey ~= FINISH_NODE_KEY or self.algernonArrived then
        return
    end
    self.algernonArrived = true
    self:PlayStory(Story.ch4_2_algernon_finish)
    print("Director4_2: algernon reached finish slowly")
end

function Director4_2:QueuePauseStory()
    if self.pauseCount == 1 then
        self.pendingPauseStory = Story.ch4_2_first_pause
    elseif self.pauseCount == 2 then
        self.pendingPauseStory = Story.ch4_2_second_pause
    end
end

function Director4_2:ObserveAlgernonPause()
    local paused = self:IsAlgernonExplorationPaused()
    if paused and not self.algernonWasPaused then
        self.pauseCount = self.pauseCount + 1
        self:QueuePauseStory()
        print("Director4_2: algernon pause #" .. tostring(self.pauseCount))
    end
    self.algernonWasPaused = paused
end

function Director4_2:PlayPendingPauseStory()
    if not self.pendingPauseStory or self:IsStoryPlaying() then
        return
    end
    local lines = self.pendingPauseStory
    self.pendingPauseStory = nil
    self:PlayStory(lines)
end

function Director4_2:OnFinish(payload)
    if self.finishStoryPlayed then
        return
    end
    self.finishStoryPlayed = true
    self.finishPayload = payload
    self.pendingPauseStory = nil
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    self:StopAlgernon()
    self:PlayStory(Story.ch4_2_finish, {
        onComplete = function()
            local session = self.session
            if session and session.onFinish then
                session.onFinish(session, self.finishPayload)
            end
        end,
    })
end

function Director4_2:OnUpdate(timeStep)
    if self.stage ~= "exploration" or self.finishStoryPlayed then
        return
    end
    self:ObserveAlgernonPause()
    self:PlayPendingPauseStory()
end

function Director4_2:OnDispose()
    self:StopAlgernon()
    self:SetAlgernonVisible(false)
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
end

return Director4_2
