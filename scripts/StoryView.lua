-- 轻剧情外壳：fullscreen / banner / modal。
-- 只负责显示当前句，不排队、不打字。

local UI = require("urhox-libs/UI")

local StoryView = {}
StoryView.__index = StoryView

local FULLSCREEN_BG = { 18, 16, 14, 236 }
local BANNER_BG = { 18, 16, 14, 210 }
local TEXT = { 236, 230, 218, 255 }
local MUTED = { 176, 164, 148, 255 }
local HINT = { 132, 122, 110, 255 }

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
    self.bottom = nil
    ---@type Label|nil
    self.fullSpeaker = nil
    ---@type Label|nil
    self.fullText = nil
    ---@type Label|nil
    self.fullHint = nil
    ---@type Label|nil
    self.bottomSpeaker = nil
    ---@type Label|nil
    self.bottomText = nil
    ---@type Label|nil
    self.bottomHint = nil
    self.mode = nil
    self.onAdvance = nil
    return self
end

function StoryView:Build()
    self.fullSpeaker = UI.Label {
        text = "",
        fontSize = 16,
        fontColor = MUTED,
        visible = false,
    }
    self.fullText = UI.Label {
        text = "",
        fontSize = 22,
        fontColor = TEXT,
        whiteSpace = "normal",
        textAlign = "center",
    }
    self.fullHint = UI.Label {
        text = "点击继续",
        fontSize = 12,
        fontColor = HINT,
    }
    self.fullscreen = UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        top = 0,
        bottom = 0,
        backgroundColor = FULLSCREEN_BG,
        justifyContent = "center",
        alignItems = "center",
        padding = 48,
        visible = false,
        pointerEvents = "auto",
        onClick = function()
            if self.onAdvance then
                self.onAdvance()
            end
        end,
        children = {
            UI.Panel {
                width = "70%",
                maxWidth = 720,
                gap = 16,
                alignItems = "center",
                children = {
                    self.fullSpeaker,
                    self.fullText,
                    self.fullHint,
                },
            },
        },
    }

    self.bottomSpeaker = UI.Label {
        text = "",
        fontSize = 13,
        fontColor = MUTED,
        visible = false,
    }
    self.bottomText = UI.Label {
        text = "",
        fontSize = 16,
        fontColor = TEXT,
        whiteSpace = "normal",
    }
    self.bottomHint = UI.Label {
        text = "点击继续",
        fontSize = 11,
        fontColor = HINT,
        visible = false,
    }
    self.bottom = UI.Panel {
        position = "absolute",
        left = 24,
        right = 24,
        bottom = 24,
        paddingHorizontal = 20,
        paddingVertical = 16,
        gap = 6,
        backgroundColor = BANNER_BG,
        borderRadius = 10,
        visible = false,
        pointerEvents = "none",
        onClick = function()
            if self.mode == "modal" and self.onAdvance then
                self.onAdvance()
            end
        end,
        children = {
            self.bottomSpeaker,
            self.bottomText,
            self.bottomHint,
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

function StoryView:Hide()
    self.mode = nil
    if self.fullscreen then
        self.fullscreen:SetVisible(false)
    end
    if self.bottom then
        self.bottom:SetVisible(false)
    end
end

---@param line table
---@param visibleChars number
---@param complete boolean
function StoryView:ShowLine(line, visibleChars, complete)
    local mode = line.mode or "banner"
    self.mode = mode
    local speaker = line.speaker or ""
    local shown = VisibleText(line, visibleChars)
    local hint = complete and "点击继续" or "点击显示全部"
    if mode == "fullscreen" then
        if self.fullscreen then
            self.fullscreen:SetVisible(true)
        end
        if self.bottom then
            self.bottom:SetVisible(false)
        end
        if self.fullSpeaker then
            self.fullSpeaker:SetVisible(speaker ~= "")
            self.fullSpeaker:SetText(speaker)
        end
        if self.fullText then
            self.fullText:SetText(shown)
        end
        if self.fullHint then
            self.fullHint:SetText(hint)
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
    if self.bottomSpeaker then
        self.bottomSpeaker:SetVisible(speaker ~= "")
        self.bottomSpeaker:SetText(speaker)
    end
    if self.bottomText then
        self.bottomText:SetText(shown)
    end
    if self.bottomHint then
        self.bottomHint:SetVisible(mode == "modal")
        self.bottomHint:SetText(hint)
    end
end

function StoryView:Destroy()
    self:Hide()
    self.root = nil
    self.fullscreen = nil
    self.bottom = nil
    self.fullSpeaker = nil
    self.fullText = nil
    self.fullHint = nil
    self.bottomSpeaker = nil
    self.bottomText = nil
    self.bottomHint = nil
    self.onAdvance = nil
end

return StoryView
