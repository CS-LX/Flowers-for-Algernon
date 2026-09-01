-- 轻剧情外壳：fullscreen / banner / modal。
-- 只负责显示当前句、背景 crossfade 和六边形提示，不排队、不打字。

local UI = require("urhox-libs/UI")
local StoryHexPrompt = require "StoryHexPrompt"

local StoryView = {}
StoryView.__index = StoryView

local WHITE = { 255, 255, 255, 255 }
local DEFAULT_FULLSCREEN_BG = { 18, 16, 14, 236 }
local CROSSFADE_SECONDS = 0.45
local BANNER_HEIGHT = 168
local EXIT_SECONDS = 0.35
local EXIT_SLIDE = 28
local WAVE_WAIT = 0.45

local function CopyColor(color, fallback)
    local source = color
    if type(source) ~= "table" then
        source = fallback
    end
    return {
        source[1] or 0,
        source[2] or 0,
        source[3] or 0,
        source[4] or 255,
    }
end

local function MixColor(fromColor, toColor, t)
    if t <= 0.0 then
        return CopyColor(fromColor)
    end
    if t >= 1.0 then
        return CopyColor(toColor)
    end
    return {
        fromColor[1] + (toColor[1] - fromColor[1]) * t,
        fromColor[2] + (toColor[2] - fromColor[2]) * t,
        fromColor[3] + (toColor[3] - fromColor[3]) * t,
        fromColor[4] + (toColor[4] - fromColor[4]) * t,
    }
end

local function VisibleText(line, visibleChars)
    local text = line and line.text or ""
    local total = utf8.len(text)
    if type(total) ~= "number" then
        total = #text
    end
    if visibleChars >= total then
        return text
    end
    if visibleChars <= 0 then
        return ""
    end
    local index = utf8.offset(text, math.floor(visibleChars) + 1)
    if not index then
        return text
    end
    return text:sub(1, index - 1)
end

function StoryView.New()
    local self = setmetatable({}, StoryView)
    ---@type Widget|nil
    self.root = nil
    ---@type Widget|nil
    self.fullscreen = nil
    ---@type Widget|nil
    self.fullBgFrom = nil
    ---@type Widget|nil
    self.fullBgTo = nil
    ---@type Widget|nil
    self.fullContent = nil
    ---@type Label|nil
    self.fullText = nil
    ---@type Widget|nil
    self.fullTextHost = nil
    ---@type table|nil
    self.fullPrompt = nil
    ---@type Widget|nil
    self.bottom = nil
    ---@type Widget|nil
    self.bannerFade = nil
    ---@type Label|nil
    self.bottomText = nil
    ---@type Widget|nil
    self.bottomTextHost = nil
    ---@type table|nil
    self.bottomPrompt = nil
    self.mode = nil
    self.lineComplete = false
    self.bgFrom = CopyColor(DEFAULT_FULLSCREEN_BG)
    self.bgTo = CopyColor(DEFAULT_FULLSCREEN_BG)
    self.bgMix = 1.0
    self.exitElapsed = -1.0
    self.exitKind = nil
    ---@type fun()|nil
    self.exitCallback = nil
    self.contentOpacity = 1.0
    self.contentTranslateY = 0.0
    self.onAdvance = nil
    return self
end

function StoryView:RequestAdvance()
    if self.mode == "banner" then
        return
    end
    if self.onAdvance then
        self.onAdvance()
    end
end

