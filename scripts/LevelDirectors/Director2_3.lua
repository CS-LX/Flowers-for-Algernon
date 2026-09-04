-- 第二章第三关演出：滚筒实验室中的探索与对照。
-- 研究员不明说术后功效对照测试，只通过“熟悉这里的结构”“你正在形成自己的判断”暗示。
-- 阿尔吉侬使用专用探索寻路；查理仍使用正常玩家寻路，不读取或修改小鼠的探索状态。

local LevelDirector = require "LevelDirector"
local Story = require "Story.Chapter2"

local Director2_3 = LevelDirector.Extend()

local MOUSE_NODE_KEY = "part_staticpart_1_1:mouse_node"
local FINISH_NODE_KEY = "part_rotateablepart_1_2:finish_node"
local ALGERNON_EXIT_DURATION = 1.0
local ALGERNON_SCALE = 1.05
local ALGERNON_SPEED = 1.7

local function Clamp01(value)
    return math.max(0.0, math.min(1.0, value))
end

function Director2_3:OnStart()
    self.stage = "intro"
    self.stageElapsed = 0.0
    self.algernonExitElapsed = 0.0
    self.algernonStarted = false
    self.algernonFinished = false
    self.playerFinished = false
    self.finishStoryPlayed = false
    self.narrativeFinished = false
    self.finishPayload = nil

    self:SetInputLocked(true)
    self:SetPlayerLocked(true)

    local enabled, enableError = self:SetAlgernonEnabled(true, MOUSE_NODE_KEY)
    if not enabled then
        print("Director2_3: algernon enable failed " .. tostring(enableError))
    else
        self:SetAlgernonVisible(true)
        self:SetAlgernonLocalTransform({ scale = ALGERNON_SCALE })
        self:SetAlgernonSpeed(ALGERNON_SPEED)
        print("Director2_3: algernon waiting at " .. MOUSE_NODE_KEY)
    end

    self:SetAlgernonOnArrived(function(nodeKey)
        self:OnAlgernonArrived(nodeKey)
    end)

    self:PlayStory(Story.ch2_3_intro, {
        onComplete = function()
            self:SetPlayerLocked(false)
            self:SetInputLocked(false)
            self:BeginAlgernonExploration()
        end,
    })
end

function Director2_3:BeginAlgernonExploration()
    if self.algernonStarted then
        return
    end
    self.algernonStarted = true
    self.stage = "algernon_exploration"
    self.stageElapsed = 0.0
    local started, errorMessage = self:StartAlgernonExplorationCommand(FINISH_NODE_KEY)
    if not started then
        print("Director2_3: exploration start failed " .. tostring(errorMessage))
        self.stage = "await_finish"
        return
    end
    print("Director2_3: algernon started exploratory path to " .. FINISH_NODE_KEY)
end

function Director2_3:StartAlgernonExplorationCommand(nodeKey)
    return self:StartAlgernonExploration(nodeKey, {
        minPause = 1.0,
        maxPause = 4.0,
        candidateProbability = 0.4,
    })
end

function Director2_3:OnAlgernonArrived(nodeKey)
    if nodeKey ~= FINISH_NODE_KEY or self.algernonFinished then
        return
    end
    self.algernonFinished = true
    self.stage = "algernon_exit"
    self.stageElapsed = 0.0
    self.algernonExitElapsed = 0.0
    print("Director2_3: algernon reached finish")
end

function Director2_3:FinishAlgernonExit()
    self:SetAlgernonVisible(false)
    if self.playerFinished then
        return
    end
    self.stage = "await_finish"
    self.stageElapsed = 0.0
    self:PlayStory(Story.algernon_first_banner)
    print("Director2_3: algernon arrived before Charlie")
end

function Director2_3:FinishNarrative()
    if self.narrativeFinished then
        return
    end
    self.narrativeFinished = true
    local session = self.session
    if session and session.onFinish then
        session.onFinish(session, self.finishPayload)
    end
end

function Director2_3:OnFinish(payload)
    if self.finishStoryPlayed then
        return
    end
    self.finishStoryPlayed = true
    self.finishPayload = payload
    self.playerFinished = true
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    self:StopAlgernon()
    self:SetAlgernonVisible(false)

    local lines = self.algernonFinished
        and Story.algernon_first
        or Story.charlie_first
    self:PlayStory(lines, {
        onComplete = function()
            self:FinishNarrative()
        end,
    })
end

function Director2_3:OnUpdate(timeStep)
    self.stageElapsed = self.stageElapsed + timeStep

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

function Director2_3:OnDispose()
    self:StopAlgernon()
    self:SetAlgernonVisible(false)
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
end

return Director2_3
