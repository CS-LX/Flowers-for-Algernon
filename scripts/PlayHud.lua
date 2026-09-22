-- 关卡内 HUD：剧情层 + 退出按钮 + modal 跳过。
-- 退出/跳过和对话 Mark 共用 HexMarkDraw；Esc 仍由 GameApp 处理，按钮走同一回调。

local UI = require("urhox-libs/UI")
local StoryView = require "StoryView"
local LevelExitButton = require "LevelExitButton"
local StorySkipButton = require "StorySkipButton"

---@class PlayHud
---@field onExit fun()|nil
---@field onSkip fun()|nil
---@field root Widget|nil
---@field storyView table|nil
---@field storyHost Widget|nil
---@field exitButton LevelExitButton|nil
---@field skipButton StorySkipButton|nil
---@field hiding boolean
---@field skipVisible boolean
---@field creditsRoll table|nil
local PlayHud = {}
PlayHud.__index = PlayHud

local EXIT_FADE = LevelExitButton.FADE_DURATION
local SKIP_FADE = StorySkipButton.FADE_DURATION

local function EnsureUI()
    UI.Init({
        theme = "default-dark",
        fonts = {
            {
                family = "sans",
                weights = {
                    normal = "Fonts/MiSans-Regular.ttf",
                    bold = "Fonts/MiSans-Bold.ttf",
                },
            },
        },
        scale = UI.Scale.DESIGN_RESOLUTION(1920, 1080),
    })
    UI.SetScale(UI.Scale.DESIGN_RESOLUTION(1920, 1080))
end

function PlayHud.New(onExit)
    local self = setmetatable({}, PlayHud)
    self.onExit = onExit
    ---@type fun()|nil
    self.onSkip = nil
    ---@type Widget|nil
    self.root = nil
    ---@type table|nil
    self.storyView = nil
    ---@type Widget|nil
    self.storyHost = nil
    ---@type LevelExitButton|nil
    self.exitButton = nil
    ---@type Widget|nil
    self.exitHost = nil
    ---@type StorySkipButton|nil
    self.skipButton = nil
    ---@type Widget|nil
    self.skipHost = nil
    self.hiding = false
    self.skipVisible = false
    ---@type table|nil
    self.creditsRoll = nil
    return self
end

function PlayHud:RequestExit()
    if self.hiding then
        return
    end
    if self.onExit then
        self.onExit()
    end
end

function PlayHud:RequestSkip()
    if self.hiding or not self.skipVisible then
        return
    end
    if self.onSkip then
        self.onSkip()
    end
    self:SyncSkipButton()
end

function PlayHud:SetSkipVisible(visible)
    local show = visible == true
    if self.skipVisible == show then
        return
    end
    self.skipVisible = show
    if not self.skipButton then
        return
    end
    if show then
        self.skipButton:SetClickArmed(true)
        self.skipButton:FadeTo(1.0, SKIP_FADE)
        print("PlayHud: story skip shown")
    else
        self.skipButton:SetClickArmed(false)
        self.skipButton:FadeTo(0.0, SKIP_FADE)
        print("PlayHud: story skip hidden")
    end
end

function PlayHud:SyncSkipButton()
    local show = not self.hiding
        and self.creditsRoll == nil
        and self.storyView ~= nil
        and self.storyView.mode == "modal"
    self:SetSkipVisible(show)
end

function PlayHud:Show(definition)
    EnsureUI()
    self.hiding = false
    self.storyView = StoryView.New()
    self.storyHost = self.storyView:Build()
    self.exitButton = LevelExitButton {
        onExit = function()
            self:RequestExit()
        end,
    }
    self.exitButton:SetIconAlpha(0.0)
    self.exitButton:FadeTo(1.0, EXIT_FADE)
    self.exitHost = UI.Panel {
        position = "absolute",
        left = 0,
        top = 0,
        width = 140,
        height = 140,
        paddingTop = 24,
        paddingLeft = 24,
        pointerEvents = "box-none",
        children = {
            self.exitButton,
        },
    }
    self.skipButton = StorySkipButton {
        onSkip = function()
            self:RequestSkip()
        end,
    }
    self.skipButton:SetIconAlpha(0.0)
    self.skipButton:SetClickArmed(false)
    self.skipVisible = false
    self.skipHost = UI.Panel {
        position = "absolute",
        right = 0,
        top = 0,
        width = 140,
        height = 140,
        paddingTop = 24,
        paddingRight = 24,
        pointerEvents = "box-none",
        children = {
            self.skipButton,
        },
    }
    self.root = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            self.storyHost,
            self.exitHost,
            self.skipHost,
        },
    }
    UI.SetRoot(self.root, true)
    print("PlayHud: story+exit hud for " .. tostring(definition and definition.id))
end

function PlayHud:BeginExitFade()
    if not self.exitButton then
        return
    end
    self.hiding = true
    self.exitButton:SetClickArmed(false)
    self.exitButton:FadeTo(0.0, EXIT_FADE)
    self:SetSkipVisible(false)
    if self.storyView then
        self.storyView:Hide()
    end
    print("PlayHud: exit button fade out")
end

function PlayHud:SetStatus(text)
    -- 关内不再显示调试状态条。
end

function PlayHud:ShowFinish()
    print("PlayHud: finish acknowledged without overlay")
end

function PlayHud:Update(timeStep)
    if self.creditsRoll then
        self.creditsRoll:Update(timeStep)
    end
    self:SyncSkipButton()
end

function PlayHud:ShowCredits(onComplete, onFadeOut, canSkip)
    EnsureUI()
    if not self.root or not self.exitButton then
        self:Show(nil)
    end
    self.hiding = true
    self:SetSkipVisible(false)
    if self.storyView then
        self.storyView:Hide()
    end
    if not self.creditsRoll then
        local CreditsRoll = require "CreditsRoll"
        self.creditsRoll = CreditsRoll.New()
    end
    self.creditsRoll:Show(onComplete, onFadeOut, canSkip == true)
    if self.root and self.creditsRoll.root then
        self.root:AddChild(self.creditsRoll.root)
        if self.exitHost then
            self.root:AddChild(self.exitHost)
        end
    end
    if self.exitButton then
        if canSkip == true then
            self.hiding = false
            self.exitButton:SetClickArmed(true)
            self.exitButton:SetIconAlpha(0.0)
            self.exitButton:FadeTo(1.0, EXIT_FADE)
        else
            self.exitButton:SetClickArmed(false)
            self.exitButton:FadeTo(0.0, EXIT_FADE)
        end
    end
    print("PlayHud: credits roll started skip=" .. tostring(canSkip == true))
end

function PlayHud:CanSkipCredits()
    return self.creditsRoll ~= nil and self.creditsRoll:CanSkip()
end

function PlayHud:SkipCredits()
    if not self.creditsRoll then
        return false
    end
    if self.exitButton then
        self.hiding = true
        self.exitButton:SetClickArmed(false)
        self.exitButton:FadeTo(0.0, EXIT_FADE)
    end
    return self.creditsRoll:BeginSkip()
end

function PlayHud:Hide()
    self.hiding = false
    if self.root then
        UI.SetRoot(nil, true)
        self.root = nil
    end
    if self.storyView then
        self.storyView:Destroy()
        self.storyView = nil
    end
    self.storyHost = nil
    self.exitButton = nil
    self.exitHost = nil
    self.skipButton = nil
    self.skipHost = nil
    self.skipVisible = false
    if self.creditsRoll then
        self.creditsRoll:Hide()
        self.creditsRoll = nil
    end
end

return PlayHud