function StoryView:Build()
    self.fullBgFrom = UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        top = 0,
        bottom = 0,
        backgroundColor = DEFAULT_FULLSCREEN_BG,
        pointerEvents = "none",
    }
    self.fullBgTo = UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        top = 0,
        bottom = 0,
        backgroundColor = DEFAULT_FULLSCREEN_BG,
        pointerEvents = "none",
    }
    self.fullText = UI.Label {
        text = "",
        fontSize = 22,
        fontColor = WHITE,
        whiteSpace = "normal",
        textAlign = "center",
    }
    self.fullPrompt = StoryHexPrompt {
        width = 56,
        height = 56,
        marginTop = 18,
    }
    self.fullTextHost = UI.Panel {
        width = "76%",
        maxWidth = 720,
        alignItems = "center",
        pointerEvents = "none",
        children = { self.fullText },
    }
    self.fullContent = UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        bottom = 56,
        paddingHorizontal = 48,
        alignItems = "center",
        gap = 8,
        pointerEvents = "none",
        children = {
            self.fullTextHost,
            self.fullPrompt,
        },
    }
    self.fullscreen = UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        top = 0,
        bottom = 0,
        visible = false,
        pointerEvents = "auto",
        onClick = function()
            self:RequestAdvance()
        end,
        children = {
            self.fullBgFrom,
            self.fullBgTo,
            self.fullContent,
        },
    }

    self.bannerFade = UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        top = 0,
        bottom = 0,
        pointerEvents = "none",
        backgroundGradient = {
            direction = "to-top",
            from = { 0, 0, 0, 220 },
            to = { 0, 0, 0, 0 },
        },
    }
    self.bottomText = UI.Label {
        text = "",
        fontSize = 16,
        fontColor = WHITE,
        whiteSpace = "normal",
        textAlign = "center",
    }
    self.bottomTextHost = UI.Panel {
        width = "80%",
        maxWidth = 720,
        alignItems = "center",
        pointerEvents = "none",
        children = { self.bottomText },
    }
    self.bottomPrompt = StoryHexPrompt {
        width = 56,
        height = 56,
        marginTop = 10,
        visible = false,
    }
    self.bottom = UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        bottom = 0,
        height = BANNER_HEIGHT,
        paddingHorizontal = 36,
        paddingBottom = 28,
        paddingTop = 36,
        alignItems = "center",
        justifyContent = "flex-end",
        gap = 8,
        visible = false,
        pointerEvents = "none",
        onClick = function()
            if self.mode == "modal" then
                self:RequestAdvance()
            end
        end,
        children = {
            self.bannerFade,
            self.bottomTextHost,
            self.bottomPrompt,
        },
    }

    self.root = UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        top = 0,
        bottom = 0,
        pointerEvents = "box-none",
        children = {
            self.fullscreen,
            self.bottom,
        },
    }
    return self.root
end

function StoryView:ApplyBackgroundMix()
    if not self.fullBgFrom or not self.fullBgTo then
        return
    end
    self.fullBgFrom:SetBackgroundColor(self.bgFrom)
    self.fullBgTo:SetBackgroundColor(self.bgTo)
    self.fullBgFrom:SetOpacity(1.0)
    self.fullBgTo:SetOpacity(self.bgMix)
end

function StoryView:BeginBackground(color)
    local nextColor = CopyColor(color, DEFAULT_FULLSCREEN_BG)
    if self.bgMix < 1.0 then
        self.bgFrom = MixColor(self.bgFrom, self.bgTo, self.bgMix)
    else
        self.bgFrom = CopyColor(self.bgTo)
    end
    self.bgTo = nextColor
    self.bgMix = 0.0
    self:ApplyBackgroundMix()
end

function StoryView:ActiveContent()
    if self.mode == "fullscreen" then
        return self.fullTextHost
    end
    if self.mode == "banner" or self.mode == "modal" then
        return self.bottomTextHost
    end
    return nil
end

function StoryView:ApplyContentMotion()
    local content = self:ActiveContent()
    if not content then
        return
    end
    content:SetStyle({
        opacity = self.contentOpacity,
        translateY = self.contentTranslateY,
    })
end

function StoryView:ResetContentMotion()
    self.contentOpacity = 1.0
    self.contentTranslateY = 0.0
    self:ApplyContentMotion()
end

function StoryView:HidePrompts()
    if self.fullPrompt then
        self.fullPrompt:HideImmediate()
    end
    if self.bottomPrompt then
        self.bottomPrompt:HideImmediate()
        self.bottomPrompt:SetVisible(false)
    end
end

function StoryView:CancelExit()
    self.exitElapsed = -1.0
    self.exitKind = nil
    self.exitCallback = nil
end

