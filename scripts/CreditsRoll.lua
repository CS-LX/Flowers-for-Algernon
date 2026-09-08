-- 片尾滚动。文案来自 docs/credits-roll.md 的填写结果。
-- 导演只负责时间轴；本模块负责居中标题层级和匀速滚动。

local UI = require("urhox-libs/UI")

local CreditsRoll = {}
CreditsRoll.__index = CreditsRoll

local HOLD_START = 5.0
local HOLD_END = 5.0
local FADE_IN = 1.2
local FADE_OUT = 10.0
local SCROLL_SPEED = 42.0
local START_OFFSET = 80.0
local END_HOLD_RATIO = 0.55
local END_SAFETY = 160.0
local TITLE_BLOCK_ESTIMATE = 96.0
local INTRO_GAP_EXTRA = 96.0

local LINES = {
    { kind = "h1", text = "留给先行者的花束" },
    { kind = "h2", text = "Flowers Left for the Forerunner" },
    { kind = "introGap" },
    { kind = "h3", text = "制作" },
    { kind = "gap", size = 18 },
    { kind = "h4", text = "策划" },
    { kind = "body", text = "离" },
    { kind = "gap", size = 16 },
    { kind = "h4", text = "程序" },
    { kind = "body", text = "离  嗒啦啦" },
    { kind = "gap", size = 16 },
    { kind = "h4", text = "关卡" },
    { kind = "body", text = "离" },
    { kind = "gap", size = 16 },
    { kind = "h4", text = "叙事" },
    { kind = "body", text = "离  Gemi离" },
    { kind = "gap", size = 16 },
    { kind = "h4", text = "美术" },
    { kind = "body", text = "离" },
    { kind = "gap", size = 16 },
    { kind = "h4", text = "音频" },
    { kind = "body", text = "离  嗒啦啦" },
    { kind = "gap", size = 40 },
    { kind = "h3", text = "灵感来源" },
    { kind = "gap", size = 18 },
    { kind = "title", text = "《纪念碑谷》" },
    { kind = "credit", text = "Monument Valley" },
    { kind = "gap", size = 12 },
    { kind = "title", text = "《献给阿尔吉侬的花束》" },
    { kind = "credit", text = "Flowers for Algernon" },
    { kind = "gap", size = 12 },
    { kind = "title", text = "《我在七年后等着你》" },
    { kind = "credit", text = "7年後で待ってる" },
    { kind = "gap", size = 40 },
    { kind = "h3", text = "外部资源" },
    { kind = "gap", size = 18 },
    { kind = "h3", text = "引擎" },
    { kind = "body", text = "UrhoX  TapTapMaker" },
    { kind = "gap", size = 28 },
    { kind = "h3", text = "模型" },
    { kind = "title", text = "Grave" },
    { kind = "credit", text = "Zsky  ·  CC-BY 3.0  ·  Poly Pizza" },
    { kind = "gap", size = 12 },
    { kind = "title", text = "Toy Mouse（阿尔吉侬）" },
    { kind = "credit", text = "sirkitree  ·  CC-BY 3.0  ·  Poly Pizza" },
    { kind = "gap", size = 12 },
    { kind = "title", text = "Daisy" },
    { kind = "credit", text = "Zsky  ·  CC-BY 3.0  ·  Poly Pizza" },
    { kind = "gap", size = 12 },
    { kind = "title", text = "Flower" },
    { kind = "credit", text = "Poly by Google  ·  CC-BY 3.0  ·  Poly Pizza" },
    { kind = "gap", size = 12 },
    { kind = "title", text = "Camera Stand" },
    { kind = "credit", text = "Jason Oudshoorn  ·  CC-BY 3.0  ·  Poly Pizza" },
    { kind = "gap", size = 12 },
    { kind = "title", text = "Monitor" },
    { kind = "credit", text = "Poly by Google  ·  CC-BY 3.0  ·  Poly Pizza" },
    { kind = "gap", size = 12 },
    { kind = "title", text = "Lab Desk" },
    { kind = "credit", text = "Colonel Cthulu  ·  CC-BY 3.0  ·  Poly Pizza" },
    { kind = "gap", size = 28 },
    { kind = "h3", text = "音乐" },
    { kind = "title", text = "Writing the future" },
    { kind = "credit", text = "Pitx  ·  CC-BY 3.0  ·  ccMixter" },
    { kind = "title", text = "Brittle Rille" },
    { kind = "credit", text = "Kevin MacLeod  ·  CC-BY 4.0" },
    { kind = "title", text = "Piece of Quiet" },
    { kind = "credit", text = "geoffpeters  ·  CC-BY 3.0  ·  ccMixter" },
    { kind = "title", text = "Envisaging" },
    { kind = "credit", text = "Cloria Sound Labs  ·  DOVA-SYNDROME" },
    { kind = "title", text = "Eschatology" },
    { kind = "credit", text = "SOUNDORBIS  ·  DOVA-SYNDROME" },
    { kind = "title", text = "添い寝" },
    { kind = "credit", text = "SOUNDORBIS  ·  DOVA-SYNDROME" },
    { kind = "title", text = "夢の中ならば" },
    { kind = "credit", text = "SOUNDORBIS  ·  DOVA-SYNDROME" },
    { kind = "title", text = "Chained Story" },
    { kind = "credit", text = "SOUNDORBIS  ·  DOVA-SYNDROME" },
    { kind = "gap", size = 28 },
    { kind = "h3", text = "音效" },
    { kind = "body", text = "嗒啦啦" },
    { kind = "gap", size = 18 },
    { kind = "h3", text = "开源与中间件" },
    { kind = "body", text = "离  嗒拉拉" },
    { kind = "gap", size = 40 },
    { kind = "h3", text = "测试" },
    { kind = "body", text = "离" },
    { kind = "gap", size = 28 },
    { kind = "h3", text = "特别感谢" },
    { kind = "body", text = "积分支持——诺米" },
    { kind = "gap", size = 48 },
    { kind = "studio", text = "钅离的工作室" },
    { kind = "body", text = "2026" },
    { kind = "gap", size = 36 },
    { kind = "closing", text = "花还在" },
    { kind = "closing", text = "路也还在" },
    { kind = "gap", size = 18 },
    { kind = "closing", text = "谢谢游玩" },
    { kind = "gap", size = 72 },
}

