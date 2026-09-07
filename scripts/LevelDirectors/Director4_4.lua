-- 第四章第四关演出：回到手术记录，解释两条异常并完成查理的接受。
-- 玩法仍由玩家完成；导演只负责在路径节点停稳后分段揭示记录。

local LevelDirector = require "LevelDirector"
local Story = require "Story.Chapter4"

local Director4_4 = LevelDirector.Extend()

local PATH_STORY_STOP_DELAY = 0.15

function Director4_4:OnStart()
    self.stage = "intro"
    self.pathStoryPending = false
    self.pathStoryElapsed = 0.0
    self.pathStoryPlayed = false
    self.finishStoryPlayed = false
    self.finishPayload = nil

    self:SetInputLocked(true)
    self:SetPlayerLocked(true)

    local player = self:GetPlayer()
    if player and player.SetOnStarted then
        player:SetOnStarted(function(targetKey)
            self:OnPlayerStarted(targetKey)
        end)
    end

    self:PlayStory(Story.ch4_4_intro, {
        onComplete = function()
            self.stage = "playable"
            self:SetPlayerLocked(false)
            self:SetInputLocked(false)
            print("Director4_4: surgery record introduction complete")
        end,
    })
end

function Director4_4:OnPlayerStarted(targetKey)
    if self.stage ~= "playable" or self.pathStoryPlayed or self.pathStoryPending then
        return
    end
    self.stage = "path_story_pending"
    self.pathStoryPending = true
    self.pathStoryElapsed = 0.0
    print("Director4_4: Charlie started the return path target=" .. tostring(targetKey))
end

function Director4_4:PlayPathStory()
    if self.pathStoryPlayed then
        return
    end
    self.pathStoryPending = false
    self.pathStoryPlayed = true
    self.stage = "path_story"
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    self:PlayStory(Story.ch4_4_path, {
        onComplete = function()
            self.stage = "playable"
            self:SetPlayerLocked(false)
            self:SetInputLocked(false)
            print("Director4_4: Algernon timeline explanation complete")
        end,
    })
end

function Director4_4:OnFinish(payload)
    if self.finishStoryPlayed then
        return
    end
    self.finishStoryPlayed = true
    self.finishPayload = payload
    self.pathStoryPending = false
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    self:PlayStory(Story.ch4_4_finish, {
        onComplete = function()
            local session = self.session
            if session and session.onFinish then
                session.onFinish(session, self.finishPayload)
            end
        end,
    })
end

function Director4_4:OnUpdate(timeStep)
    if self.stage ~= "path_story_pending" or not self.pathStoryPending then
        return
    end
    local player = self:GetPlayer()
    if not player or player:IsWalking() then
        return
    end
    self.pathStoryElapsed = self.pathStoryElapsed + timeStep
    if self.pathStoryElapsed >= PATH_STORY_STOP_DELAY then
        self:PlayPathStory()
    end
end

function Director4_4:OnDispose()
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
end

return Director4_4
