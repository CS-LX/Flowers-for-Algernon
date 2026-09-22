-- 轻剧情播放器。
-- 排队、打字、点击翻页、阻塞输入、完成回调。不写某关台词。

local StoryTextStyle = require "StoryTextStyle"
local Sfx = require "Sfx"

local StoryPlayer = {}
StoryPlayer.__index = StoryPlayer

local DEFAULT_TYPE_SPEED = 28
local BANNER_HOLD = 1.2

local function LineCharCount(text)
    if type(text) ~= "string" or text == "" then
        return 0
    end
    local count = utf8.len(text)
    if type(count) ~= "number" then
        return #text
    end
    return count
end

local function CopyLine(source)
    if type(source) ~= "table" then
        return nil
    end
    local mode = source.mode
    if mode == "fullscreen" then
        mode = "banner"
    elseif mode ~= "modal" and mode ~= "banner" then
        mode = "banner"
    end
    local blockInput = source.blockInput
    if mode == "modal" then
        blockInput = true
    elseif blockInput == nil then
        blockInput = false
    end
    local text = tostring(source.text or "")
    local style = StoryTextStyle.ResolveName(source.style)
    return {
        id = source.id,
        speaker = source.speaker,
        style = style,
        text = text,
        image = source.image,
        background = source.background,
        mode = mode,
        typeSpeed = tonumber(source.typeSpeed) or DEFAULT_TYPE_SPEED,
        blockInput = blockInput == true,
        layout = StoryTextStyle.Layout(text, style, { id = source.id }),
    }
end

---@param view table|nil
function StoryPlayer.New(view)
    local self = setmetatable({}, StoryPlayer)
    self.view = view
    self.lines = {}
    self.index = 1
    self.visibleChars = 0
    self.charProgress = 0.0
    self.playing = false
    self.lineComplete = false
    self.holdElapsed = 0.0
    self.exiting = false
    ---@type fun()|nil
    self.onComplete = nil
    ---@type table|nil
    self.sfx = nil
    if self.view then
        self.view.onAdvance = function()
            self:Advance()
        end
    end
    return self
end

function StoryPlayer:AttachView(view)
    self.view = view
    if self.view then
        self.view.onAdvance = function()
            self:Advance()
        end
    end
end

function StoryPlayer:AttachSfx(sfx)
    self.sfx = sfx
end

function StoryPlayer:PlaySfx(path)
    if self.sfx and path then
        self.sfx:Play(path)
    end
end

function StoryPlayer:TypePath(line)
    if line and line.style == StoryTextStyle.CHARLIE then
        return Sfx.TYPE_CHARLIE
    end
    return Sfx.TYPE_RESEARCHER
end

function StoryPlayer:PlayTypeChars(line, fromCount, toCount)
    local path = self:TypePath(line)
    for _ = fromCount + 1, toCount do
        self:PlaySfx(path)
    end
end

function StoryPlayer:IsPlaying()
    return self.playing
end

function StoryPlayer:IsBlocking()
    if not self.playing then
        return false
    end
    local line = self.lines[self.index]
    return line and line.blockInput == true
end

function StoryPlayer:CurrentLine()
    return self.lines[self.index]
end

