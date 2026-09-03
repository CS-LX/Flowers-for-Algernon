-- 第一章第二关演出：查理在陌生实验室里遇见阿尔吉侬。
-- 阿尔吉侬使用包含候选边的演出路径；正常玩家寻路仍只消费有效 Graph。

local LevelDirector = require "LevelDirector"
local Story = require "Story.Chapter1"

local Director1_2 = LevelDirector.Extend()

local DARK_PART_ID = "part_part_1"
local MOUSE_DOOR_ID = "still_part"
local PLAYER_DOOR_ID = "still_mousedoor_1"
local TRIGGER_NODE_KEY = "part_part_20:static_part_trigger_1"
local ALGERNON_START_KEY = "part_part_18:jump_node"
local ALGERNON_TARGET_KEY = "part_part_20:node_part_part_20_4"

local DARK_START_Y = -2.0
local DARK_END_Y = 0.0
local PLAYER_DOOR_START_Y = -0.577
local PLAYER_DOOR_END_Y = 0.5773502588272095
local PLAYER_DOOR_SCALE = 0.49
local ALGERNON_EXIT_DURATION = 1.0
local DARK_RAISE_DURATION = 1.6
local PLAYER_DOOR_RAISE_DURATION = 1.2
local PLAYER_DOOR_OPEN_DURATION = 0.8
local RESEARCHER_DELAY = 1.0

local function QuadInOut(t)
    if t < 0.5 then
        return 2.0 * t * t
    end
    local p = 1.0 - t
    return 1.0 - 2.0 * p * p
end

local function Clamp01(value)
    return math.max(0.0, math.min(1.0, value))
end

function Director1_2:OnStart()
    self.stage = "intro"
    self.stageElapsed = 0.0
    self.mouseDoorOpen = 1.0
    self.darkPartX = 0.0
    self.darkPartZ = 0.0
    self.playerDoorX = 0.0
    self.playerDoorZ = 0.0
    self.lastPlayerNodeKey = nil
    self.finishStoryPlayed = false

    local darkPart = self:GetPart(DARK_PART_ID)
    if not darkPart then
        print("Director1_2: dark path part missing")
        return
    end
    self.darkPartX = darkPart.transform.position.x
    self.darkPartZ = darkPart.transform.position.z
    self:SetPartPosition(DARK_PART_ID, {
        x = self.darkPartX,
        y = DARK_START_Y,
        z = self.darkPartZ,
    }, false)

    local playerDoor = self:GetStillObject(PLAYER_DOOR_ID)
    if playerDoor then
        self.playerDoorX = playerDoor.transform.position.x
        self.playerDoorZ = playerDoor.transform.position.z
    end

    self:SetStillTransform(PLAYER_DOOR_ID, {
        position = {
            x = self.playerDoorX,
            y = PLAYER_DOOR_START_Y,
            z = self.playerDoorZ,
        },
    })
    self:SetStillScale(PLAYER_DOOR_ID, 0.0)
    self:SetStillDriver(PLAYER_DOOR_ID, "open", 0.0)
    self:SetStillDriver(MOUSE_DOOR_ID, "open", 1.0)

    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    self:SetAlgernonEnabled(true, ALGERNON_START_KEY)
    self:SetAlgernonVisible(true)
    self:SetAlgernonLocalTransform({ scale = 1.05, rotation = { y = 0 } })
    self:SetAlgernonOnArrived(function(nodeKey)
        self:OnAlgernonArrived(nodeKey)
    end)
    local player = self:GetPlayer()
    if player and player.AddOnArrived then
        player:AddOnArrived(function(nodeKey)
            self:OnPlayerArrived(nodeKey)
        end)
    end

    self:PlayStory(Story.ch1_2_intro, {
        onComplete = function()
            self.stage = "await_trigger"
            self.stageElapsed = 0.0
            self:SetPlayerLocked(false)
            self:SetInputLocked(false)
            print("Director1_2: waiting for player at " .. TRIGGER_NODE_KEY)
        end,
    })
end

function Director1_2:OnPlayerArrived(nodeKey)
    if self.stage == "await_trigger" and nodeKey == TRIGGER_NODE_KEY then
        self:OnPlayerAtTrigger()
    end
end

function Director1_2:OnPlayerAtTrigger()
    if self.stage ~= "await_trigger" then
        return
    end
    self.stage = "algernon_motion"
    self.stageElapsed = 0.0
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    local moved, errorMessage = self:MoveAlgernonToIncludingCandidates(ALGERNON_TARGET_KEY)
    if not moved then
        print("Director1_2: algernon path rejected " .. tostring(errorMessage))
        return
    end
    print("Director1_2: algernon started candidate path to " .. ALGERNON_TARGET_KEY)
end

function Director1_2:OnAlgernonArrived(nodeKey)
    if self.stage ~= "algernon_motion" then
        return
    end
    self.stage = "algernon_exit"
    self.stageElapsed = 0.0
    print("Director1_2: algernon arrived " .. tostring(nodeKey))
end

