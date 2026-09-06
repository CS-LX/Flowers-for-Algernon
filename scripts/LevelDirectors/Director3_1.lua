-- 第三章第一关：城市仍在，但查理第一次注意到世俗世界无法进入自己的空间观测。

local LevelDirector = require "LevelDirector"
local Story = require "Story.Chapter3"

local Director3_1 = LevelDirector.Extend()

function Director3_1:OnStart()
    self.pathStoryPlayed = false
    self.finishStoryPlayed = false
    self:SetInputLocked(false)
    self:SetPlayerLocked(false)

    local player = self:GetPlayer()
    if player and player.SetOnStarted then
        player:SetOnStarted(function(targetKey)
            self:OnPlayerStarted(targetKey)
        end)
    end
    print("Director3_1: city entrance ready")
end

function Director3_1:OnPlayerStarted(targetKey)
    if self.pathStoryPlayed then
        return
    end
    self.pathStoryPlayed = true
    self:PlayStory(Story.ch3_1_path)
    print("Director3_1: Charlie started observing the city target=" .. tostring(targetKey))
end

function Director3_1:OnFinish(payload)
    if self.finishStoryPlayed then
        return
    end
    self.finishStoryPlayed = true
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    self:PlayStory(Story.ch3_1_clear, {
        onComplete = function()
            local session = self.session
            if session and session.onFinish then
                session.onFinish(session, payload)
            end
        end,
    })
end

function Director3_1:OnDispose()
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
end

return Director3_1
