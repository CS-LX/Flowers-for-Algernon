-- 第二章第四关演出：查理独立找到出口，并随 Lift 离开实验室。
-- 颜色只在运行时缓动，不改写关卡 JSON；第二章原始配色仍是本关重进时的起点。
-- 第三章色彩更冷、更开阔：高处带来清晰与能力，也开始带来距离和孤独。

local LevelDirector = require "LevelDirector"
local LookApplier = require "LookApplier"
local Story = require "Story.Chapter2"

local Director2_4 = LevelDirector.Extend()

local LIFT_PART_ID = "part_mainpart_1_2"
local LIFT_HEIGHT = 15.0
local LIFT_DURATION = 16.0
local CAMERA_LEAD_HEIGHT = 2.0
local COLOR_DELAY = 1.0
local COLOR_DURATION = LIFT_DURATION - COLOR_DELAY

local CHAPTER3_FOG = "#304A59"
local CHAPTER3_COLOR_NEG = "#294653"
local CHAPTER3_COLOR_MID = "#4F7180"
local CHAPTER3_COLOR_POS = "#86A7A5"
local CHAPTER3_HEIGHT_FOG = "#3B5961"

local function Clamp01(value)
    return math.max(0.0, math.min(1.0, value))
end

local function CubicInOut(t)
    t = Clamp01(t)
    if t < 0.5 then
        return 4.0 * t * t * t
    end
    local p = -2.0 * t + 2.0
    return 1.0 - p * p * p * 0.5
end

local function CameraLead(t)
    local leadProgress = Clamp01(t / 0.18)
    local remaining = 1.0 - leadProgress
    return CAMERA_LEAD_HEIGHT * (1.0 - remaining * remaining * remaining)
end

