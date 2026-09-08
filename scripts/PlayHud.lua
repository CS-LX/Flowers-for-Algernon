-- 关卡内 HUD：剧情层 + 退出按钮。
-- 退出按钮和对话 Mark 共用 HexMarkDraw；Esc 仍由 GameApp 处理，按钮走同一回调。

local UI = require("urhox-libs/UI")
local StoryView = require "StoryView"
local LevelExitButton = require "LevelExitButton"

---@class PlayHud
---@field onExit fun()|nil
---@field root Widget|nil
---@field storyView table|nil
---@field storyHost Widget|nil
---@field exitButton LevelExitButton|nil
---@field hiding boolean
---@field creditsRoll table|nil
local PlayHud = {}
PlayHud.__index = PlayHud

local EXIT_FADE = LevelExitButton.FADE_DURATION

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
        scale = UI.Scale.DEFAULT,
    })
end

function PlayHud.New(onExit)
    local self = setmetatable({}, PlayHud)
    self.onExit = onExit
    ---@type Widget|nil
    self.root = nil
    ---@type table|nil
    self.storyView = nil
    ---@type Widget|nil
    self.storyHost = nil
    ---@type LevelExitButton|nil
    self.exitButton = nil
    self.hiding = false
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

function PlayHud:Show(definition)
    EnsureUI()
    self.hiding = false
    self.storyView = StoryView.New()
    self.storyHost = self.storyView:Build()
    self.exitButton = LevelExitButton {
        width = 56,
        height = 56,
        onExit = function()
            self:RequestExit()
        end,
    }
    self.exitButton:SetIconAlpha(0.0)
    self.exitButton:FadeTo(1.0, EXIT_FADE)
    self.root = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            self.storyHost,
            UI.Panel {
                position = "absolute",
                left = 0,
                top = 0,
                width = 96,
                height = 96,
                paddingTop = 20,
                paddingLeft = 20,
                pointerEvents = "box-none",
                children = {
                    self.exitButton,
                },
            },
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
end

function PlayHud:ShowCredits(onComplete)
    EnsureUI()
    self.hiding = true
    if self.storyView then
        self.storyView:Hide()
    end
    if not self.creditsRoll then
        local CreditsRoll = require "CreditsRoll"
        self.creditsRoll = CreditsRoll.New()
    end
    self.creditsRoll:Show(onComplete)
    print("PlayHud: credits roll started")
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
    if self.creditsRoll then
        self.creditsRoll:Hide()
        self.creditsRoll = nil
    end
end

return PlayHud