---@param lines table
---@param options table|nil
---@return boolean
function StoryPlayer:Play(lines, options)
    options = options or {}
    self:Stop(false)
    local copied = {}
    for _, source in ipairs(lines or {}) do
        local line = CopyLine(source)
        if line and line.text ~= "" then
            copied[#copied + 1] = line
        end
    end
    if #copied == 0 then
        if type(options.onComplete) == "function" then
            options.onComplete()
        end
        return false
    end
    self.lines = copied
    self.index = 1
    self.playing = true
    self.exiting = false
    self.onComplete = options.onComplete
    self:ShowCurrent(true)
    print(string.format(
        "StoryPlayer: play lines=%d first=%s mode=%s",
        #self.lines,
        tostring(copied[1].id),
        tostring(copied[1].mode)
    ))
    return true
end

function StoryPlayer:ShowCurrent(reset)
    local line = self.lines[self.index]
    if not line then
        self:Finish()
        return
    end
    if reset then
        self.visibleChars = 0
        self.charProgress = 0.0
        self.holdElapsed = 0.0
        self.lineComplete = LineCharCount(line.text) <= 0
    end
    if self.view and self.view.ShowLine then
        self.view:ShowLine(line, self.visibleChars, self.lineComplete, reset == true)
    end
end

function StoryPlayer:Advance()
    if not self.playing then
        return false
    end
    local line = self.lines[self.index]
    if not line then
        return false
    end
    if self.exiting then
        return false
    end
    if not self.lineComplete then
        self.visibleChars = LineCharCount(line.text)
        self.lineComplete = true
        if self.view and self.view.NotifyAdvance then
            self.view:NotifyAdvance("reveal")
        end
        self:ShowCurrent(false)
        return true
    end
    if line.mode == "modal" then
        self:PlaySfx(Sfx.MODAL_CLICK)
    end
    self.exiting = true
    local function Continue()
        if not self.playing then
            return
        end
        self.exiting = false
        self.index = self.index + 1
        if self.index > #self.lines then
            self:Finish()
            return
        end
        self:ShowCurrent(true)
    end
    if self.view and self.view.NotifyAdvance then
        self.view:NotifyAdvance("advance", Continue)
        return true
    end
    Continue()
    return true
end

function StoryPlayer:Skip()
    if not self.playing then
        return false
    end
    print("StoryPlayer: skip sequence")
    self:Finish()
    return true
end

-- 跳过当前连续 modal，停在下一条非 modal（演出/banner）或整段结束。
function StoryPlayer:SkipModalRun()
    if not self.playing then
        return false
    end
    local line = self.lines[self.index]
    if not line or line.mode ~= "modal" then
        return false
    end
    if self.view and self.view.CancelExit then
        self.view:CancelExit()
    end
    local nextIndex = self.index + 1
    while nextIndex <= #self.lines and self.lines[nextIndex].mode == "modal" do
        nextIndex = nextIndex + 1
    end
    print(string.format(
        "StoryPlayer: skip modal run from=%d to=%d total=%d",
        self.index,
        nextIndex,
        #self.lines
    ))
    if nextIndex > #self.lines then
        self:Finish()
        return true
    end
    self.exiting = false
    self.index = nextIndex
    self:ShowCurrent(true)
    return true
end

function StoryPlayer:Finish()
    local complete = self.onComplete
    self:Stop(true)
    if type(complete) == "function" then
        complete()
    end
end

---@param hide boolean|nil
function StoryPlayer:Stop(hide)
    self.playing = false
    self.exiting = false
    self.lines = {}
    self.index = 1
    self.visibleChars = 0
    self.charProgress = 0.0
    self.lineComplete = false
    self.holdElapsed = 0.0
    self.onComplete = nil
    if hide ~= false and self.view and self.view.Hide then
        self.view:Hide()
    end
end

function StoryPlayer:WantsAdvance()
    return input:GetKeyPress(KEY_SPACE)
end

function StoryPlayer:Update(timeStep)
    if self.view and self.view.Update then
        self.view:Update(timeStep)
    end
    if not self.playing then
        return
    end
    local line = self.lines[self.index]
    if not line then
        return
    end
    if self.exiting then
        return
    end
    if self.lineComplete then
        if line.mode == "banner" then
            self.holdElapsed = self.holdElapsed + timeStep
            if self.holdElapsed >= BANNER_HOLD then
                self:Advance()
            end
            return
        end
        if line.mode ~= "banner" and self:WantsAdvance() then
            self:Advance()
        end
        return
    end
    local total = LineCharCount(line.text)
    local speed = line.typeSpeed
    if speed <= 0 then
        self.visibleChars = total
        self.lineComplete = true
        self:ShowCurrent(false)
        return
    end
    self.charProgress = self.charProgress + timeStep * speed
    local nextCount = math.floor(self.charProgress)
    if nextCount > self.visibleChars then
        local fromCount = self.visibleChars
        self.visibleChars = math.min(total, nextCount)
        self:PlayTypeChars(line, fromCount, self.visibleChars)
        if self.visibleChars >= total then
            self.lineComplete = true
        end
        self:ShowCurrent(false)
    end
    if line.mode ~= "banner" and self:WantsAdvance() then
        self:Advance()
    end
end

function StoryPlayer:Dispose()
    self:Stop(true)
    if self.view then
        self.view.onAdvance = nil
    end
    self.view = nil
end

return StoryPlayer