function Director2_4:OnStart()
    self.stage = "intro"
    self.stageElapsed = 0.0
    self.finishStoryPlayed = false
    self.narrativeFinished = false
    self.finishPayload = nil
    self.pathBannerPlayed = false
    self.liftElapsed = 0.0
    self.liftStartPosition = { x = 0.0, y = 0.0, z = 0.0 }
    self.partColorStarts = {}
    self.partIds = {}

    self.chapter3FogColor = LookApplier.HexToColor(CHAPTER3_FOG, Color(0.19, 0.29, 0.35, 1.0))
    self.chapter3ColorNeg = LookApplier.HexToColor(CHAPTER3_COLOR_NEG, Color(0.16, 0.27, 0.33, 1.0))
    self.chapter3ColorMid = LookApplier.HexToColor(CHAPTER3_COLOR_MID, Color(0.31, 0.44, 0.50, 1.0))
    self.chapter3ColorPos = LookApplier.HexToColor(CHAPTER3_COLOR_POS, Color(0.53, 0.65, 0.65, 1.0))
    self.chapter3HeightFog = LookApplier.HexToColor(CHAPTER3_HEIGHT_FOG, Color(0.23, 0.35, 0.38, 1.0))

    local document = self:GetDocument()
    local liftPart = self:GetPart(LIFT_PART_ID)
    if not document or not liftPart then
        print("Director2_4: missing document or LiftPart")
        return
    end

    self.liftStartPosition.x = liftPart.transform.position.x
    self.liftStartPosition.y = liftPart.transform.position.y
    self.liftStartPosition.z = liftPart.transform.position.z

    for _, part in ipairs(document:GetParts()) do
        local look = LookApplier.CopyPartLook(part.look)
        self.partIds[#self.partIds + 1] = part.id
        self.partColorStarts[part.id] = {
            colorNeg = LookApplier.HexToColor(look.colorNeg, self.chapter3ColorNeg),
            colorMid = LookApplier.HexToColor(look.colorMid, self.chapter3ColorMid),
            colorPos = LookApplier.HexToColor(look.colorPos, self.chapter3ColorPos),
            fogColor = LookApplier.HexToColor(look.fogColor, self.chapter3HeightFog),
        }
    end

    local atmosphere = LookApplier.CopyAtmosphere(document.atmosphere)
    self.fogColorStart = LookApplier.HexToColor(atmosphere.fog.color, self.chapter3FogColor)

    self:SetInputLocked(true)
    self:SetPlayerLocked(true)

    local player = self:GetPlayer()
    if player and player.SetOnStarted then
        player:SetOnStarted(function(targetKey)
            self:OnPlayerStarted(targetKey)
        end)
    end

    self:PlayStory(Story.ch2_4_intro, {
        onComplete = function()
            self.stage = "await_finish"
            self.stageElapsed = 0.0
            self:SetPlayerLocked(false)
            self:SetInputLocked(false)
            print("Director2_4: Charlie is finding the exit alone")
        end,
    })
end

function Director2_4:OnPlayerStarted(targetKey)
    if self.stage ~= "await_finish" or self.pathBannerPlayed then
        return
    end
    local preview = self:GetPreview()
    local record = preview and preview.pathRuntime and preview.pathRuntime:GetNode(targetKey) or nil
    if not record or record.partId ~= LIFT_PART_ID then
        return
    end
    self.pathBannerPlayed = true
    self:PlayStory(Story.ch2_4_path)
    print("Director2_4: independent exit path target=" .. tostring(targetKey))
end

function Director2_4:ApplyTransitionColors(progress)
    local colorMix = CubicInOut(progress)
    self:SetAtmosphereFogColor(LookApplier.MixColor(
        self.fogColorStart,
        self.chapter3FogColor,
        colorMix
    ))
    for _, partId in ipairs(self.partIds) do
        local start = self.partColorStarts[partId]
        if start then
            self:SetPartLookColors(
                partId,
                LookApplier.MixColor(start.colorNeg, self.chapter3ColorNeg, colorMix),
                LookApplier.MixColor(start.colorMid, self.chapter3ColorMid, colorMix),
                LookApplier.MixColor(start.colorPos, self.chapter3ColorPos, colorMix),
                LookApplier.MixColor(start.fogColor, self.chapter3HeightFog, colorMix)
            )
        end
    end
end

function Director2_4:BeginLift(payload)
    if self.stage == "lift" or self.narrativeFinished then
        return
    end
    self.finishPayload = payload
    self.stage = "lift"
    self.stageElapsed = 0.0
    self.liftElapsed = 0.0
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    self:PlayStory(Story.ch2_4_lift_begin)
    print(string.format(
        "Director2_4: lift transition begin height=%.1f duration=%.1f",
        LIFT_HEIGHT,
        LIFT_DURATION
    ))
end

function Director2_4:FinishLift()
    local endPosition = {
        x = self.liftStartPosition.x,
        y = self.liftStartPosition.y + LIFT_HEIGHT,
        z = self.liftStartPosition.z,
    }
    self:SetPartVisualPosition(LIFT_PART_ID, endPosition)
    self:SetPartPosition(LIFT_PART_ID, endPosition, false)
    self:SetCameraLiftOffset(LIFT_HEIGHT + CAMERA_LEAD_HEIGHT)
    self:ApplyTransitionColors(1.0)
    self.stage = "farewell"
    self.stageElapsed = 0.0
    self:PlayStory(Story.ch2_4_farewell, {
        onComplete = function()
            self:FinishNarrative()
        end,
    })
    print("Director2_4: lift stopped in chapter 3 colors")
end

function Director2_4:FinishNarrative()
    if self.narrativeFinished then
        return
    end
    self.narrativeFinished = true
    local session = self.session
    if session and session.onFinish then
        session.onFinish(session, self.finishPayload)
    end
end

function Director2_4:OnFinish(payload)
    if self.finishStoryPlayed then
        return
    end
    self.finishStoryPlayed = true
    self:BeginLift(payload)
end

function Director2_4:OnUpdate(timeStep)
    self.stageElapsed = self.stageElapsed + timeStep
    if self.stage ~= "lift" then
        return
    end

    self.liftElapsed = self.liftElapsed + timeStep
    local progress = Clamp01(self.liftElapsed / LIFT_DURATION)
    local movementMix = CubicInOut(progress)
    local liftOffset = LIFT_HEIGHT * movementMix
    self:SetPartVisualPosition(LIFT_PART_ID, {
        x = self.liftStartPosition.x,
        y = self.liftStartPosition.y + liftOffset,
        z = self.liftStartPosition.z,
    })
    self:SetCameraLiftOffset(liftOffset + CameraLead(progress))

    local colorProgress = Clamp01((self.liftElapsed - COLOR_DELAY) / COLOR_DURATION)
    self:ApplyTransitionColors(colorProgress)

    if progress >= 1.0 then
        self:FinishLift()
    end
end

function Director2_4:OnDispose()
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
end

return Director2_4