function StoryView:Hide()
    self.mode = nil
    self.lineComplete = false
    self:CancelExit()
    self:HidePrompts()
    self:ResetContentMotion()
    if self.fullscreen then
        self.fullscreen:SetVisible(false)
    end
    if self.bottom then
        self.bottom:SetVisible(false)
        self.bottom:SetProp("pointerEvents", "none")
    end
end

---@param kind string
---@param onDone fun()|nil
function StoryView:NotifyAdvance(kind, onDone)
    local prompt = self.mode == "fullscreen" and self.fullPrompt or self.bottomPrompt
    if prompt and prompt.PlayWave then
        prompt:PlayWave(kind)
    end
    if kind ~= "advance" then
        if type(onDone) == "function" then
            onDone()
        end
        return
    end
    self.exitElapsed = 0.0
    self.exitKind = kind
    self.exitCallback = onDone
end

function StoryView:SyncPrompt()
    local clickable = self.mode == "fullscreen" or self.mode == "modal"
    if self.fullPrompt then
        if self.mode == "fullscreen" and clickable then
            self.fullPrompt:SetPrompt(true, self.lineComplete)
        else
            self.fullPrompt:SetPrompt(false, false)
        end
    end
    if self.bottomPrompt then
        local show = self.mode == "modal"
        self.bottomPrompt:SetVisible(show)
        if show then
            self.bottomPrompt:SetPrompt(true, self.lineComplete)
        else
            self.bottomPrompt:SetPrompt(false, false)
        end
    end
end

---@param line table
---@param visibleChars number
---@param complete boolean
---@param isNewLine boolean|nil
function StoryView:ShowLine(line, visibleChars, complete, isNewLine)
    local mode = line.mode or "banner"
    local modeChanged = self.mode ~= mode
    self.mode = mode
    self.lineComplete = complete == true
    if isNewLine then
        self:CancelExit()
        self:ResetContentMotion()
    end
    local shown = VisibleText(line, visibleChars)
    local skipPrompt = self.exitElapsed >= 0.0
    if mode == "fullscreen" then
        if isNewLine or modeChanged then
            self:BeginBackground(line.background or DEFAULT_FULLSCREEN_BG)
        end
        if self.fullscreen then
            self.fullscreen:SetVisible(true)
        end
        if self.bottom then
            self.bottom:SetVisible(false)
            self.bottom:SetProp("pointerEvents", "none")
        end
        if self.fullText then
            self.fullText:SetText(shown)
        end
        if not skipPrompt then
            self:SyncPrompt()
        end
        return
    end
    if self.fullscreen then
        self.fullscreen:SetVisible(false)
    end
    if self.bottom then
        self.bottom:SetVisible(true)
        self.bottom:SetProp("pointerEvents", mode == "modal" and "auto" or "none")
    end
    if self.bottomText then
        self.bottomText:SetText(shown)
    end
    if not skipPrompt then
        self:SyncPrompt()
    end
end

function StoryView:Update(timeStep)
    if self.mode == "fullscreen" and self.bgMix < 1.0 then
        self.bgMix = math.min(1.0, self.bgMix + timeStep / CROSSFADE_SECONDS)
        self:ApplyBackgroundMix()
    end
    if self.exitElapsed < 0.0 then
        return
    end
    self.exitElapsed = self.exitElapsed + timeStep
    local t = math.min(1.0, self.exitElapsed / EXIT_SECONDS)
    self.contentOpacity = 1.0 - t
    self.contentTranslateY = EXIT_SLIDE * t
    self:ApplyContentMotion()
    if self.exitElapsed >= math.max(EXIT_SECONDS, WAVE_WAIT) then
        local done = self.exitCallback
        self:CancelExit()
        if type(done) == "function" then
            done()
        end
    end
end

function StoryView:Destroy()
    self:Hide()
    self.root = nil
    self.fullscreen = nil
    self.fullBgFrom = nil
    self.fullBgTo = nil
    self.fullContent = nil
    self.fullText = nil
    self.fullTextHost = nil
    self.fullPrompt = nil
    self.bottom = nil
    self.bannerFade = nil
    self.bottomText = nil
    self.bottomTextHost = nil
    self.bottomPrompt = nil
    self.onAdvance = nil
end

return StoryView
