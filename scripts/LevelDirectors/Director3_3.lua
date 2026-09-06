-- 第三章第三关：查理确认空城不是局部异常，整个世俗世界都无法进入他的空间观测。

local LevelDirector = require "LevelDirector"
local Story = require "Story.Chapter3"

local Director3_3 = LevelDirector.Extend()

function Director3_3:OnStart()
    self.pathStoryPlayed = false
    self.finishStoryPlayed = false
    self:SetInputLocked(false)
    self:SetPlayerLocked(false)

    local player = self:GetPlayer()
    if player and player.AddOnArrived then
        player:AddOnArrived(function(nodeKey)
            self:OnPlayerArrived(nodeKey)
        end)
    end
    print("Director3_3: deep empty city ready")
end

function Director3_3:OnPlayerArrived(nodeKey)
    if self.pathStoryPlayed then
        return
    end
    self.pathStoryPlayed = true
    self:PlayStory(Story.ch3_3_path)
    print("Director3_3: Charlie reached observation point " .. tostring(nodeKey))
end

function Director3_3:OnFinish(payload)
    if self.finishStoryPlayed then
        return
    end
    self.finishStoryPlayed = true
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    self:PlayStory(Story.ch3_3_clear, {
        onComplete = function()
            local session = self.session
            if session and session.onFinish then
                session.onFinish(session, payload)
            end
        end,
    })
end

function Director3_3:OnDispose()
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
end

return Director3_3