local STYLES = {
    h1 = { fontSize = 42, fontWeight = "bold", color = { 255, 248, 236, 255 }, marginBottom = 8 },
    h2 = { fontSize = 18, fontWeight = "normal", color = { 214, 196, 168, 220 }, marginBottom = 8 },
    h3 = { fontSize = 22, fontWeight = "bold", color = { 236, 224, 204, 255 }, marginTop = 6, marginBottom = 10 },
    h4 = { fontSize = 16, fontWeight = "bold", color = { 196, 176, 148, 255 }, marginBottom = 4 },
    title = { fontSize = 18, fontWeight = "normal", color = { 242, 232, 214, 255 }, marginTop = 8, marginBottom = 2 },
    body = { fontSize = 18, fontWeight = "normal", color = { 232, 220, 200, 255 }, marginBottom = 4 },
    credit = { fontSize = 15, fontWeight = "normal", color = { 176, 160, 136, 230 }, marginBottom = 8 },
    studio = { fontSize = 22, fontWeight = "bold", color = { 255, 248, 236, 255 }, marginBottom = 6 },
    closing = { fontSize = 20, fontWeight = "normal", color = { 236, 224, 204, 255 }, marginBottom = 6 },
}

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

local function ScreenHeight()
    local physH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    if not dpr or dpr <= 0.0 then
        dpr = 1.0
    end
    return physH / dpr
end

local function StartY()
    return ScreenHeight() * 0.5 - START_OFFSET
end

local function IntroGapSize()
    local screenH = ScreenHeight()
    local gap = screenH - StartY() - TITLE_BLOCK_ESTIMATE + INTRO_GAP_EXTRA
    local minimum = screenH * 0.5
    if gap < minimum then
        gap = minimum
    end
    return gap
end

function CreditsRoll.New()
    local self = setmetatable({}, CreditsRoll)
    ---@type Widget|nil
    self.root = nil
    ---@type Widget|nil
    self.scroller = nil
    ---@type Widget|nil
    self.lastLine = nil
    self.elapsed = 0.0
    self.opacity = 0.0
    self.scroll = 0.0
    self.scrollDistance = 0.0
    self.scrollDuration = 0.0
    self.finished = false
    self.fadeOutStarted = false
    ---@type fun()|nil
    self.onComplete = nil
    ---@type fun(duration: number)|nil
    self.onFadeOut = nil
    return self
end

function CreditsRoll:BuildChildren()
    local children = {}
    self.lastLine = nil
    for _, line in ipairs(LINES) do
        if line.kind == "introGap" then
            children[#children + 1] = UI.Panel {
                width = "100%",
                height = IntroGapSize(),
            }
        elseif line.kind == "gap" then
            children[#children + 1] = UI.Panel {
                width = "100%",
                height = line.size or 16,
            }
        else
            local style = STYLES[line.kind] or STYLES.body
            local label = UI.Label {
                text = line.text,
                fontSize = style.fontSize,
                fontWeight = style.fontWeight,
                fontColor = style.color,
                textAlign = "center",
                whiteSpace = "normal",
                width = "100%",
                marginTop = style.marginTop or 0,
                marginBottom = style.marginBottom or 0,
            }
            children[#children + 1] = label
            self.lastLine = label
        end
    end
    return children
end

function CreditsRoll:Show(onComplete, onFadeOut)
    EnsureUI()
    self.onComplete = onComplete
    self.onFadeOut = onFadeOut
    self.elapsed = 0.0
    self.opacity = 0.0
    self.scroll = 0.0
    self.scrollDistance = 0.0
    self.scrollDuration = 0.0
    self.finished = false
    self.fadeOutStarted = false
    self.scroller = UI.Panel {
        width = "80%",
        maxWidth = 720,
        alignItems = "center",
        translateY = StartY(),
        children = self:BuildChildren(),
    }
    self.root = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = { 0, 0, 0, 255 },
        alignItems = "center",
        justifyContent = "flex-start",
        overflow = "hidden",
        opacity = 0.0,
        children = {
            self.scroller,
        },
    }
    UI.SetRoot(self.root, true)
    print("CreditsRoll: shown")
    return true