function Director1_2:FinishAlgernonExit()
    self:SetAlgernonVisible(false)
    self:SetStillDriver(MOUSE_DOOR_ID, "open", 0.0)
    self.mouseDoorOpen = 0.0
    self.stage = "charlie_reaction"
    self.stageElapsed = 0.0
    self:PlayStory(Story.ch1_2_mouse, {
        onComplete = function()
            self.stage = "researcher_delay"
            self.stageElapsed = 0.0
        end,
    })
end

function Director1_2:StartResearcher()
    self.stage = "researcher"
    self.stageElapsed = 0.0
    self:PlayStory(Story.ch1_2_researcher, {
        onComplete = function()
            self.stage = "raise_dark_path"
            self.stageElapsed = 0.0
            print("Director1_2: researcher line complete, raising dark path")
        end,
    })
end

function Director1_2:FinishDarkPathRaise()
    self:SetPartPosition(DARK_PART_ID, {
        x = self.darkPartX,
        y = DARK_END_Y,
        z = self.darkPartZ,
    }, true)
    self.stage = "raise_player_door"
    self.stageElapsed = 0.0
    self:SetStillScale(PLAYER_DOOR_ID, PLAYER_DOOR_SCALE)
    self:SetStillTransform(PLAYER_DOOR_ID, {
        position = {
            x = self.playerDoorX,
            y = PLAYER_DOOR_START_Y,
            z = self.playerDoorZ,
        },
    })
    print("Director1_2: dark path raised, revealing PlayerDoor")
end

function Director1_2:FinishPlayerDoorRaise()
    self:SetStillTransform(PLAYER_DOOR_ID, {
        position = {
            x = self.playerDoorX,
            y = PLAYER_DOOR_END_Y,
            z = self.playerDoorZ,
        },
    })
    self.stage = "open_player_door"
    self.stageElapsed = 0.0
end

function Director1_2:FinishPlayerDoorOpen()
    self:SetStillDriver(PLAYER_DOOR_ID, "open", 1.0)
    self.stage = "playable"
    self.stageElapsed = 0.0
    self:SetPlayerLocked(false)
    self:SetInputLocked(false)
    print("Director1_2: PlayerDoor open, level playable")
end

function Director1_2:OnUpdate(timeStep)
    self.stageElapsed = self.stageElapsed + timeStep

    if self.stage == "await_trigger" then
        local player = self:GetPlayer()
        if player and player:GetCurrentNodeKey() == TRIGGER_NODE_KEY then
            self:OnPlayerAtTrigger()
        end
        return
    end

    if self.stage == "algernon_exit" then
        local progress = Clamp01(self.stageElapsed / ALGERNON_EXIT_DURATION)
        local scale = 1.05 * (1.0 - progress)
        self:SetAlgernonLocalTransform({ scale = scale })
        local open = 1.0 - progress
        self:SetStillDriver(MOUSE_DOOR_ID, "open", open)
        if progress >= 1.0 then
            self:FinishAlgernonExit()
        end
        return
    end

    if self.stage == "researcher_delay" and self.stageElapsed >= RESEARCHER_DELAY then
        self:StartResearcher()
        return
    end

    if self.stage == "raise_dark_path" then
        local progress = Clamp01(self.stageElapsed / DARK_RAISE_DURATION)
        local y = DARK_START_Y + (DARK_END_Y - DARK_START_Y) * QuadInOut(progress)
        self:SetPartPosition(DARK_PART_ID, {
            x = self.darkPartX,
            y = y,
            z = self.darkPartZ,
        }, false)
        if progress >= 1.0 then
            self:FinishDarkPathRaise()
        end
        return
    end

    if self.stage == "raise_player_door" then
        local progress = Clamp01(self.stageElapsed / PLAYER_DOOR_RAISE_DURATION)
        local y = PLAYER_DOOR_START_Y
            + (PLAYER_DOOR_END_Y - PLAYER_DOOR_START_Y) * QuadInOut(progress)
        self:SetStillTransform(PLAYER_DOOR_ID, {
            position = {
                x = self.playerDoorX,
                y = y,
                z = self.playerDoorZ,
            },
        })
        if progress >= 1.0 then
            self:FinishPlayerDoorRaise()
        end
        return
    end

    if self.stage == "open_player_door" then
        local progress = Clamp01(self.stageElapsed / PLAYER_DOOR_OPEN_DURATION)
        self:SetStillDriver(PLAYER_DOOR_ID, "open", progress)
        if progress >= 1.0 then
            self:FinishPlayerDoorOpen()
        end
    end
end

function Director1_2:OnFinish(payload)
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    if self.finishStoryPlayed then
        return
    end
    self.finishStoryPlayed = true
    self:PlayStory(Story.ch1_2_clear, {
        onComplete = function()
            local session = self.session
            if session and session.onFinish then
                session.onFinish(session, payload)
            end
        end,
    })
end

function Director1_2:OnDispose()
    self:SetAlgernonLocalTransform({ scale = 1.0 })
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
end

return Director1_2
