-- 轻剧情外壳：banner / modal。
-- 字浮在关卡下沿，柔和暗影保证暖色场景可读。fullscreen 暂不使用。

local UI = require("urhox-libs/UI")
local StoryHexPrompt = require "StoryHexPrompt"

local StoryView = {}
StoryView.__index = StoryView

local EXIT_SECONDS = 0.35
local EXIT_SLIDE = 28
local WAVE_WAIT = 0.45

function StoryView.New()
    local self = setmetatable({}, StoryView)
    ---@type Widget|nil
    self.root = nil
    ---@type Widget|nil
    self.bottom = nil
    ---@type Widget|nil
    self.bottomTextHost = nil
    ---@type table|nil
    self.bottomPrompt = nil
    self.glyphViews = {}
    self.layout = nil
    self.mode = nil
    self.lineComplete = false
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
    if self.mode ~= "modal" then
        return
    end
    if self.onAdvance then
        self.onAdvance()
    end
end

function StoryView:Build()
    -- 60% 居中列：约 22 个汉字一行，避免手机横屏从左扫到右。
    self.bottomTextHost = UI.Panel {
        width = "60%",
        maxWidth = "60%",
        flexDirection = "row",
        flexWrap = "wrap",
        justifyContent = "center",
        alignItems = "flex-end",
        pointerEvents = "none",
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
        top = 0,
        bottom = 0,
        paddingHorizontal = 36,
        paddingBottom = 28,
        alignItems = "center",
        justifyContent = "flex-end",
        gap = 8,
        visible = false,
        pointerEvents = "none",
        onClick = function()
            self:RequestAdvance()
        end,
        children = {
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
            self.bottom,
        },
    }
    return self.root
end

function StoryView:ApplyContentMotion()
    if not self.bottomTextHost then
        return
    end
    self.bottomTextHost:SetStyle({
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
    if self.bottom then
        self.bottom:SetVisible(false)
        self.bottom:SetProp("pointerEvents", "none")
    end
end

---@param kind string
---@param onDone fun()|nil
function StoryView:NotifyAdvance(kind, onDone)
    if self.bottomPrompt and self.bottomPrompt.PlayWave then
        self.bottomPrompt:PlayWave(kind)
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
    if not self.bottomPrompt then
        return
    end
    local show = self.mode == "modal"
    self.bottomPrompt:SetVisible(show)
    if show then
        self.bottomPrompt:SetPrompt(true, self.lineComplete)
    else
        self.bottomPrompt:SetPrompt(false, false)
    end
end

---@param line table
---@param visibleChars number
---@param complete boolean
---@param isNewLine boolean|nil
function StoryView:ShowLine(line, visibleChars, complete, isNewLine)
    local mode = line.mode or "banner"
    if mode == "fullscreen" then
        mode = "banner"
    end
    self.mode = mode
    self.lineComplete = complete == true
    if isNewLine then
        self:CancelExit()
        self:ResetContentMotion()
    end
    if line.layout then
        self:EnsureGlyphs(line.layout)
        self:SetVisibleGlyphs(visibleChars or 0)
    end
    if self.bottom then
        self.bottom:SetVisible(true)
        self.bottom:SetProp("pointerEvents", mode == "modal" and "auto" or "none")
    end
    if self.exitElapsed < 0.0 then
        self:SyncPrompt()
    end
end

function StoryView:Update(timeStep)
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

function StoryView:ClearGlyphs()
    if not self.bottomTextHost then
        self.glyphViews = {}
        self.layout = nil
        return
    end
    local children = self.bottomTextHost.children or {}
    for i = #children, 1, -1 do
        self.bottomTextHost:RemoveChild(children[i])
    end
    self.glyphViews = {}
    self.layout = nil
end

function StoryView:EnsureGlyphs(layout)
    if not self.bottomTextHost then
        return
    end
    if self.layout == layout and #self.glyphViews == #(layout.glyphs or {}) then
        return
    end
    self:ClearGlyphs()
    if not self.bottomTextHost then
        return
    end
    self.layout = layout
    local glyphs = layout and layout.glyphs or {}
    for i = 1, #glyphs do
        local glyph = glyphs[i]
        local label = UI.Label {
            text = glyph.text,
            fontSize = glyph.fontSize,
            fontColor = glyph.fontColor,
            fontWeight = glyph.fontWeight or "normal",
            textShadow = glyph.textShadow,
            rotate = glyph.rotate or 0,
            visible = false,
            pointerEvents = "none",
        }
        self.bottomTextHost:AddChild(label)
        self.glyphViews[i] = label
    end
end

function StoryView:SetVisibleGlyphs(count)
    for i = 1, #self.glyphViews do
        self.glyphViews[i]:SetVisible(i <= count)
    end
end

function StoryView:Destroy()
    self:Hide()
    self:ClearGlyphs()
    self.root = nil
    self.bottom = nil
    self.bottomTextHost = nil
    self.bottomPrompt = nil
    self.onAdvance = nil
end

return StoryView