end

function CreditsRoll:EstimateContentHeight()
    local contentH = 0.0
    for _, line in ipairs(LINES) do
        if line.kind == "introGap" then
            contentH = contentH + IntroGapSize()
        elseif line.kind == "gap" then
            contentH = contentH + (line.size or 16)
        else
            local style = STYLES[line.kind] or STYLES.body
            contentH = contentH
                + (style.fontSize or 18) * 1.5
                + (style.marginTop or 0)
                + (style.marginBottom or 0)
        end
    end
    return contentH
end

function CreditsRoll:ReadContentHeight()
    local estimate = self:EstimateContentHeight()
    local laidOut = 0.0
    if self.lastLine and self.lastLine.GetLayout then
        local layout = self.lastLine:GetLayout()
        if layout and layout.y and layout.h and layout.h > 8 then
            laidOut = layout.y + layout.h
        end
    end
    if laidOut < estimate then
        laidOut = estimate
    end
    return laidOut
end

function CreditsRoll:MeasureScroll()
    local t = self.elapsed or 0.0
    if self.scrollDuration > 0.0 then
        local fadeOutStart = FADE_IN + HOLD_START + self.scrollDuration + HOLD_END
        if t >= fadeOutStart then
            return
        end
    end
    local screenH = ScreenHeight()
    local contentH = self:ReadContentHeight()
    local endY = screenH * END_HOLD_RATIO
    local distance = StartY() + contentH - endY + END_SAFETY
    if distance < screenH then
        distance = screenH
    end
    if self.scrollDuration > 0.0 and distance <= self.scrollDistance + 4 then
        return
    end
    self.scrollDistance = distance
    self.scrollDuration = distance / SCROLL_SPEED
    print(string.format(
        "CreditsRoll: contentH=%.1f scroll=%.1f duration=%.1f",
        contentH,
        self.scrollDistance,
        self.scrollDuration
    ))
end

function CreditsRoll:ApplyVisual()
    if self.root and self.root.SetOpacity then
        self.root:SetOpacity(self.opacity)
    end
    if self.scroller and self.scroller.SetStyle then
        self.scroller:SetStyle({
            translateY = StartY() - self.scroll,
        })
    end
end

function CreditsRoll:Finish()
    if self.finished then
        return
    end
    self.finished = true
    local complete = self.onComplete
    self.onComplete = nil
    self:Hide()
    if type(complete) == "function" then
        complete()
    end
end

function CreditsRoll:Hide()
    self.root = nil
    self.scroller = nil
    self.lastLine = nil
    if UI.SetRoot then
        UI.SetRoot(nil, true)
    end
end

function CreditsRoll:Update(timeStep)
    if self.finished or not self.root then
        return
    end
    self:MeasureScroll()
    self.elapsed = self.elapsed + timeStep
    local t = self.elapsed
    if t < FADE_IN then
        self.opacity = t / FADE_IN
    elseif t < FADE_IN + HOLD_START + self.scrollDuration + HOLD_END then
        self.opacity = 1.0
    else
        local fadeT = (t - FADE_IN - HOLD_START - self.scrollDuration - HOLD_END) / FADE_OUT
        if fadeT < 0.0 then
            fadeT = 0.0
        elseif fadeT > 1.0 then
            fadeT = 1.0
        end
        self.opacity = 1.0 - fadeT
    end

    local scrollStart = FADE_IN + HOLD_START
    local fadeOutStart = scrollStart + self.scrollDuration + HOLD_END
    if t <= scrollStart then
        self.scroll = 0.0
    elseif t >= scrollStart + self.scrollDuration then
        self.scroll = self.scrollDistance
    else
        self.scroll = (t - scrollStart) * SCROLL_SPEED
    end
    if t >= fadeOutStart and not self.fadeOutStarted then
        self.fadeOutStarted = true
        local fadeOut = self.onFadeOut
        if type(fadeOut) == "function" then
            fadeOut(FADE_OUT)
        end
    end
    self:ApplyVisual()
    if t >= fadeOutStart + FADE_OUT then
        self:Finish()
    end
end

return CreditsRoll
